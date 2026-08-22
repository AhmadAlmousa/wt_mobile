import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/data/stock/statistics_parser.dart';
import 'package:webtrees_mobile/domain/statistics.dart';

const versions = ['v2_2_6', 'v2_3'];

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
