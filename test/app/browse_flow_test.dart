import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/app/app.dart';
import 'package:webtrees_mobile/data/session_manager.dart';
import 'package:webtrees_mobile/data/settings_store.dart';

import 'package:webtrees_mobile/domain/dates.dart';

import '../support/fake_webtrees.dart';
import '../support/test_app.dart';

String fixture(String name) =>
    File('test/fixtures/v2_2_6/$name').readAsStringSync();

String searchJson(String query) => jsonEncode({
  'data': query.contains('nobody')
      ? <Object>[]
      : [
          {
            'value': 'X42',
            'text':
                '<span class="NAME" dir="auto">عبد الله '
                '<span class="SURN">الموسى</span></span>, 1901–1974',
          },
        ],
  'nextUrl': null,
});

void main() {
  late FakeWebtrees server;
  late SessionManager session;
  late SettingsStore settings;

  Map<String, Canned Function(Sent)> browsableSite() => {
    ...workingSite(),
    // `at` is required by the real handler; a fake that ignores it hid a
    // 400 on every live search (bug 14).
    '/tree/main/tom-select-individual': (request) =>
        request.query['at'] != '' && request.query['at'] != '@'
        ? const Canned(400, body: 'The parameter is missing.')
        : Canned(
            200,
            body: searchJson(request.query['query'] ?? ''),
            contentType: 'application/json',
          ),
    '/tree/main/individual/X42': (_) =>
        Canned(200, body: fixture('individual_page.html')),
    '/tree/main/individual/X7': (_) => Canned(
      200,
      body: fixture(
        'individual_page.html',
      ).replaceAll('عبد الله', 'محمد').replaceAll('xref=X42', 'xref=X7'),
    ),
    '/module/personal_facts/Tab/main': (_) =>
        Canned(200, body: fixture('tab_personal_facts.html')),
    '/module/relatives/Tab/main': (_) =>
        Canned(200, body: fixture('tab_relatives.html')),
    '/tree/main/media-thumbnail/M11/1': (_) =>
        const Canned(200, body: 'x', contentType: 'image/png'),
    '/tree/main/media-thumbnail/M3/1': (_) =>
        const Canned(200, body: 'x', contentType: 'image/png'),
  };

  Future<void> signIn(WidgetTester tester) async {
    server = FakeWebtrees(browsableSite());
    settings = testSettings();
    session = sessionManagerFor(server, settings: settings);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      WebtreesMobileApp(session: session, settings: settings),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'host');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'mobile');
    await tester.enterText(find.byType(TextFormField).at(1), 'correct');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  /// Signs in, which lands in the tree: this account can reach exactly one,
  /// and a list of one is not a choice worth making anybody make.
  Future<void> openTree(WidgetTester tester) async {
    await signIn(tester);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  testWidgets('an account with one tree lands straight in it', (tester) async {
    await openTree(tester);

    // The account screen is not a destination when it holds a single card.
    expect(find.text('Search for a person'), findsOne);
    expect(find.text('Your access'), findsNothing);
  });

  testWidgets('the account screen is still reachable', (tester) async {
    await openTree(tester);

    await tester.tap(find.byTooltip('Your account'));
    await tester.pumpAndSettle();

    // And it must not bounce straight back into the tree it came from.
    expect(find.text('Your access'), findsOne);
    expect(find.text('Member'), findsOne);
  });

  testWidgets('asks for a name before searching', (tester) async {
    await openTree(tester);

    // The endpoint behind this screen refuses an empty query, so an empty
    // state that says "type a name" is the honest thing to show — not a
    // spinner, and not a list the app cannot fill.
    expect(find.textContaining('Type a name'), findsOne);
    expect(server.routes, isNot(contains('/tree/main/tom-select-individual')));
  });

  testWidgets('finds a person and opens them', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');

    expect(find.text('عبد الله الموسى'), findsOne);

    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    expect(find.text('Facts and events'), findsOne);
    expect(find.text('Parents'), findsOne);
  });

  testWidgets('says so when nobody matches', (tester) async {
    await openTree(tester);
    await search(tester, 'nobody');

    expect(find.textContaining('Nobody matched'), findsOne);
  });

  testWidgets('shows facts with their dates and places', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    expect(find.text('الميلاد'), findsOne);
    // The date keeps the calendar conversion webtrees rendered.
    expect(find.textContaining('١٢ مارس ١٩٠١'), findsOne);
    expect(find.textContaining('٢١ ذو القعدة ١٣١٨'), findsOne);
    expect(find.textContaining('الرياض'), findsOne);
  });

  testWidgets('keeps a relative’s event out of the main list', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    // webtrees collapses these itself; they are context, not this person's
    // facts, and mixing them in would misattribute a death.
    await tester.scrollUntilVisible(
      find.text('Events of close relatives'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Events of close relatives'), findsOne);
    expect(find.text('وفاة الأب'), findsNothing);
  });

  testWidgets('shows the second name a tree records', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    expect(find.text('Abdullah Almousa'), findsOne);
  });

  testWidgets('walks from a person to their father', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('محمد الموسى'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('محمد الموسى'));
    await tester.pumpAndSettle();

    expect(server.routes, contains('/tree/main/individual/X7'));
  });

  testWidgets('the system back button returns to the previous person', (
    tester,
  ) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('محمد الموسى'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('محمد الموسى'));
    await tester.pumpAndSettle();

    // This is what Android's back gesture does. It used to leave the app
    // outright, because the person route was declared beside the search route
    // rather than inside it, so navigating built a stack one page deep.
    expect(await WidgetsBinding.instance.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    // The page comes back as it was left, scrolled where the reader had it,
    // so the name has to be scrolled back up to.
    await tester.scrollUntilVisible(
      find.text('عبد الله الموسى'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('عبد الله الموسى'), findsOne);

    expect(await WidgetsBinding.instance.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Search for a person'), findsOne);
  });

  testWidgets('someone with no photo is drawn as their initial', (
    tester,
  ) async {
    await openTree(tester);
    await search(tester, 'الموسى');

    // Most people in a real tree have no photograph, so this placeholder is
    // what the reader sees most: a wall of identical silhouettes tells them
    // nothing about who is who.
    expect(find.text('ع'), findsOne);
  });

  testWidgets('names the tree the way the family does', (tester) async {
    await openTree(tester);

    // `main` is the identifier webtrees routes on, and this screen is the
    // app's home. The title is what the family calls the tree.
    expect(find.text('Family tree'), findsOne);
    expect(find.text('main'), findsNothing);
  });

  testWidgets('asks the site to write in the app’s language', (tester) async {
    await openTree(tester);

    // The site writes the dates, the month names and the fact labels, and it
    // writes them in the language held in its own session — seeded from the
    // account's preference, not from anything the app sent. So the app has to
    // say which language it is reading in, or an Arabic screen fills with
    // English dates.
    expect(server.routes, contains('/language/en-GB'));
  });

  testWidgets('a change of language reaches the site too', (tester) async {
    await openTree(tester);

    await settings.setLocale(const Locale('ar'));
    await tester.pumpAndSettle();

    expect(server.routes, contains('/language/ar'));
  });

  testWidgets('shows one calendar when the reader picks one', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();
    expect(find.textContaining('٢١ ذو القعدة ١٣١٨'), findsOne);

    await settings.setCalendarView(CalendarView.gregorian);
    await tester.pumpAndSettle();

    // The record is not fetched again: the site already sent both calendars,
    // and which of them to show is the reader's business, not the server's.
    expect(find.textContaining('١٢ مارس ١٩٠١'), findsOne);
    expect(find.textContaining('٢١ ذو القعدة ١٣١٨'), findsNothing);
  });

  testWidgets('fetches photos over the signed-in session', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    // A signed thumbnail URL is not an access token — webtrees still checks
    // this user's permission — so the request must carry the session.
    final image = server.requests.firstWhere(
      (r) => r.route == '/tree/main/media-thumbnail/M11/1',
    );
    expect(image.anonymous, isFalse);
  });

  testWidgets('a lost section is named, not silently blank', (tester) async {
    server = FakeWebtrees({
      ...browsableSite(),
      '/module/relatives/Tab/main': (_) => const Canned(403),
    });
    session = sessionManagerFor(server);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      WebtreesMobileApp(session: session, settings: testSettings()),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'host');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'mobile');
    await tester.enterText(find.byType(TextFormField).at(1), 'correct');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    // The person still opens; only the part that failed is missing, and it
    // says which part.
    expect(find.text('الميلاد'), findsOne);
    expect(find.textContaining('Family members'), findsOne);
    expect(find.text('Parents'), findsNothing);
  });
}
