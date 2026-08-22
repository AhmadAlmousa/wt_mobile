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
  };

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
