import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/records.dart';
import 'package:webtrees_mobile/features/charts/fan_layout.dart';

AncestorNode node(
  String xref, {
  required int sosa,
  List<AncestorNode> parents = const [],
}) => AncestorNode(
  person: PersonRef(xref: xref, name: xref),
  sosa: sosa,
  parents: parents,
);

void main() {
  const metrics = FanMetrics();

  /// A subject, both parents, and one grandparent on the father's side.
  final chart = node(
    'X1',
    sosa: 1,
    parents: [
      node('X2', sosa: 2, parents: [node('X4', sosa: 4)]),
      node('X3', sosa: 3),
    ],
  );

  group('a fan chart', () {
    late FanLayout layout;

    setUp(() => layout = layoutFan(chart));

    test('puts the subject in the middle', () {
      final centre = layout.sectors.first;
      expect(centre.node.person.xref, 'X1');
      expect(centre.innerRadius, 0);
      expect(centre.outerRadius, metrics.centreRadius);
    });

    test('halves the circle for the parents and quarters it above them', () {
      double sweepOf(String xref) => layout.sectors
          .firstWhere((sector) => sector.node.person.xref == xref)
          .sweep;

      expect(sweepOf('X2'), closeTo(math.pi, 0.0001));
      expect(sweepOf('X3'), closeTo(math.pi, 0.0001));
      expect(sweepOf('X4'), closeTo(math.pi / 2, 0.0001));
    });

    test(
      'puts the father’s line on the right and the mother’s on the left',
      () {
        // Angles run clockwise from twelve o'clock, so the first half circle is
        // the right-hand side — where a fan chart has always put a father.
        final father = layout.sectors.firstWhere(
          (sector) => sector.node.person.xref == 'X2',
        );
        expect(father.startAngle, 0);
        final mother = layout.sectors.firstWhere(
          (sector) => sector.node.person.xref == 'X3',
        );
        expect(mother.startAngle, closeTo(math.pi, 0.0001));
      },
    );

    test('gives each generation its own ring', () {
      final grandfather = layout.sectors.firstWhere(
        (sector) => sector.node.person.xref == 'X4',
      );
      expect(grandfather.innerRadius, metrics.centreRadius + metrics.ringWidth);
      expect(
        grandfather.outerRadius,
        metrics.centreRadius + metrics.ringWidth * 2,
      );
    });

    test('leaves an unrecorded ancestor’s slice empty', () {
      // The mother's parents are not in the tree. Their quarter of the ring
      // stays blank rather than being closed up — a chart that rearranged
      // itself around a gap would be saying something the tree does not.
      expect(layout.sectors, hasLength(4));

      // The mother's father would fill the slice at half past seven: two
      // rings out, a quarter turn past the bottom of the circle.
      final radius = metrics.centreRadius + metrics.ringWidth * 1.5;
      const angle = math.pi * 1.25;
      final atMothersFather = layout.at(
        math.sin(angle) * radius,
        -math.cos(angle) * radius,
      );
      expect(atMothersFather, isNull);

      // While the father's father, a quarter turn the other way, is there.
      const fathersFather = math.pi * 0.25;
      expect(
        layout
            .at(
              math.sin(fathersFather) * radius,
              -math.cos(fathersFather) * radius,
            )
            ?.person
            .xref,
        'X4',
      );
    });
  });

  group('tapping a fan', () {
    late FanLayout layout;

    setUp(() => layout = layoutFan(chart));

    test('finds the person under the finger', () {
      // Straight up from the middle, one ring out: the father's line.
      final ring = metrics.centreRadius + metrics.ringWidth / 2;
      expect(layout.at(0, -ring)?.person.xref, 'X2');
      // Straight down, same ring, is still the father's half.
      expect(layout.at(0, ring)?.person.xref, 'X2');
      // To the left is the mother.
      expect(layout.at(-ring, 0)?.person.xref, 'X3');
    });

    test('finds the subject in the middle', () {
      expect(layout.at(0, 0)?.person.xref, 'X1');
      expect(layout.at(metrics.centreRadius - 2, 0)?.person.xref, 'X1');
    });

    test('answers nobody outside the chart', () {
      expect(layout.at(layout.diameter, layout.diameter), isNull);
    });
  });
}
