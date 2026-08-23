import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/data/stock/record_parser.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/dates.dart';
import 'package:webtrees_mobile/domain/records.dart';

/// Every webtrees version the parsers claim to support.
///
/// Each case runs against both. The versions are not cosmetically different:
/// 2.2.6 gives a tab anchor no `id` at all, so a parser that keys on it finds
/// no tabs whatsoever — and 2.2.6 is what this project's own server runs.
const versions = ['v2_2_6', 'v2_3'];

String fixture(String version, String name) =>
    File('test/fixtures/$version/$name').readAsStringSync();

void main() {
  for (final version in versions) {
    group('$version individual page', () {
      late IndividualPage page;

      setUp(() {
        page = const RecordParser().parseIndividualPage(
          fixture(version, 'individual_page.html'),
          xref: 'X42',
        );
      });

      test('reads the name without the lifespan the title appends', () {
        expect(page.name, 'عبد الله الموسى');
      });

      test('keeps the second recorded name', () {
        // An Arabic tree commonly carries a romanized form alongside. Dropping
        // it would look to the family like the app lost their data.
        expect(page.alternateName, 'Abdullah Almousa');
      });

      test('finds every tab the site offers', () {
        expect(
          page.tabs.keys,
          containsAll(<String>['personal_facts', 'relatives', 'media']),
        );
      });

      test('takes each tab URL from the server verbatim', () {
        // The two versions place the tree differently — a path segment in 2.3,
        // a query parameter in 2.2.6. Reading the URL rather than building it
        // is what makes that difference cost nothing.
        expect(page.tabs['relatives'], contains('/module/relatives/Tab'));
        expect(page.tabs['relatives'], contains('xref=X42'));
      });

      test('finds the signed thumbnail', () {
        expect(page.thumbnailUrl, contains('media-thumbnail/M11/1'));
        expect(page.thumbnailUrl, contains('s=6f1c9a0b2e'));
      });

      test('finds the charts this site draws for this person', () {
        // Discovered the same way tabs are: webtrees marks its own links with
        // a class per chart, so a site with a chart module switched off
        // simply never emits one.
        expect(
          page.charts.keys,
          containsAll(<ChartKind>[
            ChartKind.ancestors,
            ChartKind.descendants,
            ChartKind.fan,
          ]),
        );
      });

      test('takes each chart URL from the server verbatim', () {
        // The URL carries the number of generations this site's administrator
        // settled on. Rebuilding it would quietly overrule them.
        expect(
          page.charts[ChartKind.ancestors],
          '/tree/main/ancestors-tree-4/X42',
        );
        expect(
          page.charts[ChartKind.descendants],
          contains('descendants-tree-3'),
        );
      });

      test('reports no inline content when every tab loads over ajax', () {
        expect(page.inlineTabs, isEmpty);
      });

      test('names itself when the markup is unrecognisable', () {
        // A blank section is the worst failure mode for a parser; the error
        // has to say which parser gave up and what it wanted.
        const parser = RecordParser(version: '9.9');
        try {
          parser.parseIndividualPage('<html><body>?</body></html>', xref: 'X1');
          fail('expected a ParseFailure');
        } on ParseFailure catch (problem) {
          expect(problem.diagnostic, contains('individual page'));
          expect(problem.diagnostic, contains('wt-page-title'));
          expect(problem.diagnostic, contains('9.9'));
        }
      });
    });

    group('$version facts tab', () {
      late List<FactEntry> facts;

      setUp(() {
        facts = const RecordParser().parseFacts(
          fixture(version, 'tab_personal_facts.html'),
        );
      });

      test('reads label, date and place', () {
        final birth = facts.first;
        expect(birth.label, 'الميلاد');
        expect(birth.date?.text, contains('مارس'));
        expect(birth.place, 'الرياض, السعودية');
      });

      test('keeps the calendar conversion webtrees rendered', () {
        // The date stays as webtrees wrote it precisely so the Hijri
        // conversion survives. Parsing it into a DateTime would throw the
        // second calendar away.
        expect(facts.first.date?.text, contains('ذو القعدة'));
      });

      test('strips the computed ages from the date', () {
        // "Father's age: 32" shares the date's box but is not part of it.
        expect(facts.first.date?.text, isNot(contains('32')));
        expect(facts.last.date?.text, isNot(contains('73')));
      });

      test('shows both calendars unless asked otherwise', () {
        expect(
          facts.first.date?.display(CalendarView.both),
          facts.first.date?.text,
        );
      });

      test('reads a value and its type', () {
        final occupation = facts.firstWhere((f) => f.label == 'المهنة');
        expect(occupation.value, 'تاجر');
        expect(occupation.type, 'Merchant');
      });

      test("marks a relative's event as secondary", () {
        final relative = facts.firstWhere((f) => f.label == 'وفاة الأب');
        expect(relative.isSecondary, isTrue);
        expect(facts.first.isSecondary, isFalse);
      });

      test('offers only the person’s own facts as primary', () {
        expect(
          const RecordParser()
              .parseFacts(fixture(version, 'tab_personal_facts.html'))
              .where((f) => !f.isSecondary)
              .map((f) => f.label),
          isNot(contains('وفاة الأب')),
        );
      });

      test('names the relative a secondary fact really belongs to', () {
        // "Death of a father" is not a fact about this person, and without
        // the name in `.wt-fact-record` it does not say whose death it was —
        // nor give the reader anywhere to go from it.
        final relative = facts.firstWhere((f) => f.label == 'وفاة الأب');
        expect(relative.about?.xref, 'X7');
        expect(relative.about?.name, 'محمد الموسى');
        // The person's own facts have nobody else attached.
        expect(facts.first.about, isNull);
      });

      test('drops a fact awaiting deletion', () {
        // v1 cannot edit, so showing a record queued for removal would only
        // mislead — the web interface strikes it through instead.
        expect(facts.map((f) => f.label), isNot(contains('حدث محذوف')));
      });
    });

    group('$version relatives tab', () {
      late List<FamilyGroup> families;

      setUp(() {
        families = const RecordParser().parseRelatives(
          fixture(version, 'tab_relatives.html'),
          xref: 'X42',
        );
      });

      test('ignores the tab’s own controls', () {
        // The date-differences toggle is a table too, but has no family
        // caption.
        expect(families.map((f) => f.xref), ['F1', 'F2', 'F3']);
      });

      test('tells a birth family from the person’s own', () {
        // Decided by where X42 appears, not by reading the caption — the
        // captions here are Arabic, and a label-driven parser would work only
        // in English.
        expect(families.first.kind, FamilyKind.parents);
        expect(families.last.kind, FamilyKind.own);
      });

      test('reads parents from the birth family', () {
        final parser = const RecordParser();
        final record = IndividualRecord(
          xref: 'X42',
          name: 'x',
          facts: const [],
          families: parser.parseRelatives(
            fixture(version, 'tab_relatives.html'),
            xref: 'X42',
          ),
        );

        expect(record.parents.map((p) => p.xref), ['X7', 'X8']);
        expect(record.siblings.map((p) => p.xref), ['X43']);
        // Two marriages, and both of them the person's own.
        expect(record.spouses.map((p) => p.xref), ['X50', 'X51']);
        expect(record.children.map((p) => p.xref), ['X60', 'X61', 'X62']);
      });

      test('does not count the person as their own sibling', () {
        final record = IndividualRecord(
          xref: 'X42',
          name: 'x',
          facts: const [],
          families: families,
        );
        expect(record.siblings.map((p) => p.xref), isNot(contains('X42')));
        expect(record.spouses.map((p) => p.xref), isNot(contains('X42')));
      });

      test('reads name, alternate name, lifespan and sex of a relative', () {
        final father = families.first.spouses.first;
        expect(father.xref, 'X7');
        expect(father.name, 'محمد الموسى');
        expect(father.alternateName, 'Mohammed Almousa');
        expect(father.lifespan, '1869–1930');
        expect(father.sex, Sex.male);
      });

      test('leaves the alternate name null when the box is empty', () {
        // webtrees always emits the element; only sometimes its content.
        expect(families.first.spouses.last.alternateName, isNull);
      });

      test('picks up a relative’s thumbnail', () {
        expect(
          families.first.spouses.first.thumbnailUrl,
          contains('media-thumbnail/M3/1'),
        );
        expect(families.first.spouses.last.thumbnailUrl, isNull);
      });

      test('reads the family label for display', () {
        expect(families.first.label, 'الوالدان');
      });

      test('keeps the marriage the couple’s own row carries', () {
        // The marriage belongs to the family, not to either person, and this
        // row is the only place the relatives tab states it. Dropping it left
        // a couple on screen with nothing said about them.
        final marriage = families[1].facts.single;
        expect(marriage.label, 'الزواج');
        expect(marriage.value, '1925 — مكة');
      });

      test('names each fact by its tag, not by its translated label', () {
        // The dictionary comes from the chart boxes on this very page, so it
        // is this site's own Arabic that maps onto GEDCOM — nothing here
        // knows the English word for a marriage.
        expect(families[1].facts.single.tag, 'MARR');
        expect(families.last.facts.map((fact) => fact.tag), ['MARR', 'DIV']);
      });

      test('tells which marriage ended in divorce', () {
        // Per family, not per person: this man married twice and the second
        // family is the one that ended.
        expect(families[1].endedInDivorce, isFalse);
        expect(families.last.endedInDivorce, isTrue);
      });

      test('reads who has died from the chart box, not from an age', () {
        final father = families.first.spouses.first;
        expect(father.xref, 'X7');
        expect(father.isDeceased, isTrue);

        // A daughter born in 1929 with no death recorded: the box prints a
        // birth and no death, which is a statement rather than a silence.
        final living = families[1].children.last;
        expect(living.xref, 'X61');
        expect(living.isDeceased, isFalse);
      });
    });

    group('$version notes tab', () {
      late List<NoteEntry> notes;

      setUp(() {
        notes = const RecordParser().parseNotes(
          fixture(version, 'tab_notes.html'),
        );
      });

      test('reads a note recorded against the person', () {
        expect(notes.first.text, startsWith('هاجر إلى الكويت'));
        expect(notes.first.isSecondary, isFalse);
        // A shared note is a record of its own, and webtrees links its label
        // to it.
        expect(notes.first.xref, 'N3');
      });

      test('reads a note attached to a fact, and says which', () {
        final onBirth = notes.firstWhere((note) => note.label == 'الميلاد');
        expect(onBirth.text, 'نُقل تاريخ الميلاد من دفتر العائلة.');
        // webtrees keeps these collapsed itself: they are notes about a fact,
        // not about the person.
        expect(onBirth.isSecondary, isTrue);
        expect(onBirth.xref, 'N7');
      });

      test('drops the link announcing a shared note, not the note', () {
        final onBirth = notes.firstWhere((note) => note.label == 'الميلاد');
        expect(onBirth.text, isNot(contains('ملاحظة مشتركة')));
      });

      test('ignores the tab’s own controls and its empty line', () {
        expect(
          notes.map((note) => note.text),
          isNot(contains(contains('إظهار'))),
        );
      });

      test('drops a note awaiting deletion', () {
        // These tabs mark a pending deletion on the cells rather than on the
        // row, so a parser that only reads the row would show it.
        expect(
          notes.map((note) => note.text),
          isNot(contains('ملاحظة في انتظار الحذف.')),
        );
      });
    });

    group('$version sources tab', () {
      late List<SourceCitation> citations;

      setUp(() {
        citations = const RecordParser().parseSources(
          fixture(version, 'tab_sources.html'),
        );
      });

      test('reads the source a citation points at', () {
        expect(citations.first.title, 'سجل قيد العائلة');
        expect(citations.first.xref, 'S4');
        expect(citations.first.isSecondary, isFalse);
      });

      test('keeps the citation’s own fields as the site worded them', () {
        // webtrees translates the separator as well as the label, so each
        // line is taken whole rather than rebuilt from a pair here.
        expect(citations.first.details, ['الصفحة: ٤٢', 'الجودة: مصدر أساسي']);
      });

      test('reads a citation attached to a fact, and says which', () {
        final onBirth = citations.firstWhere((c) => c.label == 'الميلاد');
        expect(onBirth.title, 'دفتر النفوس');
        expect(onBirth.xref, 'S9');
        expect(onBirth.isSecondary, isTrue);
        expect(onBirth.details, ['الصفحة: ١٧']);
      });

      test('does not repeat the source line as one of its own details', () {
        // The line naming the source is a label/value pair like the rest, and
        // reading it as a detail would print the title twice.
        expect(
          citations.last.details,
          isNot(contains(contains('دفتر النفوس'))),
        );
      });
    });

    group('$version media tab', () {
      late List<MediaItem> media;

      setUp(() {
        media = const RecordParser().parseMedia(
          fixture(version, 'tab_media.html'),
        );
      });

      test('reads the title and the signed thumbnail', () {
        expect(media.first.title, 'صورة العائلة');
        expect(media.first.xref, 'M11');
        expect(media.first.thumbnailUrl, contains('media-thumbnail/M11/1'));
        // The signature is the server's; it cannot be built here.
        expect(media.first.thumbnailUrl, contains('s=6f1c9a0b2e'));
      });

      test('reads a photo attached to a fact, and says which', () {
        final onBirth = media.firstWhere((item) => item.isSecondary);
        expect(onBirth.title, 'شهادة الميلاد');
        expect(onBirth.thumbnailUrl, contains('media-thumbnail/M12/1'));
      });

      test('takes the download link for a photo, never the thumbnail', () {
        // A media *record* is `/media/M11`; the bytes are at
        // `/media-download/…`. Reading the wrong one would open a file
        // instead of the record it belongs to.
        expect(media.map((item) => item.xref), ['M11', 'M12']);
      });
    });
  }

  group('across versions', () {
    test('both produce the same record', () {
      // The versions differ in markup but describe the same person. Anything
      // that reads differently between them is a compatibility bug.
      final parsed = [
        for (final version in versions)
          const RecordParser().parseRelatives(
            fixture(version, 'tab_relatives.html'),
            xref: 'X42',
          ),
      ];

      expect(
        parsed.first.map((f) => '${f.xref}:${f.kind}').toList(),
        parsed.last.map((f) => '${f.xref}:${f.kind}').toList(),
      );
    });

    test('both expose the same tabs', () {
      final tabs = [
        for (final version in versions)
          const RecordParser()
              .parseIndividualPage(
                fixture(version, 'individual_page.html'),
                xref: 'X42',
              )
              .tabs
              .keys
              .toList(),
      ];
      expect(tabs.first, tabs.last);
    });
  });

  group('choosing a calendar', () {
    List<FactEntry> factsOf(String version) => const RecordParser().parseFacts(
      fixture(version, 'tab_personal_facts.html'),
    );

    test('names the calendar of each date webtrees linked', () {
      // The `cal` parameter of a webtrees calendar link is the only place a
      // stock site states which calendar a rendered date is in. Without it
      // the app would be guessing, and it refuses to.
      final birth = factsOf('v2_2_6').first.date!;
      final value = birth.pieces.whereType<DateValue>().single;
      expect(value.calendar, DateCalendar.gregorian);
      expect(value.conversions.single.calendar, DateCalendar.hijri);
    });

    test('shows one calendar when the reader asks for one', () {
      final birth = factsOf('v2_2_6').first.date!;
      expect(birth.display(CalendarView.gregorian), '١٢ مارس ١٩٠١');
      expect(birth.display(CalendarView.hijri), '٢١ ذو القعدة ١٣١٨');
    });

    test('keeps the words a qualified date is wrapped in', () {
      // "between 1974 (1394) and 1975 (1395)" must not collapse into two bare
      // years: the qualifier is part of what the record actually says.
      final death = factsOf('v2_2_6').last.date!;
      expect(death.display(CalendarView.hijri), 'بين ١٣٩٤ و ١٣٩٥');
      expect(death.display(CalendarView.gregorian), 'بين ١٩٧٤ و ١٩٧٥');
    });

    test('shows a date that has no conversion in full', () {
      // A date webtrees did not convert still has to appear. Hiding it would
      // silently delete a fact from the record.
      final relative = factsOf(
        'v2_2_6',
      ).firstWhere((fact) => fact.label == 'وفاة الأب').date!;
      expect(relative.display(CalendarView.hijri), relative.text);
    });

    test('falls back to the whole rendering when no calendar is named', () {
      // 2.3 renders the conversion as plain text, with no link and so no
      // calendar. Rather than guess which half is which, the app shows what
      // the server sent — the same thing it showed before the choice existed.
      final birth = factsOf('v2_3').first.date!;
      expect(birth.pieces, isEmpty);
      expect(birth.display(CalendarView.hijri), birth.text);
      expect(birth.display(CalendarView.gregorian), birth.text);
    });
  });
}
