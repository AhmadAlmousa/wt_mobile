import 'package:meta/meta.dart';

/// A person's recorded sex, as webtrees renders it.
enum Sex {
  male,
  female,
  unknown;

  /// Reads the `wt-chart-box-{sex}` suffix webtrees puts on every chart box.
  static Sex fromCssSuffix(String? suffix) => switch (suffix?.toLowerCase()) {
    'm' => Sex.male,
    'f' => Sex.female,
    _ => Sex.unknown,
  };
}

/// A person as they appear in a list: enough to show a row and open them.
///
/// Deliberately not the full record. Search results and relatives both arrive
/// this way, and fetching a whole individual for each one would cost a request
/// per row.
@immutable
final class PersonRef {
  const PersonRef({
    required this.xref,
    required this.name,
    this.alternateName,
    this.lifespan,
    this.sex = Sex.unknown,
    this.thumbnailUrl,
  });

  /// The record identifier, e.g. `X42`. Unique within a tree.
  final String xref;

  /// The rendered full name, with webtrees' own markup removed.
  final String name;

  /// A second name form, where the tree records one.
  ///
  /// Common in this project's target data: an Arabic tree often carries a
  /// romanized form alongside the Arabic one.
  final String? alternateName;

  /// Birth and death years as webtrees formats them, e.g. `1901–1974`.
  final String? lifespan;

  final Sex sex;

  /// An HMAC-signed thumbnail URL, absent when the person has no photo.
  ///
  /// Signed URLs cannot be constructed by the app — the key is server-side —
  /// so this is only ever harvested from rendered HTML. It is **not** an
  /// authorization token: webtrees still checks the viewer's own permission,
  /// so it must be fetched with the session cookies.
  final String? thumbnailUrl;

  @override
  bool operator ==(Object other) => other is PersonRef && other.xref == xref;

  @override
  int get hashCode => xref.hashCode;

  @override
  String toString() => 'PersonRef($xref, $name)';
}

/// One row of a person's facts table — a birth, a death, an occupation.
@immutable
final class FactEntry {
  const FactEntry({
    required this.label,
    this.value,
    this.date,
    this.place,
    this.type,
    this.isSecondary = false,
  });

  /// What webtrees calls this fact, already translated by the server.
  final String label;

  /// The fact's own value, where it has one beyond a date and a place.
  final String? value;

  /// The date exactly as webtrees rendered it.
  ///
  /// Kept as text on purpose. webtrees supports Gregorian, Julian, Hebrew,
  /// Hijri, French Republican and Jalali calendars, plus approximations
  /// (`about`, `between … and …`), and it has already done that formatting in
  /// the tree's language. Re-parsing it into a `DateTime` would discard the
  /// calendar, lose the qualifiers, and get the conversion wrong.
  final String? date;

  final String? place;

  /// A refinement of the label, from the fact's `TYPE` field.
  final String? type;

  /// Whether webtrees itself renders this collapsed by default.
  ///
  /// Facts of close relatives, historical events and associates are marked
  /// `collapse` in the markup — context rather than facts about this person,
  /// so the interface should keep them behind a disclosure too.
  final bool isSecondary;

  @override
  String toString() => 'FactEntry($label)';
}

/// Whether a family is the one a person was born into, or the one they made.
enum FamilyKind {
  /// The person appears here as a child: its spouses are their parents.
  parents,

  /// The person appears here as a spouse: its children are their children.
  own,

  /// The person does not appear in this family at all — a step-family.
  step,
}

/// One family block from the relatives tab.
@immutable
final class FamilyGroup {
  FamilyGroup({
    required this.xref,
    required this.label,
    required this.kind,
    required List<PersonRef> spouses,
    required List<PersonRef> children,
  }) : spouses = List.unmodifiable(spouses),
       children = List.unmodifiable(children);

  /// The family record identifier, e.g. `F7`.
  final String xref;

  /// The heading webtrees gave this family, already translated.
  final String label;

  final FamilyKind kind;

  /// The couple. Usually two people, but webtrees records incomplete families.
  final List<PersonRef> spouses;

  final List<PersonRef> children;
}

/// Everything the app read about one person.
@immutable
final class IndividualRecord {
  IndividualRecord({
    required this.xref,
    required this.name,
    required List<FactEntry> facts,
    required List<FamilyGroup> families,
    this.alternateName,
    this.thumbnailUrl,
    this.sex = Sex.unknown,
    List<String> warnings = const [],
  }) : facts = List.unmodifiable(facts),
       families = List.unmodifiable(families),
       warnings = List.unmodifiable(warnings);

  final String xref;
  final String name;
  final String? alternateName;
  final String? thumbnailUrl;
  final Sex sex;

  final List<FactEntry> facts;
  final List<FamilyGroup> families;

  /// Parts that could not be read, named so the interface can say which.
  ///
  /// A tab may be switched off or restricted per tree, and markup drifts
  /// between themes and versions. Losing the relatives tab should cost the
  /// relatives section and say so — not the whole page.
  final List<String> warnings;

  /// The facts worth showing without the user asking for more.
  Iterable<FactEntry> get primaryFacts =>
      facts.where((fact) => !fact.isSecondary);

  /// Both parents, from every family this person is a child in.
  Iterable<PersonRef> get parents => families
      .where((family) => family.kind == FamilyKind.parents)
      .expand((family) => family.spouses);

  /// Everyone sharing a parent family, excluding this person.
  Iterable<PersonRef> get siblings => families
      .where((family) => family.kind == FamilyKind.parents)
      .expand((family) => family.children)
      .where((person) => person.xref != xref);

  /// The other half of each family this person is a spouse in.
  Iterable<PersonRef> get spouses => families
      .where((family) => family.kind == FamilyKind.own)
      .expand((family) => family.spouses)
      .where((person) => person.xref != xref);

  Iterable<PersonRef> get children => families
      .where((family) => family.kind == FamilyKind.own)
      .expand((family) => family.children);
}
