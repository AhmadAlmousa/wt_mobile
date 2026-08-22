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

/// A page of results, in the shape webtrees sends them.
///
/// `nextUrl` is what says a further page exists — and webtrees builds it
/// without the query, which is why the app pages by number instead of
/// following it.
String searchJson(String query, {int page = 1}) => jsonEncode({
  'data': query.contains('nobody')
      ? <Object>[]
      : [
          if (page == 1)
            {
              'value': 'X42',
              'text':
                  '<span class="NAME" dir="auto">عبد الله '
                  '<span class="SURN">الموسى</span></span>, 1901–1974',
            }
          else ...[
            {
              'value': 'X60',
              'text':
                  '<span class="NAME" dir="auto">خالد '
                  '<span class="SURN">الموسى</span></span>, 1926–2001',
            },
            // The same person twice: webtrees searches the name table, so
            // somebody recorded under two names is two rows, and it removes
            // those duplicates only within a page.
            {
              'value': 'X42',
              'text':
                  '<span class="NAME" dir="auto">عبد الله '
                  '<span class="SURN">الموسى</span></span>, 1901–1974',
            },
          ],
        ],
  'nextUrl': page == 1 && query.contains('كثير')
      ? '/tree/main/tom-select-individual?page=2'
      : null,
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
            body: searchJson(
              request.query['query'] ?? '',
              page: int.tryParse(request.query['page'] ?? '1') ?? 1,
            ),
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
    '/module/notes/Tab/main': (_) =>
        Canned(200, body: fixture('tab_notes.html')),
    '/module/sources_tab/Tab/main': (_) =>
        Canned(200, body: fixture('tab_sources.html')),
    '/module/media/Tab/main': (_) =>
        Canned(200, body: fixture('tab_media.html')),
    '/tree/main/media-thumbnail/M12/1': (_) =>
        const Canned(200, body: 'x', contentType: 'image/png'),
    '/tree/main/ancestors-tree-4/X42': (_) =>
        Canned(200, body: fixture('chart_ancestors.html')),
    '/tree/main/descendants-tree-3/X42': (_) =>
        Canned(200, body: fixture('chart_descendants.html')),
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
    expect(find.textContaining('الرياض, السعودية'), findsOne);
  });

  testWidgets('shows the marriage a family recorded', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    // A marriage belongs to the family rather than to either person, and the
    // relatives tab is the only place a stock site states it.
    expect(find.textContaining('1898 — الرياض'), findsOne);

    await tester.scrollUntilVisible(
      find.text('عائلته مع سارة'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // The heading is the site's own words, which already name the spouse.
    expect(find.text('عائلته مع سارة'), findsOne);
    expect(find.textContaining('1925 — مكة'), findsOne);
    // Children are listed under the marriage they belong to, not merged into
    // one list for everyone the person ever had.
    expect(find.text('Children'), findsOne);
  });

  testWidgets('names a family even when its caption is empty', (tester) async {
    // Some themes render the caption without text, which leaves the parser
    // holding the family's identifier — "F2" is no heading for a marriage.
    server = FakeWebtrees({
      ...browsableSite(),
      '/module/relatives/Tab/main': (_) => Canned(
        200,
        body: fixture(
          'tab_relatives.html',
        ).replaceAll('>عائلته مع سارة<', '><'),
      ),
    });
    session = sessionManagerFor(server, settings: settings = testSettings());
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
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Spouses'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('F2'), findsNothing);
  });

  testWidgets('offers only the charts the site draws and the app can', (
    tester,
  ) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ActionChip, 'Ancestors'), findsOne);
    expect(find.widgetWithText(ActionChip, 'Descendants'), findsOne);
    // The site offers these two as well, and the app cannot draw either — a
    // button it could not honour would be a promise the next tap breaks.
    expect(find.textContaining('Fan'), findsNothing);
    expect(find.textContaining('Statistics'), findsNothing);
  });

  testWidgets('draws the ancestors a site charted', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Ancestors'));
    await tester.pumpAndSettle();

    // Four generations, read from the shape webtrees described rather than
    // from its layout.
    expect(find.text('محمد الموسى'), findsOne);
    expect(find.text('سالم الموسى'), findsOne);
    expect(find.text('لطيفة العلي'), findsOne);
    // Asked for as a chart, not as the page webtrees wraps it in.
    final chart = server.requests.lastWhere(
      (request) => request.route == '/tree/main/ancestors-tree-4/X42',
    );
    expect(chart.query['ajax'], '1');
  });

  testWidgets('walks from a chart to the person tapped on it', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Ancestors'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('سالم الموسى'));
    await tester.pumpAndSettle();

    // Two things are worth doing with a box and neither is the obvious
    // default, so the sheet says both out loud.
    expect(find.text('Open this person'), findsOne);
    expect(find.text('Draw the chart from here'), findsOne);

    await tester.tap(find.text('Open this person'));
    await tester.pumpAndSettle();

    expect(server.routes, contains('/tree/main/individual/X20'));
  });

  testWidgets('the back gesture leaves a chart for the person', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Descendants'));
    await tester.pumpAndSettle();
    expect(find.text('هند الموسى'), findsOne);

    expect(await WidgetsBinding.instance.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    // Back onto the person the chart was drawn for, not out of the app.
    expect(find.text('Facts and events'), findsOne);
  });

  testWidgets('shows the notes and sources a tree publishes', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Notes'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('هاجر إلى الكويت'), findsOne);

    await tester.scrollUntilVisible(
      find.text('Sources'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('سجل قيد العائلة'), findsOne);
    // The citation's own fields, worded by the site rather than by the app.
    expect(find.text('الصفحة: ٤٢'), findsOne);
  });

  testWidgets('shows the photos a tree publishes', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Photos'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('صورة العائلة'), findsOne);

    // Every thumbnail travels over the session: webtrees checks this
    // account's permission before it honours the signature.
    final image = server.requests.firstWhere(
      (r) => r.route == '/tree/main/media-thumbnail/M12/1',
    );
    expect(image.anonymous, isFalse);
  });

  testWidgets('opens the relative a secondary fact belongs to', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Events of close relatives'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Events of close relatives'));
    await tester.pumpAndSettle();

    // "Death of a father" names the event and not the man; the name is what
    // the reader is looking for, and where they may want to go next.
    expect(find.text('محمد الموسى'), findsOne);
    await tester.tap(find.text('محمد الموسى'));
    await tester.pumpAndSettle();

    expect(server.routes, contains('/tree/main/individual/X7'));
  });

  testWidgets('fetches the next page of results when asked', (tester) async {
    await openTree(tester);
    await search(tester, 'كثير');

    // 50 per page, and webtrees says exactly whether more exist rather than
    // leaving it to be guessed from a full page.
    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();

    expect(find.text('خالد الموسى'), findsOne);
    // Somebody recorded under two names is two rows in the search webtrees
    // runs, and it drops those duplicates only within one page.
    expect(find.text('عبد الله الموسى'), findsOne);
    expect(find.text('Show more'), findsNothing);

    final second = server.requests.lastWhere(
      (r) => r.route == '/tree/main/tom-select-individual',
    );
    expect(second.query['page'], '2');
    // The query has to be repeated: webtrees builds its own `nextUrl` without
    // it, so a client that followed that link would search for nothing.
    expect(second.query['query'], 'كثير');
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
    // Found is not the same as reachable: the row may still be half off the
    // bottom of the screen, and a tap there lands on nothing.
    await tester.ensureVisible(find.text('محمد الموسى'));
    await tester.pumpAndSettle();
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
    // Found is not the same as reachable: the row may still be half off the
    // bottom of the screen, and a tap there lands on nothing.
    await tester.ensureVisible(find.text('محمد الموسى'));
    await tester.pumpAndSettle();
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
