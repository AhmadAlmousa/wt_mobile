/// Choosing between the two transports, one capability at a time.
///
/// `PROJECT.md` §4 sets the rule this file exists to obey: *compose at the
/// level of capabilities rather than swapping one global transport*. A site
/// running an older module still gets the fast path for what it does
/// implement, and the stock path answers the rest — so adopting the module is
/// never all-or-nothing, and an app newer than the module it meets degrades
/// per endpoint instead of refusing the whole thing.
///
/// Every method here falls back. The stock transport is the floor, permanently.
library;

import 'dart:developer' as developer;
import 'dart:typed_data';

import '../core/errors.dart';
import '../domain/access.dart';
import '../domain/charts.dart';
import '../domain/records.dart';
import '../domain/statistics.dart';
import 'module/module_api.dart';
import 'transport.dart';

/// The feature names the module advertises in `capabilities.features`.
abstract final class Capability {
  static const String access = 'access';
  static const String individuals = 'individuals';
  static const String individual = 'individual';
  static const String ancestors = 'ancestors';
  static const String descendants = 'descendants';
  static const String relationship = 'relationship';
  static const String timeline = 'timeline';
  static const String statistics = 'statistics';

  /// The sync wire — `GET …/records?offset=&limit=&since=`, module 1.3.0 and
  /// later. Never *answered from* a store, because it is the thing that fills
  /// one; it is here so the app can ask "can this site be kept offline at
  /// all?" the same way it asks every other question.
  static const String records = 'records';

  /// What a filled local store may answer, and nothing else.
  ///
  /// The staleness rule `sync_eval.md` §10 asks for, and it is a short list on
  /// purpose. A capability belongs here only when the store holds *the same
  /// bytes the server would have sent* — which is true of a record and its
  /// families, because [StoredPeople.payload] is the module's own JSON kept
  /// verbatim, and is not true of anything the app would have to compute.
  ///
  /// Deliberately absent, each for its own reason:
  ///
  /// - `relationship` and `statistics` — `sync_eval.md` §5. The first needs
  ///   kinship wording that is one of the largest things in webtrees and must
  ///   not be ported twice; the second is the *site's* arithmetic, and a store
  ///   computing its own would show the app's where every other screen shows
  ///   the site's.
  /// - `ancestors`, `descendants`, `timeline` — computable from the stored
  ///   family links and facts, and Phase 10d is where that happens. Until
  ///   then a chart opened from a stored record uses the handle the store
  ///   kept, which addresses the module.
  ///
  /// Answering from here is additionally conditional on the store being
  /// *complete*: a half-filled copy would answer "nobody" for half a tree.
  /// [CapabilityRecordsTransport] is only ever handed a local transport once
  /// `TreeStore` says so.
  static const Set<String> answerableLocally = {individuals, individual};

  /// What the app reads from the page even where the module offers it.
  ///
  /// Coverage, not correctness. A statistics *page* publishes everything the
  /// site computes — seventeen sections and fifteen charts on both lab
  /// installs — while the module answers a chosen four and eight. Both agree
  /// on every figure they state, checked live on 2.2.6 and 2.3, so this is
  /// not a disagreement: the module simply says less, and preferring it would
  /// cost a reader thirteen sections of their own tree.
  ///
  /// The composer working as designed rather than an exception to it: the
  /// module is preferred where it knows *more* — a fact's GEDCOM tag, a role,
  /// a date's calendar — and the floor answers where it knows less. Revisit
  /// when the endpoint covers the page; `PROJECT.md` §5 is the ledger.
  static const Set<String> readFromThePage = {statistics};

  /// Whether the module answers this capability for this site.
  ///
  /// The one place the rule lives, because the diagnostics screen has to
  /// state the same answer the transports act on — "the module is installed"
  /// and "this screen used the module" are different questions, and the
  /// second one is what a reader wondering about a figure actually needs.
  static bool prefersModule(
    String capability,
    ModuleCapabilities capabilities,
  ) => capabilities.has(capability) && !readFromThePage.contains(capability);

  /// Where this capability is actually answered from, all three cases.
  ///
  /// The one place the rule lives, because the diagnostics screen has to state
  /// the same answer the transports act on — and with a store in play a reader
  /// wondering about a figure needs a third answer, not a second
  /// (`sync_eval.md` §11 #1).
  static ReadFrom sourceOf(
    String capability,
    ModuleCapabilities capabilities, {
    bool hasStore = false,
  }) {
    if (hasStore && answerableLocally.contains(capability)) {
      return ReadFrom.store;
    }
    return prefersModule(capability, capabilities)
        ? ReadFrom.module
        : ReadFrom.page;
  }
}

/// Which of the three sources answered.
enum ReadFrom {
  /// The site's own HTML. The floor, and permanent.
  page,

  /// The optional module's JSON.
  module,

  /// This device's copy. Says nothing about how old it is — ask
  /// `TreeStore.syncedAt` for that, and always tell the reader.
  store,
}

/// Reads people from the module where it can, and from HTML where it cannot.
final class CapabilityRecordsTransport implements RecordsTransport {
  const CapabilityRecordsTransport({
    required this.stock,
    required this.module,
    required this.capabilities,
    this.local,
  });

  final RecordsTransport stock;

  /// Null when this site has no module at all, which is the ordinary case.
  final RecordsTransport? module;

  /// This device's copy, or null — which is the state whenever there is no
  /// store, the sync has not finished, or the reader is not the one it was
  /// filled for. `TreeStore` owns that decision; by the time a transport
  /// arrives here it has already been made.
  final RecordsTransport? local;

  final ModuleCapabilities capabilities;

  /// The online source for [capability] — what answers when there is no store,
  /// and what a store falls back to.
  RecordsTransport _online(String capability) =>
      Capability.prefersModule(capability, capabilities)
      ? module ?? stock
      : stock;

  RecordsTransport? _local(String capability) =>
      Capability.answerableLocally.contains(capability) ? local : null;

  @override
  Future<SearchPage> search(String tree, String query, {int page = 1}) {
    final local = _local(Capability.individuals);
    // No fallback on this one. A search that found nothing locally *has*
    // searched the whole tree — that is the point of Phase 10 and what closes
    // `PROJECT.md` §9 #24 — so asking the server the same question would
    // trade the one capability the store is best at for a second round trip.
    return (local ?? _online(Capability.individuals)).search(
      tree,
      query,
      page: page,
    );
  }

  @override
  Future<IndividualRecord> individual(String tree, String xref) async {
    final local = _local(Capability.individual);
    if (local == null) {
      return _online(Capability.individual).individual(tree, xref);
    }

    try {
      return await local.individual(tree, xref);
    } on NotFound {
      // Absent from the store, which has two readings: the reader may not see
      // them, or the copy has not caught up. Only the server can tell those
      // apart, and it applies the same privacy either way — so asking is safe,
      // and the alternative is telling a reader that somebody who exists does
      // not.
      //
      // Rare by construction: a complete store holds every visible record.
      // Worth the round trip precisely because it is rare.
      developer.log(
        'No copy of $xref in the store — asking the site.',
        name: 'webtrees.capabilities',
      );
      return _online(Capability.individual).individual(tree, xref);
    }
  }

  /// Which charts the tree as a whole offers.
  ///
  /// Answered by whichever transport will be *reading* those charts, because
  /// a handle is only meaningful to the transport that minted it. Mixing them
  /// would hand a module endpoint to the HTML parser.
  ///
  /// Which is the page, today: statistics is the only tree-level chart, and
  /// [Capability.readFromThePage] says why the module does not answer it.
  @override
  Future<Map<ChartKind, String>> treeCharts(String tree) =>
      _online(Capability.statistics).treeCharts(tree);

  /// Always the stock path.
  ///
  /// Not a limitation. A module can sign a thumbnail URL at any size — which
  /// is a real gain — but the bytes still travel over the authenticated
  /// session, because `MediaFileThumbnail` checks the viewer's own permission
  /// before it validates the signature. There is nothing here for a module to
  /// improve, and one image cache is better than two.
  @override
  Future<Uint8List> image(String url) => stock.image(url);
}

/// Reads a chart from whichever transport minted its handle.
///
/// The handle decides, not the capability list: a person's record was fetched
/// by one transport, so the chart addresses on it belong to that one. Asking
/// the other to read them would be a category error, and this is where it is
/// prevented.
final class CapabilityChartsTransport implements ChartsTransport {
  const CapabilityChartsTransport({required this.stock, required this.module});

  final ChartsTransport stock;
  final ChartsTransport? module;

  /// A handle into the module is one whose path names the module's own base.
  ChartsTransport _for(String handle) {
    final module = this.module;
    return module != null && handle.contains(kModuleBase) ? module : stock;
  }

  @override
  Future<ChartData> chart(
    ChartKind kind,
    String handle, {
    required PersonRef subject,
    int? generations,
  }) => _for(
    handle,
  ).chart(kind, handle, subject: subject, generations: generations);

  @override
  Future<ChartData> hourglass({
    required String ancestorsHandle,
    required String descendantsHandle,
    required PersonRef subject,
    int? generations,
  }) => _for(ancestorsHandle).hourglass(
    ancestorsHandle: ancestorsHandle,
    descendantsHandle: descendantsHandle,
    subject: subject,
    generations: generations,
  );

  @override
  Future<List<RelationshipPath>> relationship(
    String handle, {
    required String from,
    required String to,
    bool? bloodLinesOnly,
  }) => _for(
    handle,
  ).relationship(handle, from: from, to: to, bloodLinesOnly: bloodLinesOnly);

  @override
  bool bloodLinesOnly(String handle) => _for(handle).bloodLinesOnly(handle);

  @override
  Future<TreeStatistics> statistics(String handle) =>
      _for(handle).statistics(handle);

  @override
  Future<TimelineChart> timeline(String handle) =>
      _for(handle).timeline(handle);
}

/// Asks the module who is signed in, or probes for it the long way.
final class CapabilityAccessTransport implements AccessTransport {
  const CapabilityAccessTransport({
    required this.stock,
    required this.module,
    required this.capabilities,
  });

  final AccessTransport stock;
  final AccessTransport? module;
  final ModuleCapabilities capabilities;

  @override
  Future<AccessSummary> describe() =>
      (Capability.prefersModule(Capability.access, capabilities)
              ? module ?? stock
              : stock)
          .describe();
}
