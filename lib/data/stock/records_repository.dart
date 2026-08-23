import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../core/errors.dart';
import '../../core/response_status.dart';
import '../../core/webtrees_client.dart';
import '../../domain/charts.dart';
import '../../domain/notice.dart';
import '../../domain/records.dart';
import 'dom.dart';
import 'fact_tags.dart';
import 'media_cache.dart';
import 'record_parser.dart';

/// One page of search results, and whether more exist.
final class SearchPage {
  const SearchPage({required this.people, required this.hasMore});

  final List<PersonRef> people;

  /// webtrees fetches one row beyond the page to answer this, so it is exact
  /// rather than a guess from a full page.
  final bool hasMore;
}

/// Reads people from a stock webtrees site.
///
/// Stock webtrees has no API, so this is HTML with one JSON exception. Each
/// method says which route it uses and what it may assume of the answer;
/// nothing here infers a fact from a status code it was not promised.
final class RecordsRepository {
  RecordsRepository(this._client, {String? version, MediaCache? mediaCache})
    : _parser = RecordParser(version: version),
      _media = mediaCache ?? MediaCache();

  final WebtreesClient _client;
  final RecordParser _parser;
  final MediaCache _media;

  /// Finds people by name or XREF within [tree].
  ///
  /// Uses the site's own autocomplete endpoint, the one route on a stock
  /// instance that answers JSON. It is **search**, not enumeration: webtrees
  /// returns an empty collection for an empty query, so a blank [query] is
  /// answered here rather than wasting a request.
  ///
  /// Answers 50 people at a time, from [page] counting at one. The reply
  /// carries a `nextUrl` when more exist — but that URL is built from the
  /// tree, `at` and the page number **only**, dropping the query, so following
  /// it would search for nothing. Paging is therefore done by number.
  Future<SearchPage> search(String tree, String query, {int page = 1}) async {
    if (query.trim().isEmpty) {
      return const SearchPage(people: [], hasMore: false);
    }

    final reply = await _client.get(
      '/tree/$tree/tom-select-individual',
      query: {
        // `at` is required and has no default: the handler validates it with
        // `isInArray(['', '@'])->string('at')`, so a missing value fails the
        // rule and webtrees answers 400 rather than searching. Empty asks for
        // bare xrefs; `@` would wrap them in GEDCOM pointer form. Dart renders
        // an empty value as a bare `at`, which PHP reads as the empty string —
        // confirmed 200 against live 2.2.6.
        'at': '',
        'query': query.trim(),
        'page': '$page',
      },
    );
    if (!reply.isOk) {
      throw failureFrom(reply, probe: 'searching $tree');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(reply.body);
    } on FormatException catch (problem) {
      developer.log('Search returned non-JSON: ${problem.message}', name: _log);
      throw ParseFailure(
        parser: 'search results',
        expected: 'a JSON object with a data array',
        version: _parser.version,
      );
    }

    if (decoded is! Map<String, Object?>) {
      throw ParseFailure(
        parser: 'search results',
        expected: 'a JSON object with a data array',
        version: _parser.version,
      );
    }

    final rows = decoded['data'];
    return SearchPage(
      people: rows is List ? _peopleFrom(rows) : const [],
      // `nextUrl` is present only when a further page exists.
      hasMore: decoded['nextUrl'] != null,
    );
  }

  /// Turns autocomplete rows into people.
  ///
  /// Each row's `text` is **rendered HTML**, not a name: webtrees builds it
  /// from a view that emits a thumbnail, the full name and a lifespan. The
  /// thumbnail is present only for someone with a highlighted media file.
  ///
  /// It states no sex, so search results are the one place in the app where
  /// a person is drawn without one. Fetching each row's record to find out
  /// would cost a request per result; opening the person answers it.
  List<PersonRef> _peopleFrom(List<Object?> rows) {
    final people = <PersonRef>[];
    for (final row in rows) {
      if (row is! Map<String, Object?>) continue;
      final value = row['value'];
      final text = row['text'];
      if (value is! String || text is! String) continue;

      // The value is the XREF, wrapped in `@…@` when the caller asked for
      // GEDCOM pointer form.
      final xref = value.replaceAll('@', '');
      if (xref.isEmpty) continue;

      final fragment = html.parseFragment(text);
      final nameSpan = fragment.querySelector('span.NAME');
      final name = textOf(nameSpan);

      people.add(
        PersonRef(
          xref: xref,
          // Without the name span the whole rendered row is still better than
          // showing the user a bare identifier.
          name: name ?? cleanText(fragment.text) ?? xref,
          lifespan: _lifespanAfter(fragment, nameSpan),
          thumbnailUrl: fragment.querySelector('img')?.attributes['src'],
        ),
      );
    }
    return people;
  }

  /// The years a search row prints after the name.
  ///
  /// `selects/individual.phtml` writes `{name}, {lifespan}` with nothing
  /// marking the second part, so it is recovered by removing the first: what
  /// follows the name is the lifespan, and the comma webtrees joined them
  /// with.
  static String? _lifespanAfter(DocumentFragment row, Element? name) {
    final whole = cleanText(row.text);
    final just = cleanText(name?.text);
    if (whole == null || just == null) return null;

    final at = whole.indexOf(just);
    if (at < 0) return null;

    final rest = whole.substring(at + just.length);
    final years = cleanText(rest.replaceFirst(_leadingSeparator, ''));
    // A person with neither birth nor death still renders the dash between
    // two empty years, which says nothing worth showing.
    return years != null && _hasDigits.hasMatch(years) ? years : null;
  }

  /// The comma webtrees joins a name to its lifespan with, Arabic's included.
  static final RegExp _leadingSeparator = RegExp(r'^[,\u060C\s]+');

  static final RegExp _hasDigits = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// The charts a site offers for a whole tree rather than for one person.
  ///
  /// Read from the tree's own page, because that is where webtrees puts the
  /// links to them — the statistics of a whole database belong to nobody in
  /// particular, so no person's page carries a link with their xref in it.
  Future<Map<ChartKind, String>> treeCharts(String tree) async {
    final reply = await _client.get('/tree/$tree');
    if (!reply.isOk) {
      throw failureFrom(reply, probe: 'reading the charts $tree offers');
    }
    return _parser.parseChartMenu(html.parse(reply.body));
  }

  /// Reads one person: their names, photo, facts, family, notes, sources and
  /// media.
  ///
  /// Usually one request. The page names every tab the site offers and gives
  /// the exact URL for each, so nothing is assumed about which modules a tree
  /// has enabled — and every core tab renders its content into the page rather
  /// than over AJAX, so the sections below normally cost nothing more to read
  /// than they did to fetch.
  ///
  /// A site with the relatives tab switched off yields a record without
  /// relatives and a warning saying so, rather than a failure.
  Future<IndividualRecord> individual(String tree, String xref) async {
    final reply = await _fetchRecord(
      '/tree/$tree/individual/$xref',
      probe: 'opening $xref',
    );

    final page = _parser.parseIndividualPage(reply.body, xref: xref);
    final warnings = <Notice>[];

    final factsHtml = await _tabContent(page, 'personal_facts', warnings);
    final relativesHtml = await _tabContent(page, 'relatives', warnings);

    // Notes, sources and media are separate modules a site may simply not
    // run — this project's own target runs none of the three — so their
    // absence is the site's shape rather than a section that went missing.
    final notesHtml = await _tabContent(
      page,
      'notes',
      warnings,
      offered: false,
    );
    final sourcesHtml = await _tabContent(
      page,
      'sources_tab',
      warnings,
      offered: false,
    );
    final mediaHtml = await _tabContent(
      page,
      'media',
      warnings,
      offered: false,
    );

    // What this site calls a death, a marriage, a divorce. Learned from the
    // chart boxes on the relatives tab, because those state the GEDCOM tag in
    // a class while every label on the page is already translated. One index
    // serves the whole record: the facts table and the family blocks are the
    // same page, rendered by the same server, in the same language.
    final tags = relativesHtml == null
        ? FactTagIndex.empty
        : FactTagIndex.from(html.parseFragment(relativesHtml));

    final families = relativesHtml == null
        ? const <FamilyGroup>[]
        : _parser.parseRelatives(relativesHtml, xref: xref, tags: tags);

    // The person's own sex, lifespan and death, taken from their own chart
    // box: they appear in their own family tables like anybody else, and the
    // box is the one place a stock site states these structurally.
    final self = _selfIn(families, xref);

    return IndividualRecord(
      xref: xref,
      name: page.name,
      alternateName: page.alternateName,
      thumbnailUrl: page.thumbnailUrl,
      sex: self?.sex ?? page.sex,
      lifespan: self?.lifespan,
      isDeceased: self?.isDeceased ?? false,
      facts: factsHtml == null
          ? const []
          : _parser.parseFacts(factsHtml, tags: tags),
      families: families,
      notes: notesHtml == null ? const [] : _parser.parseNotes(notesHtml),
      sources: sourcesHtml == null
          ? const []
          : _parser.parseSources(sourcesHtml),
      media: mediaHtml == null ? const [] : _parser.parseMedia(mediaHtml),
      // What this site actually offers, for the diagnostics: two instances
      // rarely run the same modules, and that is what decides how much of a
      // record the app can show.
      sections: page.tabs.keys.toList(),
      // Discovered from the same page, so the reader can be offered exactly
      // the charts this instance draws.
      charts: page.charts,
      warnings: warnings,
    );
  }

  /// Fetches a record page, following webtrees' canonical-URL redirect.
  ///
  /// A record route is `/individual/{xref}{/slug}`, and the handler compares
  /// the slug it was given against the one it derives from the record's
  /// current name. A caller that knows only the xref — which is all a search
  /// result carries — therefore gets `301` to the canonical URL rather than
  /// the page. The slug cannot be computed here: it comes from the name as
  /// the server has it, in the server's transliteration.
  ///
  /// Only a **permanent** redirect is followed, and only once. A `302` still
  /// means the session is gone: that is the status middleware uses to bounce
  /// an unauthenticated caller to the sign-in page, and following it would
  /// turn an expiry into a confusing parse failure.
  Future<Reply> _fetchRecord(String route, {required String probe}) async {
    var reply = await _client.get(route);

    if (reply.status == 301 || reply.status == 308) {
      final target = _client.url.routeOf(reply.location ?? '');
      if (target.isEmpty) {
        throw failureFrom(reply, probe: probe);
      }
      reply = await _client.get(target);
    }

    if (!reply.isOk) {
      throw failureFrom(reply, probe: probe);
    }
    return reply;
  }

  /// The markup of one tab, however the site chooses to deliver it.
  ///
  /// A tab that does not load over AJAX is already rendered into the page, so
  /// re-requesting it would return the same bytes twice. Every core tab is
  /// this kind, which is why a stock record usually costs one request however
  /// many sections it has.
  ///
  /// [offered] says whether the app expects this tab to exist: a section it
  /// relies on going missing is worth a warning, a module the site does not
  /// run is not.
  Future<String?> _tabContent(
    IndividualPage page,
    String module,
    List<Notice> warnings, {
    bool offered = true,
  }) async {
    final inline = page.inlineTabs[module];
    if (inline != null) return inline;

    final url = page.tabs[module];
    if (url == null) {
      // A tab the site never offered is only worth mentioning when the app
      // counts on it. Warning that a site has no notes module would report
      // an ordinary configuration as a fault.
      if (offered) warnings.add(SectionUnavailable(module));
      return null;
    }

    try {
      // Only fragment routes get this header. Elsewhere webtrees uses it to
      // turn a 4xx into a 200 carrying an error page.
      final reply = await _client.get(
        _client.url.routeOf(url),
        query: _queryOf(url),
        headers: const {'X-Requested-With': 'XMLHttpRequest'},
      );
      if (reply.isOk) return reply.body;

      developer.log(
        'Tab $module answered ${reply.status}',
        name: _log,
        level: 900,
      );
      warnings.add(SectionUnavailable(module));
      return null;
    } on WebtreesError catch (problem) {
      // One unreachable tab should cost that section, not the whole record.
      developer.log('Tab $module failed: ${problem.message}', name: _log);
      warnings.add(SectionUnavailable(module));
      return null;
    }
  }

  /// This person as their own family tables describe them.
  ///
  /// Everyone in a family table is rendered as a chart box, the viewer
  /// included, and that box carries their sex, their lifespan and their death
  /// — none of which the individual page states in a way that survives
  /// translation. Answers null on a site with the relatives tab switched off,
  /// where none of it can be known.
  static PersonRef? _selfIn(List<FamilyGroup> families, String xref) {
    for (final family in families) {
      for (final person in [...family.spouses, ...family.children]) {
        if (person.xref == xref) return person;
      }
    }
    return null;
  }

  /// The query parameters of a server-supplied URL.
  ///
  /// Tab URLs come from the page rather than being built here, and carry the
  /// XREF — and, in the ugly URL style, the route and tree as well.
  static Map<String, String> _queryOf(String url) {
    final parsed = Uri.parse(Uri.decodeFull(url));
    return {
      for (final entry in parsed.queryParameters.entries)
        if (entry.key != 'route') entry.key: entry.value,
    };
  }

  /// Fetches an image through the signed-in session.
  ///
  /// A signed thumbnail URL is not an access token. webtrees resolves the tree
  /// for the *current user*, checks that they may see the media, and decides
  /// on watermarking from that — so an unauthenticated fetch gets a refusal or
  /// somebody else's view of the file. Anything caching these bytes must key
  /// on the site and the account, and drop them at sign-out.
  Future<Uint8List> image(String url) async {
    final cached = _media[url];
    if (cached != null) return cached;

    final reply = await _client.getBytes(
      _client.url.routeOf(url),
      query: _queryOf(url),
    );
    if (!reply.isOk) {
      throw failureFor(reply.status, probe: 'loading an image');
    }
    return _media[url] = reply.bytes;
  }

  static const String _log = 'webtrees.records';
}
