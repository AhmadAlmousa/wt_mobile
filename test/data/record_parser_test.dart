import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/data/stock/record_parser.dart';
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
        expect(birth.date, startsWith('12 مارس 1901'));
        expect(birth.place, 'الرياض, السعودية');
      });

      test('keeps the calendar conversion webtrees rendered', () {
        // The date stays as text precisely so a Hijri conversion survives.
        // Parsing it into a DateTime would throw the second calendar away.
        expect(facts.first.date, contains('هـ'));
      });

      test('strips the computed ages from the date', () {
        // "Father's age: 32" shares the date's box but is not part of it.
        expect(facts.first.date, isNot(contains('32')));
        expect(facts.last.date, isNot(contains('73')));
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
        expect(families.map((f) => f.xref), ['F1', 'F2']);
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
        expect(record.spouses.map((p) => p.xref), ['X50']);
        expect(record.children.map((p) => p.xref), ['X60', 'X61']);
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
}
