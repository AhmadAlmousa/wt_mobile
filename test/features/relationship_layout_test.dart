import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/records.dart';
import 'package:webtrees_mobile/features/charts/chart_layout.dart';
import 'package:webtrees_mobile/features/charts/relationship_layout.dart';

PersonRef person(String xref) => PersonRef(xref: xref, name: xref);

RelationshipStep step(String xref, StepDirection direction, [String? word]) =>
    RelationshipStep(
      relationship: word ?? direction.name,
      person: person(xref),
      direction: direction,
    );

RelationshipPath path(List<RelationshipStep> steps, {String from = 'A'}) =>
    RelationshipPath(description: 'x', from: person(from), steps: steps);

/// Where each person on a path ended up, by xref.
Map<String, ChartPlacement> placedIn(ChartLayout layout) => {
  for (final placement in layout.people) placement.person.xref: placement,
};

/// Whether any two boxes would be drawn on top of each other, which is the
/// one property a chart of any kind has to have.
List<String> overlapsIn(ChartLayout layout) {
  final clashes = <String>[];
  for (var i = 0; i < layout.people.length; i++) {
    for (var j = i + 1; j < layout.people.length; j++) {
      Rect box(int at) => Rect.fromLTWH(
        layout.people[at].topLeft.dx,
        layout.people[at].topLeft.dy,
        layout.people[at].width,
        layout.metrics.boxHeight,
      );
      if (box(i).overlaps(box(j))) {
        clashes.add(
          '${layout.people[i].person.xref} over '
          '${layout.people[j].person.xref}',
        );
      }
    }
  }
  return clashes;
}

void main() {
  const metrics = ChartMetrics();
  final row = metrics.boxHeight + metrics.generationGap;

  group('a relationship drawn as a tree', () {
    test('a step to a parent is a row up the page', () {
      final layout = layoutRelationshipPath(
        path([step('B', StepDirection.toParent)]),
      );
      final placed = placedIn(layout);

      expect(placed['B']!.topLeft.dy, lessThan(placed['A']!.topLeft.dy));
      expect(placed['A']!.topLeft.dy - placed['B']!.topLeft.dy, row);
      // Same column: a run of parents has to read straight up.
      expect(placed['B']!.topLeft.dx, placed['A']!.topLeft.dx);
    });

    test('a step to a child is a row down the page', () {
      final layout = layoutRelationshipPath(
        path([step('B', StepDirection.toChild)]),
      );
      final placed = placedIn(layout);

      expect(placed['B']!.topLeft.dy - placed['A']!.topLeft.dy, row);
      expect(placed['B']!.topLeft.dx, placed['A']!.topLeft.dx);
    });

    test('a sideways step stays on the row and moves along', () {
      final layout = layoutRelationshipPath(
        path([step('B', StepDirection.sideways)]),
      );
      final placed = placedIn(layout);

      expect(placed['B']!.topLeft.dy, placed['A']!.topLeft.dy);
      expect(placed['B']!.topLeft.dx, greaterThan(placed['A']!.topLeft.dx));
    });

    test('a direction nobody stated is drawn flat rather than guessed', () {
      final layout = layoutRelationshipPath(
        path([step('B', StepDirection.unknown)]),
      );
      final placed = placedIn(layout);

      expect(placed['B']!.topLeft.dy, placed['A']!.topLeft.dy);
    });

    // The shape the whole feature exists for. Up to a grandparent and down
    // the other branch is a cousin, and a cousin belongs *beside* the
    // subject — a layout that put them back in the same column would draw one
    // person on top of another and say they were the same generation twice.
    test('a cousin comes back down beside the subject, not on top of them', () {
      final layout = layoutRelationshipPath(
        path([
          step('F', StepDirection.toParent),
          step('G', StepDirection.toParent),
          step('U', StepDirection.toChild),
          step('C', StepDirection.toChild),
        ]),
      );
      final placed = placedIn(layout);

      expect(overlapsIn(layout), isEmpty);
      // Back on the subject's own generation…
      expect(placed['C']!.topLeft.dy, placed['A']!.topLeft.dy);
      // …and one branch along from them.
      expect(placed['C']!.topLeft.dx, greaterThan(placed['A']!.topLeft.dx));
      // The grandparent is two rows above both of them.
      expect(placed['A']!.topLeft.dy - placed['G']!.topLeft.dy, row * 2);
      expect(placed['U']!.topLeft.dy, placed['F']!.topLeft.dy);
    });

    test('the whole path fits inside the size it reports', () {
      final layout = layoutRelationshipPath(
        path([
          step('F', StepDirection.toParent),
          step('S', StepDirection.sideways),
          step('C', StepDirection.toChild),
          step('D', StepDirection.toChild),
        ]),
      );

      for (final placement in layout.people) {
        expect(placement.right, lessThanOrEqualTo(layout.size.width));
        expect(
          placement.topLeft.dy + layout.metrics.boxHeight,
          lessThanOrEqualTo(layout.size.height),
        );
        expect(placement.topLeft.dx, greaterThanOrEqualTo(0));
        expect(placement.topLeft.dy, greaterThanOrEqualTo(0));
      }
    });

    test('both ends of the path are marked', () {
      final layout = layoutRelationshipPath(
        path([
          step('F', StepDirection.toParent),
          step('C', StepDirection.toChild),
        ]),
      );
      final placed = placedIn(layout);

      expect(placed['A']!.isSubject, isTrue);
      expect(placed['C']!.isSpouse, isTrue, reason: 'the far end');
      expect(placed['F']!.isSubject, isFalse);
      expect(placed['F']!.isSpouse, isFalse);
    });

    test('a person alone is a chart of one box and no lines', () {
      final layout = layoutRelationshipPath(path(const []));

      expect(layout.people, hasLength(1));
      expect(layout.edges, isEmpty);
      expect(layout.people.single.isSubject, isTrue);
      // Not also marked as the far end: there is nowhere to have gone.
      expect(layout.people.single.isSpouse, isFalse);
    });
  });

  group('the lines between them', () {
    test('every step is one edge, carrying the site’s own word', () {
      final layout = layoutRelationshipPath(
        path([
          step('F', StepDirection.toParent, 'أب'),
          step('C', StepDirection.toChild, 'بنت'),
        ]),
      );

      expect(layout.edges.map((edge) => edge.label), ['أب', 'بنت']);
    });

    test('a vertical step leaves the box top or bottom', () {
      final layout = layoutRelationshipPath(
        path([step('F', StepDirection.toParent)]),
      );
      final edge = layout.edges.single;
      final placed = placedIn(layout);

      expect(edge.kind, EdgeKind.descent);
      // Out of the top of the subject, into the bottom of the parent.
      expect(edge.from.dy, placed['A']!.topLeft.dy);
      expect(edge.to.dy, placed['F']!.topLeft.dy + metrics.boxHeight);
      expect(edge.from.dx, placed['A']!.centreX);
    });

    test('a sideways step leaves the side and is drawn straight', () {
      final layout = layoutRelationshipPath(
        path([step('B', StepDirection.sideways)]),
      );
      final edge = layout.edges.single;
      final placed = placedIn(layout);

      expect(edge.kind, EdgeKind.sideways);
      expect(edge.isStraight, isTrue);
      // Not a couple: the grid a path is read from moves right for a sibling
      // and a spouse alike, so this says "beside" and nothing more.
      expect(edge.isCouple, isFalse);
      expect(
        edge.from.dx,
        placed['B']!.topLeft.dx > placed['A']!.topLeft.dx
            ? placed['A']!.right
            : placed['A']!.topLeft.dx,
      );
      expect(edge.from.dy, edge.to.dy);
    });

    test('mirroring for Arabic keeps every word on its own line', () {
      final layout = layoutRelationshipPath(
        path([
          step('F', StepDirection.toParent, 'أب'),
          step('S', StepDirection.sideways, 'شقيقة'),
        ]),
      ).mirrored();

      expect(layout.edges.map((edge) => edge.label), ['أب', 'شقيقة']);
      expect(layout.edges.map((edge) => edge.kind), [
        EdgeKind.descent,
        EdgeKind.sideways,
      ]);
    });
  });
}
