import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/domain/numerals.dart';
import 'package:webtrees_mobile/domain/records.dart';
import 'package:webtrees_mobile/features/browse/search_filter.dart';

PersonRef person(
  String xref, {
  Sex sex = Sex.unknown,
  int? born,
  int? died,
  String? place,
  int? age,
}) => PersonRef(
  xref: xref,
  name: xref,
  sex: sex,
  birthYear: born,
  deathYear: died,
  birthPlace: place,
  age: age,
);

void main() {
  group('reading a number in the site’s own numerals', () {
    test('Latin digits', () => expect(readNumber('1901'), 1901));

    // The one this project exists for.
    test('Arabic-Indic digits', () => expect(readNumber('١٩٠١'), 1901));

    test('Extended Arabic-Indic, as Persian and Urdu render', () {
      expect(readNumber('۱۹۰۱'), 1901);
    });

    test('digits inside words', () => expect(readNumber('حوالي ١٨٧٥'), 1875));

    test('a range answers its first number', () {
      // Which is what a lifespan is, and the birth is the first half of it.
      expect(readNumber('1901–1974'), 1901);
      expect(readNumber('١٩٠١–١٩٧٤'), 1901);
    });

    test('the ellipsis webtrees prints for an unknown year is nothing', () {
      expect(readNumber('…'), isNull);
      expect(readNumber(''), isNull);
      expect(readNumber(null), isNull);
    });
  });

  group('what a filter can be built from', () {
    test('a stock search row offers years and places, never a sex', () {
      // Exactly what the autocomplete states: `Individual::lifespan()` puts a
      // place and a date in the title of each year it prints, and nothing on
      // that row says anything about sex.
      final facets = SearchFacets.of([
        person('A', born: 1901, place: 'الكويت، الكويت'),
        person('B', born: 1935),
      ]);

      expect(facets.offersSex, isFalse);
      expect(facets.offersYears, isTrue);
      expect(facets.offersPlace, isTrue);
      expect(facets.places, ['الكويت، الكويت']);
    });

    test('a module row offers a sex, and "not recorded" beside it', () {
      final facets = SearchFacets.of([
        person('A', sex: Sex.male),
        person('B', sex: Sex.female),
        person('C'),
      ]);

      expect(facets.sexes, {Sex.male, Sex.female, Sex.unknown});
    });

    test('a tree that records no sex at all is offered no sex filter', () {
      // Otherwise the control would be a single "not recorded" chip that
      // hides nobody, which is a promise with nothing behind it.
      expect(SearchFacets.of([person('A'), person('B')]).offersSex, isFalse);
    });

    test('the slider spans the years these results actually cover', () {
      final facets = SearchFacets.of([
        person('A', born: 1901),
        person('B', born: 1974),
        person('C'),
      ]);

      expect(facets.earliestBirth, 1901);
      expect(facets.latestBirth, 1974);
    });

    test('an age is offered where the rows can be asked it', () {
      final facets = SearchFacets.of([
        person('A', born: 1901, age: 73),
        person('B', born: 1955, age: 40),
      ]);

      expect(facets.offersAges, isTrue);
      expect(facets.youngest, 40);
      expect(facets.oldest, 73);
    });

    // The two answer the same question and an age answers it better: it is
    // measured in days, so a tree that records a Hijri birth beside a
    // Gregorian death gets one scale rather than two six hundred years apart.
    test('and the birth years step aside when it is', () {
      final withAges = SearchFacets.of([
        person('A', born: 1318, age: 75),
        person('B', born: 1955, age: 40),
      ]);
      expect(withAges.offersAges, isTrue);
      expect(withAges.offersYears, isFalse);

      // Nothing states an age on a stock instance, and there the printed
      // years are the honest answer rather than no answer at all.
      final withoutAges = SearchFacets.of([
        person('A', born: 1901),
        person('B', born: 1955),
      ]);
      expect(withoutAges.offersAges, isFalse);
      expect(withoutAges.offersYears, isTrue);
    });

    test('one year is not a range, and no year is not a slider', () {
      expect(SearchFacets.of([person('A', born: 1901)]).offersYears, isFalse);
      expect(SearchFacets.of([person('A')]).offersYears, isFalse);
    });

    test('nothing to narrow by is said out loud', () {
      expect(SearchFacets.of([person('A'), person('B')]).isEmpty, isTrue);
    });
  });

  group('narrowing the results', () {
    final people = [
      person('A', sex: Sex.male, born: 1901, place: 'الكويت، الكويت'),
      person('B', sex: Sex.female, born: 1935, place: 'مكة، السعودية'),
      person('C', sex: Sex.female, born: 1970),
      person('D'),
    ];

    test('an empty filter keeps the list it was given', () {
      const filter = SearchFilter();
      expect(filter.isEmpty, isTrue);
      expect(filter.applyTo(people), same(people));
    });

    test('by sex', () {
      final women = const SearchFilter().withSexes({Sex.female});
      expect(women.applyTo(people).map((p) => p.xref), ['B', 'C']);
    });

    test('by sex, including the ones the tree never recorded', () {
      final filter = const SearchFilter().withSexes({Sex.female, Sex.unknown});
      expect(filter.applyTo(people).map((p) => p.xref), ['B', 'C', 'D']);
    });

    test('by year of birth', () {
      final filter = const SearchFilter().withYears(1930, 1980);
      // B and C are inside it; A is too early; D says nothing.
      expect(filter.applyTo(people).map((p) => p.xref), ['B', 'C', 'D']);
    });

    // The rule the whole library turns on. A tree records a birth for maybe
    // half its people, and hiding the rest would assert something it never
    // said — the reader asked for a range of years, not for "everybody the
    // tree dates".
    test('a person with no recorded birth survives a year filter', () {
      final filter = const SearchFilter().withYears(1900, 1910);
      expect(filter.applyTo(people).map((p) => p.xref), ['A', 'D']);
    });

    test('by age, whether it was reached or is still being lived', () {
      final mixed = [
        // Two dead men and a living one, and the reader asking for people in
        // their seventies means all three kinds.
        person('A', age: 75),
        person('B', age: 40),
        person('C', age: 73),
        person('D'),
      ];
      final filter = const SearchFilter().withAges(70, 80);

      expect(filter.applyTo(mixed).map((p) => p.xref), ['A', 'C', 'D']);
    });

    test('a person the tree states no age for survives an age filter', () {
      // The same rule as the years: a tree that recorded no birth has not
      // said this person is outside the range.
      final filter = const SearchFilter().withAges(0, 10);
      expect(filter.applyTo([person('A')]).map((p) => p.xref), ['A']);
    });

    test('an age and a year of birth are different narrowings', () {
      final filter = const SearchFilter().withAges(1, 2).withYears(3, 4);

      expect(filter.agedFrom, 1);
      expect(filter.bornFrom, 3);
      expect(filter.count, 2);
    });

    test('by birthplace, exactly as the site wrote it', () {
      final filter = const SearchFilter().withBirthPlace('مكة، السعودية');
      expect(filter.applyTo(people).map((p) => p.xref), ['B']);
    });

    // webtrees writes a place smallest-part-first, so a country is the tail
    // of every place inside it — which is what lets one chip mean "anywhere
    // in Saudi Arabia" without this code knowing what a country is.
    test('choosing a country keeps the towns inside it', () {
      final filter = const SearchFilter().withBirthPlace('السعودية');
      expect(filter.applyTo(people).map((p) => p.xref), ['B']);
    });

    test('a person with no recorded birthplace is not "anywhere"', () {
      // Unlike a year: asking for people born in Kuwait is asking about a
      // stated place, and an unstated one is not it.
      final filter = const SearchFilter().withBirthPlace('الكويت، الكويت');
      expect(filter.applyTo(people).map((p) => p.xref), ['A']);
    });

    test('narrowings compound', () {
      final filter = const SearchFilter()
          .withSexes({Sex.female})
          .withYears(1960, 1980);
      expect(filter.applyTo(people).map((p) => p.xref), ['C']);
      expect(filter.count, 2);
    });

    test('the badge counts narrowings, not people', () {
      expect(const SearchFilter().count, 0);
      expect(const SearchFilter().withBirthPlace('x').count, 1);
      expect(const SearchFilter().withYears(1900, null).count, 1);
      expect(const SearchFilter().withYears(null, 1900).count, 1);
    });

    test('two filters that say the same thing are the same filter', () {
      expect(
        const SearchFilter().withSexes({Sex.male, Sex.female}),
        const SearchFilter().withSexes({Sex.female, Sex.male}),
      );
    });
  });
}
