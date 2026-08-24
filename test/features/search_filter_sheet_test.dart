import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/domain/records.dart';
import 'package:webtrees_mobile/features/browse/search_filter.dart';
import 'package:webtrees_mobile/features/browse/search_filter_sheet.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';

/// The sheet, and the one thing about it that is not arithmetic: which
/// controls a reader is offered.
///
/// A stock instance and a module answer the same search with different
/// amounts of truth — the module states a sex and the page cannot — and the
/// sheet is built from the rows rather than from the transport, so this is
/// where that rule is checked against a real widget tree.
void main() {
  PersonRef person(
    String xref, {
    Sex sex = Sex.unknown,
    int? born,
    String? place,
    int? age,
  }) => PersonRef(
    xref: xref,
    name: xref,
    sex: sex,
    birthYear: born,
    birthPlace: place,
    age: age,
  );

  Future<void> open(
    WidgetTester tester,
    List<PersonRef> people, {
    SearchFilter filter = const SearchFilter(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: Scaffold(
          body: SearchFilterSheet(
            filter: filter,
            facets: SearchFacets.of(people),
            people: people,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Rows shaped as a stock instance sends them: years and places, no sex.
  final fromThePage = [
    person('A', born: 1901, place: 'الكويت، الكويت'),
    person('B', born: 1955, place: 'مكة، السعودية'),
    person('C'),
  ];

  /// The same people as the module states them — with a sex and an age the
  /// page could not have computed.
  final fromTheModule = [
    person('A', sex: Sex.male, born: 1901, place: 'الكويت، الكويت', age: 73),
    person('B', sex: Sex.female, born: 1955, place: 'مكة، السعودية', age: 40),
    person('C', sex: Sex.female),
  ];

  testWidgets('a stock instance offers years and places, not sex', (
    tester,
  ) async {
    await open(tester, fromThePage);

    expect(find.text('Year of birth'), findsOne);
    expect(find.text('Born at'), findsOne);
    // The autocomplete a stock site answers with says nothing about sex, so
    // the control that would filter on it is not there to be tapped.
    expect(find.text('Sex'), findsNothing);
    expect(find.text('Women'), findsNothing);
  });

  testWidgets('a module adds the sex the page could not state', (tester) async {
    await open(tester, fromTheModule);

    expect(find.text('Sex'), findsOne);
    expect(find.text('Men'), findsOne);
    expect(find.text('Women'), findsOne);
    // Offered beside the two, because a tree this old records plenty of
    // people whose sex nobody wrote down.
    expect(find.text('Not recorded'), findsOne);
  });

  testWidgets('an age takes the place of the years where one is known', (
    tester,
  ) async {
    await open(tester, fromTheModule);

    // Both answer "which generation", and an age answers it in days rather
    // than by subtracting one printed year from another — so only one slider
    // is offered, and it is the better one.
    expect(find.text('Age'), findsOne);
    expect(find.text('Year of birth'), findsNothing);

    await open(tester, fromThePage);
    expect(find.text('Age'), findsNothing);
    expect(find.text('Year of birth'), findsOne);
  });

  testWidgets('the age slider narrows to the people inside it', (tester) async {
    await open(tester, fromTheModule);

    final track = tester.getRect(find.byType(RangeSlider));
    await tester.dragFrom(
      Offset(track.right - 24, track.center.dy),
      Offset(-track.width, 0),
    );
    await tester.pumpAndSettle();

    // The forty-year-old, and the person the tree states no age for — who is
    // not somebody outside the range, only somebody it did not say.
    expect(find.text('Show 2 people'), findsOne);
  });

  testWidgets('the button says how many people the choice leaves', (
    tester,
  ) async {
    await open(tester, fromTheModule);

    expect(find.text('Show 3 people'), findsOne);

    await tester.tap(find.text('Women'));
    await tester.pumpAndSettle();

    // Counted before it is applied: a filter that hides everything and a
    // search that found nothing look identical afterwards.
    expect(find.text('Show 2 people'), findsOne);
  });

  testWidgets('the chosen filter comes back, and only when asked for', (
    tester,
  ) async {
    SearchFilter? chosen;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await SearchFilterSheet.show(
                  context,
                  filter: const SearchFilter(),
                  facets: SearchFacets.of(fromTheModule),
                  people: fromTheModule,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Women'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show 2 people'));
    await tester.pumpAndSettle();

    expect(chosen?.sexes, {Sex.female});
  });

  testWidgets('a place chip narrows to that place', (tester) async {
    await open(tester, fromThePage);

    await tester.tap(find.text('مكة، السعودية'));
    await tester.pumpAndSettle();

    // One of the three, and not the person whose birthplace is unrecorded:
    // asking for people born somewhere is asking about a stated place.
    expect(find.text('Show 1 person'), findsOne);
  });

  testWidgets('clearing puts everything back', (tester) async {
    await open(
      tester,
      fromTheModule,
      filter: const SearchFilter().withSexes({Sex.male}),
    );

    expect(find.text('Show 1 person'), findsOne);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Show 3 people'), findsOne);
  });

  testWidgets('nothing to narrow by is said rather than shown empty', (
    tester,
  ) async {
    await open(tester, [person('A'), person('B')]);

    expect(find.text('Year of birth'), findsNothing);
    expect(find.text('Born at'), findsNothing);
    expect(find.textContaining('Nothing to narrow'), findsOne);
  });
}
