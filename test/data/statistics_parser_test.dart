import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/data/stock/statistics_parser.dart';
import 'package:webtrees_mobile/domain/statistics.dart';

/// Only 2.2.6 here. The two versions genuinely disagree about how a chart's
/// data reaches the page, so one fixture cannot stand for both — which is
/// precisely the mistake that hid this: the old `v2_3` fixture was written by
/// hand in **2.2.6's** shape, so these tests were green while every chart on a
/// real 2.3 site came back empty. 2.3 has a group of its own, below, over
/// markup captured from a running install.
const versions = ['v2_2_6'];

String fixture(String version, String name) =>
    File('test/fixtures/$version/$name').readAsStringSync();

void main() {
  for (final version in versions) {
    group('$version statistics', () {
      late List<StatisticSection> sections;

      setUp(() {
        sections = const StatisticsParser().parseSections(
          fixture(version, 'statistics_individuals.html'),
        );
      });

      test('splits the page at its headings', () {
        expect(sections.map((section) => section.title), [
          'مجموع الأفراد',
          'أحداث',
          'المواقع',
        ]);
      });

      test('keeps a count exactly as the site rendered it', () {
        // Arabic-Indic digits and an Arabic thousands separator. Rewriting
        // these would mean deciding for the reader which numerals they use —
        // the same decision the app leaves to the server for dates.
        expect(sections.first.total, '١٬٤٦٣');
        expect(sections.first.items.first.value, '٧٤٤');
        expect(sections.first.items.first.label, 'إجمالي الذكور');
      });

      test('keeps a figure that has no number of its own', () {
        // "Earliest birth" is a heading over a record, not a count.
        final events = sections[1];
        expect(
          events.items.map((item) => item.label),
          containsAll(<String>['إجمالي الولادات', 'أقدم ولادة']),
        );
        expect(
          events.items.firstWhere((item) => item.label == 'أقدم ولادة').value,
          isNull,
        );
      });

      test('reads the data behind a chart, whatever drew it', () {
        final sexes = sections.first.datasets.single;
        expect(sexes.shape, StatisticShape.pie);
        // The title comes out of options webtrees writes as JavaScript rather
        // than JSON — comments, unquoted keys and all.
        expect(sexes.title, 'الجنس');
        expect(sexes.columns, ['الجنس', 'الإجمالي']);
        expect(sexes.rows.map((row) => row.label), [
          'ذكور',
          'إناث',
          'غير معروف',
          'أخرى',
        ]);
        expect(sexes.rows.first.value, 744);
        expect(sexes.total, 1463);
      });

      test('reads a chart whose options really are JSON', () {
        final births = sections[1].datasets.single;
        expect(births.shape, StatisticShape.column);
        expect(births.title, 'ولادات حسب القرن');
        expect(births.rows.last.value, 229);
      });

      test('names a place rather than plotting its code', () {
        // A map chart names each place twice: the code it plots by, and the
        // name a reader wants.
        final places = sections.last.datasets.single;
        expect(places.shape, StatisticShape.other);
        expect(places.rows.map((row) => row.label), ['الكويت', 'الهند']);
      });

      test('knows when there is nothing worth drawing', () {
        final empty = StatisticDataset(
          title: 'x',
          shape: StatisticShape.pie,
          columns: const ['a', 'b'],
          rows: [
            StatisticRow(label: 'none', values: const [0]),
          ],
        );
        expect(empty.hasData, isFalse);
        expect(sections.first.datasets.single.hasData, isTrue);
      });
    });
  }

  group('v2_3 statistics', () {
    // Captured from a 2.3.0-dev lab rather than transcribed from a template.
    late List<StatisticSection> sections;

    setUp(() {
      sections = const StatisticsParser().parseSections(
        fixture('v2_3', 'statistics_individuals.html'),
      );
    });

    test('reads the counts the same way 2.2 does', () {
      // Unchanged between the versions: a heading, a badge, the site's own
      // numerals.
      expect(sections.single.title, 'مجموع الأفراد');
      expect(sections.single.total, '١٤');
      expect(sections.single.items.single.label, 'إجمالي الذكور');
      expect(sections.single.items.single.value, '٦');
    });

    test('reads a chart out of the attributes 2.3 puts on its canvas', () {
      // 2.2.6 called `statistics.drawPieChart(…)` from a script; 2.3 hands
      // Chart.js the same numbers in `data-wt-chart-data`.
      final sexes = sections.single.datasets.first;
      expect(sexes.shape, StatisticShape.pie);
      expect(sexes.title, 'الجنس');
      expect(sexes.rows.map((row) => row.label), [
        'ذكور',
        'إناث',
        'غير معروف',
        'أخرى',
      ]);
      expect(sexes.rows.first.value, 6);
      expect(sexes.total, 14);
    });

    test('transposes a chart with more than one series', () {
      // Chart.js holds one array per series, parallel to a shared list of
      // labels — the transpose of the row-per-category shape Google Charts
      // took, and of the shape the app draws.
      final ages = sections.single.datasets.last;
      expect(ages.shape, StatisticShape.column);
      expect(ages.title, 'متوسط العمر حسب قرن الوفاة');
      expect(ages.columns, ['ذكور', 'إناث', 'متوسط العمر']);
      expect(ages.rows.map((row) => row.label), ['الـ19', 'الـ20']);
      // One value per series, in series order.
      expect(ages.rows.first.values, [70.2, 71, 70.6]);
      expect(ages.rows.last.values, [0, 71.7, 35.8]);
    });

    test('the options really are JSON now', () {
      // §7 bug 23 was that 2.2.6 wrote some option objects by hand, with
      // comments and unquoted keys, so a parser decoding them dropped the
      // chart. 2.3 emits strict JSON, and the title comes straight out of it.
      expect(
        sections.single.datasets.map((dataset) => dataset.title),
        everyElement(isNotEmpty),
      );
    });
  });

  group('a page that says nothing', () {
    test('is no sections rather than empty ones', () {
      // webtrees offers a tab for *building* a chart, which holds a form and
      // no figures at all.
      const parser = StatisticsParser();
      expect(parser.parseSections('<form><select></select></form>'), isEmpty);
      expect(parser.parseSections('<h4>Only a heading</h4>'), isEmpty);
    });

    test('a script that is not a chart is left alone', () {
      const parser = StatisticsParser();
      final sections = parser.parseSections(
        '<h4>x<span class="badge">1</span></h4>'
        '<script>window.alert("statistics.drawPieChart");</script>',
      );
      expect(sections.single.datasets, isEmpty);
    });

    test('a chart whose data will not parse is skipped, not thrown', () {
      // The counts around it are still worth showing: one unreadable chart
      // should cost that chart and nothing else.
      const parser = StatisticsParser();
      final sections = parser.parseSections(
        '<h4>x<span class="badge">1</span></h4>'
        '<script>statistics.drawPieChart("id", [oops], {});</script>',
      );
      expect(sections.single.total, '1');
      expect(sections.single.datasets, isEmpty);
    });
  });
}
