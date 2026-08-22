/// The charts a webtrees site offers, and the shapes they describe.
///
/// webtrees draws these itself, in HTML built for a wide screen and a mouse.
/// This app reads the *structure* out of them — who descends from whom — and
/// draws it again for a phone. Nothing here holds a pixel, a colour or a
/// layout: those belong to the interface, which has to mirror for Arabic and
/// fit a hand.
library;

import 'package:meta/meta.dart';

import 'records.dart';

/// A chart a site offers for a person.
///
/// Named after the CSS class webtrees puts on its own menu links
/// (`menu-chart-ancestry`), because that class is how the app discovers which
/// charts an instance actually runs — the same rule tabs follow. A site with a
/// chart module switched off simply never emits the link.
enum ChartKind {
  ancestors('menu-chart-ancestry'),
  descendants('menu-chart-descendants'),
  pedigree('menu-chart-pedigree'),
  fan('menu-chart-fanchart'),
  compact('menu-chart-compact'),
  hourglass('menu-chart-hourglass'),
  familyBook('menu-chart-familybook'),
  interactiveTree('menu-chart-tree'),
  relationship('menu-chart-relationship'),
  pedigreeMap('menu-chart-pedigreemap'),
  timeline('menu-chart-timeline'),
  lifespan('menu-chart-lifespan'),
  statistics('menu-chart-statistics');

  const ChartKind(this.menuClass);

  /// The class webtrees marks its own link to this chart with.
  final String menuClass;

  /// The charts this app draws for itself.
  ///
  /// webtrees renders each of these as a shape — who descends from whom — that
  /// survives being drawn again for a phone. The rest of what a site offers is
  /// a map, a statistics page or a report, which are not shapes of this kind
  /// and are not claimed here.
  static const Set<ChartKind> drawable = {
    ChartKind.ancestors,
    ChartKind.descendants,
    ChartKind.hourglass,
    ChartKind.relationship,
  };

  /// The charts the app can actually draw for a person, given what the site
  /// offered for them.
  ///
  /// An hourglass is not fetched: it is the two charts either side of a
  /// person, stacked. So a site that runs the hourglass module but not both
  /// of those cannot have one drawn here, and is not offered it.
  static List<ChartKind> drawnFrom(Map<ChartKind, String> offered) {
    final halves =
        offered.containsKey(ChartKind.ancestors) &&
        offered.containsKey(ChartKind.descendants);

    return [
      for (final kind in drawable)
        if (offered.containsKey(kind))
          if (kind != ChartKind.hourglass || halves) kind,
    ];
  }

  /// The chart [cssClass] names, or null when it names none of them.
  static ChartKind? fromMenuClass(String cssClass) {
    for (final kind in values) {
      if (kind.menuClass == cssClass) return kind;
    }
    return null;
  }
}

/// One person in an ancestor chart, with the parents recorded above them.
///
/// The tree is read from webtrees' own nesting rather than from the
/// Sosa-Stradonitz numbers it prints beside each box: those are rendered in
/// the reader's numerals — `٤` in Arabic — so a parser that read them would
/// work in English and quietly fail in the language this app was built for.
/// [sosa] is therefore computed here, by webtrees' own rule.
@immutable
final class AncestorNode {
  AncestorNode({
    required this.person,
    required this.sosa,
    this.familyXref,
    this.parentsLabel,
    List<AncestorNode> parents = const [],
  }) : parents = List.unmodifiable(parents);

  final PersonRef person;

  /// The Sosa-Stradonitz number: 1 is the subject, 2 their father, 3 their
  /// mother, and a person's parents are always 2n and 2n+1.
  final int sosa;

  /// The family this person was born into, when the chart shows it.
  final String? familyXref;

  /// What webtrees wrote on the control above the parents — "Parents —
  /// Marriage 1898 — 3 children" — already translated, so it is shown as it
  /// arrived rather than rebuilt from parts.
  final String? parentsLabel;

  /// Father first, mother second, as webtrees emits them; either may be
  /// absent, and a chart stops where the tree does.
  final List<AncestorNode> parents;

  /// This node and every ancestor above it.
  Iterable<AncestorNode> get everyone sync* {
    yield this;
    for (final parent in parents) {
      yield* parent.everyone;
    }
  }

  /// Everyone in the chart, by their Sosa number.
  ///
  /// Safe as a key where a person is not: the numbering is derived from where
  /// somebody sits, so a tree that folds back on itself — cousins marrying,
  /// which is ordinary in this family — holds one person under two numbers,
  /// exactly as a pedigree should.
  Map<int, AncestorNode> get bySosa => {
    for (final node in everyone) node.sosa: node,
  };

  /// How many generations this chart actually holds, the subject counting as
  /// one — which is rarely the number that was asked for, because a tree runs
  /// out before the chart does.
  int get depth =>
      1 +
      parents.fold(
        0,
        (deepest, parent) => deepest > parent.depth ? deepest : parent.depth,
      );
}

/// One family in a descendant chart: a couple and their children.
@immutable
final class DescendantFamily {
  DescendantFamily({
    required this.xref,
    this.spouse,
    this.label,
    List<DescendantNode> children = const [],
  }) : children = List.unmodifiable(children);

  final String xref;

  /// The other parent, absent when the tree records only one.
  final PersonRef? spouse;

  /// webtrees' own summary of the family — "Marriage 1925 — 2 children".
  final String? label;

  final List<DescendantNode> children;
}

/// One person in a descendant chart, with the families they made.
@immutable
final class DescendantNode {
  DescendantNode({
    required this.person,
    required this.number,
    List<DescendantFamily> families = const [],
  }) : families = List.unmodifiable(families);

  final PersonRef person;

  /// The d'Aboville number webtrees prints beside the box — `1.2.1`, the
  /// second child's first child. Unlike the Sosa numbers on an ancestor
  /// chart it is built by string concatenation, so it arrives in plain
  /// digits whatever language the site is rendering in.
  final String number;

  final List<DescendantFamily> families;

  /// Everyone below this person, including them.
  Iterable<DescendantNode> get everyone sync* {
    yield this;
    for (final family in families) {
      for (final child in family.children) {
        yield* child.everyone;
      }
    }
  }

  /// The generation this person sits in, counting the subject as one.
  int get depth => '.'.allMatches(number).length + 1;
}

/// One step along a relationship path: a link, and who it reaches.
@immutable
final class RelationshipStep {
  const RelationshipStep({required this.relationship, required this.person});

  /// How the two are related, in the site's own words — `father`, `أم` —
  /// already translated, and already knowing whether a brother is older or
  /// younger, which is a distinction Arabic makes and English does not.
  final String relationship;

  /// The person this step arrives at.
  final PersonRef person;
}

/// One way two people are related.
///
/// webtrees can find several: a family where cousins marry links two people
/// through more than one line, and each is true.
@immutable
final class RelationshipPath {
  RelationshipPath({
    required this.description,
    required this.from,
    required List<RelationshipStep> steps,
  }) : steps = List.unmodifiable(steps);

  /// The whole relationship as one phrase, as the site put it.
  final String description;

  /// Where the path starts — the person whose page it was opened from.
  final PersonRef from;

  final List<RelationshipStep> steps;

  /// The person at the far end.
  PersonRef? get to => steps.isEmpty ? null : steps.last.person;
}

/// A chart as the app read it, whichever direction it runs in.
@immutable
final class ChartData {
  const ChartData({
    required this.kind,
    required this.subject,
    this.ancestors,
    this.descendants,
  });

  final ChartKind kind;

  /// The person the chart was drawn for.
  final PersonRef subject;

  /// Present for a chart that runs upwards.
  final AncestorNode? ancestors;

  /// Present for a chart that runs downwards.
  final DescendantNode? descendants;

  /// How many people the chart holds, the subject included.
  int get size =>
      ancestors?.everyone.length ?? descendants?.everyone.length ?? 0;
}
