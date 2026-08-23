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

import 'dart:typed_data';

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
}

/// Reads people from the module where it can, and from HTML where it cannot.
final class CapabilityRecordsTransport implements RecordsTransport {
  const CapabilityRecordsTransport({
    required this.stock,
    required this.module,
    required this.capabilities,
  });

  final RecordsTransport stock;

  /// Null when this site has no module at all, which is the ordinary case.
  final RecordsTransport? module;

  final ModuleCapabilities capabilities;

  RecordsTransport _for(String capability) =>
      capabilities.has(capability) ? module ?? stock : stock;

  @override
  Future<SearchPage> search(String tree, String query, {int page = 1}) =>
      _for(Capability.individuals).search(tree, query, page: page);

  @override
  Future<IndividualRecord> individual(String tree, String xref) =>
      _for(Capability.individual).individual(tree, xref);

  /// Which charts the tree as a whole offers.
  ///
  /// Answered by whichever transport will be *reading* those charts, because
  /// a handle is only meaningful to the transport that minted it. Mixing them
  /// would hand a module endpoint to the HTML parser.
  @override
  Future<Map<ChartKind, String>> treeCharts(String tree) =>
      _for(Capability.statistics).treeCharts(tree);

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
  }) => _for(handle).relationship(
    handle,
    from: from,
    to: to,
    bloodLinesOnly: bloodLinesOnly,
  );

  @override
  bool bloodLinesOnly(String handle) => _for(handle).bloodLinesOnly(handle);

  @override
  Future<TreeStatistics> statistics(String handle) =>
      _for(handle).statistics(handle);

  @override
  Future<TimelineChart> timeline(String handle) => _for(handle).timeline(handle);
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
      (capabilities.has(Capability.access) ? module ?? stock : stock).describe();
}
