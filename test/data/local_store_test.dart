import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Table, TableInfo, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/data/local/local_records.dart';
import 'package:webtrees_mobile/data/local/records_page.dart';
import 'package:webtrees_mobile/data/local/store.dart';
import 'package:webtrees_mobile/data/local/sync.dart';
import 'package:webtrees_mobile/data/module/module_decode.dart';
import 'package:webtrees_mobile/data/transport.dart';
import 'package:webtrees_mobile/domain/access.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/records.dart';

/// The store, and the loop that fills it.
///
/// Everything here runs against a real SQLite database in memory and a fake
/// server, which is the point: the behaviour worth testing is not "does the
/// endpoint answer" — a lab and `tool/live_check.dart` prove that once a day —
/// but what happens when a page fails halfway, when a record is deleted, when
/// the reader changes, and when the server says the copy cannot be caught up.
/// None of those are things a live run reliably produces.
void main() {
  late LocalStore store;

  // Each test opens its own in-memory database, and one test opens several to
  // check three stamps in a row. They share no executor, so drift's warning
  // about a class opened twice is about a hazard that cannot arise here.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() => store = LocalStore.forTesting(NativeDatabase.memory()));
  tearDown(() => store.close());

  const stamp = StoreStamp(
    tree: 'main',
    username: 'mobile',
    role: TreeRole.member,
    language: 'ar',
    moduleVersion: '1.3.0',
  );

  /// A person as the sync endpoint states one: enough of the real shape to
  /// exercise the columns and the family rows.
  Map<String, Object?> person(
    String xref, {
    String? name,
    String? alternateName,
    String sex = 'male',
    bool deceased = false,
    int? birthYear,
    List<Map<String, Object?>> families = const [],
  }) => {
    'xref': xref,
    'name': name ?? 'Person $xref',
    'alternateName': alternateName,
    'sex': sex,
    'deceased': deceased,
    'lifespan': null,
    'birthYear': birthYear,
    'deathYear': null,
    'age': null,
    'birthPlace': null,
    'thumbnail': null,
    'private': false,
    'pending': null,
    'facts': const [],
    'families': families,
    'notes': null,
    'sources': null,
    'media': null,
    'warnings': const [],
  };

  Map<String, Object?> family(
    String xref, {
    String kind = 'own',
    List<String> spouses = const [],
    List<String> children = const [],
  }) => {
    'xref': xref,
    'label': 'Family $xref',
    'kind': kind,
    'spouses': [for (final one in spouses) person(one)],
    'children': [for (final one in children) person(one)],
    'facts': const [],
    'endedInDivorce': false,
    'pending': null,
  };

  RecordsPage page({
    required String token,
    required List<Map<String, Object?>> people,
    bool hasMore = false,
    List<String> deleted = const [],
    bool resync = false,
    int offset = 0,
    int limit = 2,
  }) => RecordsPage(
    token: token,
    offset: offset,
    limit: limit,
    total: 6,
    hasMore: hasMore,
    resync: resync,
    sections: const ['personal_facts', 'relatives'],
    chartClasses: const ['menu-chart-ancestry', 'menu-chart-descendants'],
    people: people,
    deleted: deleted,
  );

  group('filling the store', () {
    test('a walk writes every page, and says when it is done', () async {
      final source = _ScriptedSource([
        page(token: 't1', people: [person('X1'), person('X2')], hasMore: true),
        page(token: 't1', people: [person('X3'), person('X4')], hasMore: true),
        page(token: 't1', people: [person('X5')]),
      ]);

      final report = await TreeSync(
        store: store,
        source: source,
        stamp: stamp,
        pageSize: 2,
      ).run();

      expect(report.written, 5);
      expect(report.requests, 3);
      expect(report.complete, isTrue);
      expect(report.token, 't1');
      expect(await _count(store, store.storedPeople), 5);

      final state = await store.select(store.storedTreeStates).getSingle();
      expect(state.filling, isFalse);
      expect(state.token, 't1');
      expect(state.syncedAt, isNotNull);
      expect(jsonDecode(state.sections), contains('relatives'));
    });

    test('the offset advances by the limit, not by what arrived', () async {
      // Privacy is applied after a page of rows is taken, so a page can be
      // shorter than the limit without being the last page. A client that
      // advanced by `people.length` would re-read the rows it had, forever.
      final source = _ScriptedSource([
        page(token: 't1', people: [person('X1')], hasMore: true),
        page(token: 't1', people: [person('X3'), person('X4')]),
      ]);

      await TreeSync(
        store: store,
        source: source,
        stamp: stamp,
        pageSize: 2,
      ).run();

      expect(source.offsets, [0, 2]);
      expect(await _count(store, store.storedPeople), 3);
    });

    test('a page that fails is resumed, not restarted', () async {
      final source = _ScriptedSource([
        page(token: 't1', people: [person('X1'), person('X2')], hasMore: true),
        const _Boom(),
        page(token: 't1', people: [person('X3')]),
      ]);

      final sync = TreeSync(
        store: store,
        source: source,
        stamp: stamp,
        pageSize: 2,
      );

      await expectLater(sync.run(), throwsA(isA<UnreachableHost>()));
      expect(await _count(store, store.storedPeople), 2);

      // The cursor was saved with the page that succeeded, so the second call
      // asks for the third row rather than the first.
      final resumed = await sync.run();
      expect(source.offsets, [0, 2, 2]);
      expect(resumed.complete, isTrue);
      expect(await _count(store, store.storedPeople), 3);
    });

    test(
      'a mid-walk change is caught by a delta from the first token',
      () async {
        // Every page states the fingerprint as it is *now*. Keeping the last
        // one would claim a change this walk never saw; keeping the first and
        // running a delta gets the record instead of losing it.
        final source = _ScriptedSource([
          page(token: 't1', people: [person('X1')], hasMore: true),
          page(token: 't2', people: [person('X2')]),
          page(
            token: 't2',
            people: [person('X1', name: 'Renamed')],
          ),
        ]);

        final report = await TreeSync(
          store: store,
          source: source,
          stamp: stamp,
          pageSize: 1,
        ).run();

        expect(source.sinces, [null, null, 't1']);
        expect(report.complete, isTrue);
        expect(report.token, 't2');

        final renamed = await (store.select(
          store.storedPeople,
        )..where((row) => row.xref.equals('X1'))).getSingle();
        expect(renamed.name, 'Renamed');
      },
    );
  });

  group('keeping it filled', () {
    Future<void> fill(SyncSource source, {int pageSize = 10}) => TreeSync(
      store: store,
      source: source,
      stamp: stamp,
      pageSize: pageSize,
    ).run();

    test('a delta rewrites what changed and removes a tombstone', () async {
      final source = _ScriptedSource([
        page(token: 't1', people: [person('X1'), person('X2')]),
        page(
          token: 't2',
          people: [person('X1', name: 'Renamed')],
          deleted: ['X2'],
        ),
      ]);

      await fill(source);
      final report = await TreeSync(
        store: store,
        source: source,
        stamp: stamp,
      ).run();

      expect(source.sinces.last, 't1');
      expect(report.deleted, 1);
      expect(report.token, 't2');

      final left = await store.select(store.storedPeople).get();
      expect(left.map((row) => row.xref), ['X1']);
      expect(left.single.name, 'Renamed');
    });

    test('a fingerprint the server refuses starts the copy again', () async {
      final source = _ScriptedSource([
        page(token: 't1', people: [person('X1'), person('X2')]),
        page(token: 't9', people: const [], resync: true),
        page(token: 't9', people: [person('X3')]),
      ]);

      await fill(source);
      final report = await TreeSync(
        store: store,
        source: source,
        stamp: stamp,
      ).run();

      expect(report.startedFresh, isTrue);
      expect(report.complete, isTrue);
      // The old copy is gone rather than merged: a resync means the server
      // cannot describe a path from where this store was.
      final left = await store.select(store.storedPeople).get();
      expect(left.map((row) => row.xref), ['X3']);
    });

    test('nothing changed is a request and no writes', () async {
      final source = _ScriptedSource([
        page(token: 't1', people: [person('X1')]),
        page(token: 't1', people: const []),
      ]);

      await fill(source);
      final report = await TreeSync(
        store: store,
        source: source,
        stamp: stamp,
      ).run();

      expect(report.written, 0);
      expect(report.deleted, 0);
      expect(report.requests, 1);
      expect(await _count(store, store.storedPeople), 1);
    });
  });

  group('whose copy it is', () {
    test('a different reader gets a new store, not a filtered one', () async {
      // webtrees privacy is per user and per record, so a copy filled for one
      // reader can only ever be wrong for another — permissively wrong, which
      // is the direction that matters.
      final source = _ScriptedSource([
        page(token: 't1', people: [person('X1'), person('X2')]),
        page(token: 't2', people: [person('X1')]),
      ]);

      await TreeSync(store: store, source: source, stamp: stamp).run();

      const other = StoreStamp(
        tree: 'main',
        username: 'someone-else',
        role: TreeRole.member,
        language: 'ar',
        moduleVersion: '1.3.0',
      );

      final report = await TreeSync(
        store: store,
        source: source,
        stamp: other,
      ).run();

      expect(report.startedFresh, isTrue);
      // A full walk, not a delta: there was nothing to catch up from.
      expect(source.sinces.last, isNull);
      final left = await store.select(store.storedPeople).get();
      expect(left.map((row) => row.xref), ['X1']);
      expect(
        (await store.select(store.storedTreeStates).getSingle()).username,
        'someone-else',
      );
    });

    test('a changed language, role or module replaces the copy', () async {
      for (final changed in [
        const StoreStamp(
          tree: 'main',
          username: 'mobile',
          role: TreeRole.member,
          language: 'en-GB',
          moduleVersion: '1.3.0',
        ),
        const StoreStamp(
          tree: 'main',
          username: 'mobile',
          role: TreeRole.manager,
          language: 'ar',
          moduleVersion: '1.3.0',
        ),
        const StoreStamp(
          tree: 'main',
          username: 'mobile',
          role: TreeRole.member,
          language: 'ar',
          moduleVersion: '1.2.1',
        ),
      ]) {
        final fresh = LocalStore.forTesting(NativeDatabase.memory());
        addTearDown(fresh.close);

        final source = _ScriptedSource([
          page(token: 't1', people: [person('X1')]),
          page(token: 't1', people: [person('X1')]),
        ]);

        await TreeSync(store: fresh, source: source, stamp: stamp).run();
        final report = await TreeSync(
          store: fresh,
          source: source,
          stamp: changed,
        ).run();

        expect(report.startedFresh, isTrue, reason: '$changed');
      }
    });

    test('signing out leaves nothing behind', () async {
      final source = _ScriptedSource([
        page(
          token: 't1',
          people: [
            person('X1', families: [family('F1')]),
          ],
        ),
      ]);

      await TreeSync(store: store, source: source, stamp: stamp).run();
      await TreeSync(store: store, source: source, stamp: stamp).wipe('main');

      expect(await _count(store, store.storedPeople), 0);
      expect(await _count(store, store.storedMemberships), 0);
      expect(await _count(store, store.storedTreeStates), 0);
    });
  });

  group('who is in which family', () {
    test('every member of every family a record states', () async {
      // What a chart is a walk over. The module states, per person, each
      // family they belong to with *all* of its spouses and children — the
      // subject included — so a membership needs no inference.
      final source = _ScriptedSource([
        page(
          token: 't1',
          people: [
            person(
              'X42',
              families: [
                family(
                  'F1',
                  kind: 'parents',
                  spouses: ['X7', 'X8'],
                  children: ['X42', 'X43'],
                ),
                family('F2', spouses: ['X42', 'X50'], children: ['X60']),
              ],
            ),
          ],
        ),
      ]);

      await TreeSync(store: store, source: source, stamp: stamp).run();

      final rows = await store.select(store.storedMemberships).get();
      expect(
        rows.map((row) => '${row.familyXref}:${row.personXref}:${row.role}'),
        containsAll([
          'F1:X7:spouse',
          'F1:X8:spouse',
          'F1:X42:child',
          'F1:X43:child',
          'F2:X42:spouse',
          'F2:X50:spouse',
          'F2:X60:child',
        ]),
      );
      // Only the subject's own statement is stored, so nothing else is
      // claiming X43 or X50 has been synced.
      expect(rows.every((row) => row.statedBy == 'X42'), isTrue);
    });

    test('a re-stated family replaces only that person\'s statement', () async {
      final source = _ScriptedSource([
        page(
          token: 't1',
          people: [
            person(
              'A',
              families: [
                family('F1', spouses: ['A', 'B']),
              ],
            ),
            person(
              'B',
              families: [
                family('F1', spouses: ['A', 'B']),
              ],
            ),
          ],
        ),
        page(
          token: 't2',
          people: [
            person(
              'A',
              families: [
                family('F9', spouses: ['A']),
              ],
            ),
          ],
        ),
      ]);

      await TreeSync(store: store, source: source, stamp: stamp).run();
      await TreeSync(store: store, source: source, stamp: stamp).run();

      final rows = await store.select(store.storedMemberships).get();
      // A's old statement about F1 is gone; B's identical statement is not,
      // because B was not re-sent and B still says so.
      expect(
        rows.where((row) => row.statedBy == 'A').map((r) => r.familyXref),
        everyElement('F9'),
      );
      expect(
        rows.where((row) => row.statedBy == 'B').map((r) => r.familyXref),
        everyElement('F1'),
      );
    });
  });

  group('reading it back', () {
    test(
      'a record read from the store is the record that was stored',
      () async {
        // The fixture is a **captured** page from a running 2.2.6 lab (its host
        // rewritten, nothing else), which is the first module fixture in this
        // project that was not written from the design — the gap PROJECT.md §9
        // #26 names. Two real records, one of them with four families, notes, a
        // citation and two photographs.
        final captured =
            jsonDecode(
                  File('test/fixtures/module/records.json').readAsStringSync(),
                )
                as Map<String, Object?>;
        final wire = RecordsPage.fromJson(captured);

        await TreeSync(
          store: store,
          source: _ScriptedSource([wire]),
          stamp: stamp,
        ).run();

        final local = LocalRecordsTransport(store: store, online: _NoOnline());

        final read = await local.individual('main', 'X42');
        final direct = individualFrom(
          wire.people.first,
          xref: 'X42',
          sections: wire.sections,
          charts: read.charts,
        );

        expect(read.name, direct.name);
        expect(read.alternateName, direct.alternateName);
        expect(read.sex, direct.sex);
        expect(read.isDeceased, direct.isDeceased);
        expect(read.facts.length, direct.facts.length);
        expect(read.families.length, direct.families.length);
        expect(read.notes.length, direct.notes.length);
        expect(read.sources.length, direct.sources.length);
        expect(read.media.length, direct.media.length);
        expect(read.sections, contains('relatives'));
        // The page states the tree's charts once; a stored record gets them
        // back, so it opens the same charts as one read from the wire.
        expect(read.charts.keys, contains(ChartKind.ancestors));
      },
    );

    test('a search row out of the columns says what the payload does', () async {
      // The invariant behind Phase 10c's one optimisation. A search row is
      // built from the stored **columns** rather than by decoding the payload,
      // which is what makes answering with the whole tree affordable — and it
      // is only safe while the columns say exactly what `personFrom` would.
      // They are written by that same function, so this holds by
      // construction; it is asserted because nothing else would notice if a
      // future column stopped being filled.
      final captured =
          jsonDecode(
                File('test/fixtures/module/records.json').readAsStringSync(),
              )
              as Map<String, Object?>;
      final wire = RecordsPage.fromJson(captured);

      await TreeSync(
        store: store,
        source: _ScriptedSource([wire]),
        stamp: stamp,
      ).run();

      final local = LocalRecordsTransport(store: store, online: _NoOnline());
      final found = await local.search('main', 'X42');
      final row = found.people.single;
      final direct = personFrom(
        wire.people.firstWhere((person) => person['xref'] == 'X42'),
      );

      expect(row.xref, direct.xref);
      expect(row.name, direct.name);
      expect(row.alternateName, direct.alternateName);
      expect(row.sex, direct.sex);
      expect(row.isDeceased, direct.isDeceased);
      expect(row.lifespan, direct.lifespan);
      expect(row.birthYear, direct.birthYear);
      expect(row.deathYear, direct.deathYear);
      expect(row.age, direct.age);
      expect(row.birthPlace, direct.birthPlace);
      expect(row.thumbnailUrl, direct.thumbnailUrl);
    });

    test('a record this copy does not hold is absent, not empty', () async {
      final local = LocalRecordsTransport(store: store, online: _NoOnline());
      await expectLater(
        local.individual('main', 'X404'),
        throwsA(isA<NotFound>()),
      );
    });

    test(
      'search matches either name form, and an empty query enumerates',
      () async {
        final source = _ScriptedSource([
          page(
            token: 't1',
            people: [
              person(
                'X42',
                name: 'عبد الله الموسى',
                alternateName: 'Abdullah Almousa',
              ),
              person('X50', name: 'سارة العنزي'),
            ],
          ),
        ]);

        await TreeSync(store: store, source: source, stamp: stamp).run();
        final local = LocalRecordsTransport(store: store, online: _NoOnline());

        expect(
          (await local.search('main', 'Abdullah')).people.map((p) => p.xref),
          ['X42'],
        );
        expect(
          (await local.search('main', 'الموسى')).people.map((p) => p.xref),
          ['X42'],
        );
        expect((await local.search('main', 'X50')).people.map((p) => p.xref), [
          'X50',
        ]);
        // The thing no stock route can do at all, and here it costs a LIMIT.
        expect((await local.search('main', '')).people.length, 2);
        expect((await local.search('main', 'nobody')).people, isEmpty);
      },
    );

    test('a copy mid-walk does not claim to be the tree', () async {
      final source = _ScriptedSource([
        page(token: 't1', people: [person('X1')], hasMore: true),
        const _Boom(),
      ]);

      final sync = TreeSync(
        store: store,
        source: source,
        stamp: stamp,
        pageSize: 1,
      );
      await expectLater(sync.run(), throwsA(isA<UnreachableHost>()));

      final local = LocalRecordsTransport(store: store, online: _NoOnline());
      expect(await local.isComplete('main'), isFalse);

      // ...and does once the walk has finished, which is the other half of
      // the same rule: a store is answerable when it holds the whole of what
      // the reader may see, and not a page before.
      await sync.run();
      expect(await local.isComplete('main'), isTrue);
    });
  });
}

/// Stands in a script where a request should fail rather than answer.
final class _Boom {
  const _Boom();
}

/// How many rows a table holds.
Future<int> _count<T extends Table, D>(
  LocalStore store,
  TableInfo<T, D> table,
) async => (await store.select(table).get()).length;

final class _ScriptedSource implements SyncSource {
  _ScriptedSource(this._pages);

  final List<Object> _pages;
  var _index = 0;

  final offsets = <int>[];
  final sinces = <String?>[];

  @override
  Future<RecordsPage> records(
    String tree, {
    required int offset,
    required int limit,
    String? since,
  }) async {
    offsets.add(offset);
    sinces.add(since);

    if (_index >= _pages.length) {
      return RecordsPage(
        token: 'exhausted',
        offset: offset,
        limit: limit,
        total: 0,
        hasMore: false,
        resync: false,
        sections: const [],
        chartClasses: const [],
        people: const [],
        deleted: const [],
      );
    }

    final next = _pages[_index++];
    if (next is _Boom) {
      throw const UnreachableHost('host', detail: 'the network went away');
    }

    return next as RecordsPage;
  }
}

/// Stands in for the online transport, and fails if anything reaches it.
final class _NoOnline implements RecordsTransport {
  @override
  Future<SearchPage> search(String tree, String query, {int page = 1}) =>
      throw StateError('the store should have answered this');

  @override
  Future<IndividualRecord> individual(String tree, String xref) =>
      throw StateError('the store should have answered this');

  @override
  Future<Map<ChartKind, String>> treeCharts(String tree) =>
      throw StateError('not asked for in these tests');

  @override
  Future<Uint8List> image(String url) =>
      throw StateError('not asked for in these tests');
}
