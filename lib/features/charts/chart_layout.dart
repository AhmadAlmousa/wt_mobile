/// Placing a family chart on a canvas.
///
/// webtrees lays its charts out in HTML built for a wide screen: floated
/// boxes, background images for the connecting lines, and a reading direction
/// baked into the stylesheet. None of that survives a phone, so the app takes
/// the *shape* the server described and places it here — where a mirrored
/// layout for Arabic is one flag rather than a second stylesheet.
///
/// Deliberately free of widgets. Where a box lands is arithmetic, and
/// arithmetic can be tested without pumping a frame.
library;

import 'dart:ui' show Offset, Size;

import 'package:meta/meta.dart';

import '../../domain/charts.dart';
import '../../domain/records.dart';

/// Which way a chart runs from the person it was drawn for.
enum ChartFlow {
  /// Ancestors: generations march sideways, parents beside their children.
  sideways,

  /// Descendants: generations march down the page.
  downwards,
}

/// How big the pieces of a chart are drawn.
@immutable
final class ChartMetrics {
  const ChartMetrics({
    this.boxWidth = 168,
    this.boxHeight = 68,
    this.generationGap = 44,
    this.siblingGap = 16,
    this.coupleGap = 10,
  });

  final double boxWidth;
  final double boxHeight;

  /// Between one generation and the next.
  final double generationGap;

  /// Between two people of the same generation.
  final double siblingGap;

  /// Between the two halves of a couple, who are drawn as a pair.
  final double coupleGap;
}

/// One person, placed.
@immutable
final class ChartPlacement {
  const ChartPlacement({
    required this.person,
    required this.topLeft,
    required this.generation,
    this.isSubject = false,
    this.isSpouse = false,
  });

  final PersonRef person;
  final Offset topLeft;

  /// Counting from the person the chart was drawn for, who is generation 0.
  final int generation;

  /// The person the chart is about, drawn with more weight than the rest.
  final bool isSubject;

  /// Married into the family rather than descended through it.
  final bool isSpouse;
}

/// A line joining two boxes.
///
/// Generations are joined by an elbow, which says plainly which box a line
/// came from; a couple is joined by a straight one, because they are beside
/// each other rather than one above the other.
@immutable
final class ChartEdge {
  const ChartEdge({
    required this.from,
    required this.to,
    this.isCouple = false,
  });

  final Offset from;
  final Offset to;

  /// A marriage rather than a descent.
  final bool isCouple;
}

/// Everything needed to draw a chart, and how large a canvas it needs.
@immutable
final class ChartLayout {
  ChartLayout({
    required List<ChartPlacement> people,
    required List<ChartEdge> edges,
    required this.size,
    required this.metrics,
    required this.flow,
  }) : people = List.unmodifiable(people),
       edges = List.unmodifiable(edges);

  final List<ChartPlacement> people;
  final List<ChartEdge> edges;
  final Size size;
  final ChartMetrics metrics;

  /// Which way the generations run, which is also the way each joining line
  /// turns its corner.
  final ChartFlow flow;

  /// The same layout with every x mirrored, for a right-to-left interface.
  ///
  /// Mirroring the finished arithmetic rather than the algorithm keeps one
  /// layout to reason about and one to test: an Arabic reader expects the
  /// generations to march the other way, not a different chart.
  ChartLayout mirrored() => ChartLayout(
    metrics: metrics,
    size: size,
    flow: flow,
    people: [
      for (final placement in people)
        ChartPlacement(
          person: placement.person,
          topLeft: Offset(
            size.width - placement.topLeft.dx - metrics.boxWidth,
            placement.topLeft.dy,
          ),
          generation: placement.generation,
          isSubject: placement.isSubject,
          isSpouse: placement.isSpouse,
        ),
    ],
    edges: [
      for (final edge in edges)
        ChartEdge(
          from: Offset(size.width - edge.from.dx, edge.from.dy),
          to: Offset(size.width - edge.to.dx, edge.to.dy),
          isCouple: edge.isCouple,
        ),
    ],
  );
}

/// Lays an ancestor chart out with generations running to the right.
///
/// A person sits level with the middle of their parents, which is what makes
/// a pedigree readable: the eye follows a bracket rather than hunting for the
/// next box. People with no recorded parents take the next free row, so a
/// tree that runs out in one branch does not leave a column of gaps.
ChartLayout layoutAncestors(
  AncestorNode root, {
  ChartMetrics metrics = const ChartMetrics(),
}) {
  final people = <ChartPlacement>[];
  final edges = <ChartEdge>[];
  var nextRow = 0;
  var deepest = 0;

  /// Places [node] and every ancestor above it, answering where its own box
  /// ended up. Answering rather than looking the box up again matters: a
  /// family tree can hold the same person twice — cousins marry — and a
  /// search by name or identifier would find the wrong one of them.
  double place(AncestorNode node, int generation) {
    deepest = generation > deepest ? generation : deepest;
    final x = generation * (metrics.boxWidth + metrics.generationGap);

    final parentCentres = [
      for (final parent in node.parents) place(parent, generation + 1),
    ];

    // Level with the middle of the parents, which is what makes a pedigree
    // readable: the eye follows a bracket rather than hunting for a box.
    // Someone with no recorded parents takes the next free row, so a branch
    // that runs out early leaves no column of gaps.
    final centreY = parentCentres.isEmpty
        ? nextRow++ * (metrics.boxHeight + metrics.siblingGap) +
              metrics.boxHeight / 2
        : (parentCentres.first + parentCentres.last) / 2;

    people.add(
      ChartPlacement(
        person: node.person,
        topLeft: Offset(x, centreY - metrics.boxHeight / 2),
        generation: generation,
        isSubject: generation == 0,
      ),
    );

    for (final parentCentre in parentCentres) {
      edges.add(
        ChartEdge(
          from: Offset(x + metrics.boxWidth, centreY),
          to: Offset(
            x + metrics.boxWidth + metrics.generationGap,
            parentCentre,
          ),
        ),
      );
    }
    return centreY;
  }

  place(root, 0);

  return ChartLayout(
    metrics: metrics,
    flow: ChartFlow.sideways,
    people: people,
    edges: edges,
    size: Size(
      (deepest + 1) * metrics.boxWidth + deepest * metrics.generationGap,
      nextRow * (metrics.boxHeight + metrics.siblingGap) - metrics.siblingGap,
    ),
  );
}

/// Lays a descendant chart out with generations running downwards.
///
/// Each couple is drawn as a pair with their children centred beneath them,
/// so it is clear which marriage a child belongs to — the one thing a merged
/// list of children cannot say. Widths accumulate as the tree is walked, so
/// two large families never land on top of each other.
ChartLayout layoutDescendants(
  DescendantNode root, {
  ChartMetrics metrics = const ChartMetrics(),
}) {
  final people = <ChartPlacement>[];
  final edges = <ChartEdge>[];

  /// How far each generation has been filled. Per generation, because a
  /// parent is drawn *above* its own children and must be free to sit over
  /// them — only the people beside it can push it along.
  final filled = <int, double>{};
  var deepest = 0;

  /// Places [node] and everyone below it, answering the centre of its own box.
  double place(DescendantNode node, int generation) {
    deepest = generation > deepest ? generation : deepest;
    final y = generation * (metrics.boxHeight + metrics.generationGap);

    // Children first: a parent is placed over the family it turned out to
    // have, not the other way round.
    final childCentres = <double>[];
    for (final family in node.families) {
      for (final child in family.children) {
        childCentres.add(place(child, generation + 1));
      }
    }

    // The person, plus one box for each spouse, drawn side by side.
    final unit =
        metrics.boxWidth +
        node.families.length * (metrics.coupleGap + metrics.boxWidth);

    final start = filled[generation] ?? 0;
    var left = childCentres.isEmpty
        ? start
        : (childCentres.first + childCentres.last) / 2 - unit / 2;
    // Never overlap somebody already placed in this generation.
    if (left < start) left = start;

    people.add(
      ChartPlacement(
        person: node.person,
        topLeft: Offset(left, y),
        generation: generation,
        isSubject: generation == 0,
      ),
    );

    var spouseLeft = left + metrics.boxWidth + metrics.coupleGap;
    var childIndex = 0;
    for (final family in node.families) {
      final spouse = family.spouse;
      if (spouse != null) {
        people.add(
          ChartPlacement(
            person: spouse,
            topLeft: Offset(spouseLeft, y),
            generation: generation,
            isSpouse: true,
          ),
        );
        // A short line between the two, so a spouse is never mistaken for
        // another child standing in the same row.
        edges.add(
          ChartEdge(
            from: Offset(
              spouseLeft - metrics.coupleGap,
              y + metrics.boxHeight / 2,
            ),
            to: Offset(spouseLeft, y + metrics.boxHeight / 2),
            isCouple: true,
          ),
        );
      }

      // The line to the children hangs from between the couple, whether or
      // not the tree records the other parent.
      final from = Offset(
        spouse == null
            ? left + metrics.boxWidth / 2
            : spouseLeft - metrics.coupleGap / 2,
        y + metrics.boxHeight,
      );
      for (var i = 0; i < family.children.length; i++) {
        edges.add(
          ChartEdge(
            from: from,
            to: Offset(
              childCentres[childIndex++],
              y + metrics.boxHeight + metrics.generationGap,
            ),
          ),
        );
      }
      spouseLeft += metrics.boxWidth + metrics.coupleGap;
    }

    filled[generation] = left + unit + metrics.siblingGap;
    return left + metrics.boxWidth / 2;
  }

  place(root, 0);

  return ChartLayout(
    metrics: metrics,
    flow: ChartFlow.downwards,
    people: people,
    edges: edges,
    size: Size(
      (filled.values.fold(0.0, _larger) - metrics.siblingGap).clamp(
        metrics.boxWidth,
        double.infinity,
      ),
      (deepest + 1) * metrics.boxHeight + deepest * metrics.generationGap,
    ),
  );
}

double _larger(double a, double b) => a > b ? a : b;
