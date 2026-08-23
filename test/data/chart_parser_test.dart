import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/data/stock/chart_parser.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/records.dart';

const versions = ['v2_2_6', 'v2_3'];

String fixture(String version, String name) =>
    File('test/fixtures/$version/$name').readAsStringSync();

/// The numbers webtrees printed beside each box, read back as integers.
///
/// This exists **only** in the test. webtrees renders a Sosa number with the
/// reader's own numerals — `٤` in Arabic — so the app derives the numbering
/// from the nesting instead of reading it. Reading it here is how that
/// derivation is checked against the site's own answer.
List<int> renderedSosa(String fragment) => RegExp(
  r'wt-sosa-number[^>]*>\s*([^<\s]+)\s*<',
).allMatches(fragment).map((match) => _digits(match.group(1)!)).toList();

List<String> renderedDaboville(String fragment) => RegExp(
  r'wt-daboville-number[^>]*>\s*([^<\s]+)\s*<',
).allMatches(fragment).map((match) => match.group(1)!).toList();

/// Arabic-Indic digits read as a number.
int _digits(String text) => int.parse(
  text.runes
      .map((rune) {
        // U+0660 is Arabic-Indic zero; the ten digits follow it in order.
        if (rune >= 0x0660 && rune <= 0x0669) return '${rune - 0x0660}';
        return String.fromCharCode(rune);
      })
      .join()
      .replaceAll(RegExp(r'[^0-9]'), ''),
);

void main() {
  for (final version in versions) {
    group('$version ancestors chart', () {
      late AncestorNode chart;
      late String fragment;

      setUp(() {
        fragment = fixture(version, 'chart_ancestors.html');
        chart = const ChartParser().parseAncestors(fragment);
      });

      test('reads the person the chart was drawn for', () {
        expect(chart.person.xref, 'X42');
        expect(chart.person.name, 'عبد الله الموسى');
        expect(chart.sosa, 1);
      });

      test('reads the generations above them', () {
        expect(chart.parents.map((node) => node.person.xref), ['X7', 'X8']);
        expect(chart.parents.first.parents.map((n) => n.person.xref), [
          'X20',
          'X21',
        ]);
        expect(chart.depth, 3);
        expect(chart.everyone.length, 5);
      });

      test('numbers people the way the site itself numbered them', () {
        // The app works the Sosa numbers out from the nesting rather than
        // reading them, because webtrees prints them in the reader's numerals.
        // This is the check that the two agree.
        expect(
          chart.everyone.map((node) => node.sosa).toList()..sort(),
          renderedSosa(fragment)..sort(),
        );
      });

      test('puts the father in the even slot and the mother beside him', () {
        expect(chart.parents.first.sosa, 2);
        expect(chart.parents.last.sosa, 3);
        // And their parents continue the doubling.
        expect(chart.parents.first.parents.map((n) => n.sosa), [4, 5]);
      });

      test('keeps the family each pair of parents belongs to', () {
        expect(chart.familyXref, 'F1');
        expect(chart.parents.first.familyXref, 'F5');
        // Nobody above them is recorded, so there is no family to name.
        expect(chart.parents.last.familyXref, isNull);
      });

      test('keeps the site’s own summary of a marriage', () {
        // Already translated, and carrying the date in the site's numerals —
        // so it is shown as it arrived rather than rebuilt from parts.
        expect(chart.parentsLabel, contains('الوالدان'));
        expect(chart.parentsLabel, contains('١٨٩٨'));
      });

      test('reads each box as a person, photo and all', () {
        expect(chart.person.thumbnailUrl, contains('media-thumbnail/M11/1'));
        expect(chart.parents.first.person.sex, Sex.male);
        expect(chart.parents.last.person.sex, Sex.female);
        expect(chart.parents.first.person.lifespan, '1869–1930');
      });
    });

    group('$version descendants chart', () {
      late DescendantNode chart;
      late String fragment;

      setUp(() {
        fragment = fixture(version, 'chart_descendants.html');
        chart = const ChartParser().parseDescendants(fragment);
      });

      test('reads the person, their families and their children', () {
        expect(chart.person.xref, 'X42');
        expect(chart.families.map((f) => f.xref), ['F2', 'F4']);
        expect(chart.families.first.spouse?.xref, 'X50');
        expect(chart.families.first.children.map((n) => n.person.xref), [
          'X60',
          'X61',
        ]);
      });

      test('keeps a second marriage’s children under that marriage', () {
        // Merging them would put a child under the wrong mother, which is not
        // a crowded chart but a false one.
        expect(chart.families.last.spouse?.xref, 'X51');
        expect(chart.families.last.children.map((n) => n.person.xref), [
          'X62',
        ]);
      });

      test('goes on down the generations', () {
        final son = chart.families.first.children.first;
        expect(son.families.single.spouse?.xref, 'X70');
        expect(son.families.single.children.single.person.xref, 'X80');
        expect(chart.everyone.length, 5);
      });

      test('tells which marriage ended in a divorce', () {
        // The caption is one sentence with no markup between its parts, so
        // the only way to read a divorce out of it is against the vocabulary
        // this site's own chart boxes taught the app.
        expect(chart.families.first.endedInDivorce, isFalse);
        expect(chart.families.last.endedInDivorce, isTrue);
      });

      test('claims no divorce when the page named no tags', () {
        // Strip the fact blocks and the dictionary is empty — which has to
        // read as silence, not as a marriage that held.
        final mute = fragment.replaceAll(RegExp(r'fact_[_A-Z]+'), 'fact');
        final read = const ChartParser().parseDescendants(mute);
        expect(read.families.last.endedInDivorce, isFalse);
      });

      test('numbers people the way the site itself numbered them', () {
        expect(
          chart.everyone.map((node) => node.number).toList()..sort(),
          renderedDaboville(fragment)..sort(),
        );
      });

      test('knows which generation a person is in', () {
        final son = chart.families.first.children.first;
        expect(chart.depth, 1);
        expect(son.depth, 2);
        expect(son.families.single.children.single.depth, 3);
      });

      test('keeps the site’s own summary of each family', () {
        expect(chart.families.first.label, contains('الزواج'));
        expect(chart.families.first.label, contains('١٩٢٥'));
      });

      test('does not mistake a spouse for a descendant', () {
        // The spouse's box sits inside the family block without a number: it
        // is the one box there that is nobody's subtree.
        expect(
          chart.everyone.map((node) => node.person.xref),
          isNot(contains('X50')),
        );
      });
    });
    group('$version timeline', () {
      late TimelineChart chart;

      setUp(() {
        chart = const ChartParser().parseTimeline(
          fixture(version, 'timeline.html'),
        );
      });

      test('reads the scale the site drew', () {
        // The year is in the element's id as plain digits; the label beside
        // it is written in the reader's own numerals.
        expect(chart.ticks.map((tick) => tick.year), [
          1900,
          1910,
          1920,
          1930,
          1940,
          1950,
        ]);
        expect(chart.ticks.first.position, -5);
      });

      test('reads each event where the site put it', () {
        expect(chart.events, hasLength(2));
        expect(chart.events.first.label, startsWith('الميلاد'));
        expect(chart.events.first.position, 35);
        expect(chart.events.last.position, 135);
      });

      test('keeps the date as the site wrote it', () {
        // Both calendars, in the site's own numerals — the app never reads a
        // year out of a box's position.
        expect(chart.events.first.label, contains('١٩٠١'));
        expect(chart.events.last.label, contains('مكة'));
      });

      test('knows the ground it covers', () {
        final (first, last) = chart.extent;
        expect(first, -5);
        expect(last, 195);
        expect(chart.isEmpty, isFalse);
      });

      test('a scale with nothing on it is empty, not a chart', () {
        final empty = const ChartParser().parseTimeline(
          '<div id="scale1900" style="top:0px">1900</div>',
        );
        expect(empty.isEmpty, isTrue);
      });
    });

    group('$version relationship chart', () {
      test('reads the path from one person to the other', () {
        final paths = const ChartParser().parseRelationships(
          fixture(version, 'relationship_ancestors.html'),
          from: 'X42',
        );

        final path = paths.single;
        // The site's own phrase for the whole relationship. Arabic separates
        // kinds of kin English has one word for, so composing this in the app
        // would mean inventing terms in two languages.
        expect(path.description, 'القرابة: جد لأب');
        expect(path.from.xref, 'X42');
        expect(path.steps.map((step) => step.person.xref), ['X7', 'X20']);
        expect(path.steps.map((step) => step.relationship), ['أب', 'أب']);
        expect(path.to?.xref, 'X20');
      });

      test('starts from the person it was asked about', () {
        // webtrees prints the grid from the far end down, so the person whose
        // page this was opened from is the *last* box in the markup.
        final paths = const ChartParser().parseRelationships(
          fixture(version, 'relationship_ancestors.html'),
          from: 'X20',
        );
        expect(paths.single.steps.map((step) => step.person.xref), [
          'X7',
          'X42',
        ]);
      });

      test('walks a path that runs sideways as well as up', () {
        // A sibling step is drawn across a row rather than down a column.
        final paths = const ChartParser().parseRelationships(
          fixture(version, 'relationship_sibling.html'),
          from: 'X42',
        );
        expect(paths.single.steps.single.person.xref, 'X43');
        expect(paths.single.steps.single.relationship, 'أخت');
      });

      test('answers nothing when the site found no link', () {
        // Two people in one tree need not be related at all, and webtrees
        // says so in a sentence rather than an empty chart.
        expect(
          const ChartParser().parseRelationships(
            fixture(version, 'relationship_none.html'),
            from: 'X42',
          ),
          isEmpty,
        );
      });
    });
  }

  group('across versions', () {
    test('both describe the same ancestors', () {
      final parsed = [
        for (final version in versions)
          const ChartParser()
              .parseAncestors(fixture(version, 'chart_ancestors.html'))
              .everyone
              .map((node) => '${node.sosa}:${node.person.xref}')
              .toList(),
      ];
      expect(parsed.first, parsed.last);
    });

    test('both describe the same descendants', () {
      final parsed = [
        for (final version in versions)
          const ChartParser()
              .parseDescendants(fixture(version, 'chart_descendants.html'))
              .everyone
              .map((node) => '${node.number}:${node.person.xref}')
              .toList(),
      ];
      expect(parsed.first, parsed.last);
    });
  });

  group('a chart that cannot be read', () {
    test('names itself, the version and what it wanted', () {
      const parser = ChartParser(version: '9.9');
      try {
        parser.parseAncestors('<div class="wt-chart"><p>?</p></div>');
        fail('expected a ParseFailure');
      } on ParseFailure catch (problem) {
        expect(problem.diagnostic, contains('ancestors chart'));
        expect(problem.diagnostic, contains('wt-chart-box'));
        expect(problem.diagnostic, contains('9.9'));
      }
    });
  });
}
