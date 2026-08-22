import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:html/parser.dart' as html;

import '../../core/errors.dart';
import '../../core/response_status.dart';
import '../../core/webtrees_client.dart';
import '../../domain/records.dart';
import 'dom.dart';
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
  Future<SearchPage> search(
    String tree,
    String query, {
    int page = 1,
  }) async {
    if (query.trim().isEmpty) {
      return const SearchPage(people: [], hasMore: false);
    }

    final reply = await _client.get(
      '/tree/$tree/tom-select-individual',
      query: {'query': query.trim(), 'page': '$page'},
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
      final name = textOf(fragment.querySelector('span.NAME'));

      people.add(
        PersonRef(
          xref: xref,
          // Without the name span the whole rendered row is still better than
          // showing the user a bare identifier.
          name: name ?? cleanText(fragment.text) ?? xref,
          thumbnailUrl: fragment.querySelector('img')?.attributes['src'],
        ),
      );
    }
    return people;
  }

  /// Reads one person: their names, photo, facts and relatives.
  ///
  /// Two or three requests. The page itself names every tab the site offers
  /// and gives the exact URL for each, so nothing is assumed about which
  /// modules a tree has enabled — a site with the relatives tab switched off
  /// yields a record without relatives and a warning saying so, rather than a
  /// failure.
  Future<IndividualRecord> individual(String tree, String xref) async {
    final reply = await _client.get('/tree/$tree/individual/$xref');
    if (!reply.isOk) {
      throw failureFrom(reply, probe: 'opening $xref');
    }

    final page = _parser.parseIndividualPage(reply.body, xref: xref);
    final warnings = <String>[];

    final factsHtml = await _tabContent(page, 'personal_facts', warnings);
    final relativesHtml = await _tabContent(page, 'relatives', warnings);

    return IndividualRecord(
      xref: xref,
      name: page.name,
      alternateName: page.alternateName,
      thumbnailUrl: page.thumbnailUrl,
      facts: factsHtml == null ? const [] : _parser.parseFacts(factsHtml),
      families: relativesHtml == null
          ? const []
          : _parser.parseRelatives(relativesHtml, xref: xref),
      warnings: warnings,
    );
  }

  /// The markup of one tab, however the site chooses to deliver it.
  ///
  /// A tab that does not load over AJAX is already rendered into the page, so
  /// re-requesting it would return the same bytes twice.
  Future<String?> _tabContent(
    IndividualPage page,
    String module,
    List<String> warnings,
  ) async {
    final inline = page.inlineTabs[module];
    if (inline != null) return inline;

    final url = page.tabs[module];
    if (url == null) {
      warnings.add(_missing(module));
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
      warnings.add(_missing(module));
      return null;
    } on WebtreesError catch (problem) {
      // One unreachable tab should cost that section, not the whole record.
      developer.log('Tab $module failed: ${problem.message}', name: _log);
      warnings.add(_missing(module));
      return null;
    }
  }

  static String _missing(String module) => switch (module) {
    'personal_facts' => 'Facts and events could not be loaded for this person.',
    'relatives' => 'Family members could not be loaded for this person.',
    _ => 'The $module section could not be loaded.',
  };

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
