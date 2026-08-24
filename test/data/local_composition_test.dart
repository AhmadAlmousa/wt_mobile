import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/data/capabilities.dart';
import 'package:webtrees_mobile/data/diagnostics.dart';
import 'package:webtrees_mobile/data/module/module_api.dart';
import 'package:webtrees_mobile/data/session_manager.dart';
import 'package:webtrees_mobile/data/transport.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/records.dart';

/// Where an answer comes from, once there are three places it could.
///
/// Phase 10b built the store and Phase 10c is where the composer starts
/// preferring it — which is the moment `sync_eval.md` §11 #1 stops being a
/// risk on a list and becomes something the code has to be right about:
/// *"two sources of truth become 'is it stale or is it wrong?'"*.
///
/// The rule these tests pin down is deliberately narrow. A store may answer
/// only what it holds **as the bytes the server sent** — a record and a
/// search over records — and nothing that would make the app compute something
/// the site publishes itself.
void main() {
  ModuleCapabilities withEverything() => ModuleCapabilities(
    apiVersion: 1,
    moduleVersion: '1.3.0',
    webtreesVersion: '2.2.6',
    features: const {
      Capability.access,
      Capability.individuals,
      Capability.individual,
      Capability.ancestors,
      Capability.descendants,
      Capability.relationship,
      Capability.timeline,
      Capability.statistics,
      Capability.records,
    },
    languages: const {'en'},
  );

  group('the staleness rule', () {
    test('lets the store answer a record and a search, and nothing else', () {
      expect(Capability.answerableLocally, {
        Capability.individuals,
        Capability.individual,
      });
    });

    test('never lets it answer a relationship or the statistics', () {
      // `sync_eval.md` §5. The first needs kinship wording that is one of the
      // largest things in webtrees and must not be ported twice; the second is
      // the site's own arithmetic, and a store computing its own would show
      // the app's where every other screen shows the site's.
      for (final capability in [
        Capability.relationship,
        Capability.statistics,
      ]) {
        expect(
          Capability.sourceOf(capability, withEverything(), hasStore: true),
          isNot(ReadFrom.store),
          reason: '$capability must stay online',
        );
      }
    });

    test('never lets it answer a chart yet', () {
      // Computable from the stored family links — Phase 10d — and until then
      // a chart opened from a stored record uses the handle the store kept,
      // which addresses the module.
      for (final capability in [
        Capability.ancestors,
        Capability.descendants,
        Capability.timeline,
      ]) {
        expect(
          Capability.sourceOf(capability, withEverything(), hasStore: true),
          ReadFrom.module,
        );
      }
    });

    test('says "page" for what the page answers, store or no store', () {
      // Statistics is read from the page even where the module offers it, and
      // a local copy does not change that.
      expect(
        Capability.sourceOf(
          Capability.statistics,
          withEverything(),
          hasStore: true,
        ),
        ReadFrom.page,
      );
    });

    test('falls back to the old two answers with no store', () {
      expect(
        Capability.sourceOf(Capability.individual, withEverything()),
        ReadFrom.module,
      );
      expect(
        Capability.sourceOf(Capability.individual, ModuleCapabilities.none),
        ReadFrom.page,
      );
    });
  });

  group('the composer', () {
    CapabilityRecordsTransport composed({
      RecordsTransport? local,
      RecordsTransport? module,
      RecordsTransport? stock,
    }) => CapabilityRecordsTransport(
      stock: stock ?? _Named('stock'),
      module: module ?? _Named('module'),
      local: local,
      capabilities: withEverything(),
    );

    test('reads a person from the store when there is one', () async {
      final transport = composed(local: _Named('local'));
      expect((await transport.individual('main', 'I1')).name, 'local');
    });

    test('reads a person from the module when there is not', () async {
      expect((await composed().individual('main', 'I1')).name, 'module');
    });

    test('searches the store, and does not ask the site as well', () async {
      // No fallback on this one, on purpose: a search that found nothing
      // locally *has* searched the whole tree, which is the point of Phase 10
      // and what closes `PROJECT.md` §9 #24. Asking the server the same
      // question would trade the capability the store is best at for a round
      // trip.
      final transport = composed(
        local: _Named('local', people: const []),
        module: _Exploding(),
      );

      expect((await transport.search('main', 'nobody')).people, isEmpty);
    });

    test('asks the site for a person the copy has not caught up to', () async {
      // Absent from a store has two readings — the reader may not see them, or
      // the copy is behind — and only the server can tell them apart. It
      // applies the same privacy either way, so asking is safe, and the
      // alternative is telling a reader that somebody who exists does not.
      final transport = composed(local: _Empty(), module: _Named('module'));

      expect((await transport.individual('main', 'I9')).name, 'module');
    });

    test('lets a real failure through rather than papering over it', () async {
      // Only [NotFound] means "the copy does not have them". Anything else is
      // a store that is broken, and hiding that behind a silent round trip is
      // how a bug survives a release.
      final transport = composed(local: _Exploding(), module: _Named('module'));

      expect(
        () => transport.individual('main', 'I1'),
        throwsA(isA<StateError>()),
      );
    });

    test('never routes a relationship or the statistics locally', () async {
      // The store is handed in, and must still not be consulted: these two
      // are not in `answerableLocally`, so `treeCharts` goes to whichever
      // transport will read the handles it mints.
      final transport = composed(local: _Exploding());
      expect((await transport.treeCharts('main')).isEmpty, isTrue);
    });

    test('image bytes always travel over the session', () async {
      // Not a limitation. A thumbnail URL is HMAC-signed and
      // `MediaFileThumbnail` checks the viewer's own permission *before*
      // validating the signature, so the bytes cannot come from a store until
      // Phase 10e keeps them as blobs.
      final transport = composed(local: _Exploding());
      expect(await transport.image('any'), isEmpty);
    });
  });

  group('diagnostics', () {
    test('says a figure came from this device, and when', () {
      final at = DateTime.utc(2026, 8, 24, 9, 30);
      final report = Diagnostics(
        stage: ConnectionStage.signedIn,
        instance: null,
        username: 'mobile',
        capabilities: withEverything(),
        hasStore: true,
        syncedAt: at,
        storedPeople: 1463,
      ).report;

      expect(report, contains('store: 1463 people'));
      expect(report, contains(at.toIso8601String()));
      // The line a maintainer greps. Three answers now, not two.
      expect(report, contains('individual=store'));
      expect(report, contains('relationship=module'));
      expect(report, contains('statistics=pages'));
    });

    test('says so plainly when there is no copy', () {
      final report = Diagnostics(
        stage: ConnectionStage.signedIn,
        instance: null,
        username: 'mobile',
        capabilities: withEverything(),
      ).report;

      expect(report, contains('store: none'));
      expect(report, contains('individual=module'));
    });
  });
}

/// Answers everything with its own name, so a test can see who replied.
final class _Named implements RecordsTransport {
  _Named(this.label, {this.people});

  final String label;
  final List<PersonRef>? people;

  @override
  Future<SearchPage> search(
    String tree,
    String query, {
    int page = 1,
  }) async => SearchPage(
    people:
        people ??
        [PersonRef(xref: 'I1', name: label, sex: Sex.male, isDeceased: true)],
    hasMore: false,
  );

  @override
  Future<IndividualRecord> individual(String tree, String xref) async =>
      IndividualRecord(
        xref: xref,
        name: label,
        facts: const [],
        families: const [],
      );

  @override
  Future<Map<ChartKind, String>> treeCharts(String tree) async => const {};

  @override
  Future<Uint8List> image(String url) async => Uint8List(0);
}

/// A store with nothing in it, which is what a copy that has not caught up
/// looks like from the outside.
final class _Empty implements RecordsTransport {
  @override
  Future<SearchPage> search(String tree, String query, {int page = 1}) async =>
      const SearchPage(people: [], hasMore: false);

  @override
  Future<IndividualRecord> individual(String tree, String xref) =>
      throw NotFound(detail: 'No copy of $xref in this store.');

  @override
  Future<Map<ChartKind, String>> treeCharts(String tree) async => const {};

  @override
  Future<Uint8List> image(String url) async => Uint8List(0);
}

/// Fails if anything reaches it.
final class _Exploding implements RecordsTransport {
  @override
  Future<SearchPage> search(String tree, String query, {int page = 1}) =>
      throw StateError('should not have been asked');

  @override
  Future<IndividualRecord> individual(String tree, String xref) =>
      throw StateError('should not have been asked');

  @override
  Future<Map<ChartKind, String>> treeCharts(String tree) =>
      throw StateError('should not have been asked');

  @override
  Future<Uint8List> image(String url) =>
      throw StateError('should not have been asked');
}
