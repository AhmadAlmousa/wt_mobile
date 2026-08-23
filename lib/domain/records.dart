import 'package:meta/meta.dart';

import 'charts.dart';
import 'dates.dart';
import 'notice.dart';

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
    this.isDeceased = false,
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

  /// Whether the tree records this person as no longer living.
  ///
  /// Read from the death event webtrees prints inside every chart box, not
  /// inferred from an age: a tree may record a death with no date at all, and
  /// it may record a birth two centuries ago for somebody it still lists as
  /// living. False therefore means "nothing said so", not "alive".
  final bool isDeceased;

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
    this.about,
    this.tag,
    this.isSecondary = false,
  });

  /// What webtrees calls this fact, already translated by the server.
  final String label;

  /// The GEDCOM tag behind [label] — `INDI:DEAT`, `FAM:DIV` — where the page
  /// said enough to know it.
  ///
  /// The label itself is translated, so an interface that switched on it
  /// would work in English and quietly do nothing in Arabic. The tag comes
  /// from a dictionary built out of the same page: see [FactTagIndex]. Null
  /// where the page named no tag, which every reader must survive.
  final String? tag;

  /// The fact's own value, where it has one beyond a date and a place.
  final String? value;

  /// The date exactly as webtrees rendered it, and the calendars it used.
  ///
  /// Never a `DateTime`. webtrees supports Gregorian, Julian, Hebrew, Hijri,
  /// French Republican and Jalali calendars, plus approximations (`about`,
  /// `between … and …`), and it has already done that formatting in the
  /// reader's language. Parsing it into a `DateTime` would discard the
  /// calendar, lose the qualifiers, and get the conversion wrong — so the
  /// structure exists only to *choose between* the calendars on offer.
  final RenderedDate? date;

  final String? place;

  /// A refinement of the label, from the fact's `TYPE` field.
  final String? type;

  /// Whose event this really is, when it is not this person's.
  ///
  /// webtrees folds a relative's birth and a family's marriage into the
  /// person's own list, and names the other record in `.wt-fact-record`.
  /// Without it "Birth of a sibling" says nothing about *which* sibling, and
  /// the reader has no way to walk to them.
  final PersonRef? about;

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
    List<FactEntry> facts = const [],
    this.endedInDivorce = false,
  }) : spouses = List.unmodifiable(spouses),
       children = List.unmodifiable(children),
       facts = List.unmodifiable(facts);

  /// The family record identifier, e.g. `F7`.
  final String xref;

  /// The heading webtrees gave this family, already translated.
  final String label;

  final FamilyKind kind;

  /// The couple. Usually two people, but webtrees records incomplete families.
  final List<PersonRef> spouses;

  final List<PersonRef> children;

  /// What happened to the couple — a marriage, a divorce.
  ///
  /// These belong to the family record rather than to either person, which is
  /// why they have to be read here: a marriage date shown against one spouse
  /// and not the other would be an odd thing to claim.
  final List<FactEntry> facts;

  /// Whether this couple separated — a divorce, an annulment.
  ///
  /// Worth its own field rather than left for each screen to look for: a
  /// chart draws the line between two people differently, and a chart has no
  /// fact rows to search.
  final bool endedInDivorce;
}

/// A note recorded against a person, or against one of their facts.
///
/// webtrees keeps both in one tab: a note about the person, and a note
/// hanging off their birth. The second kind is collapsed by the site itself,
/// so [isSecondary] carries that distinction rather than losing it.
@immutable
final class NoteEntry {
  const NoteEntry({
    required this.label,
    required this.text,
    this.xref,
    this.isSecondary = false,
  });

  /// What the note is attached to, in the site's own words — `Note` for one
  /// recorded against the person, the fact's own label for the rest.
  final String label;

  /// The note itself, exactly as webtrees rendered it.
  final String text;

  /// The record identifier when this is a *shared* note, e.g. `N3`.
  ///
  /// A shared note is a record of its own that several people may cite; a
  /// plain one is text inside this record and has no identifier.
  final String? xref;

  final bool isSecondary;

  @override
  String toString() => 'NoteEntry($label)';
}

/// One citation: the source a fact came from, and where in it to look.
@immutable
final class SourceCitation {
  SourceCitation({
    required this.label,
    required this.title,
    this.xref,
    List<String> details = const [],
    this.isSecondary = false,
  }) : details = List.unmodifiable(details);

  /// What this citation supports — the fact's label, or `Source` when it is
  /// cited against the person as a whole.
  final String label;

  /// The source record's title, as webtrees rendered it.
  final String title;

  /// The source record identifier, e.g. `S4`.
  final String? xref;

  /// The citation's own fields — page, quality, date — each already worded
  /// and translated by the server as `Page: 42`.
  ///
  /// Kept as the site's own sentences rather than as pairs to re-join here:
  /// webtrees translates the separator too, and rebuilding it in Dart would
  /// mean guessing at punctuation the site has already chosen.
  final List<String> details;

  final bool isSecondary;

  @override
  String toString() => 'SourceCitation($title)';
}

/// One media object linked to a person.
@immutable
final class MediaItem {
  const MediaItem({
    required this.title,
    this.xref,
    this.thumbnailUrl,
    this.isSecondary = false,
  });

  /// The media record's title, already rendered by the server.
  final String title;

  /// The media record identifier, e.g. `M11`.
  final String? xref;

  /// A signed thumbnail URL, which must be fetched through the session — see
  /// [PersonRef.thumbnailUrl].
  final String? thumbnailUrl;

  /// Whether this hangs off a fact rather than off the person.
  final bool isSecondary;

  @override
  String toString() => 'MediaItem($title)';
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
    this.lifespan,
    this.isDeceased = false,
    List<NoteEntry> notes = const [],
    List<SourceCitation> sources = const [],
    List<MediaItem> media = const [],
    List<String> sections = const [],
    Map<ChartKind, String> charts = const {},
    List<Notice> warnings = const [],
  }) : facts = List.unmodifiable(facts),
       families = List.unmodifiable(families),
       notes = List.unmodifiable(notes),
       sources = List.unmodifiable(sources),
       media = List.unmodifiable(media),
       sections = List.unmodifiable(sections),
       charts = Map.unmodifiable(charts),
       warnings = List.unmodifiable(warnings);

  final String xref;
  final String name;
  final String? alternateName;
  final String? thumbnailUrl;
  final Sex sex;

  /// Birth and death years as webtrees formats them, e.g. `1901–1974`.
  final String? lifespan;

  /// Whether the tree records this person as no longer living. See
  /// [PersonRef.isDeceased].
  final bool isDeceased;

  final List<FactEntry> facts;
  final List<FamilyGroup> families;

  /// Notes, source citations and photographs, when the tree offers those tabs.
  ///
  /// All three are optional modules a site may switch off — this project's own
  /// target has all three off — so an empty list means "this site does not
  /// publish them", not "this person has none".
  final List<NoteEntry> notes;
  final List<SourceCitation> sources;
  final List<MediaItem> media;

  /// Every tab this site offered on the page, by webtrees module name.
  ///
  /// Not used by the interface: it is what the diagnostics report, because
  /// which modules a site runs decides what the app can show at all, and no
  /// two instances agree. A custom tab appears here beside the core ones.
  final List<String> sections;

  /// The charts this site offers for this person, at the URLs it gave.
  ///
  /// Read from the page the app already fetched, so knowing what a site can
  /// draw costs nothing. The URLs carry that instance's own settings — how
  /// many generations its administrator chose — and are used as they arrived.
  final Map<ChartKind, String> charts;

  /// Parts that could not be read, named so the interface can say which.
  ///
  /// A tab may be switched off or restricted per tree, and markup drifts
  /// between themes and versions. Losing the relatives tab should cost the
  /// relatives section and say so — not the whole page.
  final List<Notice> warnings;

  /// This person as they would appear in a list.
  ///
  /// A record already holds everything a reference does, and every screen
  /// that shows a person beside their relatives needs them in the same shape
  /// the relatives arrive in.
  PersonRef get asReference => PersonRef(
    xref: xref,
    name: name,
    alternateName: alternateName,
    lifespan: lifespan,
    sex: sex,
    isDeceased: isDeceased,
    thumbnailUrl: thumbnailUrl,
  );

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
