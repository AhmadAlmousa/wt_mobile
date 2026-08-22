/// Placing an ancestor chart round a circle.
///
/// The same people as the pedigree, arranged the way a fan chart arranges
/// them: the subject in the middle, each generation a ring outside the last,
/// and every person's slice exactly half their child's. That regularity is
/// what makes a fan readable at a glance — and it comes free from the
/// Sosa-Stradonitz numbering, where a person's parents are always 2n and 2n+1.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../domain/charts.dart';

/// How big the rings are drawn.
@immutable
final class FanMetrics {
  const FanMetrics({this.centreRadius = 60, this.ringWidth = 96});

  /// The disc the subject sits in.
  final double centreRadius;

  /// How thick each generation's ring is.
  ///
  /// Wide enough for a name to be written along the radius: a family name
  /// takes room, and a ring that only fits `محمد ال…` has told the reader
  /// nothing they did not already know.
  final double ringWidth;
}

/// One person's slice of a fan.
@immutable
final class FanSector {
  const FanSector({
    required this.node,
    required this.generation,
    required this.startAngle,
    required this.sweep,
    required this.innerRadius,
    required this.outerRadius,
  });

  final AncestorNode node;

  /// Counting from the subject, who is generation 0 and fills the middle.
  final int generation;

  /// Radians clockwise from twelve o'clock.
  final double startAngle;
  final double sweep;

  final double innerRadius;
  final double outerRadius;

  double get middleAngle => startAngle + sweep / 2;

  /// Whether [radius] and [angle] — measured the same way — fall inside.
  bool contains(double radius, double angle) {
    if (radius < innerRadius || radius > outerRadius) return false;
    final turned = (angle - startAngle) % (math.pi * 2);
    return turned >= 0 && turned <= sweep;
  }
}

/// A fan chart, and the square of canvas it needs.
@immutable
final class FanLayout {
  FanLayout({
    required List<FanSector> sectors,
    required this.diameter,
    required this.metrics,
  }) : sectors = List.unmodifiable(sectors);

  final List<FanSector> sectors;

  /// The canvas is square: a circle has no better shape to sit in.
  final double diameter;

  final FanMetrics metrics;

  double get centre => diameter / 2;

  /// The person at a point, measured from the centre of the fan.
  ///
  /// Answers null for a tap in the empty space of a ring — an ancestor the
  /// tree does not record — which is not nobody so much as nobody *yet*.
  AncestorNode? at(double dx, double dy) {
    final radius = math.sqrt(dx * dx + dy * dy);
    // Angles run clockwise from twelve o'clock, as the sectors were placed.
    final angle = (math.atan2(dy, dx) + math.pi / 2) % (math.pi * 2);

    for (final sector in sectors) {
      if (sector.contains(radius, angle)) return sector.node;
    }
    return null;
  }
}

/// Lays an ancestor chart out as a full circle.
///
/// A whole circle rather than a half or a quarter: on a phone the screen is
/// as tall as it is narrow, and a semicircle wastes the half it does not use.
FanLayout layoutFan(
  AncestorNode root, {
  FanMetrics metrics = const FanMetrics(),
}) {
  final sectors = <FanSector>[
    FanSector(
      node: root,
      generation: 0,
      startAngle: 0,
      sweep: math.pi * 2,
      innerRadius: 0,
      outerRadius: metrics.centreRadius,
    ),
  ];

  var deepest = 0;
  for (final node in root.everyone) {
    final generation = _generationOf(node.sosa);
    if (generation == 0) continue;
    deepest = generation > deepest ? generation : deepest;

    // Every generation is divided equally, whether or not the tree records
    // the people who would fill it: a slice that keeps its place says plainly
    // that somebody is missing, where a chart that closed the gap would
    // quietly rearrange the family.
    final slots = 1 << generation;
    final sweep = math.pi * 2 / slots;
    final index = node.sosa - slots;

    sectors.add(
      FanSector(
        node: node,
        generation: generation,
        startAngle: index * sweep,
        sweep: sweep,
        innerRadius:
            metrics.centreRadius + (generation - 1) * metrics.ringWidth,
        outerRadius: metrics.centreRadius + generation * metrics.ringWidth,
      ),
    );
  }

  return FanLayout(
    sectors: sectors,
    metrics: metrics,
    diameter: (metrics.centreRadius + deepest * metrics.ringWidth) * 2,
  );
}

/// Which generation a Sosa number belongs to: 1 is the subject, 2–3 their
/// parents, 4–7 their grandparents, and so on by doubling.
int _generationOf(int sosa) {
  var generation = 0;
  var slot = sosa;
  while (slot > 1) {
    slot ~/= 2;
    generation++;
  }
  return generation;
}
