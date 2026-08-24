/// Answering from the store.
///
/// The third implementation of `RecordsTransport`, and the seam it plugs into
/// was already there: the screens depend on the interface, and
/// `CapabilityRecordsTransport` already chooses a source per capability. So
/// this file adds a source and changes no screen.
///
/// **Nothing composes it yet.** Phase 10b fills the store and reads it back in
/// tests; Phase 10c is where the composer starts preferring it, because
/// preferring it needs a staleness rule and a way to tell a reader where a
/// figure came from — and a store that is answering before it can say "from
/// last night" is the failure mode `sync_eval.md` §11 #1 names.
///
/// Two capabilities pass straight through, and neither is a limitation:
///
/// - **Image bytes.** A thumbnail URL is HMAC-signed with a server-side key
///   and `MediaFileThumbnail` checks the viewer's own permission *before*
///   validating the signature, so the bytes always travel over the session.
///   Phase 10e stores them as blobs; until then the store holds addresses.
/// - **Tree-level charts**, which today means statistics only — deliberately
///   read from the page, because the page publishes seventeen sections where
///   the module answers four (`Capability.readFromThePage`). A store computing
///   its own would be showing the app's arithmetic where every other screen
///   shows the site's, and that is a product decision rather than a cache.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/errors.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import '../module/module_decode.dart';
import '../module/module_records.dart';
import '../transport.dart';
import 'records_page.dart';
import 'store.dart';

/// Reads people out of the local store, and defers what a store cannot hold.
final class LocalRecordsTransport implements RecordsTransport {
  const LocalRecordsTransport({
    required this.store,
    required this.online,
    this.pageSize = 50,
  });

  final LocalStore store;

  /// For the bytes and the tree-level charts a store does not hold.
  final RecordsTransport online;

  final int pageSize;

  /// Whether this tree's copy is complete enough to answer from.
  ///
  /// A store mid-walk holds *part* of a tree, which is fine to add to and not
  /// fine to read as though it were the tree: a search would quietly answer
  /// "nobody" for half of it. The composer will ask this before preferring the
  /// store (Phase 10c); it is here because the rule belongs with the data.
  Future<bool> isComplete(String tree) async {
    final state = await _state(tree);
    return state != null && !state.filling && state.token != null;
  }

  /// When this copy was last written to.
  Future<DateTime?> syncedAt(String tree) async =>
      (await _state(tree))?.syncedAt;

  @override
  Future<SearchPage> search(String tree, String query, {int page = 1}) async {
    final trimmed = query.trim();
    final offset = (page - 1) * pageSize;

    // The first time this app can look at a whole tree at once. An empty query
    // enumerates — which no stock route can do and the module does one page at
    // a time — and here it costs a `LIMIT`.
    final select = store.select(store.storedPeople)
      ..where((row) {
        final tree_ = row.tree.equals(tree);
        if (trimmed.isEmpty) return tree_;
        // Matched against both name forms at once, lower-cased when the row
        // was written: an Arabic tree with romanized second names has to find
        // `Abdullah` for `عبد الله الموسى`.
        return tree_ &
            (row.nameFold.like('%${trimmed.toLowerCase()}%') |
                row.xref.equals(trimmed));
      })
      ..orderBy([(row) => OrderingTerm(expression: row.sortName)])
      // One row beyond the page, so "are there more" is a fact rather than an
      // inference from a full page — the same rule both other transports keep.
      ..limit(pageSize + 1, offset: offset);

    final rows = await select.get();

    return SearchPage(
      people: [
        for (final row in rows.take(pageSize))
          personFrom(personFromPayload(row.payload)),
      ],
      hasMore: rows.length > pageSize,
    );
  }

  @override
  Future<IndividualRecord> individual(String tree, String xref) async {
    final row =
        await (store.select(store.storedPeople)
              ..where((row) => row.tree.equals(tree) & row.xref.equals(xref)))
            .getSingleOrNull();

    if (row == null) {
      // Absent, not empty. A store cannot tell "this reader may not see them"
      // from "this copy does not have them yet", and inventing a placeholder
      // would state something neither the tree nor the sync ever said.
      throw NotFound(detail: 'No copy of $xref in this store.');
    }

    final state = await _state(tree);

    return individualFrom(
      personFromPayload(row.payload),
      xref: xref,
      sections: _strings(state?.sections),
      // Handles into the *module*, which is where a chart is still drawn from.
      // Phase 10d computes the shapes locally; until then a record read from
      // the store opens the same charts as one read from the wire, because a
      // handle is only ever passed back unread.
      charts: ModuleRecordsTransport.chartHandles(
        tree,
        xref,
        _strings(state?.chartClasses),
      ),
    );
  }

  /// Straight through — see the library comment.
  @override
  Future<Map<ChartKind, String>> treeCharts(String tree) =>
      online.treeCharts(tree);

  /// Straight through — see the library comment.
  @override
  Future<Uint8List> image(String url) => online.image(url);

  Future<StoredTreeState?> _state(String tree) => (store.select(
    store.storedTreeStates,
  )..where((row) => row.tree.equals(tree))).getSingleOrNull();

  static List<String> _strings(String? json) {
    if (json == null || json.isEmpty) return const [];
    final decoded = jsonDecode(json);
    return [
      for (final item in decoded is List ? decoded : const [])
        if (item is String) item,
    ];
  }
}
