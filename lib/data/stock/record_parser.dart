import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:meta/meta.dart';

import '../../core/errors.dart';
import '../../domain/records.dart';
import 'dom.dart';

/// Reads individuals out of the HTML a stock webtrees site renders.
///
/// Every selector here was taken from the upstream templates and checked
/// against both 2.2.6 and 2.3, which render these parts identically. Where a
/// choice existed the structural signal was preferred over the visible one:
/// `data-wt-chart-xref` rather than a link position, a CSS class rather than a
/// heading, because the headings are translated and this app's first real tree
/// is in Arabic.
final class RecordParser {
  const RecordParser({this.version});

  /// The webtrees version that produced the page, carried into failures so a
  /// bug report says which version broke.
  final String? version;

  /// Reads the name, photo and available tabs from an individual's page.
  ///
  /// The tabs matter as much as the content: webtrees prints each one's exact
  /// fragment URL in `data-wt-href`, so the app never has to build those URLs
  /// or assume which tabs a tree has enabled.
  IndividualPage parseIndividualPage(String body, {required String xref}) {
    final document = html.parse(body);

    final title = document.querySelector('h2.wt-page-title');
    if (title == null) {
      throw ParseFailure(
        parser: 'individual page',
        expected: 'h2.wt-page-title',
        version: version,
      );
    }

    // Every rendered name webtrees produces — on the page title and on each
    // entry of the names accordion — is wrapped in `span.NAME`. The title
    // itself also carries the lifespan and age, so the span is the only part
    // that is purely the name.
    final names = _names(document, title);

    return IndividualPage(
      xref: xref,
      name: names.isEmpty ? xref : names.first,
      // A second NAME record: a romanized form beside an Arabic one, a
      // married name beside a maiden one. Common enough in real trees that
      // dropping it would look like data loss.
      alternateName: names.length > 1 ? names[1] : null,
      thumbnailUrl: document
          .querySelector('img.img-thumbnail')
          ?.attributes['src'],
      tabs: _tabs(document),
      inlineTabs: _inlineTabs(document),
    );
  }

  /// Every name recorded for this person, primary first.
  List<String> _names(Document document, Element title) {
    final names = <String>[
      for (final name in document.querySelectorAll(
        '#individual-names span.NAME',
      ))
        ?textOf(name),
    ];
    if (names.isNotEmpty) return names;

    // No names accordion — an older theme, or a page rendered with sidebars
    // laid out differently. The title still holds the primary name.
    final fromTitle = textOf(title.querySelector('span.NAME'));
    return fromTitle == null ? const [] : [fromTitle];
  }

  /// The fragment URL of each tab the site offers, keyed by module name.
  ///
  /// The module name comes from the anchor's `href="#name"`, which points at
  /// the pane the tab fills. 2.3 also gives the anchor `id="name-tab"`, but
  /// 2.2.6 does not — keying on the id would find no tabs at all on the older
  /// version, which is the one this project's own server runs.
  Map<String, String> _tabs(Document document) {
    final tabs = <String, String>{};
    for (final link in document.querySelectorAll('a[data-wt-href]')) {
      final href = link.attributes['data-wt-href'];
      final target = link.attributes['href'];
      if (href == null || target == null || !target.startsWith('#')) continue;

      final module = target.substring(1);
      if (module.isNotEmpty) tabs[module] = href;
    }
    return tabs;
  }

  /// Tab panes whose content webtrees already rendered into the page.
  ///
  /// A tab only loads over AJAX when its module says it may; the rest arrive
  /// inline, and re-requesting them would be a wasted round trip that returns
  /// the same markup.
  Map<String, String> _inlineTabs(Document document) {
    final panes = <String, String>{};
    for (final pane in document.querySelectorAll('.tab-pane[id]')) {
      final content = pane.innerHtml.trim();
      if (content.isNotEmpty) panes[pane.id] = content;
    }
    return panes;
  }

  /// Reads the rows of a personal facts tab.
  ///
  /// Missing rows are not an error: a tree can restrict facts per record, and
  /// a person with nothing recorded legitimately renders an empty table.
  List<FactEntry> parseFacts(String fragment) {
    final document = html.parseFragment(fragment);
    final facts = <FactEntry>[];

    for (final row in document.querySelectorAll('tr')) {
      final label = textOf(row.querySelector('.wt-fact-label'));
      if (label == null) continue;

      // Pending deletions are shown struck through in the web interface. The
      // app has no editing story in v1, so they would only mislead.
      final classes = row.className;
      if (classes.contains('wt-old')) continue;

      final value = textOf(row.querySelector('.wt-fact-value'));
      final place = textOf(row.querySelector('.wt-fact-place'));

      facts.add(
        FactEntry(
          label: label,
          value: value,
          // The date box also holds computed ages, which belong to the
          // rendering rather than to the fact.
          date: textWithout(row.querySelector('.wt-fact-date-age'), const [
            '.age',
            '.label',
          ]),
          place: place,
          type: textOf(row.querySelector('.wt-fact-type')),
          // webtrees collapses relatives' events, historical events and
          // associates by default; they are context, not this person's facts.
          isSecondary: classes.contains('collapse'),
        ),
      );
    }
    return facts;
  }

  /// Reads the family blocks of a relatives tab.
  ///
  /// Each family is its own table: a caption linking to the family record,
  /// then the couple, then any marriage facts, then the children — the order
  /// the upstream template emits in both supported versions.
  List<FamilyGroup> parseRelatives(String fragment, {required String xref}) {
    final document = html.parseFragment(fragment);
    final families = <FamilyGroup>[];

    for (final table in document.querySelectorAll('table')) {
      final caption = table.querySelector('caption a[href]');
      final familyXref = xrefIn(caption?.attributes['href'], 'family');
      // Tables without a family caption are the tab's own controls, such as
      // the "date differences" toggle.
      if (familyXref == null) continue;

      final (spouses, children) = _splitFamily(table);
      families.add(
        FamilyGroup(
          xref: familyXref,
          label: textOf(caption) ?? familyXref,
          kind: _kindOf(xref, spouses, children),
          spouses: spouses,
          children: children,
        ),
      );
    }
    return families;
  }

  /// Splits a family table into its couple and its children.
  ///
  /// The template emits spouses, then marriage facts, then children. The fact
  /// rows carry no chart box, which makes them a reliable divider; when a
  /// family records no marriage at all there is no divider, and the leading
  /// pair of people are the couple.
  (List<PersonRef>, List<PersonRef>) _splitFamily(Element table) {
    final spouses = <PersonRef>[];
    final children = <PersonRef>[];
    var seenDivider = false;

    for (final row in table.querySelectorAll('tr')) {
      final box = row.querySelector('.wt-chart-box[data-wt-chart-xref]');
      if (box == null) {
        // A marriage or divorce row. Rows that are neither — the "add a
        // child" links an editor sees — carry no chart box either, but they
        // only ever appear after the children, so treating them as a divider
        // costs nothing.
        if (row.querySelector('.field') != null) seenDivider = true;
        continue;
      }

      final person = _personFrom(box);
      if (person == null) continue;

      if (!seenDivider && spouses.length < 2) {
        spouses.add(person);
      } else {
        seenDivider = true;
        children.add(person);
      }
    }
    return (spouses, children);
  }

  /// Decides what a family is to the person being viewed.
  ///
  /// Structural, not textual: the captions say "Parents" and "Family with …"
  /// in the tree's own language, so reading them would make the app work in
  /// English and quietly mis-sort every other language.
  FamilyKind _kindOf(
    String xref,
    List<PersonRef> spouses,
    List<PersonRef> children,
  ) {
    if (spouses.any((person) => person.xref == xref)) return FamilyKind.own;
    if (children.any((person) => person.xref == xref)) {
      return FamilyKind.parents;
    }
    // Step-families list neither the viewer as spouse nor as child.
    return FamilyKind.step;
  }

  /// Reads one `chart-box`, webtrees' standard person card.
  PersonRef? _personFrom(Element box) {
    final xref = box.attributes['data-wt-chart-xref'];
    if (xref == null || xref.isEmpty) return null;

    final nameBox = box.querySelector(
      '.wt-chart-box-name:not(.wt-chart-box-name-alt)',
    );

    return PersonRef(
      xref: xref,
      name: textOf(nameBox) ?? textOf(box.querySelector('a[href]')) ?? xref,
      alternateName: textOf(box.querySelector('.wt-chart-box-name-alt')),
      lifespan: textOf(box.querySelector('.wt-chart-box-lifespan')),
      sex: _sexOf(box),
      thumbnailUrl: box
          .querySelector('.wt-chart-box-thumbnail img')
          ?.attributes['src'],
    );
  }

  static Sex _sexOf(Element box) {
    for (final name in box.classes) {
      if (name.startsWith('wt-chart-box-') && name.length == 14) {
        return Sex.fromCssSuffix(name.substring(13));
      }
    }
    return Sex.unknown;
  }
}

/// The parts of an individual's page that are not in a tab.
@immutable
final class IndividualPage {
  IndividualPage({
    required this.xref,
    required this.name,
    required Map<String, String> tabs,
    required Map<String, String> inlineTabs,
    this.alternateName,
    this.thumbnailUrl,
  }) : tabs = Map.unmodifiable(tabs),
       inlineTabs = Map.unmodifiable(inlineTabs);

  final String xref;
  final String name;
  final String? alternateName;
  final String? thumbnailUrl;

  /// Module name to fragment URL, exactly as the server wrote it.
  final Map<String, String> tabs;

  /// Module name to already-rendered content, for tabs that do not use AJAX.
  final Map<String, String> inlineTabs;
}
