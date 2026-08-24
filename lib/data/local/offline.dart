/// What answers when there is no site to ask.
///
/// The store holds records, and Phase 10c wired it in behind a signed-in
/// session — which was the whole gap the first offline test found: the app
/// would not *start* without a network, because every route into it went
/// through a sign-in. These are the transports that let it start anyway.
///
/// The rule they keep is the same one the rest of the project keeps: **say
/// what is true rather than approximate it.** A store cannot produce the
/// site's kinship wording or the site's arithmetic (`sync_eval.md` §5), and
/// until Phase 10e it holds no image bytes. So those throw
/// [NotAvailableOffline], which the interface words as *"this needs the
/// site"* — an honest answer, and one a reader can act on by finding signal.
library;

import 'dart:typed_data';

import '../../core/errors.dart';
import '../../domain/access.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import '../../domain/statistics.dart';
import '../transport.dart';

/// Stands where the network would be, and refuses politely.
final class OfflineRecordsTransport implements RecordsTransport {
  const OfflineRecordsTransport();

  @override
  Future<SearchPage> search(String tree, String query, {int page = 1}) =>
      throw const NotAvailableOffline('searching the site');

  @override
  Future<IndividualRecord> individual(String tree, String xref) =>
      throw const NotAvailableOffline('this record');

  /// Tree-level charts means statistics, which is read from the site's own
  /// page on purpose (`Capability.readFromThePage`) and has no local form.
  @override
  Future<Map<ChartKind, String>> treeCharts(String tree) async => const {};

  /// A thumbnail URL is an address, not a picture: the bytes travel over the
  /// session because `MediaFileThumbnail` checks the viewer's permission
  /// before it validates the signature. Phase 10e stores them as blobs.
  @override
  Future<Uint8List> image(String url) =>
      throw const NotAvailableOffline('photographs');
}

/// The charts a store cannot draw yet.
///
/// Phase 10d computes ancestors, descendants and the timeline from the stored
/// family links; until then every chart is a handle into the module, and a
/// handle is useless with nothing to hand it to. Relationships and statistics
/// stay here permanently for the reasons in `sync_eval.md` §5.
final class OfflineChartsTransport implements ChartsTransport {
  const OfflineChartsTransport();

  @override
  Future<ChartData> chart(
    ChartKind kind,
    String handle, {
    required PersonRef subject,
    int? generations,
  }) => throw const NotAvailableOffline('this chart');

  @override
  Future<ChartData> hourglass({
    required String ancestorsHandle,
    required String descendantsHandle,
    required PersonRef subject,
    int? generations,
  }) => throw const NotAvailableOffline('this chart');

  @override
  Future<List<RelationshipPath>> relationship(
    String handle, {
    required String from,
    required String to,
    bool? bloodLinesOnly,
  }) => throw const NotAvailableOffline('how two people are related');

  /// Nothing is known about the site's settings offline, and `false` is the
  /// answer that describes *more* paths rather than fewer — so a reader is
  /// never told "no link found" on the strength of a guess.
  @override
  bool bloodLinesOnly(String handle) => false;

  @override
  Future<TreeStatistics> statistics(String handle) =>
      throw const NotAvailableOffline('what the site says about the tree');

  @override
  Future<TimelineChart> timeline(String handle) =>
      throw const NotAvailableOffline('this timeline');
}

/// What the app knows about the reader with no site to ask.
///
/// Read back out of the store's own stamp rather than probed: the row that
/// records *whose* copy this is carries the account and the role, which is
/// exactly what an access summary states.
final class OfflineAccessTransport implements AccessTransport {
  const OfflineAccessTransport(this.summary);

  final AccessSummary summary;

  @override
  Future<AccessSummary> describe() async => summary;
}
