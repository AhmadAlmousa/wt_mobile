/// Turning the module's JSON into the app's own model.
///
/// The module was shaped to fill `domain/` rather than to be adapted into it,
/// so nearly everything here is a constructor call. What is left is the two
/// places where the JSON is deliberately *richer* than the model: a fact's
/// five-valued `origin`, which collapses onto one boolean, and a date's list
/// of per-calendar renderings, which becomes the piece structure
/// [RenderedDate] already uses to drop a calendar the reader did not ask for.
library;

import '../../domain/charts.dart';
import '../../domain/dates.dart';
import '../../domain/records.dart';
import '../../domain/statistics.dart';

/// Reads one person reference.
PersonRef personFrom(Map<String, Object?> json) => PersonRef(
  xref: stringOf(json['xref']) ?? '',
  name: stringOf(json['name']) ?? '',
  alternateName: stringOf(json['alternateName']),
  lifespan: stringOf(json['lifespan']),
  sex: sexFrom(stringOf(json['sex'])),
  isDeceased: json['deceased'] == true,
  thumbnailUrl: stringOf(json['thumbnail']),
  // Absent from module 1.1.1 and older. A filter with nothing to compare
  // leaves the row alone, so an older module costs the reader a narrower
  // filter rather than a wrong answer.
  birthYear: intOf(json['birthYear']),
  deathYear: intOf(json['deathYear']),
  birthPlace: stringOf(json['birthPlace']),
);

/// The GEDCOM sex the module states outright.
///
/// A stock instance renders it as a translated *word* on the individual page,
/// so the app has to find the person's own chart box on their relatives tab to
/// recover it — and search results never carry one at all.
Sex sexFrom(String? name) => switch (name) {
  'male' => Sex.male,
  'female' => Sex.female,
  // `other` is a real GEDCOM value (`1 SEX X`) the app draws no differently
  // from unknown, so it maps here rather than adding a case to every switch.
  _ => Sex.unknown,
};

/// Reads a date, keeping every calendar the site offers.
///
/// [RenderedDate.text] is the whole thing — the tree's own calendar and its
/// conversions — and the pieces beneath it let the reader ask for one. The
/// module sends each calendar separately with its GEDCOM escape attached,
/// which is the same statement a stock 2.2.6 page makes through the `cal`
/// parameter of a calendar link, and which 2.3 stopped making at all.
RenderedDate? dateFrom(Object? value) {
  if (value is! Map<String, Object?>) return null;

  final text = stringOf(value['text']);
  if (text == null) return null;

  final rendered = value['rendered'];
  if (rendered is! List || rendered.isEmpty) {
    return RenderedDate(text: text);
  }

  final values = <DateValue>[
    for (final entry in rendered)
      if (entry is Map<String, Object?>)
        DateValue(
          text: stringOf(entry['text']) ?? '',
          calendar: DateCalendar.fromGedcomEscape(stringOf(entry['escape'])),
        ),
  ];

  if (values.isEmpty) return RenderedDate(text: text);

  // The first is the calendar the tree records the date in; the rest are its
  // conversions, which is exactly the shape `inCalendar` walks.
  return RenderedDate(
    text: text,
    pieces: [
      DateValue(
        text: values.first.text,
        calendar: values.first.calendar,
        conversions: values.skip(1).toList(),
      ),
    ],
  );
}

/// Reads one fact.
FactEntry factFrom(Map<String, Object?> json) {
  final place = json['place'];

  return FactEntry(
    label: stringOf(json['label']) ?? '',
    // The bare GEDCOM word, for every fact — including a relative's death
    // under its own translated label, which no chart box ever prints and the
    // stock tag dictionary therefore never learns.
    tag: stringOf(json['tag']),
    value: stringOf(json['value']),
    date: dateFrom(json['date']),
    place: place is Map<String, Object?> ? stringOf(place['full']) : null,
    type: stringOf(json['type']),
    about: json['about'] is Map<String, Object?>
        ? personFrom(json['about']! as Map<String, Object?>)
        : null,
    // The module states which of the five lists a fact came from; the app
    // needs only the distinction webtrees itself draws when it renders the
    // last three collapsed.
    isSecondary: json['secondary'] == true,
  );
}

/// The lines that make a family a family, rather than things that happened
/// to it.
///
/// webtrees keeps `HUSB`, `WIFE` and `CHIL` in the same list as a marriage,
/// and a module that hands that list over unfiltered puts the word "son" on a
/// person's page once per son. The module answers only events now, and its
/// own family page has always filtered exactly these three — but which
/// version of the module a site runs is the site's choice, so the app drops
/// them again on the way in. It already has these people as `spouses` and
/// `children`.
const Set<String> _pointerTags = {'HUSB', 'WIFE', 'CHIL'};

/// Reads one family block.
FamilyGroup familyFrom(Map<String, Object?> json) => FamilyGroup(
  xref: stringOf(json['xref']) ?? '',
  label: stringOf(json['label']) ?? '',
  kind: switch (stringOf(json['kind'])) {
    'parents' => FamilyKind.parents,
    'step' => FamilyKind.step,
    _ => FamilyKind.own,
  },
  spouses: peopleFrom(json['spouses']),
  children: peopleFrom(json['children']),
  facts: factsFrom(
    json['facts'],
  ).where((fact) => !_pointerTags.contains(fact.tag)).toList(),
  endedInDivorce: json['endedInDivorce'] == true,
);

NoteEntry noteFrom(Map<String, Object?> json) => NoteEntry(
  label: stringOf(json['label']) ?? '',
  text: stringOf(json['text']) ?? '',
  xref: stringOf(json['xref']),
  isSecondary: json['secondary'] == true,
);

SourceCitation sourceFrom(Map<String, Object?> json) => SourceCitation(
  label: stringOf(json['label']) ?? '',
  title: stringOf(json['title']) ?? '',
  xref: stringOf(json['xref']),
  details: [
    for (final line in json['details'] is List ? json['details']! as List : [])
      if (line is String) line,
  ],
  isSecondary: json['secondary'] == true,
);

MediaItem mediaFrom(Map<String, Object?> json) {
  final files = json['files'];
  String? thumbnail;

  if (files is List) {
    for (final file in files) {
      if (file is Map<String, Object?> && file['isImage'] == true) {
        thumbnail = stringOf(file['url']);
        break;
      }
    }
  }

  return MediaItem(
    title: stringOf(json['title']) ?? '',
    xref: stringOf(json['xref']),
    thumbnailUrl: thumbnail,
    isSecondary: json['secondary'] == true,
  );
}

/// Reads an ancestor tree, which the module sends already nested.
AncestorNode? ancestorFrom(Object? value) {
  if (value is! Map<String, Object?>) return null;

  final person = value['person'];
  if (person is! Map<String, Object?>) return null;

  return AncestorNode(
    person: personFrom(person),
    // Computed server-side by webtrees' own rule and sent as a number, not as
    // the localized digits a rendered chart prints beside each box.
    sosa: intOf(value['sosa']) ?? 1,
    familyXref: stringOf(value['familyXref']),
    parentsLabel: stringOf(value['parentsLabel']),
    parents: [
      for (final parent in listOf(value['parents'])) ?ancestorFrom(parent),
    ],
  );
}

/// Reads a descendant tree.
DescendantNode? descendantFrom(Object? value) {
  if (value is! Map<String, Object?>) return null;

  final person = value['person'];
  if (person is! Map<String, Object?>) return null;

  return DescendantNode(
    person: personFrom(person),
    number: stringOf(value['number']) ?? '1',
    families: [
      for (final family in listOf(value['families']))
        if (family is Map<String, Object?>)
          DescendantFamily(
            xref: stringOf(family['xref']) ?? '',
            spouse: family['spouse'] is Map<String, Object?>
                ? personFrom(family['spouse']! as Map<String, Object?>)
                : null,
            label: stringOf(family['label']),
            endedInDivorce: family['endedInDivorce'] == true,
            children: [
              for (final child in listOf(family['children']))
                ?descendantFrom(child),
            ],
          ),
    ],
  );
}

/// Reads the datasets and counts behind a statistics page.
TreeStatistics statisticsFrom(Map<String, Object?> json) => TreeStatistics(
  parts: [
    for (final part in listOf(json['parts']))
      if (part is Map<String, Object?>)
        StatisticPart(
          title: stringOf(part['title']) ?? '',
          sections: [
            for (final section in listOf(part['sections']))
              if (section is Map<String, Object?>) _sectionFrom(section),
          ],
        ),
  ],
);

StatisticSection _sectionFrom(Map<String, Object?> json) => StatisticSection(
  title: stringOf(json['title']) ?? '',
  total: stringOf(json['total']),
  items: [
    for (final item in listOf(json['items']))
      if (item is Map<String, Object?>)
        StatisticItem(
          label: stringOf(item['label']) ?? '',
          // The site's own rendering, numerals and separators included.
          value: stringOf(item['value']),
        ),
  ],
  datasets: [
    for (final dataset in listOf(json['datasets']))
      if (dataset is Map<String, Object?>) _datasetFrom(dataset),
  ],
);

StatisticDataset _datasetFrom(Map<String, Object?> json) => StatisticDataset(
  title: stringOf(json['title']) ?? '',
  shape: StatisticShape.fromCall(stringOf(json['shape']) ?? ''),
  columns: [
    for (final column in listOf(json['columns']))
      if (column is String) column,
  ],
  rows: [
    for (final row in listOf(json['rows']))
      if (row is Map<String, Object?>)
        StatisticRow(
          label: stringOf(row['label']) ?? '',
          values: [for (final value in listOf(row['values'])) ?doubleOf(value)],
        ),
  ],
);

List<PersonRef> peopleFrom(Object? value) => [
  for (final person in listOf(value))
    if (person is Map<String, Object?>) personFrom(person),
];

List<FactEntry> factsFrom(Object? value) => [
  for (final fact in listOf(value))
    if (fact is Map<String, Object?>) factFrom(fact),
];

List<Object?> listOf(Object? value) => value is List ? value : const [];

String? stringOf(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? intOf(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  final String text => int.tryParse(text),
  _ => null,
};

double? doubleOf(Object? value) => switch (value) {
  final num number => number.toDouble(),
  final String text => double.tryParse(text),
  _ => null,
};

/// Reads a timeline: events with their own Julian days, and the range they
/// span.
///
/// A stock timeline states everything in **pixels** — a year label's position
/// and an event box's position, measured in the site's own drawing — so the
/// app compares one position with another and is careful never to read a year
/// out of one, because the box sits a few pixels above the line it points at.
///
/// Here the positions are Julian days. The scale is generated from the range
/// rather than read off the page, which is why the ticks are round decades:
/// nothing in the payload dictates where a label goes, so the app chooses.
TimelineChart timelineFrom(Map<String, Object?> json) {
  final events = <TimelineEvent>[];

  for (final event in listOf(json['events'])) {
    if (event is! Map<String, Object?>) continue;

    final day = doubleOf(event['julianDay']);
    final label = stringOf(event['summary']) ?? stringOf(event['label']);
    if (day == null || label == null) continue;

    events.add(TimelineEvent(label: label, position: day));
  }

  final range = json['range'];
  final from = range is Map<String, Object?> ? intOf(range['fromYear']) : null;
  final to = range is Map<String, Object?> ? intOf(range['toYear']) : null;

  return TimelineChart(ticks: _ticksBetween(from, to), events: events);
}

/// A tick every decade across the years the events cover.
///
/// Positioned in Julian days like the events, using the astronomical formula
/// for 1 January — which is arithmetic on a scale, not a conversion of
/// anybody's date. Every date a reader *sees* is still the server's own
/// rendering, in whichever calendars the tree converts to.
List<TimelineTick> _ticksBetween(int? from, int? to) {
  if (from == null || to == null || to < from) return const [];

  final first = (from ~/ 10) * 10;
  final last = ((to + 9) ~/ 10) * 10;

  // More than a couple of centuries and a decade tick every ten years is a
  // solid line, so the step widens with the span.
  final step = last - first > 200 ? 50 : 10;

  return [
    for (var year = first; year <= last; year += step)
      TimelineTick(year: year, position: _januaryFirst(year).toDouble()),
  ];
}

/// The Julian day number of 1 January in a Gregorian year.
int _januaryFirst(int year) {
  final a = (14 - 1) ~/ 12;
  final y = year + 4800 - a;
  final m = 1 + 12 * a - 3;

  return 1 +
      (153 * m + 2) ~/ 5 +
      365 * y +
      y ~/ 4 -
      y ~/ 100 +
      y ~/ 400 -
      32045;
}
