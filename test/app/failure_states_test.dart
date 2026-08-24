import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/app/app.dart';
import 'package:webtrees_mobile/data/local/tree_store.dart';
import 'package:webtrees_mobile/data/session_manager.dart';
import 'package:webtrees_mobile/data/settings_store.dart';
import 'package:webtrees_mobile/features/shared/message_panel.dart';

import '../support/fake_webtrees.dart';
import '../support/test_app.dart';

/// What every screen does when the thing it needs does not arrive.
///
/// The happy paths are covered elsewhere, screen by screen. These are the
/// other half, and they matter more than usual here: this app reads somebody
/// else's webtrees install over markup that differs by version, theme and
/// module configuration, so a section that cannot be read is an *ordinary*
/// outcome rather than an exceptional one.
///
/// The property being asserted is the same everywhere and is deliberately
/// modest: **a failure is visible, and it is specific.** Not a spinner that
/// never stops, not an empty list that reads as "this person has no family",
/// and not "something went wrong" where the app knows more than that.
void main() {
  late FakeWebtrees server;
  late SessionManager session;
  late SettingsStore settings;

  String fixture(String name) =>
      File('test/fixtures/v2_2_6/$name').readAsStringSync();

  String searchJson() => jsonEncode({
    'data': [
      {
        'value': 'X42',
        'text':
            '<span class="NAME" dir="auto">عبد الله '
            '<span class="SURN">الموسى</span></span>, 1901–1974',
      },
    ],
    'nextUrl': null,
  });

  /// A working site, then whatever this test wants to break on top of it.
  Map<String, Canned Function(Sent)> siteWith(
    Map<String, Canned Function(Sent)> broken,
  ) => {
    ...workingSite(),
    '/tree/main/tom-select-individual': (_) =>
        Canned(200, body: searchJson(), contentType: 'application/json'),
    '/tree/main/individual/X42': (_) =>
        Canned(200, body: fixture('individual_page.html')),
    '/module/personal_facts/Tab/main': (_) =>
        Canned(200, body: fixture('tab_personal_facts.html')),
    '/module/relatives/Tab/main': (_) =>
        Canned(200, body: fixture('tab_relatives.html')),
    '/tree/main/ancestors-tree-4/X42': (_) =>
        Canned(200, body: fixture('chart_ancestors.html')),
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
    ...broken,
  };

  Future<void> signIn(
    WidgetTester tester,
    Map<String, Canned Function(Sent)> broken,
  ) async {
    server = FakeWebtrees(siteWith(broken));
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

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  Future<void> openPerson(WidgetTester tester) async {
    await search(tester, 'الموسى');
    await tester.tap(find.text('عبد الله الموسى'));
    await tester.pumpAndSettle();
  }

  /// The panel the app shows a reader when something failed.
  Finder problem() => find.byWidgetPredicate(
    (widget) => widget is MessagePanel && widget.tone == MessageTone.error,
  );

  testWidgets('a search that fails says so rather than finding nobody', (
    tester,
  ) async {
    await signIn(tester, {
      '/tree/main/tom-select-individual': (_) => const Canned(500),
    });
    await search(tester, 'الموسى');

    // "Nobody matched" and "the search broke" are different sentences, and
    // showing the first for the second is how a reader concludes their
    // grandmother is not in the tree.
    expect(problem(), findsOne);
    expect(find.textContaining('500'), findsOne);
  });

  testWidgets('a person who cannot be fetched is named as missing', (
    tester,
  ) async {
    await signIn(tester, {
      '/tree/main/individual/X42': (_) => const Canned(404),
    });
    await openPerson(tester);

    expect(problem(), findsOne);
    expect(
      find.text('That item does not exist, or is not visible to you.'),
      findsOne,
    );
  });

  testWidgets('markup the parsers cannot read names the parser', (
    tester,
  ) async {
    await signIn(tester, {
      // A theme this app has never seen: a page that is valid HTML and holds
      // none of the shapes the parser looks for.
      '/tree/main/individual/X42': (_) =>
          const Canned(200, body: '<html><body><p>A page.</p></body></html>'),
    });
    await openPerson(tester);

    expect(problem(), findsOne);
    // Specific enough to act on: which parser, not "something went wrong".
    expect(find.textContaining('theme'), findsOne);
  });

  testWidgets('a tab that will not load is a warning, not a blank section', (
    tester,
  ) async {
    await signIn(tester, {
      '/module/relatives/Tab/main': (_) => const Canned(500),
    });
    await openPerson(tester);

    // A warning rather than an error: the rest of the record is readable, and
    // an empty family list would otherwise read as a person with no family.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MessagePanel && widget.tone == MessageTone.warning,
      ),
      findsWidgets,
    );
  });

  testWidgets('a chart that will not draw says so', (tester) async {
    await signIn(tester, {
      '/tree/main/ancestors-tree-4/X42': (_) => const Canned(500),
    });
    await openPerson(tester);

    await tester.tap(find.text('Ancestors'));
    await tester.pumpAndSettle();

    expect(problem(), findsOne);
  });

  testWidgets('a timeline that will not load says so', (tester) async {
    await signIn(tester, {'/tree/main/timeline-10': (_) => const Canned(500)});
    await openPerson(tester);

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();

    expect(problem(), findsOne);
  });

  testWidgets('statistics that will not load say so', (tester) async {
    await signIn(tester, {
      '/module/statistics_chart/Chart/main': (_) => const Canned(500),
    });

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();

    expect(problem(), findsOne);
  });

  testWidgets('an account whose access cannot be read is not left blank', (
    tester,
  ) async {
    await signIn(tester, const {});

    // Sign-in reads the account page once; breaking it afterwards is what a
    // session dying between screens looks like.
    server.handlers['/my-account'] = (_) => const Canned(500);

    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pumpAndSettle();

    expect(problem(), findsOne);
  });
}
