/// Narrowing a page of search results without asking the server again.
///
/// A common surname in this family matches hundreds of people, and the thing
/// a reader is usually doing next is one of three: looking for the women,
/// looking for a generation, or looking for the branch that stayed in one
/// town. Each of those is a property of rows the app already has, so each is
/// answered here rather than by a second request against somebody else's
/// server.
///
/// **What is filtered on is what the transport stated.** A stock instance
/// puts a birth year and a birthplace in the title attribute of every search
/// row and never states a sex; the module states all three. So a filter is
/// offered when the rows can answer it and not otherwise — see
/// [SearchFacets], which reads that off the results themselves rather than
/// asking which transport answered.
///
/// **A row that does not say is kept.** A person with no recorded birth is
/// not a person born outside the range: hiding them would be an assertion the
/// tree never made, and the tree not saying is the ordinary case.
library;

import 'package:meta/meta.dart';

import '../../domain/records.dart';

/// What the reader has narrowed the results to.
@immutable
final class SearchFilter {
  const SearchFilter({
    this.sexes = const {},
    this.bornFrom,
    this.bornTo,
    this.birthPlace,
  });

  /// The sexes to keep, or empty for all of them.
  ///
  /// A set rather than one value: "the women" and "everybody whose sex the
  /// tree does not record" are both ordinary things to ask for, and a tree
  /// this old holds plenty of the second.
  final Set<Sex> sexes;

  /// The earliest and latest year of birth to keep, inclusive.
  ///
  /// Years as the site counts them — see [PersonRef.birthYear]. Null at
  /// either end means unbounded there.
  final int? bornFrom;
  final int? bornTo;

  /// The birthplace to keep, matched as the site wrote it.
  ///
  /// One of the places the results actually name rather than free text: a
  /// place in this tree is `الكويت، الكويت`, and asking a reader to type that
  /// on a phone would be a filter nobody uses. Matched as a *suffix-aware*
  /// containment so that choosing a country keeps the towns inside it — see
  /// [_placeMatches].
  final String? birthPlace;

  bool get isEmpty =>
      sexes.isEmpty && bornFrom == null && bornTo == null && birthPlace == null;

  /// How many separate narrowings are in force, for a badge on the button.
  int get count =>
      (sexes.isEmpty ? 0 : 1) +
      (bornFrom == null && bornTo == null ? 0 : 1) +
      (birthPlace == null ? 0 : 1);

  /// Whether [person] survives this filter.
  bool matches(PersonRef person) {
    if (sexes.isNotEmpty && !sexes.contains(person.sex)) return false;

    final born = person.birthYear;
    // Only where the tree said. A row with no year is not a row outside the
    // range — see the note at the top of this library.
    if (born != null) {
      if (bornFrom != null && born < bornFrom!) return false;
      if (bornTo != null && born > bornTo!) return false;
    }

    final place = birthPlace;
    if (place != null && !_placeMatches(person.birthPlace, place)) return false;

    return true;
  }

  /// Everyone in [people] this filter keeps, in the order they arrived.
  List<PersonRef> applyTo(List<PersonRef> people) => isEmpty
      ? people
      : [
          for (final person in people)
            if (matches(person)) person,
        ];

  SearchFilter withSexes(Set<Sex> sexes) => SearchFilter(
    sexes: sexes,
    bornFrom: bornFrom,
    bornTo: bornTo,
    birthPlace: birthPlace,
  );

  SearchFilter withYears(int? from, int? to) => SearchFilter(
    sexes: sexes,
    bornFrom: from,
    bornTo: to,
    birthPlace: birthPlace,
  );

  SearchFilter withBirthPlace(String? place) => SearchFilter(
    sexes: sexes,
    bornFrom: bornFrom,
    bornTo: bornTo,
    birthPlace: place,
  );

  /// Whether a person born at [recorded] belongs under the chosen [wanted].
  ///
  /// webtrees writes a place from the smallest part outwards — `مكة، السعودية`
  /// — so a country is the *end* of every place inside it. Matching a chosen
  /// place either exactly or as the tail of a longer one is therefore what
  /// makes choosing a country keep its towns, without this code knowing which
  /// level of a hierarchy it was handed or what separates them.
  static bool _placeMatches(String? recorded, String wanted) {
    if (recorded == null) return false;
    if (recorded == wanted) return true;
    return recorded.endsWith(wanted);
  }

  @override
  bool operator ==(Object other) =>
      other is SearchFilter &&
      other.bornFrom == bornFrom &&
      other.bornTo == bornTo &&
      other.birthPlace == birthPlace &&
      other.sexes.length == sexes.length &&
      other.sexes.containsAll(sexes);

  @override
  int get hashCode =>
      Object.hash(bornFrom, bornTo, birthPlace, Object.hashAllUnordered(sexes));
}

/// What the results on screen can actually be filtered by.
///
/// Read off the rows rather than from the transport that fetched them, which
/// is what keeps the interface honest on both: a stock instance never states
/// a sex, so no sex is offered; a module does, so it is. Nothing has to ask
/// which one answered, and a module that gains a field later needs no change
/// here.
@immutable
final class SearchFacets {
  SearchFacets._({
    required Set<Sex> sexes,
    required List<String> places,
    required this.earliestBirth,
    required this.latestBirth,
  }) : sexes = Set.unmodifiable(sexes),
       places = List.unmodifiable(places);

  factory SearchFacets.of(List<PersonRef> people) {
    final sexes = <Sex>{};
    final places = <String>{};
    int? earliest;
    int? latest;

    for (final person in people) {
      if (person.sex != Sex.unknown) sexes.add(person.sex);
      final place = person.birthPlace;
      if (place != null && place.isNotEmpty) places.add(place);

      final born = person.birthYear;
      if (born != null) {
        if (earliest == null || born < earliest) earliest = born;
        if (latest == null || born > latest) latest = born;
      }
    }

    // Offered only once some row states one, so a tree that records no sex at
    // all is not given a control that would hide everybody.
    if (sexes.isNotEmpty) sexes.add(Sex.unknown);

    return SearchFacets._(
      sexes: sexes,
      places: places.toList()..sort(),
      earliestBirth: earliest,
      latestBirth: latest,
    );
  }

  /// The sexes worth offering, empty when no row states one.
  final Set<Sex> sexes;

  /// Every birthplace the results name, in order.
  final List<String> places;

  /// The span of birth years the results cover.
  ///
  /// The slider is built from *these* rather than from a fixed range, which
  /// is the only way one control works for a tree of Gregorian years and a
  /// tree of Hijri ones: whatever the site counts in, the ends of the slider
  /// are two years it printed.
  final int? earliestBirth;
  final int? latestBirth;

  bool get offersSex => sexes.isNotEmpty;
  bool get offersPlace => places.isNotEmpty;

  /// Whether there is a *range* of years to slide through. One year, or none,
  /// is not a slider.
  bool get offersYears =>
      earliestBirth != null &&
      latestBirth != null &&
      latestBirth! > earliestBirth!;

  /// Whether anything at all can be narrowed.
  bool get isEmpty => !offersSex && !offersPlace && !offersYears;
}
