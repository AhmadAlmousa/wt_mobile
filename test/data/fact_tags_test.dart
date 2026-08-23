import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:webtrees_mobile/data/stock/fact_tags.dart';

/// One chart box's worth of rendered facts, in the shape `Fact::summary()`
/// emits: the GEDCOM tag in the class, this site's translation in the label.
const String _box = '''
<div class="wt-chart-box wt-chart-box-m" data-wt-chart-xref="X42">
  <div class="wt-chart-box-facts">
    <div class="fact_INDI:BIRT"><span class="label">الميلاد</span>: 1901</div>
    <div class="fact_INDI:DEAT"><span class="label">الوفاة</span>: 1974</div>
  </div>
  <div class="wt-chart-box-zoom-dropdown">
    <div class="fact_FAM:MARR"><span class="label">الزواج</span>: 1925</div>
    <div class="fact_FAM:DIV"><span class="label">الطلاق</span>: 1948</div>
  </div>
</div>
''';

void main() {
  group('fact tag index', () {
    late FactTagIndex index;

    setUp(() {
      index = FactTagIndex.from(html.parseFragment(_box));
    });

    test('learns what this site calls each kind of fact', () {
      expect(index.tagFor('الميلاد'), 'INDI:BIRT');
      expect(index.tagFor('الوفاة'), 'INDI:DEAT');
      expect(index.tagFor('الزواج'), 'FAM:MARR');
      expect(index.tagFor('الطلاق'), 'FAM:DIV');
    });

    test('recognises a death and a divorce by tag, not by word', () {
      // The whole point: nothing in this test's subject knows the English
      // for either, and the answers still come out right.
      expect(index.isDeath('الوفاة'), isTrue);
      expect(index.isDeath('الميلاد'), isFalse);
      expect(index.isDivorce('الطلاق'), isTrue);
      expect(index.isDivorce('الزواج'), isFalse);
    });

    test('ignores case and stray whitespace in a label', () {
      final english = FactTagIndex.from(
        html.parseFragment(
          '<div class="fact_INDI:DEAT"><span class="label"> Death </span></div>',
        ),
      );
      expect(english.tagFor('death'), 'INDI:DEAT');
      expect(english.tagFor('DEATH'), 'INDI:DEAT');
    });

    test('finds a divorce inside a caption that runs several labels together',
        () {
      // A descendants chart announces a family as one sentence, with no
      // markup between the marriage, the divorce and the child count.
      expect(
        index.mentionsDivorce('الزواج 1940 — الطلاق 1948 — ولد واحد'),
        isTrue,
      );
      expect(index.mentionsDivorce('الزواج 1925 — ولدان'), isFalse);
    });

    test('says nothing about a label it never saw', () {
      expect(index.tagFor('المهنة'), isNull);
      expect(index.isDeath('المهنة'), isFalse);
      expect(index.isDivorce('المهنة'), isFalse);
    });

    test('an empty index claims nothing at all', () {
      // A theme that renders no fact blocks leaves the app knowing nothing,
      // which must read as silence rather than as "no death here".
      final nothing = FactTagIndex.from(html.parseFragment('<div></div>'));
      expect(nothing.isEmpty, isTrue);
      expect(nothing.tagFor('الوفاة'), isNull);
      expect(nothing.isDeath('الوفاة'), isFalse);
      expect(nothing.mentionsDivorce('الطلاق 1948'), isFalse);
      expect(FactTagIndex.empty.isEmpty, isTrue);
    });

    test('splits a qualified tag from its record type', () {
      expect(FactTagIndex.bareTagOf('INDI:DEAT'), 'DEAT');
      expect(FactTagIndex.bareTagOf('FAM:_SEPR'), '_SEPR');
      // Already bare, which is what a caller passing a raw tag would give.
      expect(FactTagIndex.bareTagOf('DEAT'), 'DEAT');
      expect(FactTagIndex.bareTagOf(null), isNull);
    });
  });
}
