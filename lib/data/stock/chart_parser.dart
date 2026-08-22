import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../core/errors.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import 'chart_box.dart';
import 'dom.dart';

/// Reads the structure out of the charts a webtrees site draws.
///
/// The app cannot show webtrees' own chart markup: it is built for a wide
/// screen, positions boxes with CSS floats and background images, and reads
/// left to right. What it *can* take from it is the shape — who descends from
/// whom — which webtrees states by nesting one recursion of its template
/// inside another.
///
/// Both charts also print a number beside each person, and neither is read
/// here. The ancestors chart numbers people the Sosa-Stradonitz way and
/// renders that number in the reader's own numerals — `٤` in Arabic — so a
/// parser keyed on it would work in English and fail in the language this app
/// was built for. The nesting says the same thing in every language.
final class ChartParser {
  const ChartParser({this.version});

  /// The webtrees version that produced the chart, carried into failures.
  final String? version;

  /// Reads an ancestors chart: the subject, and the parents above them.
  AncestorNode parseAncestors(String fragment) {
    final level = _topLevel(fragment, 'ancestors chart');
    final node = _ancestorFrom(level);
    if (node == null) {
      throw ParseFailure(
        parser: 'ancestors chart',
        expected: 'a chart box for the person the chart was drawn for',
        version: version,
      );
    }
    return _numbered(node, 1);
  }

  /// Reads a descendants chart: the subject, their families, their children.
  DescendantNode parseDescendants(String fragment) {
    final level = _topLevel(fragment, 'descendants chart');
    final node = _descendantFrom(level, '1');
    if (node == null) {
      throw ParseFailure(
        parser: 'descendants chart',
        expected: 'a chart box for the person the chart was drawn for',
        version: version,
      );
    }
    return node;
  }

  /// The elements one recursion of a chart template emits.
  ///
  /// A chart arrives as a run of sibling elements rather than one container —
  /// the box, the control above the parents, the block holding them — so the
  /// first chart box is what locates the level everything else sits in. That
  /// also lets the same parser read a whole page and the AJAX fragment of it.
  List<Element> _topLevel(String fragment, String parser) {
    final root = html.parseFragment(fragment);
    final box = root.querySelector('.wt-chart-box[data-wt-chart-xref]');
    if (box == null) {
      throw ParseFailure(
        parser: parser,
        expected: '.wt-chart-box[data-wt-chart-xref]',
        version: version,
      );
    }
    return _siblingsOf(box.parent?.parentNode);
  }

  static List<Element> _siblingsOf(Node? node) =>
      node == null ? const [] : node.nodes.whereType<Element>().toList();

  /// The element a nested recursion was rendered into.
  ///
  /// Each row inside a family block is an indent drawing the connecting lines
  /// followed by the subtree itself, so the subtree is the row's last child.
  static List<Element> _nestedLevel(Element row) {
    final children = row.children;
    return children.isEmpty ? const [] : _siblingsOf(children.last);
  }

  /// One person of an ancestors chart, and everyone above them.
  ///
  /// Numbering happens afterwards: a person's Sosa number depends on their
  /// recorded sex, which is only known once their box has been read.
  _Ancestor? _ancestorFrom(List<Element> level) {
    Element? boxRow;
    Element? familyBlock;
    String? label;

    for (final element in level) {
      // The block holding the parents. Skipped here so the search for this
      // person's own box cannot reach into it and find their father instead.
      if (element.id.startsWith('fam-')) {
        familyBlock ??= element;
        continue;
      }
      if (boxRow == null &&
          element.querySelector('.wt-chart-box[data-wt-chart-xref]') != null) {
        boxRow = element;
        continue;
      }
      label ??= textOf(element.querySelector('.wt-chart-expansion-control'));
    }

    final box = boxRow?.querySelector('.wt-chart-box[data-wt-chart-xref]');
    final person = box == null ? null : personFromChartBox(box);
    if (person == null) return null;

    final parents = <_Ancestor>[];
    for (final row in familyBlock?.children ?? const <Element>[]) {
      final parent = _ancestorFrom(_nestedLevel(row));
      if (parent != null) parents.add(parent);
    }

    return _Ancestor(
      person: person,
      familyXref: familyBlock?.id.replaceFirst('fam-', ''),
      label: label,
      parents: parents,
    );
  }

  /// Numbers a parsed ancestor tree the way webtrees does.
  ///
  /// The subject is 1, and a person's parents are 2n and 2n+1 — the father
  /// taking the even slot. webtrees decides that by recorded sex, so a family
  /// where neither parent is recorded female would put both in the same slot;
  /// the order the site emitted them in settles it.
  AncestorNode _numbered(_Ancestor node, int sosa) {
    final taken = <int>{};
    final numbered = <AncestorNode>[];

    for (var index = 0; index < node.parents.length; index++) {
      final parent = node.parents[index];
      var slot = sosa * 2 + (parent.person.sex == Sex.female ? 1 : 0);
      if (!taken.add(slot)) {
        slot = sosa * 2 + (index == 0 ? 0 : 1);
        taken.add(slot);
      }
      numbered.add(_numbered(parent, slot));
    }

    return AncestorNode(
      person: node.person,
      sosa: sosa,
      familyXref: node.familyXref,
      parentsLabel: node.label,
      parents: numbered,
    );
  }

  /// One person of a descendants chart, and everyone below them.
  ///
  /// The d'Aboville number webtrees prints is not read either, for the same
  /// reason the Sosa numbers are not — though this one arrives in plain
  /// digits, because webtrees builds it by joining integers rather than
  /// formatting a number. It is rebuilt here from the nesting, which says the
  /// same thing.
  DescendantNode? _descendantFrom(List<Element> level, String number) {
    Element? boxRow;
    final families = <DescendantFamily>[];
    String? pendingLabel;

    for (final element in level) {
      if (element.id.startsWith('fam-')) {
        families.add(
          _descendantFamily(element, label: pendingLabel, number: number),
        );
        pendingLabel = null;
        continue;
      }
      if (boxRow == null &&
          element.querySelector('.wt-chart-box[data-wt-chart-xref]') != null) {
        boxRow = element;
        continue;
      }
      // Every family is announced by a control carrying webtrees' own summary
      // of it — the marriage, and how many children it had.
      pendingLabel =
          textOf(element.querySelector('.wt-chart-expansion-control')) ??
          pendingLabel;
    }

    final box = boxRow?.querySelector('.wt-chart-box[data-wt-chart-xref]');
    final person = box == null ? null : personFromChartBox(box);
    if (person == null) return null;

    return DescendantNode(person: person, number: number, families: families);
  }

  /// One family block of a descendants chart.
  ///
  /// The spouse's box sits directly inside the block, before the rows holding
  /// the children — the one chart box here that is nobody's subtree.
  DescendantFamily _descendantFamily(
    Element block, {
    required String number,
    String? label,
  }) {
    PersonRef? spouse;
    final children = <DescendantNode>[];

    for (final element in block.children) {
      if (element.classes.contains('wt-chart-box')) {
        spouse ??= personFromChartBox(element);
        continue;
      }
      final child = _descendantFrom(
        _nestedLevel(element),
        '$number.${children.length + 1}',
      );
      if (child != null) children.add(child);
    }

    return DescendantFamily(
      xref: block.id.replaceFirst('fam-', ''),
      spouse: spouse,
      label: label,
      children: children,
    );
  }
}

/// An ancestor read from the markup, before it has been numbered.
final class _Ancestor {
  _Ancestor({
    required this.person,
    required this.parents,
    this.familyXref,
    this.label,
  });

  final PersonRef person;
  final String? familyXref;
  final String? label;
  final List<_Ancestor> parents;
}
