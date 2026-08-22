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

      test('reads the person, their family and their children', () {
        expect(chart.person.xref, 'X42');
        expect(chart.families.single.xref, 'F2');
        expect(chart.families.single.spouse?.xref, 'X50');
        expect(chart.families.single.children.map((n) => n.person.xref), [
          'X60',
          'X61',
        ]);
      });

      test('goes on down the generations', () {
        final son = chart.families.single.children.first;
        expect(son.families.single.spouse?.xref, 'X70');
        expect(son.families.single.children.single.person.xref, 'X80');
        expect(chart.everyone.length, 4);
      });

      test('numbers people the way the site itself numbered them', () {
        expect(
          chart.everyone.map((node) => node.number).toList()..sort(),
          renderedDaboville(fragment)..sort(),
        );
      });

      test('knows which generation a person is in', () {
        final son = chart.families.single.children.first;
        expect(chart.depth, 1);
        expect(son.depth, 2);
        expect(son.families.single.children.single.depth, 3);
      });

      test('keeps the site’s own summary of each family', () {
        expect(chart.families.single.label, contains('الزواج'));
        expect(chart.families.single.label, contains('١٩٢٥'));
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
