import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:meta/meta.dart';

import '../../core/errors.dart';
import '../../domain/charts.dart';
import '../../domain/dates.dart';
import '../../domain/records.dart';
import 'chart_box.dart';
import 'dom.dart';
import 'fact_tags.dart';

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
      sex: _sexFromSilhouette(document),
      tabs: _tabs(document),
      inlineTabs: _inlineTabs(document),
      charts: parseChartMenu(document, xref: xref),
    );
  }

  /// The sex webtrees encoded in the silhouette it drew for this person.
  ///
  /// A weak signal and only a fallback: webtrees renders the silhouette in
  /// place of a photograph, so it exists only for someone with no media on a
  /// tree that has silhouettes switched on. It is here because the page's own
  /// statement of sex — inside the names accordion — is the *translated* word
  /// for it, and reading that would work in English alone. The reliable
  /// answer comes from the chart boxes on the relatives tab.
  static Sex _sexFromSilhouette(Document document) {
    final silhouette = document.querySelector('.wt-individual-silhouette');
    for (final name in silhouette?.classes ?? const <String>{}) {
      if (name.startsWith('wt-individual-silhouette-') &&
          name.length == 'wt-individual-silhouette-x'.length) {
        return Sex.fromCssSuffix(name.substring(name.length - 1));
      }
    }
    return Sex.unknown;
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

  /// The charts a page links to, by kind.
  ///
  /// webtrees puts its own class on every link to a chart —
  /// `menu-chart-ancestry` — so the app discovers what an instance runs the
  /// same way it discovers tabs, and a site with a chart module switched off
  /// simply never emits the link. The URLs carry that site's own settings,
  /// such as how many generations its administrator chose, so they are used
  /// exactly as they arrived.
  ///
  /// The page's own menu is preferred because its links are for *this*
  /// person; the same classes appear inside every chart box on the page, each
  /// pointing at whoever that box holds.
  Map<ChartKind, String> parseChartMenu(Document document, {String? xref}) {
    final charts = <ChartKind, String>{};

    void collect(Iterable<Element> links) {
      for (final link in links) {
        final href = link.attributes['href'];
        if (href == null) continue;

        for (final name in link.classes) {
          final kind = ChartKind.fromMenuClass(name);
          if (kind != null) charts.putIfAbsent(kind, () => href);
        }
      }
    }

    collect(document.querySelectorAll('.menu-chart a[href]'));
    if (charts.isNotEmpty) return charts;

    // No recognisable menu — a theme that lays its navigation out
    // differently. Any link to a chart will do, so long as it is a link to
    // *this* person's chart: the boxes on the page each carry their own.
    if (xref != null) {
      collect(
        document
            .querySelectorAll('a[href]')
            .where((link) => (link.attributes['href'] ?? '').contains(xref)),
      );
    }
    return charts;
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
  List<FactEntry> parseFacts(String fragment, {FactTagIndex? tags}) {
    final document = html.parseFragment(fragment);
    final index = tags ?? FactTagIndex.empty;
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
          date: _dateOf(row),
          place: place,
          type: textOf(row.querySelector('.wt-fact-type')),
          // Whose event this is, when webtrees folded someone else's into
          // this list: a sibling's birth, a family's marriage.
          about: _aboutOf(row),
          // What kind of event it is, in GEDCOM's terms rather than in the
          // reader's language — so an icon can be chosen for a death without
          // the app knowing the word for one.
          tag: index.tagFor(label),
          // webtrees collapses relatives' events, historical events and
          // associates by default; they are context, not this person's facts.
          isSecondary: classes.contains('collapse'),
        ),
      );
    }
    return facts;
  }

  /// The other person a fact really belongs to, when there is one.
  ///
  /// webtrees names them in `.wt-fact-record` — the block it uses to say "this
  /// happened to someone else". A marriage names the spouse there and links to
  /// the family beside them, so only the individual link is read.
  PersonRef? _aboutOf(Element row) {
    final block = row.querySelector('.wt-fact-record');
    final link = recordLink(block, 'individual');
    final xref = xrefIn(link?.attributes['href'], 'individual');
    if (link == null || xref == null) return null;

    return PersonRef(
      xref: xref,
      // The name is wrapped in the usual NAME span; older markup and some
      // themes put a relationship word there instead, which is still better
      // than showing nobody.
      name: textOf(link.querySelector('span.NAME')) ?? textOf(link) ?? xref,
    );
  }

  /// Reads the date box of a fact row.
  ///
  /// The text webtrees produced is kept verbatim — it has already applied the
  /// tree's calendar, the reader's language and its own numerals. The pieces
  /// beside it exist only so the interface can *drop* a calendar the reader
  /// did not ask for; nothing here ever rebuilds a date from components.
  RenderedDate? _dateOf(Element row) {
    final box = row.querySelector('.wt-fact-date-age');
    if (box == null) return null;

    // The box also holds computed ages, which belong to the rendering rather
    // than to the fact.
    final copy = box.clone(true);
    for (final selector in const ['.age', '.label']) {
      for (final unwanted in copy.querySelectorAll(selector)) {
        unwanted.remove();
      }
    }

    final text = cleanText(copy.text);
    if (text == null) return null;

    final pieces = <DatePiece>[];
    _readDatePieces(copy, pieces);
    return RenderedDate(
      text: text,
      // Structure is only useful when at least one calendar was named. A
      // rendering that drops the calendar links says nothing about which
      // calendar anything is in, and guessing would be worse than showing
      // the reader everything the server sent.
      pieces: pieces.any(_namesACalendar) ? pieces : const [],
    );
  }

  static bool _namesACalendar(DatePiece piece) =>
      piece is DateValue &&
      (piece.calendar != DateCalendar.unknown ||
          piece.conversions.any(
            (conversion) => conversion.calendar != DateCalendar.unknown,
          ));

  /// Walks a date box, in document order, collecting words and dates.
  ///
  /// webtrees renders each date as a link to its own calendar page, and each
  /// conversion as a `dir`-bearing span holding another such link. The `cal`
  /// parameter of those links is the only place a stock site states which
  /// calendar a rendered date is in.
  void _readDatePieces(Node node, List<DatePiece> pieces) {
    for (final child in node.nodes) {
      if (child is Text) {
        final words = cleanText(child.text);
        if (words != null) pieces.add(DateWords(words));
        continue;
      }
      if (child is! Element) continue;

      final calendar = _calendarOf(child);
      if (child.localName == 'a' && calendar != null) {
        final text = textOf(child);
        if (text != null) pieces.add(DateValue(text: text, calendar: calendar));
        continue;
      }

      // A conversion: webtrees wraps it in a span carrying the reading
      // direction, because a converted date may read the other way round.
      if (child.localName == 'span' && child.attributes.containsKey('dir')) {
        _attachConversion(child, pieces);
        continue;
      }

      _readDatePieces(child, pieces);
    }
  }

  /// Hangs a converted date off the date it converts.
  void _attachConversion(Element group, List<DatePiece> pieces) {
    final text = _unbracket(textOf(group));
    if (text == null) return;

    final conversion = DateValue(
      text: text,
      calendar:
          _calendarOf(group.querySelector('a[href]')) ?? DateCalendar.unknown,
    );

    final index = pieces.lastIndexWhere((piece) => piece is DateValue);
    if (index < 0) {
      // A conversion with nothing to convert. Not a shape webtrees emits, but
      // losing the date would be worse than showing it unattached.
      pieces.add(conversion);
      return;
    }

    final converted = pieces[index] as DateValue;
    pieces[index] = DateValue(
      text: converted.text,
      calendar: converted.calendar,
      conversions: [...converted.conversions, conversion],
    );
  }

  /// The calendar a webtrees calendar link points at, or null if it is not one.
  static DateCalendar? _calendarOf(Element? link) {
    final href = link?.attributes['href'];
    if (href == null) return null;

    // Parsed before decoding, not after: the escape is `@#DGREGORIAN@`, and
    // decoding the whole URL first turns its `#` into a fragment marker that
    // swallows the rest of the query. `Uri.queryParameters` decodes the value
    // on its own, which is exactly what is wanted.
    final escape = Uri.tryParse(href)?.queryParameters['cal'];
    if (escape == null) return null;
    return DateCalendar.fromGedcomEscape(escape);
  }

  /// Strips the brackets webtrees wraps a conversion in — round in 2.2.6,
  /// square in 2.3.
  static String? _unbracket(String? text) {
    if (text == null) return null;
    final trimmed = text.replaceAll(RegExp(r'^[(\[]|[)\]]$'), '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Reads the rows of a notes tab.
  ///
  /// Two shapes share one table, and both are wanted: a note recorded against
  /// the person, rendered as an ordinary fact row, and a note hanging off one
  /// of their facts, rendered as a relationship row webtrees keeps collapsed.
  List<NoteEntry> parseNotes(String fragment) {
    final document = html.parseFragment(fragment);
    final notes = <NoteEntry>[];

    for (final row in _recordRows(document)) {
      final label = _rowLabel(row);
      if (label == null) continue;
      final secondary = _isSecondaryRow(row);

      // A note of the person's own: the text is in the value box, and a
      // *shared* note also turns the label into a link to its record.
      final value = row.querySelector('.wt-fact-value');
      if (value != null) {
        final text = textOf(value);
        if (text == null) continue;
        notes.add(
          NoteEntry(
            label: label,
            text: text,
            xref: _xrefOf(row.querySelector('th'), 'note'),
            isSecondary: secondary,
          ),
        );
        continue;
      }

      // A note on a fact: one block per note, each holding the text and, for
      // a shared note, a link announcing it as one.
      for (final block in row.querySelectorAll('td > div')) {
        final link = recordLink(block, 'note');
        // Only that announcement is dropped. A note may carry links of its
        // own, and cutting them would edit the family's words.
        final text = link == null
            ? textOf(block)
            : textExcluding(block, [link]);
        if (text == null) continue;

        notes.add(
          NoteEntry(
            label: label,
            text: text,
            xref: xrefIn(link?.attributes['href'], 'note'),
            isSecondary: secondary,
          ),
        );
      }
    }
    return notes;
  }

  /// Reads the rows of a sources tab.
  ///
  /// A citation is a source record plus where in it to look. Both shapes —
  /// the person's own citations and those hanging off a fact — put the source
  /// behind a link and its fields in `label: value` lines the server has
  /// already worded.
  List<SourceCitation> parseSources(String fragment) {
    final document = html.parseFragment(fragment);
    final citations = <SourceCitation>[];

    for (final row in _recordRows(document)) {
      final label = _rowLabel(row);
      final cell = row.querySelector('td');
      if (label == null || cell == null) continue;

      final link = recordLink(cell, 'source');
      final title =
          textOf(link) ?? textOf(cell.querySelector('.wt-fact-value'));
      // A citation of a source this account may not see renders with neither
      // link nor title; there is nothing to show and nothing to say.
      if (title == null) continue;

      citations.add(
        SourceCitation(
          label: label,
          title: title,
          xref: xrefIn(link?.attributes['href'], 'source'),
          details: _citationDetails(cell, link),
          isSecondary: _isSecondaryRow(row),
        ),
      );
    }
    return citations;
  }

  /// The fields of one citation — page, quality, date.
  ///
  /// webtrees renders each as `<div><span class="label">…</span>: …</div>`,
  /// with the wording and the separator already translated, so each line is
  /// taken whole rather than split into a pair this app would have to rejoin.
  List<String> _citationDetails(Element cell, Element? source) {
    final details = <String>[];

    for (final block in cell.querySelectorAll('div')) {
      // The label must be a *direct* child: webtrees wraps a citation's
      // fields in a collapsible div, which holds the same spans one level
      // deeper — reading that too would repeat every field as one run-on line.
      if (!block.children.any((child) => child.classes.contains('label'))) {
        continue;
      }
      // The line naming the source is the title, not a detail about it.
      if (source != null &&
          block.querySelectorAll('a[href]').contains(source)) {
        continue;
      }

      final text = textOf(block);
      if (text != null) details.add(text);
    }
    return details;
  }

  /// Reads the rows of a media tab.
  ///
  /// The thumbnails here are signed URLs like any other, so they carry no
  /// authority of their own: webtrees checks this account's permission when
  /// they are fetched, which is why they must travel over the session.
  List<MediaItem> parseMedia(String fragment) {
    final document = html.parseFragment(fragment);
    final media = <MediaItem>[];

    for (final row in _recordRows(document)) {
      final label = _rowLabel(row);
      final cell = row.querySelector('td');
      if (label == null || cell == null) continue;

      final link = recordLink(cell, 'media');
      final images = cell.querySelectorAll('img[src]');
      if (link == null && images.isEmpty) continue;

      final item = MediaItem(
        title: textOf(link) ?? label,
        xref: xrefIn(link?.attributes['href'], 'media'),
        isSecondary: _isSecondaryRow(row),
      );

      // A media record may hold several files, and one that is not an image
      // at all — a sound file, a document — renders as an icon rather than a
      // thumbnail. Naming it is better than dropping it.
      if (images.isEmpty) {
        media.add(item);
        continue;
      }
      for (final image in images) {
        media.add(
          MediaItem(
            title: item.title,
            xref: item.xref,
            thumbnailUrl: image.attributes['src'],
            isSecondary: item.isSecondary,
          ),
        );
      }
    }
    return media;
  }

  /// The rows of a record tab that describe something.
  ///
  /// Skips the tab's own controls and its "there is nothing here" line, which
  /// have no header cell, and anything queued for deletion — the notes,
  /// sources and media tabs mark those on the cells rather than on the row.
  Iterable<Element> _recordRows(DocumentFragment document) => document
      .querySelectorAll('tr')
      .where((row) => row.querySelector('th') != null)
      .where(
        (row) =>
            !row.classes.contains('wt-old') &&
            !row
                .querySelectorAll('th, td')
                .any((cell) => cell.classes.contains('wt-old')),
      );

  /// What a row is about, in the site's own words.
  String? _rowLabel(Element row) {
    final head = row.querySelector('th');
    if (head == null) return null;

    final own = textOf(head.querySelector('.wt-fact-label'));
    if (own != null) return own;

    // A row for something attached to a fact carries no fact label: webtrees
    // prints that fact's label straight into the header cell, followed by the
    // editing controls only an editor is served.
    return textWithout(head, const ['.wt-fact-edit-links', '.wt-fact-icon']);
  }

  /// Whether webtrees renders this row collapsed — attached to a fact rather
  /// than recorded against the person.
  bool _isSecondaryRow(Element row) => row.classes.contains('collapse');

  /// The identifier of the [type] record [element] links to, if it links to
  /// one at all.
  String? _xrefOf(Element? element, String type) =>
      xrefIn(recordLink(element, type)?.attributes['href'], type);

  /// Reads the family blocks of a relatives tab.
  ///
  /// Each family is its own table: a caption linking to the family record,
  /// then the couple, then any marriage facts, then the children — the order
  /// the upstream template emits in both supported versions.
  List<FamilyGroup> parseRelatives(
    String fragment, {
    required String xref,
    FactTagIndex? tags,
  }) {
    final document = html.parseFragment(fragment);
    final index = tags ?? FactTagIndex.from(document);
    final families = <FamilyGroup>[];

    for (final table in document.querySelectorAll('table')) {
      final caption = table.querySelector('caption a[href]');
      final familyXref = xrefIn(caption?.attributes['href'], 'family');
      // Tables without a family caption are the tab's own controls, such as
      // the "date differences" toggle.
      if (familyXref == null) continue;

      final (spouses, children, facts) = _splitFamily(table, index);
      families.add(
        FamilyGroup(
          xref: familyXref,
          label: textOf(caption) ?? familyXref,
          kind: _kindOf(xref, spouses, children),
          spouses: spouses,
          children: children,
          facts: facts,
          // Read from this family's own rows, so a person married twice is
          // divorced from one of them and not from the other.
          endedInDivorce: facts.any((fact) => index.isDivorce(fact.label)),
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
  (List<PersonRef>, List<PersonRef>, List<FactEntry>) _splitFamily(
    Element table,
    FactTagIndex index,
  ) {
    final spouses = <PersonRef>[];
    final children = <PersonRef>[];
    final facts = <FactEntry>[];
    var seenDivider = false;

    for (final row in table.querySelectorAll('tr')) {
      final box = row.querySelector('.wt-chart-box[data-wt-chart-xref]');
      if (box == null) {
        // A marriage or divorce row. Rows that are neither — the "add a
        // child" links an editor sees — carry no chart box either, but they
        // only ever appear after the children, so treating them as a divider
        // costs nothing.
        final fact = _familyFact(row, index);
        if (fact != null) facts.add(fact);
        if (row.querySelector('.field') != null) seenDivider = true;
        continue;
      }

      final person = personFromChartBox(box);
      if (person == null) continue;

      if (!seenDivider && spouses.length < 2) {
        spouses.add(person);
      } else {
        seenDivider = true;
        children.add(person);
      }
    }
    return (spouses, children, facts);
  }

  /// A marriage or divorce row of a family table.
  ///
  /// Rendered as a label beside a field rather than as a fact row, and the
  /// date carries no calendar links here — `Date::display()` is called without
  /// them — so this text is all there is. An empty field is normal: webtrees
  /// still prints the row for a marriage it has no date or place for.
  FactEntry? _familyFact(Element row, FactTagIndex index) {
    final label = textOf(row.querySelector('td span.label'));
    if (label == null) return null;

    final value = cleanText(textOf(row.querySelector('td span.field')));
    return FactEntry(
      label: label,
      value: _hasContent(value) ? value : null,
      tag: index.tagFor(label),
    );
  }

  /// Whether a rendered value says anything at all.
  ///
  /// A marriage with neither date nor place still renders its separators, so
  /// the field arrives as a lone dash — punctuation the reader would have to
  /// decode as "nothing recorded".
  static bool _hasContent(String? text) =>
      text != null && RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text);

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
}

/// The parts of an individual's page that are not in a tab.
@immutable
final class IndividualPage {
  IndividualPage({
    required this.xref,
    required this.name,
    required Map<String, String> tabs,
    required Map<String, String> inlineTabs,
    Map<ChartKind, String> charts = const {},
    this.alternateName,
    this.thumbnailUrl,
    this.sex = Sex.unknown,
  }) : tabs = Map.unmodifiable(tabs),
       inlineTabs = Map.unmodifiable(inlineTabs),
       charts = Map.unmodifiable(charts);

  final String xref;
  final String name;
  final String? alternateName;
  final String? thumbnailUrl;

  /// What the page itself gave away about this person's sex, which on a stock
  /// site is usually nothing. See [RecordParser._sexFromSilhouette].
  final Sex sex;

  /// Module name to fragment URL, exactly as the server wrote it.
  final Map<String, String> tabs;

  /// Module name to already-rendered content, for tabs that do not use AJAX.
  final Map<String, String> inlineTabs;

  /// Each chart this site offers for this person, at the URL it gave.
  final Map<ChartKind, String> charts;
}
