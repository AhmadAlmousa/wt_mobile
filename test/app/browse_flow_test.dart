import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/app/app.dart';
import 'package:webtrees_mobile/app/theme.dart';
import 'package:webtrees_mobile/data/local/tree_store.dart';
import 'package:webtrees_mobile/data/session_manager.dart';
import 'package:webtrees_mobile/data/settings_store.dart';
import 'package:webtrees_mobile/domain/dates.dart';
import 'package:webtrees_mobile/features/browse/authenticated_image.dart';
import 'package:webtrees_mobile/features/charts/chart_canvas.dart';
import 'package:webtrees_mobile/features/charts/fan_canvas.dart';

import '../support/fake_webtrees.dart';
import '../support/test_app.dart';

String fixture(String name) =>
    File('test/fixtures/v2_2_6/$name').readAsStringSync();

/// A lifespan as `Individual::lifespan()` really writes one.
///
/// Two spans, each carrying the place and the full date in its `title` and
/// separated from it by the Unicode isolates webtrees wraps a rendered date
/// in — which is where the app gets a birth year and a birthplace for a
/// search result, and therefore what the filter runs on.
String lifespanMarkup(int born, int died, String place) =>
    '<span title="$place \u2068about $born\u2069">$born</span>'
    '–<span title=" \u2068$died\u2069">$died</span>';

/// A page of results, in the shape webtrees sends them.
///
/// `nextUrl` is what says a further page exists — and webtrees builds it
/// without the query, which is why the app pages by number instead of
/// following it.
String searchJson(String query, {int page = 1}) => jsonEncode({
  'data': query.contains('nobody')
      ? <Object>[]
      : query.contains('نورة')
      ? [
          {
            'value': 'X43',
            'text':
                '<span class="NAME" dir="auto">نورة '
                '<span class="SURN">الموسى</span></span>, '
                '${lifespanMarkup(1903, 1980, 'مكة، السعودية')}',
          },
        ]
      : [
          if (page == 1)
            {
              'value': 'X42',
              'text':
                  '<span class="NAME" dir="auto">عبد الله '
                  '<span class="SURN">الموسى</span></span>, '
                  '${lifespanMarkup(1901, 1974, 'الكويت، الكويت')}',
            }
          else ...[
            {
              'value': 'X60',
              'text':
                  '<span class="NAME" dir="auto">خالد '
                  '<span class="SURN">الموسى</span></span>, '
                  '${lifespanMarkup(1926, 2001, 'مكة، السعودية')}',
            },
            // The same person twice: webtrees searches the name table, so
            // somebody recorded under two names is two rows, and it removes
            // those duplicates only within a page.
            {
              'value': 'X42',
              'text':
                  '<span class="NAME" dir="auto">عبد الله '
                  '<span class="SURN">الموسى</span></span>, '
                  '${lifespanMarkup(1901, 1974, 'الكويت، الكويت')}',
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
    '/tree/main/relationships-1-3/X42/X43': (_) =>
        Canned(200, body: fixture('relationship_sibling.html')),
    // The same two people, asked for without the blood-lines limit.
    '/tree/main/relationships-0-3/X42/X43': (_) =>
        Canned(200, body: fixture('relationship_sibling.html')),
    '/tree/main/timeline-10': (_) =>
        Canned(200, body: fixture('timeline.html')),
    '/module/statistics_chart/Chart/main': (_) => const Canned(
      200,
      body:
          '<div id="statistics-tabs"><ul class="nav nav-tabs"><li>'
          '<a class="nav-link" href="#tab-1" '
          'data-wt-href="/module/statistics_chart/Individuals/main">أفراد</a>'
          '</li></ul></div>',
    ),
    '/module/statistics_chart/Individuals/main': (_) =>
        Canned(200, body: fixture('statistics_individuals.html')),
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
      WebtreesMobileApp(
        session: session,
        settings: settings,
        treeStore: TreeStore.none(),
      ),
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

    await tester.scrollUntilVisible(
      find.text('Parents'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
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
    await tester.scrollUntilVisible(
      find.textContaining('1898 — الرياض'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
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
    // one list for everyone the person ever had — and counted, so a reader
    // can see at a glance how big each family was.
    expect(find.text('2 children'), findsOne);
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
      WebtreesMobileApp(
        session: session,
        settings: settings,
        treeStore: TreeStore.none(),
      ),
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
    // An hourglass is not fetched at all: it is those two charts stacked, so
    // it is offered exactly when both of them are.
    expect(find.widgetWithText(ActionChip, 'Hourglass'), findsOne);
    // In the app's own order, not the order the site's menu happened to list
    // them in — and only the charts it can actually draw.
    expect(
      tester
          .widgetList<ActionChip>(find.byType(ActionChip))
          .map((chip) => (chip.label as Text).data),
      ['Ancestors', 'Descendants', 'Hourglass', 'Relationship', 'Timeline'],
    );
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

  testWidgets('stacks an hourglass out of the two charts', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Hourglass'));
    await tester.pumpAndSettle();

    // A grandfather above and a granddaughter below, on one canvas, with the
    // person they have in common drawn once between them. Scoped to the
    // canvas: the bar names the subject too, and that is not a second box.
    Finder onTheChart(String name) => find.descendant(
      of: find.byType(ChartCanvas),
      matching: find.text(name),
    );
    expect(onTheChart('سالم الموسى'), findsOne);
    expect(onTheChart('ريم الموسى'), findsOne);
    expect(onTheChart('عبد الله الموسى'), findsOne);

    expect(server.routes, contains('/tree/main/ancestors-tree-4/X42'));
    expect(server.routes, contains('/tree/main/descendants-tree-3/X42'));
    // webtrees offers an hourglass of its own; the app never asks for it.
    expect(server.routes, isNot(contains('/tree/main/hourglass-3-0/X42')));
  });

  testWidgets('bends the ancestors round a circle when asked', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Ancestors'));
    await tester.pumpAndSettle();
    expect(find.byType(FanCanvas), findsNothing);

    // Every question about how a chart is drawn is asked in one place.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Circle').hitTestable());
    await tester.pumpAndSettle();
    // Dismissed through the barrier: the sheet's own button is below the
    // fold on a surface this size.
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    // The same fetch, the same people, a different way of looking at them.
    expect(find.byType(FanCanvas), findsOne);
    expect(
      server.routes.where((route) => route.contains('ancestors-tree-4')),
      hasLength(1),
    );
  });

  testWidgets('lays a life out on a timeline', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Timeline'));
    await tester.pumpAndSettle();

    // The scale the site drew, and the events it placed against it — each
    // still carrying the date in the site's own words.
    // Isolated, because a year is Latin whichever way the page reads.
    expect(find.textContaining('1900'), findsOne);
    expect(find.textContaining('الميلاد'), findsOne);
    expect(find.textContaining('١٩٠١'), findsOne);
    // The person is in the address the site gave, so the app asked for the
    // chart rather than building one.
    final asked = server.requests.lastWhere(
      (request) => request.route == '/tree/main/timeline-10',
    );
    expect(asked.query['xrefs[0]'], 'X42');
    expect(asked.query['ajax'], '1');
  });

  testWidgets('says how two people are related', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Relationship'));
    await tester.pumpAndSettle();

    // A relationship needs a second person before there is anything to show,
    // so the screen asks for one rather than guessing.
    expect(find.textContaining('Whose relationship to'), findsOne);
    await tester.enterText(find.byType(TextField), 'نورة');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('نورة الموسى').last);
    await tester.pumpAndSettle();

    // The site's own words for the relationship and for each step of it.
    expect(find.text('القرابة: أخت'), findsOne);
    expect(find.text('أخت'), findsOne);
    expect(server.routes, contains('/tree/main/relationships-1-3/X42/X43'));
  });

  testWidgets('draws the same relationship as a family tree', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Relationship'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'نورة');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('نورة الموسى').last);
    await tester.pumpAndSettle();

    // The list of steps, which is the mode it opens in.
    expect(find.byType(ChartCanvas), findsNothing);

    await tester.tap(find.text('Tree'));
    await tester.pumpAndSettle();

    // The same two people, placed rather than listed — and the site's own
    // word still on the line between them.
    final canvas = tester.widget<ChartCanvas>(find.byType(ChartCanvas));
    expect(canvas.layout.people.map((p) => p.person.xref), ['X42', 'X43']);
    expect(canvas.layout.edges.single.label, 'أخت');
    // A sister is a step along the page, so both boxes sit on one row.
    expect(
      canvas.layout.people.first.topLeft.dy,
      canvas.layout.people.last.topLeft.dy,
    );

    // And back again, because a path says what a tree cannot.
    await tester.tap(find.text('Path'));
    await tester.pumpAndSettle();
    expect(find.byType(ChartCanvas), findsNothing);
    expect(find.text('القرابة: أخت'), findsOne);
  });

  testWidgets('the button beside a relationship draws it', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Relationship'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'نورة');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('نورة الموسى').last);
    await tester.pumpAndSettle();

    // Beside the site's own phrase for this relationship rather than in the
    // bar: a screen can be showing several, and each is a different shape.
    await tester.tap(find.byTooltip('Draw this as a family tree'));
    await tester.pumpAndSettle();

    expect(find.byType(ChartCanvas), findsOne);
  });

  testWidgets('offers the ways of asking, and says which have no answer', (
    tester,
  ) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Relationship'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'نورة');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('نورة الموسى').last);
    await tester.pumpAndSettle();

    // A sister is reached through neither parent nor a marriage, so those
    // ways have nothing to say — and are shown saying so rather than hidden.
    ChoiceChip way(String label) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

    expect(way('Closest').selected, isTrue);
    expect(way('Closest').onSelected, isNotNull);
    for (final absent in const [
      'Father’s side',
      'Mother’s side',
      'Through a spouse',
    ]) {
      expect(way(absent).onSelected, isNull, reason: absent);
    }
  });

  testWidgets('can ask a blood-only site for any relationship', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Relationship'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'نورة');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('نورة الموسى').last);
    await tester.pumpAndSettle();

    // This site's own link says blood lines only, and webtrees reads that
    // number straight off the route — so the switch is a real request rather
    // than a note about a setting the reader cannot change.
    expect(find.text('Blood relatives only'), findsOne);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Any relationship'), findsOne);
    expect(server.routes, contains('/tree/main/relationships-0-3/X42/X43'));
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

  testWidgets('narrows the results without asking the server again', (
    tester,
  ) async {
    await openTree(tester);
    await search(tester, 'كثير');
    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();

    expect(find.text('خالد الموسى'), findsOne);
    final asked = server.routes.length;

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    // A birthplace the page states in an attribute nobody would look at,
    // which is the whole reason this filter costs no request.
    await tester.tap(find.text('الكويت، الكويت'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show 1 person'));
    await tester.pumpAndSettle();

    expect(find.text('عبد الله الموسى'), findsOne);
    expect(find.text('خالد الموسى'), findsNothing);
    // Says what it is doing, and against how many rows. `Show more` was
    // tapped and the site offered no further page, so those two rows are
    // every match there is — and the bar drops the word "loaded", which was
    // the apology `PROJECT.md` §9 #24 is about.
    expect(find.textContaining('Showing 1 of 2'), findsOne);
    expect(find.textContaining('loaded'), findsNothing);
    expect(server.routes.length, asked, reason: 'no further request');
  });

  testWidgets('a filter that hides everything says so', (tester) async {
    await openTree(tester);
    await search(tester, 'كثير');
    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    // Two narrowings, because one is never enough here: every place chip is
    // a place some loaded row names, so choosing one always keeps somebody.
    await tester.tap(find.text('مكة، السعودية'));
    await tester.pumpAndSettle();
    // From the end thumb rather than from the middle of the track: with the
    // whole span selected both thumbs sit at the edges, and a drag begun
    // halfway between them could take hold of either.
    final track = tester.getRect(find.byType(RangeSlider));
    await tester.dragFrom(
      Offset(track.right - 24, track.center.dy),
      Offset(-track.width, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show no matches'));
    await tester.pumpAndSettle();

    // Which is a different thing from a search that found nobody, and the
    // difference is worth a sentence.
    //
    // Every page has been fetched here, so the sentence is the *tree-wide*
    // one: nothing further can arrive to change the answer. On a search still
    // holding a further page it reads "None of the results loaded so far
    // match", which is the version `PROJECT.md` §9 #24 apologises for and the
    // next test pins down.
    expect(find.textContaining('Nobody in this tree matches'), findsOne);
    expect(find.textContaining('Showing 0 of 2'), findsOne);
  });

  testWidgets('a filter over a part-loaded search says only that much', (
    tester,
  ) async {
    await openTree(tester);
    await search(tester, 'كثير');
    // Deliberately *not* tapping `Show more`. The filter can only see the
    // first page, so every count it states is a count of *those* rows — and
    // the bar says "loaded" to admit it. That word is the apology
    // `PROJECT.md` §9 #24 is about, and the test above is what removes it:
    // once there is no further page, the same bar drops it.
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الكويت، الكويت'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show 1 person'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Showing 1 of 1 loaded'), findsOne);
  });

  testWidgets('a new search starts unfiltered', (tester) async {
    await openTree(tester);
    await search(tester, 'كثير');
    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مكة، السعودية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show 1 person'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Showing 1 of 2'), findsOne);

    // A filter chosen for one surname says nothing about the next, and one
    // left in force would look like a search that found less than it did.
    await search(tester, 'نورة');
    expect(find.text('نورة الموسى'), findsOne);
    expect(find.textContaining('Showing'), findsNothing);
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

  testWidgets('colours a relative by the sex their record states', (
    tester,
  ) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('فاطمة السالم'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final colours = PersonColors.of(
      tester.element(find.byType(Scaffold).first),
    );
    Color fillBehind(String name) {
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(of: find.text(name), matching: find.byType(DecoratedBox))
            .first,
      );
      return (box.decoration as BoxDecoration).color!;
    }

    // The father's initial sits on the blue container and the mother's on the
    // pink one — read from `wt-chart-box-m`/`-f`, not from the name.
    expect(fillBehind('م'), colours.male);
    expect(fillBehind('ف'), colours.female);
  });

  testWidgets('marks someone the tree records as dead', (tester) async {
    await openTree(tester);
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();

    // Read from the death event in the person's own chart box, not from the
    // years: a tree can record a death with no date at all.
    expect(find.text('Deceased'), findsOne);

    // Every portrait of them carries the ribbon, the one in the bar included.
    final portraits = tester
        .widgetList<AuthenticatedImage>(find.byType(AuthenticatedImage))
        .where((image) => image.name == 'عبد الله الموسى');
    expect(portraits, isNotEmpty);
    expect(portraits.every((image) => image.deceased), isTrue);
  });

  testWidgets('offers a site’s statistics from the tree screen', (
    tester,
  ) async {
    await openTree(tester);
    await tester.pumpAndSettle();

    // Statistics belong to a whole tree rather than to anybody in it, so the
    // link lives on the tree's own page — and the button appears only where
    // the site actually publishes them.
    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();

    expect(find.text('مجموع الأفراد'), findsOne);
    // A count as the site rendered it, in its own numerals — isolated so an
    // Arabic layout cannot reorder the digits around it.
    expect(find.textContaining('١٬٤٦٣'), findsOne);
    // And a chart the app drew for itself, from the numbers behind the
    // site's own.
    expect(find.text('الجنس'), findsOne);
    expect(find.text('ذكور'), findsOne);
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
      WebtreesMobileApp(
        session: session,
        settings: testSettings(),
        treeStore: TreeStore.none(),
      ),
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
