/// Placing a family chart on a canvas.
///
/// webtrees lays its charts out in HTML built for a wide screen: floated
/// boxes, background images for the connecting lines, and a reading direction
/// baked into the stylesheet. None of that survives a phone, so the app takes
/// the *shape* the server described and places it here — where a mirrored
/// layout for Arabic is one flag rather than a second stylesheet.
///
/// Deliberately free of widgets. Where a box lands is arithmetic, and
/// arithmetic can be tested without pumping a frame. A box's *width* may
/// depend on the name inside it, which only the interface can measure — so
/// that arrives as a function rather than as a dependency on a font.
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

/// What a line between two boxes means.
enum EdgeKind {
  /// One generation to the next.
  descent,

  /// A couple, drawn side by side.
  marriage,

  /// A couple whose marriage ended — a divorce, an annulment, a separation.
  ///
  /// Worth distinguishing because it changes how the family reads: the
  /// children still belong to both parents, and the parents no longer belong
  /// to each other. webtrees says so in words the app cannot translate; a
  /// chart says it in the line.
  divorce,
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

/// How wide one person's box is drawn.
///
/// The default answers the same for everybody, which is what makes a chart of
/// even columns; a measurer that reads the name gives boxes that hold their
/// names instead. Either way the arithmetic below is the same.
typedef BoxWidth = double Function(PersonRef person);

/// One person, placed.
@immutable
final class ChartPlacement {
  const ChartPlacement({
    required this.person,
    required this.topLeft,
    required this.generation,
    required this.width,
    this.isSubject = false,
    this.isSpouse = false,
  });

  final PersonRef person;
  final Offset topLeft;

  /// How wide this box is drawn. Per person rather than per chart, because a
  /// reader may ask for boxes that hold their names — and this family's names
  /// run from three characters to thirty.
  final double width;

  /// Counting from the person the chart was drawn for, who is generation 0.
  final int generation;

  /// The person the chart is about, drawn with more weight than the rest.
  final bool isSubject;

  /// Married into the family rather than descended through it.
  final bool isSpouse;

  double get right => topLeft.dx + width;
  double get centreX => topLeft.dx + width / 2;
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
    this.kind = EdgeKind.descent,
  });

  final Offset from;
  final Offset to;

  final EdgeKind kind;

  /// A marriage rather than a descent, however it ended.
  bool get isCouple => kind != EdgeKind.descent;
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

  /// Where the person the chart was drawn for ended up, which is where a
  /// viewer too small to hold the whole chart should open.
  ChartPlacement? get subject {
    for (final placement in people) {
      if (placement.isSubject) return placement;
    }
    return people.isEmpty ? null : people.first;
  }

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
            size.width - placement.topLeft.dx - placement.width,
            placement.topLeft.dy,
          ),
          width: placement.width,
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
          kind: edge.kind,
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
  BoxWidth? widthOf,
}) {
  final width = widthOf ?? (_) => metrics.boxWidth;
  final people = <ChartPlacement>[];
  final edges = <ChartEdge>[];
  var nextRow = 0;
  var deepest = 0;

  // Each generation is a column, and a column is as wide as its widest name.
  // Ragged columns would cost the pedigree the one thing it is good at:
  // being read straight down a generation.
  final columnWidth = <int, double>{};
  void measure(AncestorNode node, int generation) {
    final here = width(node.person);
    final widest = columnWidth[generation] ?? 0;
    if (here > widest) columnWidth[generation] = here;
    for (final parent in node.parents) {
      measure(parent, generation + 1);
    }
  }

  measure(root, 0);

  double columnLeft(int generation) {
    var x = 0.0;
    for (var at = 0; at < generation; at++) {
      x += (columnWidth[at] ?? metrics.boxWidth) + metrics.generationGap;
    }
    return x;
  }

  /// Places [node] and every ancestor above it, answering where its own box
  /// ended up. Answering rather than looking the box up again matters: a
  /// family tree can hold the same person twice — cousins marry — and a
  /// search by name or identifier would find the wrong one of them.
  double place(AncestorNode node, int generation) {
    deepest = generation > deepest ? generation : deepest;
    final x = columnLeft(generation);

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
        width: columnWidth[generation] ?? metrics.boxWidth,
        generation: generation,
        isSubject: generation == 0,
      ),
    );

    for (final parentCentre in parentCentres) {
      edges.add(
        ChartEdge(
          from: Offset(
            x + (columnWidth[generation] ?? metrics.boxWidth),
            centreY,
          ),
          to: Offset(columnLeft(generation + 1), parentCentre),
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
      columnLeft(deepest) + (columnWidth[deepest] ?? metrics.boxWidth),
      nextRow * (metrics.boxHeight + metrics.siblingGap) - metrics.siblingGap,
    ),
  );
}

/// Lays a descendant chart out with generations running downwards.
///
/// The one thing this has to get right is *which* marriage a child belongs
/// to. A man with two wives has two sets of children, and a layout that
/// centres him over all of them puts a child under the wrong mother — which
/// is not a crowded chart but a false one. So each family's children are laid
/// out as a contiguous block, and the couple strip above them is built so
/// that each family's line hangs over its own block.
///
/// Children are placed first because a parent is drawn over the family they
/// turned out to have, not the other way round. The strip then adapts: a slot
/// is pushed along when its family's children demand it, and never allowed to
/// land on the slot before it.
ChartLayout layoutDescendants(
  DescendantNode root, {
  ChartMetrics metrics = const ChartMetrics(),
  BoxWidth? widthOf,
}) {
  final width = widthOf ?? (_) => metrics.boxWidth;
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
    final own = width(node.person);

    // Each family's children, laid out one family at a time so a block is
    // contiguous and in the order the site gave — and the middle of each
    // block, which is where that family's line has to hang from.
    final centresPerFamily = <List<double>>[];
    final wanted = <double?>[];
    for (final family in node.families) {
      final centres = [
        for (final child in family.children) place(child, generation + 1),
      ];
      centresPerFamily.add(centres);
      wanted.add(centres.isEmpty ? null : (centres.first + centres.last) / 2);
    }

    // A lone family with no recorded spouse hangs its children from under the
    // person themselves; there is no couple gap to hang them from.
    final hangsFromTheMiddle =
        node.families.length <= 1 &&
        (node.families.isEmpty || node.families.single.spouse == null);

    var left = filled[generation] ?? 0;
    final first = wanted.isEmpty ? null : wanted.first;
    if (first != null) {
      final target = hangsFromTheMiddle
          ? first - own / 2
          : first - metrics.coupleGap / 2 - own;
      // Never over somebody already placed in this generation.
      if (target > left) left = target;
    }

    people.add(
      ChartPlacement(
        person: node.person,
        topLeft: Offset(left, y),
        width: own,
        generation: generation,
        isSubject: generation == 0,
      ),
    );

    var previousRight = left + own;
    for (var index = 0; index < node.families.length; index++) {
      final family = node.families[index];
      final want = wanted[index];

      // The slot this family occupies: after the box before it, and far
      // enough along that the gap in front of it sits over its own children.
      var slot = previousRight + metrics.coupleGap;
      if (want != null && !hangsFromTheMiddle) {
        final overItsChildren = want + metrics.coupleGap / 2;
        if (overItsChildren > slot) slot = overItsChildren;
      }

      final spouse = family.spouse;
      final spouseWidth = spouse == null ? metrics.boxWidth : width(spouse);
      if (spouse != null) {
        people.add(
          ChartPlacement(
            person: spouse,
            topLeft: Offset(slot, y),
            width: spouseWidth,
            generation: generation,
            isSpouse: true,
          ),
        );
        // A line between the two, so a spouse is never mistaken for another
        // child standing in the same row — drawn from the box actually beside
        // them, which is not always one couple gap away once a family has
        // been pushed along to reach its children.
        edges.add(
          ChartEdge(
            from: Offset(previousRight, y + metrics.boxHeight / 2),
            to: Offset(slot, y + metrics.boxHeight / 2),
            kind: family.endedInDivorce ? EdgeKind.divorce : EdgeKind.marriage,
          ),
        );
      }

      // The line to the children hangs from between the couple, whether or
      // not the tree records the other parent.
      final from = Offset(
        hangsFromTheMiddle ? left + own / 2 : slot - metrics.coupleGap / 2,
        y + metrics.boxHeight,
      );
      for (final centre in centresPerFamily[index]) {
        edges.add(
          ChartEdge(
            from: from,
            to: Offset(centre, y + metrics.boxHeight + metrics.generationGap),
          ),
        );
      }

      previousRight = slot + spouseWidth;
    }

    filled[generation] = previousRight + metrics.siblingGap;
    return left + own / 2;
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

/// Lays an ancestor chart out with generations running *upwards*.
///
/// The sideways pedigree is the better read on its own, but an hourglass has
/// to stack: ancestors climbing away from the subject, descendants falling
/// from them, and one person in the middle belonging to both halves.
ChartLayout layoutAncestorsUpwards(
  AncestorNode root, {
  ChartMetrics metrics = const ChartMetrics(),
  BoxWidth? widthOf,
}) {
  final width = widthOf ?? (_) => metrics.boxWidth;
  final people = <ChartPlacement>[];
  final edges = <ChartEdge>[];
  final filled = <int, double>{};
  final generations = root.depth;

  double place(AncestorNode node, int generation) {
    final y =
        (generations - 1 - generation) *
        (metrics.boxHeight + metrics.generationGap);
    final own = width(node.person);

    final parentCentres = [
      for (final parent in node.parents) place(parent, generation + 1),
    ];

    final start = filled[generation] ?? 0;
    var left = parentCentres.isEmpty
        ? start
        : (parentCentres.first + parentCentres.last) / 2 - own / 2;
    if (left < start) left = start;

    people.add(
      ChartPlacement(
        person: node.person,
        topLeft: Offset(left, y),
        width: own,
        generation: generation,
        isSubject: generation == 0,
      ),
    );

    for (final parentCentre in parentCentres) {
      edges.add(
        ChartEdge(
          from: Offset(left + own / 2, y),
          to: Offset(parentCentre, y - metrics.generationGap),
        ),
      );
    }

    filled[generation] = left + own + metrics.siblingGap;
    return left + own / 2;
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
      generations * metrics.boxHeight +
          (generations - 1) * metrics.generationGap,
    ),
  );
}

/// Lays one person's ancestors and descendants out around them.
///
/// The person appears once, in the middle, belonging to both halves — which
/// is the whole point of an hourglass and the one thing stitching two charts
/// together has to get right.
ChartLayout layoutHourglass(
  AncestorNode ancestors,
  DescendantNode descendants, {
  ChartMetrics metrics = const ChartMetrics(),
  BoxWidth? widthOf,
}) {
  final above = layoutAncestorsUpwards(
    ancestors,
    metrics: metrics,
    widthOf: widthOf,
  );
  final below = layoutDescendants(
    descendants,
    metrics: metrics,
    widthOf: widthOf,
  );

  final subjectAbove = above.people.firstWhere((person) => person.isSubject);
  final subjectBelow = below.people.firstWhere((person) => person.isSubject);
  final shift = subjectAbove.topLeft - subjectBelow.topLeft;

  final people = <ChartPlacement>[
    ...above.people,
    // The subject is in both halves and drawn once, from the half that
    // decided where the middle is.
    for (final placement in below.people)
      if (!placement.isSubject)
        ChartPlacement(
          person: placement.person,
          topLeft: placement.topLeft + shift,
          width: placement.width,
          generation: placement.generation,
          isSpouse: placement.isSpouse,
        ),
  ];
  final edges = <ChartEdge>[
    ...above.edges,
    for (final edge in below.edges)
      ChartEdge(from: edge.from + shift, to: edge.to + shift, kind: edge.kind),
  ];

  // The descendants may reach further left than the ancestors do, so the
  // whole thing is nudged back onto the canvas rather than drawn off it.
  final left = people.fold(
    0.0,
    (least, p) => p.topLeft.dx < least ? p.topLeft.dx : least,
  );
  final nudge = Offset(-left, 0);

  final placed = [
    for (final placement in people)
      ChartPlacement(
        person: placement.person,
        topLeft: placement.topLeft + nudge,
        width: placement.width,
        generation: placement.generation,
        isSubject: placement.isSubject,
        isSpouse: placement.isSpouse,
      ),
  ];

  return ChartLayout(
    metrics: metrics,
    flow: ChartFlow.downwards,
    people: placed,
    edges: [
      for (final edge in edges)
        ChartEdge(
          from: edge.from + nudge,
          to: edge.to + nudge,
          kind: edge.kind,
        ),
    ],
    size: Size(
      placed.fold(0.0, (widest, p) => p.right > widest ? p.right : widest),
      placed.fold(
        0.0,
        (tallest, p) => p.topLeft.dy + metrics.boxHeight > tallest
            ? p.topLeft.dy + metrics.boxHeight
            : tallest,
      ),
    ),
  );
}

double _larger(double a, double b) => a > b ? a : b;
