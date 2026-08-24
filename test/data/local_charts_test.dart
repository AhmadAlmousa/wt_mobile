import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/data/local/local_charts.dart';
import 'package:webtrees_mobile/data/local/local_records.dart';
import 'package:webtrees_mobile/data/local/records_page.dart';
import 'package:webtrees_mobile/data/local/store.dart';
import 'package:webtrees_mobile/data/local/sync.dart';
import 'package:webtrees_mobile/data/transport.dart';
import 'package:webtrees_mobile/domain/access.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/records.dart';

/// Charts walked out of the store rather than fetched.
///
/// `sync_eval.md` §4 predicted the shape of this: *"the shapes are walks over
/// the stored family links. The app already owns every layout; only the shape
/// was ever fetched."* These tests are about the walk being **the same shape
/// the server would have sent** — Sosa numbers where webtrees puts them,
/// d'Aboville numbers built the same way, fathers before mothers — because a
/// chart that renumbered itself offline would be a different chart.
///
/// The family fixture, three generations:
///
///     X1 ─┬─ X2          grandfather and grandmother
///         │
///     X3 ─┴─ X4          father (child of X1/X2) and mother
///         │
///     X5, X6             the subject and a sibling
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late LocalStore store;

  setUp(() async {
    store = LocalStore.forTesting(NativeDatabase.memory());
    await TreeSync(
      store: store,
      source: _ThreeGenerations(),
      stamp: const StoreStamp(
        tree: 'main',
        username: 'mobile',
        role: TreeRole.member,
        language: 'en',
        moduleVersion: '1.3.0',
      ),
    ).run();
  });

  tearDown(() => store.close());

  LocalChartsTransport charts() =>
      LocalChartsTransport(store: store, tree: 'main', online: const _NoSite());

  Future<PersonRef> person(String xref) async {
    final local = LocalRecordsTransport(store: store, online: _NoRecords());
    final found = await local.search('main', xref);
    return found.people.single;
  }

  group('walking upwards', () {
    test('numbers the generations the way webtrees does', () async {
      final subject = await person('X5');
      final data = await charts().chart(
        ChartKind.ancestors,
        localChartHandle(ChartKind.ancestors, 'main', 'X5'),
        subject: subject,
      );

      final root = data.ancestors!;
      expect(root.sosa, 1);
      expect(root.person.xref, 'X5');

      // 2 is the father and 3 the mother, always — a person's parents are 2n
      // and 2n+1, which is what every upward layout in the app draws from.
      final parents = root.parents;
      expect(parents.map((p) => p.sosa), [2, 3]);
      expect(parents.first.person.xref, 'X3', reason: 'father first');
      expect(parents.last.person.xref, 'X4');

      // And one more generation, on the father's side.
      final grandparents = parents.first.parents;
      expect(grandparents.map((p) => p.sosa), [4, 5]);
      expect(grandparents.first.person.xref, 'X1');
    });

    test('stops where the reader asked it to', () async {
      final subject = await person('X5');
      final data = await charts().chart(
        ChartKind.ancestors,
        localChartHandle(ChartKind.ancestors, 'main', 'X5'),
        subject: subject,
        generations: 2,
      );

      expect(data.ancestors!.parents, hasLength(2));
      expect(data.ancestors!.parents.first.parents, isEmpty);
    });

    test('stops where the tree does', () async {
      // X1 has no recorded parents. A chart ends there rather than inventing
      // an empty box, which is what the server does too.
      final subject = await person('X1');
      final data = await charts().chart(
        ChartKind.ancestors,
        localChartHandle(ChartKind.ancestors, 'main', 'X1'),
        subject: subject,
      );

      expect(data.ancestors!.parents, isEmpty);
    });

    test('cannot reach what the copy does not hold', () async {
      // The property that makes a locally drawn chart *correct* rather than
      // merely fast. A record this reader may not see was never synced
      // (`sync_eval.md` §6: a hidden record is absent, not empty), so privacy
      // pruning happens by construction — the walk has nothing to walk to.
      await (store.delete(
        store.storedPeople,
      )..where((row) => row.xref.equals('X1'))).go();

      final subject = await person('X5');
      final data = await charts().chart(
        ChartKind.ancestors,
        localChartHandle(ChartKind.ancestors, 'main', 'X5'),
        subject: subject,
      );

      final grandparents = data.ancestors!.parents.first.parents;
      expect(grandparents.map((p) => p.person.xref), ['X2']);
    });
  });

  group('walking downwards', () {
    test('numbers children the way webtrees does', () async {
      final subject = await person('X1');
      final data = await charts().chart(
        ChartKind.descendants,
        localChartHandle(ChartKind.descendants, 'main', 'X1'),
        subject: subject,
      );

      final root = data.descendants!;
      expect(root.number, '1');
      expect(root.families, hasLength(1));

      final family = root.families.single;
      expect(family.spouse?.xref, 'X2');
      expect(family.children.map((c) => c.number), ['1.1']);
      expect(family.children.single.person.xref, 'X3');

      // And the generation below, which is what makes the numbering worth
      // asserting: it is built by concatenation, so a mistake compounds.
      final below = family.children.single.families.single;
      expect(below.children.map((c) => c.number), ['1.1.1', '1.1.2']);
    });

    test('stops where the reader asked it to', () async {
      final subject = await person('X1');
      final data = await charts().chart(
        ChartKind.descendants,
        localChartHandle(ChartKind.descendants, 'main', 'X1'),
        subject: subject,
        generations: 2,
      );

      expect(
        data.descendants!.families.single.children.single.families,
        isEmpty,
      );
    });
  });

  test('an hourglass is both walks stitched at the subject', () async {
    final subject = await person('X3');
    final data = await charts().chart(
      ChartKind.hourglass,
      localChartHandle(ChartKind.hourglass, 'main', 'X3'),
      subject: subject,
    );

    expect(data.ancestors!.person.xref, 'X3');
    expect(data.ancestors!.parents.map((p) => p.person.xref), ['X1', 'X2']);
    expect(data.descendants!.person.xref, 'X3');
    expect(
      data.descendants!.families.single.children.map((c) => c.person.xref),
      ['X5', 'X6'],
    );
  });

  group('what a store must not draw', () {
    test('a relationship goes to the site, always', () async {
      // `sync_eval.md` §5: the path is a walk this file could do; the *words*
      // on it come from a per-language kinship table that is one of the
      // largest things in webtrees, and porting it twice is not a trade worth
      // making.
      expect(
        () => charts().relationship('local:x', from: 'X5', to: 'X1'),
        throwsA(isA<NotAvailableOffline>()),
      );
    });

    test('statistics go to the site, always', () async {
      expect(
        () => charts().statistics('local:x'),
        throwsA(isA<NotAvailableOffline>()),
      );
    });

    test('a timeline goes to the site, and the reason is not laziness', () async {
      // Every position on a timeline is the *site's* measurement in the site's
      // own layout, and a stored fact carries its date as rendered text in six
      // possible calendars with no year behind it. A local scale would be a
      // different scale.
      expect(
        () => charts().timeline('local:x'),
        throwsA(isA<NotAvailableOffline>()),
      );
    });
  });

  test('a handle it did not mint is handed on unread', () async {
    // The rule `CapabilityChartsTransport` already keeps: a handle is only
    // meaningful to whoever made it.
    final subject = await person('X5');
    await expectLater(
      charts().chart(
        ChartKind.ancestors,
        '/tree/main/module/ancestors',
        subject: subject,
      ),
      throwsA(isA<NotAvailableOffline>()),
    );
  });

  test('a stored record opens the charts this device can draw', () async {
    final local = LocalRecordsTransport(store: store, online: _NoRecords());
    final record = await local.individual('main', 'X5');

    expect(isLocalChartHandle(record.charts[ChartKind.ancestors]!), isTrue);
    expect(isLocalChartHandle(record.charts[ChartKind.descendants]!), isTrue);
    // And the ones it cannot: still addressed to the module, so they work
    // exactly as before whenever there is a site to ask.
    expect(isLocalChartHandle(record.charts[ChartKind.relationship]!), isFalse);
    expect(isLocalChartHandle(record.charts[ChartKind.timeline]!), isFalse);
  });
}

/// Three generations, stated the way the sync endpoint states them: every
/// person naming every family they belong to, with all of its members.
final class _ThreeGenerations implements SyncSource {
  static const List<Map<String, Object?>> _people = [
    {
      'xref': 'X1',
      'name': 'Grandfather',
      'sex': 'male',
      'families': [_upper],
    },
    {
      'xref': 'X2',
      'name': 'Grandmother',
      'sex': 'female',
      'families': [_upper],
    },
    {
      'xref': 'X3',
      'name': 'Father',
      'sex': 'male',
      'families': [_upper, _lower],
    },
    {
      'xref': 'X4',
      'name': 'Mother',
      'sex': 'female',
      'families': [_lower],
    },
    {
      'xref': 'X5',
      'name': 'Subject',
      'sex': 'male',
      'families': [_lower],
    },
    {
      'xref': 'X6',
      'name': 'Sibling',
      'sex': 'female',
      'families': [_lower],
    },
  ];

  static const Map<String, Object?> _upper = {
    'xref': 'F1',
    'spouses': [
      {'xref': 'X1', 'name': 'Grandfather', 'sex': 'male'},
      {'xref': 'X2', 'name': 'Grandmother', 'sex': 'female'},
    ],
    'children': [
      {'xref': 'X3', 'name': 'Father', 'sex': 'male'},
    ],
  };

  static const Map<String, Object?> _lower = {
    'xref': 'F2',
    'spouses': [
      {'xref': 'X3', 'name': 'Father', 'sex': 'male'},
      {'xref': 'X4', 'name': 'Mother', 'sex': 'female'},
    ],
    'children': [
      {'xref': 'X5', 'name': 'Subject', 'sex': 'male'},
      {'xref': 'X6', 'name': 'Sibling', 'sex': 'female'},
    ],
  };

  @override
  Future<RecordsPage> records(
    String tree, {
    required int offset,
    required int limit,
    String? since,
  }) async => RecordsPage(
    token: 'w1',
    offset: offset,
    limit: limit,
    total: _people.length,
    hasMore: false,
    resync: false,
    sections: const ['facts'],
    // The CSS classes webtrees marks its own chart links with, which is what
    // the module states and what the store keeps.
    chartClasses: const [
      'menu-chart-ancestry',
      'menu-chart-descendants',
      'menu-chart-relationship',
      'menu-chart-timeline',
    ],
    people: _people,
    deleted: const [],
  );
}

/// Refuses everything, so a test can prove the store answered.
final class _NoSite implements ChartsTransport {
  const _NoSite();

  @override
  bool bloodLinesOnly(String handle) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const NotAvailableOffline('this');
}

final class _NoRecords implements RecordsTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const NotAvailableOffline('this');
}
