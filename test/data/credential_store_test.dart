import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/secret_store.dart';
import 'package:webtrees_mobile/core/unlock_gate.dart';
import 'package:webtrees_mobile/core/webtrees_url.dart';
import 'package:webtrees_mobile/data/credential_store.dart';

/// A gate that records whether it was asked, and can refuse.
final class _FakeGate implements UnlockGate {
  bool allow = true;
  int attempts = 0;
  String? lastReason;

  @override
  bool get isEnforcing => true;

  @override
  Future<bool> unlock(String reason) async {
    attempts++;
    lastReason = reason;
    return allow;
  }
}

void main() {
  late MemorySecretStore secrets;
  late _FakeGate gate;
  late CredentialStore store;

  setUp(() {
    secrets = MemorySecretStore();
    gate = _FakeGate();
    store = CredentialStore(secrets, gate);
  });

  SavedConnection connection({
    String base = 'https://host',
    String username = 'mobile',
  }) => SavedConnection(
    base: Uri.parse(base),
    style: UrlStyle.pretty,
    username: username,
  );

  group('connections', () {
    test('start empty', () async {
      expect(await store.connections(), isEmpty);
    });

    test('are listed most recently used first', () async {
      await store.remember(connection(username: 'first'));
      await store.remember(connection(username: 'second'));

      expect((await store.connections()).map((c) => c.username), [
        'second',
        'first',
      ]);
    });

    test('re-signing in moves a connection to the front', () async {
      await store.remember(connection(username: 'a'));
      await store.remember(connection(username: 'b'));
      await store.remember(connection(username: 'a'));

      expect((await store.connections()).map((c) => c.username), ['a', 'b']);
    });

    test('the same site with two accounts stays two connections', () async {
      await store.remember(connection(username: 'mum'));
      await store.remember(connection(username: 'dad'));

      expect(await store.connections(), hasLength(2));
    });

    test('survive a round trip through storage', () async {
      await store.remember(
        SavedConnection(
          base: Uri.parse('https://host/wt'),
          style: UrlStyle.ugly,
          username: 'mobile',
          displayName: 'Mobile Client',
          version: '2.2.6',
        ),
      );

      final restored = (await store.connections()).single;

      expect(restored.base.toString(), 'https://host/wt');
      expect(restored.style, UrlStyle.ugly);
      expect(restored.displayName, 'Mobile Client');
      expect(restored.version, '2.2.6');
      expect(restored.url.base.path, '/wt');
    });

    test('a corrupt index is discarded rather than crashing', () async {
      await secrets.write('webtrees.connections', 'not json at all');

      expect(await store.connections(), isEmpty);
      // And the store recovers for subsequent writes.
      await store.remember(connection());
      expect(await store.connections(), hasLength(1));
    });
  });

  group('passwords', () {
    test('are returned once the gate is satisfied', () async {
      final saved = connection();
      await store.remember(saved, password: 'secret');

      final password = await store.password(saved, reason: 'Sign in');

      expect(password, 'secret');
      expect(gate.attempts, 1);
      expect(gate.lastReason, 'Sign in');
    });

    test('are withheld when the unlock is refused', () async {
      final saved = connection();
      await store.remember(saved, password: 'secret');
      gate.allow = false;

      expect(await store.password(saved, reason: 'Sign in'), isNull);
    });

    test('do not prompt when nothing is stored', () async {
      final saved = connection();
      await store.remember(saved);

      expect(await store.password(saved, reason: 'Sign in'), isNull);
      expect(gate.attempts, 0, reason: 'no secret means nothing to unlock');
    });

    test('can be checked for without unlocking', () async {
      final saved = connection();
      await store.remember(saved, password: 'secret');

      expect(await store.hasPassword(saved), isTrue);
      expect(gate.attempts, 0);
    });

    test('are kept separate per account on one site', () async {
      final mum = connection(username: 'mum');
      final dad = connection(username: 'dad');
      await store.remember(mum, password: 'mum-secret');
      await store.remember(dad, password: 'dad-secret');

      expect(await store.password(mum, reason: 'x'), 'mum-secret');
      expect(await store.password(dad, reason: 'x'), 'dad-secret');
    });

    test('forgetPassword keeps the connection listed', () async {
      final saved = connection();
      await store.remember(saved, password: 'secret');

      await store.forgetPassword(saved);

      expect(await store.hasPassword(saved), isFalse);
      expect(await store.connections(), hasLength(1));
    });

    test('forget removes both the connection and its password', () async {
      final saved = connection();
      await store.remember(saved, password: 'secret');

      await store.forget(saved);

      expect(await store.connections(), isEmpty);
      expect(await store.hasPassword(saved), isFalse);
    });
  });

  group('capability disclosure', () {
    test('reports honestly when storage does not persist', () {
      expect(store.canRemember, isFalse);
      expect(store.isGated, isTrue);
    });

    test('reports an open gate as not enforcing', () {
      final open = CredentialStore(MemorySecretStore(), const OpenGate());

      expect(open.isGated, isFalse);
    });
  });
}
