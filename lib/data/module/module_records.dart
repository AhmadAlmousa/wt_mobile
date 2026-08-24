import 'dart:typed_data';

import '../../core/response_status.dart';
import '../../core/webtrees_client.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import '../stock/media_cache.dart';
import '../transport.dart';
import 'module_api.dart';
import 'module_decode.dart';

/// Reading people through the module.
///
/// This is what retires 727 lines of the most fragile parser in the app, and
/// the reason is not that JSON is easier to read than HTML. It is that four
/// things a page cannot state are stated here: the GEDCOM tag of every fact,
/// where each fact came from, what kind of family each block is, and the
/// subject's own sex — all of which the stock path has to recover indirectly,
/// and one of which (a relative's death under its own label) it cannot
/// recover at all.
final class ModuleRecordsTransport implements RecordsTransport {
  ModuleRecordsTransport(
    WebtreesClient client, {
    MediaCache? mediaCache,
    this.thumbnailSize = 160,
    this.pageSize = 50,
  }) : _api = ModuleApi(client),
       _client = client,
       _media = mediaCache ?? MediaCache();

  final ModuleApi _api;
  final WebtreesClient _client;

  /// Shared with the stock transport wherever both are in play, because the
  /// bytes are the same bytes and the account they belong to is the same
  /// account.
  final MediaCache _media;

  /// The longest edge of a portrait to ask the module to sign.
  ///
  /// A stock instance can only offer the 100 pixels its media tab happens to
  /// emit, because the signature covers the dimensions and the key is the
  /// server's. Here the size is a request.
  final int thumbnailSize;

  final int pageSize;

  @override
  Future<SearchPage> search(String tree, String query, {int page = 1}) async {
    final trimmed = query.trim();

    final body = await _api.tree(
      tree,
      '/individuals',
      query: {
        // An empty query enumerates rather than answering nothing: the same
        // `SearchService` call walks a whole tree in name order when its term
        // list is empty, which is the one thing no stock route can do.
        if (trimmed.isNotEmpty) 'q': trimmed,
        'offset': '${(page - 1) * pageSize}',
        'limit': '$pageSize',
        'thumb': '$thumbnailSize',
      },
      probe: 'searching $tree',
    );

    return SearchPage(
      people: peopleFrom(body['people']),
      // Stated, not inferred. The module fetches one row beyond the page, and
      // its paging deduplicates a person recorded under two names across the
      // *whole* cursor rather than only within the page being built — which
      // is the trap the stock autocomplete falls into.
      hasMore: body['hasMore'] == true,
    );
  }

  /// People whose surname begins with [surname], as a browsable index.
  ///
  /// Not on the interface, because a stock instance has no way to answer it.
  /// A client that has probed for it can use it; nothing depends on it.
  Future<SearchPage> bySurname(
    String tree,
    String surname, {
    int page = 1,
  }) async {
    final body = await _api.tree(
      tree,
      '/individuals',
      query: {
        'surname': surname,
        'offset': '${(page - 1) * pageSize}',
        'limit': '$pageSize',
        'thumb': '$thumbnailSize',
      },
      probe: 'listing $surname in $tree',
    );

    return SearchPage(
      people: peopleFrom(body['people']),
      hasMore: body['hasMore'] == true,
    );
  }

  @override
  Future<IndividualRecord> individual(String tree, String xref) async {
    final body = await _api.tree(
      tree,
      '/individual/$xref',
      query: {'thumb': '$thumbnailSize'},
      probe: 'opening $xref',
    );

    return individualFrom(
      body,
      xref: xref,
      sections: [
        for (final section in listOf(body['sections']))
          if (section is String) section,
      ],
      charts: chartHandles(tree, xref, body['charts']),
    );
  }

  @override
  Future<Map<ChartKind, String>> treeCharts(String tree) async {
    // Site-wide charts are the ones that belong to a whole database rather
    // than to anybody in it, which is only ever statistics.
    return {ChartKind.statistics: moduleHandle(tree, '/statistics')};
  }

  /// Turns the chart classes a site runs into module endpoints.
  ///
  /// The module names its charts with the very CSS classes webtrees puts on
  /// its own links — `menu-chart-ancestry` — so a client that already knows
  /// how to discover charts from a page needs no second dictionary. What
  /// changes is the value: an address into the module rather than into the
  /// site's own chart page.
  ///
  /// A chart the module cannot serve is dropped even when the site runs it,
  /// because offering a button that answers nothing is worse than not
  /// offering one. A chart the *site* has switched off is dropped too: the
  /// module could compute it, but a manager said not to.
  static Map<ChartKind, String> chartHandles(
    String tree,
    String xref,
    Object? classes,
  ) {
    const served = <ChartKind, String>{
      ChartKind.ancestors: '/ancestors',
      ChartKind.descendants: '/descendants',
      ChartKind.relationship: '/relationship',
      ChartKind.timeline: '/timeline',
      ChartKind.statistics: '/statistics',
    };

    final handles = <ChartKind, String>{};

    for (final entry in listOf(classes)) {
      if (entry is! String) continue;

      final kind = ChartKind.fromMenuClass(entry);
      final path = kind == null ? null : served[kind];
      if (kind == null || path == null) continue;

      handles[kind] = kind == ChartKind.statistics
          ? moduleHandle(tree, path)
          : moduleHandle(tree, '$path/$xref');
    }

    // The hourglass is not fetched: it is the two charts either side of a
    // person, stitched. Offered exactly when both halves are.
    if (handles.containsKey(ChartKind.ancestors) &&
        handles.containsKey(ChartKind.descendants)) {
      handles[ChartKind.hourglass] = handles[ChartKind.ancestors]!;
    }

    return handles;
  }

  static String moduleHandle(String tree, String path) =>
      '/tree/$tree$kModuleBase$path';

  /// Fetches an image through the signed-in session.
  ///
  /// Deliberately identical to the stock path, and permanently so. The module
  /// can sign a URL at any size the screen wants — which is the whole of what
  /// it adds here — but `MediaFileThumbnail` still checks `canShow()` for the
  /// current user *before* validating the signature and picks watermarking
  /// from the same answer. The bytes come back over the session or not at all.
  @override
  Future<Uint8List> image(String url) async {
    final cached = _media[url];
    if (cached != null) return cached;

    final reply = await _client.getBytes(
      _client.url.routeOf(url),
      query: {
        for (final entry in Uri.parse(
          Uri.decodeFull(url),
        ).queryParameters.entries)
          if (entry.key != 'route') entry.key: entry.value,
      },
    );

    if (!reply.isOk) {
      throw failureFor(reply.status, probe: 'loading an image');
    }

    return _media[url] = reply.bytes;
  }
}
