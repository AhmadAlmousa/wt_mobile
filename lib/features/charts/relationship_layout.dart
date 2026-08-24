/// Placing a relationship path on a canvas as a family tree.
///
/// The path view down the page answers *what the link is* — a spine of names
/// with the site's own word on every rung. It does not answer the other
/// question a reader has, which is *where these people sit in the family*: a
/// list cannot show that two branches leave from one grandfather and come back
/// together three generations later, because a list has no up and no down.
///
/// A tree does. Every step states which way it goes ([StepDirection]), so a
/// generation is arithmetic: a step to a parent is a row up, a step to a child
/// is a row down, and anybody the site placed beside somebody stays on their
/// row. That is the same shape webtrees lays out in its own grid, drawn for a
/// phone instead of for a wide screen.
///
/// Deliberately free of widgets, like `chart_layout.dart`: where a box lands
/// is arithmetic, and arithmetic can be tested without pumping a frame.
library;

import 'dart:ui' show Offset, Size;

import '../../domain/charts.dart';
import 'chart_layout.dart';

/// Lays one relationship path out as a family tree.
///
/// Columns advance only when they have to. Two people are drawn in the same
/// column where one is directly above the other — which is what makes a run
/// of parents read as one line up the page — and the column moves along when
/// the path steps sideways, or when it would otherwise land on somebody
/// already placed. That last rule is what draws a cousin correctly: up to a
/// grandparent and down the other branch puts the far end *beside* the
/// subject rather than on top of them.
///
/// Both ends are marked: [ChartPlacement.isSubject] is the person the path
/// starts from, and the person it arrives at is the one the reader was going
/// to — so the canvas can weight them both, and the viewport can open on the
/// start.
ChartLayout layoutRelationshipPath(
  RelationshipPath path, {
  ChartMetrics metrics = const ChartMetrics(),
  BoxWidth? widthOf,
}) {
  final width = widthOf ?? (_) => metrics.boxWidth;

  // Everyone on the path in order, each with the row and column they landed
  // in. Rows are generations and may go negative — a path that leaves upwards
  // starts by climbing — so they are normalised once at the end rather than
  // guessed at up front.
  final rows = <int>[];
  final columns = <int>[];
  final people = [path.from, for (final step in path.steps) step.person];
  final taken = <(int, int)>{};

  var row = 0;
  var column = 0;
  rows.add(row);
  columns.add(column);
  taken.add((row, column));

  for (final step in path.steps) {
    row += step.direction.generations;
    // A sideways step is a step along the page by definition; a vertical one
    // stays in its column unless somebody is already standing there.
    if (step.direction.generations == 0) column += 1;
    while (!taken.add((row, column))) {
      column += 1;
    }
    rows.add(row);
    columns.add(column);
  }

  final topRow = rows.reduce((a, b) => a < b ? a : b);

  // A column is as wide as its widest name, so a tree of long Arabic names
  // and short ones still reads straight down.
  final columnWidth = <int, double>{};
  for (var at = 0; at < people.length; at++) {
    final here = width(people[at]);
    final widest = columnWidth[columns[at]] ?? 0;
    if (here > widest) columnWidth[columns[at]] = here;
  }

  final lastColumn = columns.reduce((a, b) => a > b ? a : b);
  double columnLeft(int index) {
    var x = 0.0;
    for (var at = 0; at < index; at++) {
      x += (columnWidth[at] ?? metrics.boxWidth) + metrics.generationGap;
    }
    return x;
  }

  double rowTop(int index) =>
      (index - topRow) * (metrics.boxHeight + metrics.generationGap);

  final placements = <ChartPlacement>[
    for (var at = 0; at < people.length; at++)
      ChartPlacement(
        person: people[at],
        topLeft: Offset(columnLeft(columns[at]), rowTop(rows[at])),
        width: columnWidth[columns[at]] ?? metrics.boxWidth,
        generation: rows[at] - topRow,
        isSubject: at == 0,
        // The far end is where the reader was going. Marked as a spouse
        // rather than with a field of its own: the canvas already draws that
        // one quietly-different, and a path has no married-in people to
        // confuse it with.
        isSpouse: at == people.length - 1 && people.length > 1,
      ),
  ];

  final edges = <ChartEdge>[
    for (var at = 0; at < path.steps.length; at++)
      _edgeBetween(
        placements[at],
        placements[at + 1],
        step: path.steps[at],
        metrics: metrics,
      ),
  ];

  return ChartLayout(
    metrics: metrics,
    // The generations run down the page, so the joining elbows turn the same
    // way a descendant chart's do.
    flow: ChartFlow.downwards,
    people: placements,
    edges: edges,
    size: Size(
      columnLeft(lastColumn) + (columnWidth[lastColumn] ?? metrics.boxWidth),
      rowTop(rows.reduce((a, b) => a > b ? a : b)) + metrics.boxHeight,
    ),
  );
}

/// The line from one box on the path to the next, and what it is called.
///
/// A step that changes generation leaves the bottom or the top of its box and
/// arrives at the other; a step along the page leaves the side. Anything else
/// would draw a line through the box it came from.
ChartEdge _edgeBetween(
  ChartPlacement from,
  ChartPlacement to, {
  required RelationshipStep step,
  required ChartMetrics metrics,
}) {
  final label = step.relationship.isEmpty ? null : step.relationship;

  return switch (step.direction) {
    StepDirection.toChild => ChartEdge(
      from: Offset(from.centreX, from.topLeft.dy + metrics.boxHeight),
      to: Offset(to.centreX, to.topLeft.dy),
      label: label,
    ),
    StepDirection.toParent => ChartEdge(
      from: Offset(from.centreX, from.topLeft.dy),
      to: Offset(to.centreX, to.topLeft.dy + metrics.boxHeight),
      label: label,
    ),
    // Along the page — and where the direction was never stated, which lands
    // both boxes on the same row and so is the same drawing.
    StepDirection.sideways || StepDirection.unknown => ChartEdge(
      from: Offset(from.right, from.topLeft.dy + metrics.boxHeight / 2),
      to: Offset(to.topLeft.dx, to.topLeft.dy + metrics.boxHeight / 2),
      kind: EdgeKind.sideways,
      label: label,
    ),
  };
}
