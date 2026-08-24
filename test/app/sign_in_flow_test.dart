import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/app/app.dart';
import 'package:webtrees_mobile/core/secret_store.dart';
import 'package:webtrees_mobile/data/local/tree_store.dart';
import 'package:webtrees_mobile/data/session_manager.dart';

import '../support/fake_webtrees.dart';
import '../support/test_app.dart';

void main() {
  late FakeWebtrees server;
  late SessionManager session;

  Future<void> launch(
    WidgetTester tester, {
    Map<String, Canned Function(Sent)>? site,
    SecretStore? secrets,
  }) async {
    server = FakeWebtrees(site ?? workingSite());
    session = sessionManagerFor(server, secrets: secrets);
    addTearDown(session.dispose);

    // Tear down any previous tree first. Pumping the same widget type would
    // otherwise reuse its State, carrying the old session across what is meant
    // to represent a fresh launch of the app.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      WebtreesMobileApp(
        session: session,
        settings: testSettings(),
        treeStore: TreeStore.none(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Types an address and connects.
  Future<void> connect(WidgetTester tester, [String address = 'host']) async {
    await tester.enterText(find.byType(TextFormField), address);
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
  }

  Future<void> signIn(
    WidgetTester tester, {
    String username = 'mobile',
    String password = 'correct',
  }) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), username);
    await tester.enterText(fields.at(1), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  /// Opens the account screen from wherever signing in landed.
  ///
  /// An account that can reach one tree goes straight into it, so what the
  /// app knows about the site and the role is one tap away rather than the
  /// first thing anybody sees.
  Future<void> openAccount(WidgetTester tester) async {
    final account = find.byTooltip('Your account');
    if (account.evaluate().isNotEmpty) {
      await tester.tap(account);
      await tester.pumpAndSettle();
    }
  }

  group('connect', () {
    testWidgets('starts by asking for a site address', (tester) async {
      await launch(tester);

      expect(find.text('Connect to your family tree'), findsOne);
      expect(find.widgetWithText(FilledButton, 'Connect'), findsOne);
    });

    testWidgets('refuses to submit an empty address', (tester) async {
      await launch(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('An address is needed'), findsOne);
      expect(server.requests, isEmpty);
    });

    testWidgets('moves to sign-in once the site is identified', (tester) async {
      await launch(tester);
      await connect(tester);

      expect(find.text('Sign in'), findsWidgets);
      // The site is confirmed before any password is typed.
      expect(find.text('host'), findsOne);
      expect(find.text('webtrees 2.2.6'), findsOne);
    });

    testWidgets('explains an unreachable site and stays put', (tester) async {
      await launch(tester, site: {'/ping': (_) => const Canned(404)});
      await connect(tester);

      expect(
        find.textContaining('does not look like a webtrees site'),
        findsOne,
      );
      expect(find.text('Connect to your family tree'), findsOne);
    });

    testWidgets('warns that maintenance mode is not a wrong address', (
      tester,
    ) async {
      await launch(
        tester,
        site: {'/ping': (_) => const Canned(503, body: '<html>Offline</html>')},
      );
      await connect(tester);

      expect(find.textContaining('offline for maintenance'), findsOne);
    });
  });

  group('sign in', () {
    testWidgets('signs in and shows who is signed in', (tester) async {
      await launch(tester);
      await connect(tester);
      await signIn(tester);
      await openAccount(tester);

      expect(find.text('Your access'), findsOne);
      expect(find.text('Mobile Client'), findsOne);
      expect(find.text('mobile@example.com'), findsOne);
    });

    testWidgets('shows the site\'s own wording when rejected', (tester) async {
      await launch(tester);
      await connect(tester);
      await signIn(tester, password: 'wrong');

      expect(find.textContaining('not accepted'), findsOne);
      expect(find.text('Your access'), findsNothing);
    });

    testWidgets('will not submit without a password', (tester) async {
      await launch(tester);
      await connect(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'mobile');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your password.'), findsOne);
    });

    testWidgets('says so when the device cannot keep a password', (
      tester,
    ) async {
      // MemorySecretStore reports isPersistent false, standing in for a device
      // with no keystore.
      await launch(tester, secrets: MemorySecretStore());
      await connect(tester);

      expect(
        find.textContaining('no secure storage'),
        findsOne,
        reason: 'the interface must not imply it will remember',
      );
    });
  });

  group('access', () {
    testWidgets('reports a member of a private tree', (tester) async {
      await launch(tester);
      await connect(tester);
      await signIn(tester);
      await openAccount(tester);

      expect(find.text('Member'), findsOne);
      expect(find.textContaining('including living relatives'), findsOne);
      expect(find.text('Linked to X42'), findsOne);
      expect(find.text('Can edit'), findsNothing);
    });

    testWidgets('reports an administrator as managing every tree', (
      tester,
    ) async {
      await launch(tester, site: workingSite(administrator: true));
      await connect(tester);
      await signIn(tester);
      await openAccount(tester);

      expect(find.text('Site administrator'), findsOne);
      expect(find.text('Administrator'), findsOne);
      expect(find.text('Can manage'), findsOne);
    });

    testWidgets('signing out returns to the connect screen', (tester) async {
      await launch(tester);
      await connect(tester);
      await signIn(tester);
      await openAccount(tester);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Connect to your family tree'), findsOne);
    });
  });

  group('returning user', () {
    testWidgets('offers the site used last time', (tester) async {
      final secrets = MemorySecretStore();
      await launch(tester, secrets: secrets);
      await connect(tester);
      await signIn(tester);

      // Relaunch against the same storage, as though the app restarted.
      await launch(tester, secrets: secrets);

      expect(find.text('Recent'), findsOne);
      expect(find.text('host'), findsOne);
      expect(find.textContaining('mobile'), findsOne);
    });

    testWidgets('signs straight back in with the password it kept', (
      tester,
    ) async {
      final secrets = FakeKeystore();
      await launch(tester, secrets: secrets);
      await connect(tester);
      await signIn(tester);
      expect(find.text('Search for a person'), findsOne);

      await launch(tester, secrets: secrets);

      // This is the whole promise of "stay signed in", and it has to cost
      // nothing: no address to retype, no site to pick out of a list of one,
      // no password to re-enter. Straight into the family tree.
      expect(find.text('Search for a person'), findsOne);
      expect(find.text('Connect to your family tree'), findsNothing);
      expect(find.text('Sign in'), findsNothing);
    });

    testWidgets('offers the address it used last when it cannot resume', (
      tester,
    ) async {
      final secrets = MemorySecretStore();
      await launch(tester, secrets: secrets);
      await connect(tester);
      await signIn(tester);

      await launch(tester, secrets: secrets);

      // Nothing could be resumed, so the form is right — but it should not be
      // empty. The address is almost always the same one as last time.
      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller?.text, contains('host'));
    });

    testWidgets('asks only for the password when the site is known', (
      tester,
    ) async {
      // A stored password that has stopped working leaves the app connected
      // but signed out. It knows the address perfectly well by then, so
      // asking for it again would be asking a question it can answer itself.
      final secrets = FakeKeystore();
      await launch(tester, secrets: secrets);
      await connect(tester);
      await signIn(tester);

      await launch(
        tester,
        site: workingSite(password: 'changed'),
        secrets: secrets,
      );

      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOne);
      expect(find.text('Connect to your family tree'), findsNothing);
      expect(find.textContaining('was not accepted'), findsOne);
    });

    testWidgets('asks for the password when none could be kept', (
      tester,
    ) async {
      // A device with no keystore. The site is still remembered, but the
      // password never was, so the sign-in form must appear rather than the
      // app pretending it can resume.
      final secrets = MemorySecretStore();
      await launch(tester, secrets: secrets);
      await connect(tester);
      await signIn(tester);

      await launch(tester, secrets: secrets);
      await tester.tap(find.text('host'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOne);
      expect(find.text('Search for a person'), findsNothing);
    });
  });
}
