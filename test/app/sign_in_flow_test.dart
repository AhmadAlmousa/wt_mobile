import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/app/app.dart';
import 'package:webtrees_mobile/core/secret_store.dart';
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
    await tester.pumpWidget(WebtreesMobileApp(session: session));
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
    testWidgets('reaches the access screen with correct credentials', (
      tester,
    ) async {
      await launch(tester);
      await connect(tester);
      await signIn(tester);

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

      expect(find.text('Site administrator'), findsOne);
      expect(find.text('Administrator'), findsOne);
      expect(find.text('Can manage'), findsOne);
    });

    testWidgets('signing out returns to the connect screen', (tester) async {
      await launch(tester);
      await connect(tester);
      await signIn(tester);

      await tester.tap(find.byTooltip('Sign out'));
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

      expect(find.text('RECENT'), findsOne);
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
      expect(find.text('Your access'), findsOne);

      await launch(tester, secrets: secrets);
      await tester.tap(find.text('host'));
      await tester.pumpAndSettle();

      // This is the whole promise of "stay signed in": no address to retype,
      // no password to re-enter, straight to the content.
      expect(find.text('Your access'), findsOne);
      expect(find.text('Sign in'), findsNothing);
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
      expect(find.text('Your access'), findsNothing);
    });
  });
}
