import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../core/errors.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import 'chart_box.dart';
import 'dom.dart';
import 'fact_tags.dart';

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
    final root = html.parseFragment(fragment);
    final level = _topLevel(fragment, 'descendants chart');
    // What this site calls a divorce, learned from the fact blocks inside its
    // own chart boxes. Each family's caption runs its labels together into
    // one sentence, so the dictionary is the only way to read one out of it
    // without knowing the language the sentence is in.
    final node = _descendantFrom(level, '1', FactTagIndex.from(root));
    if (node == null) {
      throw ParseFailure(
        parser: 'descendants chart',
        expected: 'a chart box for the person the chart was drawn for',
        version: version,
      );
    }
    return node;
  }

  /// Reads a timeline: events against a scale of years.
  ///
  /// webtrees draws this one by absolute position — a column of year labels
  /// down one side and a box per event beside them, each placed with a `top`
  /// in pixels. That is not a layout worth keeping, but it *is* a statement
  /// of where every event sits relative to every year, which is exactly what
  /// a timeline is. So both are read as positions and compared with each
  /// other; no date is parsed, and no numeral has to be understood.
  TimelineChart parseTimeline(String fragment) {
    final root = html.parseFragment(fragment);
    final ticks = <TimelineTick>[];
    final events = <TimelineEvent>[];

    for (final element in root.querySelectorAll('div[id]')) {
      final id = element.id;
      final top = _topOf(element);
      if (top == null) continue;

      if (id.startsWith('scale')) {
        final year = int.tryParse(id.substring(5));
        // The year is in the id as plain digits, where the label beside it is
        // written in the reader's own numerals.
        if (year != null) ticks.add(TimelineTick(year: year, position: top));
        continue;
      }
      if (id.startsWith('fact')) {
        final label = textOf(element);
        if (label != null) {
          events.add(TimelineEvent(label: label, position: top));
        }
      }
    }

    return TimelineChart(ticks: ticks, events: events);
  }

  /// The `top` of an absolutely positioned element, in pixels.
  static double? _topOf(Element element) {
    final style = element.attributes['style'];
    if (style == null) return null;

    final match = RegExp(r'top:\s*(-?[\d.]+)px').firstMatch(style);
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  /// Reads a relationship chart: how two people are connected, and by whom.
  ///
  /// webtrees lays this one out as a grid of positioned cells with lines drawn
  /// in background images — a shape that says nothing on a phone. What it does
  /// state is a path: boxes joined by named steps, laid out so that each step
  /// sits between the two people it links. Walking that grid recovers the
  /// order; the heading above it carries webtrees' own phrase for the whole
  /// relationship, which no app should try to compose for itself.
  ///
  /// Several paths may be found — a family where cousins marry connects two
  /// people by more than one line, and each is true — so this answers a list.
  List<RelationshipPath> parseRelationships(
    String fragment, {
    required String from,
  }) {
    final root = html.parseFragment(fragment);
    final paths = <RelationshipPath>[];

    String heading = '';
    for (final element in root.querySelectorAll('h3, table')) {
      if (element.localName == 'h3') {
        heading = textOf(element) ?? '';
        continue;
      }

      final path = _relationshipIn(element, heading: heading, from: from);
      if (path != null) paths.add(path);
    }
    return paths;
  }

  /// Walks one relationship grid from [from] outwards.
  RelationshipPath? _relationshipIn(
    Element table, {
    required String heading,
    required String from,
  }) {
    // Every cell is printed, empty ones included, so a row and column index
    // is a position rather than a guess.
    final grid = <List<Element>>[
      for (final row in table.querySelectorAll('tr'))
        row.querySelectorAll('td'),
    ];

    PersonRef? personAt(int row, int column) {
      if (row < 0 || row >= grid.length) return null;
      if (column < 0 || column >= grid[row].length) return null;
      final box = grid[row][column].querySelector(
        '.wt-chart-box[data-wt-chart-xref]',
      );
      return box == null ? null : personFromChartBox(box);
    }

    String? labelAt(int row, int column) {
      if (row < 0 || row >= grid.length) return null;
      if (column < 0 || column >= grid[row].length) return null;
      final cell = grid[row][column];
      if (cell.querySelector('.wt-chart-box') != null) return null;
      return textOf(cell);
    }

    var atRow = -1;
    var atColumn = -1;
    PersonRef? start;
    for (var row = 0; row < grid.length && start == null; row++) {
      for (var column = 0; column < grid[row].length; column++) {
        final person = personAt(row, column);
        if (person?.xref == from) {
          start = person;
          atRow = row;
          atColumn = column;
          break;
        }
      }
    }
    if (start == null) return null;

    // A step moves two cells: the relationship's name sits between the two
    // people it links, whether they are stacked, side by side, or — where
    // webtrees turns a corner — diagonally apart.
    const directions = [
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1],
      [-1, -1],
      [-1, 1],
      [1, -1],
      [1, 1],
    ];

    final steps = <RelationshipStep>[];
    final seen = <String>{start.xref};

    var moved = true;
    while (moved) {
      moved = false;
      for (final direction in directions) {
        final label = labelAt(atRow + direction[0], atColumn + direction[1]);
        if (label == null) continue;

        final next = personAt(
          atRow + direction[0] * 2,
          atColumn + direction[1] * 2,
        );
        if (next == null || !seen.add(next.xref)) continue;

        steps.add(RelationshipStep(relationship: label, person: next));
        atRow += direction[0] * 2;
        atColumn += direction[1] * 2;
        moved = true;
        break;
      }
    }

    return RelationshipPath(description: heading, from: start, steps: steps);
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
  DescendantNode? _descendantFrom(
    List<Element> level,
    String number,
    FactTagIndex tags,
  ) {
    Element? boxRow;
    final families = <DescendantFamily>[];
    String? pendingLabel;

    // webtrees numbers a person's children across *all* their families —
    // `$child_number` is declared before the family loop in its own template
    // and never reset — so a second marriage continues the count rather than
    // starting it again. Numbering per family gave two children `1.1`.
    var born = 0;

    for (final element in level) {
      if (element.id.startsWith('fam-')) {
        families.add(
          _descendantFamily(
            element,
            label: pendingLabel,
            nextNumber: () => '$number.${++born}',
            tags: tags,
          ),
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
    required String Function() nextNumber,
    required FactTagIndex tags,
    String? label,
  }) {
    PersonRef? spouse;
    final children = <DescendantNode>[];

    for (final element in block.children) {
      if (element.classes.contains('wt-chart-box')) {
        spouse ??= personFromChartBox(element);
        continue;
      }
      final child = _descendantFrom(_nestedLevel(element), nextNumber(), tags);
      if (child != null) children.add(child);
    }

    return DescendantFamily(
      xref: block.id.replaceFirst('fam-', ''),
      spouse: spouse,
      label: label,
      // The caption webtrees writes above a family runs its marriage, its
      // divorce and its child count together with no markup between them —
      // so the question is whether any of this site's divorce labels appears
      // in it, which the dictionary can answer and a word list cannot.
      endedInDivorce: tags.mentionsDivorce(label),
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
