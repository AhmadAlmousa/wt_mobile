import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/core/unlock_gate.dart';
import 'package:webtrees_mobile/data/access_probe.dart';
import 'package:webtrees_mobile/data/credential_store.dart';
import 'package:webtrees_mobile/data/session_manager.dart';

import '../support/fake_site.dart';
import '../support/fake_webtrees.dart';
import '../support/test_app.dart';

/// An unlock gate that records how often it was asked, and can refuse.
final class CountingGate implements UnlockGate {
  CountingGate({this.allow = true});

  bool allow;
  int prompts = 0;

  @override
  bool get isEnforcing => true;

  @override
  Future<bool> unlock(String reason) async {
    prompts++;
    return allow;
  }
}

void main() {
  late FakeSite site;
  late FakeWebtrees server;
  late FakeKeystore secrets;

  setUp(() {
    site = FakeSite();
    server = FakeWebtrees(site.handlers);
    secrets = FakeKeystore();
  });

  SessionManager managerWith({
    UnlockGate gate = const OpenGate(),
    Duration keepAlive = Duration.zero,
    // Long enough that "was held off" and "was not" cannot be confused for
    // scheduler noise. A 20ms backoff left a 5ms margin, which a loaded
    // machine crosses on its own.
    Duration backoff = const Duration(milliseconds: 300),
  }) => SessionManager(
    CredentialStore(secrets, gate),
    clientFactory: clientFactoryFor(server),
    keepAliveInterval: keepAlive,
    signInBackoff: backoff,
  );

  Future<SessionManager> signedInManager({
    UnlockGate gate = const OpenGate(),
    Duration keepAlive = Duration.zero,
    bool remember = true,
  }) async {
    final manager = managerWith(gate: gate, keepAlive: keepAlive);
    expect(await manager.connect('host'), isTrue);
    expect(
      await manager.signIn('mobile', 'correct', remember: remember),
      isTrue,
    );
    return manager;
  }

  group('staying signed in', () {
    test('recovers from an expired session even though the token died '
        'with it', () async {
      final manager = await signedInManager();
      addTearDown(manager.dispose);

      // An idle timeout on the server. The app is unaware, and still holds a
      // CSRF token that is now worthless.
      site.expire();

      final summary = await manager.withSession(
        () => AccessProbe(manager.client).describe(),
      );

      expect(summary.account.username, 'mobile');
      expect(manager.isSignedIn, isTrue);
      // The recovery fetched a fresh token rather than posting the dead one.
      expect(site.staleTokenAttempts, 0);
    });

    test('does not treat a server fault as a signed-out session', () async {
      final manager = await signedInManager();
      addTearDown(manager.dispose);

      server.handlers['/my-account'] = (_) => const Canned(500);

      await expectLater(
        manager.withSession(() => AccessProbe(manager.client).describe()),
        throwsA(isA<UnexpectedResponse>()),
      );
      // A failing server says nothing about the session, so no re-login was
      // attempted and the user stays signed in.
      expect(site.signInAttempts, 1);
      expect(manager.isSignedIn, isTrue);
    });

    test('signs in once when several requests meet the expiry '
        'together', () async {
      final manager = await signedInManager();
      addTearDown(manager.dispose);
      site.expire();

      await Future.wait([
        manager.withSession(() => AccessProbe(manager.client).describe()),
        manager.withSession(() => AccessProbe(manager.client).describe()),
        manager.withSession(() => AccessProbe(manager.client).describe()),
      ]);

      // One initial sign-in plus exactly one shared recovery.
      expect(site.signInAttempts, 2);
      expect(manager.isSignedIn, isTrue);
    });

    test('asks the device to unlock only once for a shared recovery', () async {
      final gate = CountingGate();
      final manager = await signedInManager(gate: gate);
      addTearDown(manager.dispose);
      site.expire();

      await Future.wait([
        manager.withSession(() => AccessProbe(manager.client).describe()),
        manager.withSession(() => AccessProbe(manager.client).describe()),
      ]);

      expect(gate.prompts, 1);
    });

    test('keep-alive brings back a session that died between '
        'requests', () async {
      final manager = await signedInManager(
        keepAlive: const Duration(milliseconds: 20),
      );
      addTearDown(manager.dispose);

      site.expire();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(site.signInAttempts, greaterThan(1));
      expect(manager.isSignedIn, isTrue);
      expect(site.signedIn, isTrue);
    });

    test('signs the user out when nothing is stored to sign in '
        'with again', () async {
      final manager = await signedInManager(remember: false);
      addTearDown(manager.dispose);
      site.expire();

      await expectLater(
        manager.withSession(() => AccessProbe(manager.client).describe()),
        throwsA(isA<SessionExpired>()),
      );
      expect(manager.isSignedIn, isFalse);
    });
  });

  group('returning to a site', () {
    test('resumes with the stored password', () async {
      final first = await signedInManager();
      first.dispose();

      // A fresh manager over the same keystore, as after a restart.
      final manager = managerWith();
      addTearDown(manager.dispose);

      final saved = (await manager.savedConnections()).single;
      expect(saved.username, 'mobile');

      expect(await manager.resume(saved), isTrue);
      expect(manager.isSignedIn, isTrue);
    });

    test('does not resume when the unlock is refused', () async {
      final first = await signedInManager();
      first.dispose();

      final gate = CountingGate(allow: false);
      final manager = managerWith(gate: gate);
      addTearDown(manager.dispose);

      final saved = (await manager.savedConnections()).single;
      expect(await manager.resume(saved), isFalse);
      expect(manager.isSignedIn, isFalse);
      expect(gate.prompts, 1);
      // Refusing to identify yourself is not a reason to lose the password.
      expect(await manager.hasStoredPassword(saved), isTrue);
    });

    test('discards a stored password the server now rejects', () async {
      final first = await signedInManager();
      first.dispose();

      // The account's password was changed elsewhere.
      site.password = 'changed';

      final manager = managerWith();
      addTearDown(manager.dispose);

      final saved = (await manager.savedConnections()).single;
      expect(await manager.resume(saved), isFalse);
      expect(manager.error, isA<SignInRejected>());
      // Kept, it would fail identically on every future launch.
      expect(await manager.hasStoredPassword(saved), isFalse);
      // The site itself is still remembered, so the user can just retype.
      expect(await manager.savedConnections(), isNotEmpty);
    });

    test('holds off before retrying after a rejection', () async {
      final manager = managerWith();
      addTearDown(manager.dispose);
      await manager.connect('host');

      expect(await manager.signIn('mobile', 'wrong'), isFalse);

      final clock = Stopwatch()..start();
      expect(await manager.signIn('mobile', 'wrong'), isFalse);
      clock.stop();

      // webtrees does not rate-limit sign-in at all, so the restraint that
      // keeps a stale password out of the site's authentication log has to be
      // here.
      expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(300));
    });

    test('stops holding off once the password is accepted', () async {
      final manager = managerWith();
      addTearDown(manager.dispose);
      await manager.connect('host');
      expect(await manager.signIn('mobile', 'wrong'), isFalse);
      expect(await manager.signIn('mobile', 'correct'), isTrue);

      await manager.signOut();

      final clock = Stopwatch()..start();
      expect(await manager.signIn('mobile', 'correct'), isTrue);
      clock.stop();
      expect(clock.elapsedMilliseconds, lessThan(150));
    });
  });

  group('credentials', () {
    test('turning off "stay signed in" withdraws the stored '
        'password', () async {
      final first = await signedInManager();
      first.dispose();

      final manager = managerWith();
      addTearDown(manager.dispose);
      final saved = (await manager.savedConnections()).single;
      expect(await manager.hasStoredPassword(saved), isTrue);

      await manager.connect('host');
      expect(
        await manager.signIn('mobile', 'correct', remember: false),
        isTrue,
      );

      expect(await manager.hasStoredPassword(saved), isFalse);
    });

    test('keeps the account name against the connection', () async {
      final manager = await signedInManager();
      addTearDown(manager.dispose);

      await manager.noteAccountName('Mobile Client');

      expect(
        (await manager.savedConnections()).single.displayName,
        'Mobile Client',
      );
    });

    test('signing in again keeps the name already recorded', () async {
      final first = await signedInManager();
      await first.noteAccountName('Mobile Client');
      first.dispose();

      final manager = await signedInManager();
      addTearDown(manager.dispose);

      expect(manager.connection?.displayName, 'Mobile Client');
    });
  });

  group('connecting', () {
    test('a failed reconnect leaves no trace of the previous site', () async {
      final manager = await signedInManager();
      addTearDown(manager.dispose);

      server.handlers['/ping'] = (_) => const Canned(503);
      expect(await manager.connect('elsewhere'), isFalse);

      // Reporting the old site while the client points at the new one would
      // be worse than reporting nothing.
      expect(manager.instance, isNull);
      expect(manager.connection, isNull);
      expect(manager.isSignedIn, isFalse);
      expect(manager.stage, ConnectionStage.disconnected);
      expect(() => manager.client, throwsStateError);
    });
  });
}
