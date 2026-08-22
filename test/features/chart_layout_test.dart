import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/records.dart';
import 'package:webtrees_mobile/features/charts/chart_layout.dart';

PersonRef person(String xref, {Sex sex = Sex.unknown}) =>
    PersonRef(xref: xref, name: xref, sex: sex);

AncestorNode ancestor(
  String xref, {
  int sosa = 1,
  List<AncestorNode> parents = const [],
}) => AncestorNode(person: person(xref), sosa: sosa, parents: parents);

DescendantNode descendant(
  String xref, {
  String number = '1',
  List<DescendantFamily> families = const [],
}) => DescendantNode(person: person(xref), number: number, families: families);

/// Whether any two boxes in a layout would be drawn on top of each other.
///
/// The one property a chart must have: two people in the same place is not a
/// crowded chart, it is an unreadable one.
List<String> overlapsIn(ChartLayout layout) {
  final boxes = layout.people;
  final clashes = <String>[];

  for (var i = 0; i < boxes.length; i++) {
    for (var j = i + 1; j < boxes.length; j++) {
      final a = Rect.fromLTWH(
        boxes[i].topLeft.dx,
        boxes[i].topLeft.dy,
        layout.metrics.boxWidth,
        layout.metrics.boxHeight,
      );
      final b = Rect.fromLTWH(
        boxes[j].topLeft.dx,
        boxes[j].topLeft.dy,
        layout.metrics.boxWidth,
        layout.metrics.boxHeight,
      );
      if (a.overlaps(b)) {
        clashes.add('${boxes[i].person.xref} over ${boxes[j].person.xref}');
      }
    }
  }
  return clashes;
}

void main() {
  const metrics = ChartMetrics();

  group('an ancestor chart', () {
    late ChartLayout layout;

    setUp(() {
      // Four generations down one line, and a branch that stops early — the
      // ordinary shape of a real tree.
      layout = layoutAncestors(
        ancestor(
          'X1',
          parents: [
            ancestor(
              'X2',
              sosa: 2,
              parents: [ancestor('X4', sosa: 4), ancestor('X5', sosa: 5)],
            ),
            ancestor('X3', sosa: 3),
          ],
        ),
      );
    });

    test('puts each generation in its own column', () {
      double columnOf(String xref) => layout.people
          .firstWhere((placement) => placement.person.xref == xref)
          .topLeft
          .dx;

      expect(columnOf('X1'), 0);
      expect(columnOf('X2'), metrics.boxWidth + metrics.generationGap);
      expect(columnOf('X3'), columnOf('X2'));
      expect(columnOf('X4'), 2 * (metrics.boxWidth + metrics.generationGap));
    });

    test('sits a person level with the middle of their parents', () {
      double centreOf(String xref) =>
          layout.people
              .firstWhere((placement) => placement.person.xref == xref)
              .topLeft
              .dy +
          metrics.boxHeight / 2;

      expect(centreOf('X2'), (centreOf('X4') + centreOf('X5')) / 2);
      expect(centreOf('X1'), (centreOf('X2') + centreOf('X3')) / 2);
    });

    test('draws nobody on top of anybody', () {
      expect(overlapsIn(layout), isEmpty);
    });

    test('joins each person to each parent', () {
      // Three parent links: X1→X2, X1→X3, X2→X4, X2→X5.
      expect(layout.edges, hasLength(4));
    });

    test('is as large as the chart it holds', () {
      expect(
        layout.size.width,
        3 * metrics.boxWidth + 2 * metrics.generationGap,
      );
      expect(
        layout.size.height,
        3 * (metrics.boxHeight + metrics.siblingGap) - metrics.siblingGap,
      );
    });
  });

  group('a descendant chart', () {
    late ChartLayout layout;

    setUp(() {
      layout = layoutDescendants(
        descendant(
          'X1',
          families: [
            DescendantFamily(
              xref: 'F1',
              spouse: person('X9'),
              children: [
                descendant(
                  'X10',
                  number: '1.1',
                  families: [
                    DescendantFamily(
                      xref: 'F2',
                      spouse: person('X11'),
                      children: [
                        descendant('X12', number: '1.1.1'),
                        descendant('X13', number: '1.1.2'),
                      ],
                    ),
                  ],
                ),
                descendant('X14', number: '1.2'),
              ],
            ),
          ],
        ),
      );
    });

    test('runs generations down the canvas', () {
      double rowOf(String xref) => layout.people
          .firstWhere((placement) => placement.person.xref == xref)
          .topLeft
          .dy;

      expect(rowOf('X1'), 0);
      expect(rowOf('X9'), 0, reason: 'a spouse belongs to the same row');
      expect(rowOf('X10'), metrics.boxHeight + metrics.generationGap);
      expect(rowOf('X12'), 2 * (metrics.boxHeight + metrics.generationGap));
    });

    test('draws a couple side by side', () {
      double leftOf(String xref) => layout.people
          .firstWhere((placement) => placement.person.xref == xref)
          .topLeft
          .dx;

      expect(leftOf('X9') - leftOf('X1'), metrics.boxWidth + metrics.coupleGap);
    });

    test('centres a couple over the children they had', () {
      double centreOf(String xref) =>
          layout.people
              .firstWhere((placement) => placement.person.xref == xref)
              .topLeft
              .dx +
          metrics.boxWidth / 2;

      // The pair X10 + X11 sits over X12 and X13.
      final couple = (centreOf('X10') + centreOf('X11')) / 2;
      expect(couple, closeTo((centreOf('X12') + centreOf('X13')) / 2, 0.01));
    });

    test('marks a spouse as married in, not descended', () {
      final spouse = layout.people.firstWhere(
        (placement) => placement.person.xref == 'X9',
      );
      expect(spouse.isSpouse, isTrue);
      expect(spouse.isSubject, isFalse);
    });

    test('joins a couple so a spouse is not read as another child', () {
      final couples = layout.edges.where((edge) => edge.isCouple).toList();
      expect(couples, hasLength(2));
      // Straight and level: they stand beside each other, not one above the
      // other.
      expect(couples.first.from.dy, couples.first.to.dy);
    });

    test('draws nobody on top of anybody', () {
      // Two families of different sizes on the same row is exactly where a
      // naïve layout puts one child through another.
      expect(overlapsIn(layout), isEmpty);
    });
  });

  group('mirroring for a right-to-left reader', () {
    test('turns the chart round without reshaping it', () {
      final layout = layoutAncestors(
        ancestor(
          'X1',
          parents: [ancestor('X2', sosa: 2), ancestor('X3', sosa: 3)],
        ),
      );
      final mirrored = layout.mirrored();

      double leftOf(ChartLayout chart, String xref) => chart.people
          .firstWhere((placement) => placement.person.xref == xref)
          .topLeft
          .dx;

      // The subject was against the left edge; now they are against the right.
      expect(leftOf(layout, 'X1'), 0);
      expect(
        leftOf(mirrored, 'X1'),
        layout.size.width - ChartMetrics().boxWidth,
      );
      // Rows are untouched: only the reading direction changed.
      expect(
        mirrored.people.map((p) => p.topLeft.dy).toList(),
        layout.people.map((p) => p.topLeft.dy).toList(),
      );
      expect(overlapsIn(mirrored), isEmpty);
    });
  });
}
