import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/secret_store.dart';
import 'package:webtrees_mobile/core/webtrees_url.dart';
import 'package:webtrees_mobile/data/credential_store.dart';
import 'package:webtrees_mobile/data/local/records_page.dart';
import 'package:webtrees_mobile/data/local/store.dart';
import 'package:webtrees_mobile/data/local/store_key.dart';
import 'package:webtrees_mobile/data/local/tree_store.dart';
import 'package:webtrees_mobile/domain/access.dart';

/// When a copy is made, and when it is destroyed.
///
/// The policy half of Phase 10, and the half a reader actually meets. Two
/// rules are worth more than the rest:
///
/// - **Nobody's data plan is spent without being asked.** A first sync is
///   about 5 MB. On wifi it happens in the background on first use; on a
///   cellular network the app waits, says so, and starts the moment an
///   unmetered network appears — which is what makes *"it will download next
///   time you are on Wi-Fi"* a promise rather than a note the reader has to
///   come back and collect.
/// - **Signing out takes the tree with it.** `sync_eval.md` §6 #2: a store
///   makes yesterday's permissions durable, so the answer is not to keep them.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  final connection = SavedConnection(
    base: Uri.parse('https://tree.example.com'),
    style: UrlStyle.pretty,
    username: 'mobile',
  );

  const tree = TreeAccess(name: 'main', role: TreeRole.member);

  LocalStore? opened;

  TreeStore build({
    required List<ConnectivityResult> network,
    SecretStore? secrets,
    void Function()? onDestroy,
  }) {
    opened = null;
    return TreeStore(
      StoreKeys(secrets ?? _Keyring()),
      connectivity: _FakeConnectivity(network),
      open: ({required String key}) async =>
          opened = LocalStore.forTesting(NativeDatabase.memory()),
      destroy: () async => onDestroy?.call(),
    );
  }

  Future<void> bind(TreeStore store, SyncSource source) => store.bind(
    connection: connection,
    tree: tree,
    language: 'ar',
    moduleVersion: '1.3.0',
    source: source,
  );

  tearDown(() async => opened?.close());

  group('on a cellular network', () {
    test('a first copy waits, rather than spending the plan', () async {
      final source = _OnePage();
      final store = build(network: [ConnectivityResult.mobile]);

      await bind(store, source);
      await store.catchUp();

      expect(store.phase, SyncPhase.waitingForWifi);
      expect(source.requests, 0, reason: 'nothing should have been fetched');
      store.dispose();
    });

    test('the reader can overrule it, because advice that cannot be '
        'overruled is a lock', () async {
      final source = _OnePage();
      final store = build(network: [ConnectivityResult.mobile]);

      await bind(store, source);
      await store.catchUp();
      await store.catchUp(force: true);

      expect(store.phase, SyncPhase.ready);
      expect(source.requests, 1);
      store.dispose();
    });

    test('it starts on its own when wifi arrives', () async {
      final source = _OnePage();
      final network = _FakeConnectivity([ConnectivityResult.mobile]);
      final store = TreeStore(
        StoreKeys(_Keyring()),
        connectivity: network,
        open: ({required String key}) async =>
            opened = LocalStore.forTesting(NativeDatabase.memory()),
      );

      await bind(store, source);
      await store.catchUp();
      expect(store.phase, SyncPhase.waitingForWifi);

      // The promise being kept, which is the whole reason the store watches
      // the network rather than re-checking when a screen happens to open.
      network.becomes([ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(source.requests, 1);
      expect(store.phase, SyncPhase.ready);
      store.dispose();
    });

    test('a delta is not worth waiting for', () async {
      // The protection is for the *first* copy, which is megabytes. A catch-up
      // is one request and a handful of records, and making a reader wait for
      // wifi to see yesterday's edits would be protecting them from nothing.
      final source = _OnePage();
      final network = _FakeConnectivity([ConnectivityResult.wifi]);
      final store = TreeStore(
        StoreKeys(_Keyring()),
        connectivity: network,
        open: ({required String key}) async =>
            opened = LocalStore.forTesting(NativeDatabase.memory()),
      );

      await bind(store, source);
      await store.catchUp();
      expect(store.phase, SyncPhase.ready);

      // The reader walks out of the house. The copy is already there, so the
      // next catch-up should just run.
      network.becomes([ConnectivityResult.mobile]);
      await store.catchUp();

      expect(store.phase, SyncPhase.ready);
      expect(source.requests, 2, reason: 'the delta should have been fetched');
      store.dispose();
    });
  });

  group('on wifi', () {
    test('the copy is made without asking', () async {
      final source = _OnePage();
      final store = build(network: [ConnectivityResult.wifi]);

      await bind(store, source);
      await store.catchUp();

      expect(store.phase, SyncPhase.ready);
      expect(store.people, 2);
      expect(store.syncedAt, isNotNull);
      expect(store.isReadable, isTrue);
      store.dispose();
    });

    test('a half-filled copy is not readable', () async {
      // A store mid-walk holds part of a tree, which is fine to add to and not
      // fine to read as though it were the tree: a search would quietly answer
      // "nobody" for half of it.
      final source = _Failing();
      final store = build(network: [ConnectivityResult.wifi]);

      await bind(store, source);
      await store.catchUp();

      expect(store.phase, SyncPhase.failed);
      expect(store.isReadable, isFalse);
      expect(store.transportOver(() => throw StateError('unused')), isNull);
      store.dispose();
    });
  });

  group('the store as a whole', () {
    test('is refused outright where no key could be kept', () async {
      // A device with no keystore. An unencrypted copy of somebody's whole
      // family is the exposure `sync_eval.md` §6 #3 is about, and a key that
      // will be forgotten on restart leaves a file nothing can ever open.
      final store = build(
        network: [ConnectivityResult.wifi],
        secrets: MemorySecretStore(),
      );

      await bind(store, _OnePage());

      expect(store.phase, SyncPhase.unavailable);
      expect(store.store, isNull);
      store.dispose();
    });

    test('is destroyed on sign-out, file and key together', () async {
      var destroyed = false;
      final secrets = _Keyring();
      final store = build(
        network: [ConnectivityResult.wifi],
        secrets: secrets,
        onDestroy: () => destroyed = true,
      );

      await bind(store, _OnePage());
      await store.catchUp();
      expect(store.isReadable, isTrue);

      await store.destroy();

      expect(destroyed, isTrue, reason: 'the file must go');
      expect(
        await secrets.contains('webtrees.store.key|${connection.key}'),
        isFalse,
        reason: 'the key must go too — ciphertext is not destruction',
      );
      expect(store.phase, SyncPhase.unavailable);
      expect(store.isReadable, isFalse);
      store.dispose();
    });

    test('is replaced, not filtered, when the reader changes', () async {
      final store = build(network: [ConnectivityResult.wifi]);
      await bind(store, _OnePage());
      await store.catchUp();
      final first = store.store;

      // A demotion. The copy was filled for a member and this reader is not
      // one any more, so it is a different store — `sync_eval.md` §6 #1.
      await store.bind(
        connection: connection,
        tree: const TreeAccess(name: 'main', role: TreeRole.memberOrVisitor),
        language: 'ar',
        moduleVersion: '1.3.0',
        source: _OnePage(),
      );

      expect(store.store, isNot(same(first)));
      store.dispose();
    });

    test('does not report another tree\'s copy as this one\'s', () async {
      // One file holds several trees, so the same reader opening a second tree
      // keeps the same store — but the *phase* describes a tree, and a copy of
      // `main` reporting itself readable while `other` is open would answer
      // every search in `other` with "nobody".
      final store = build(network: [ConnectivityResult.wifi]);
      await bind(store, _OnePage());
      await store.catchUp();
      expect(store.isReadable, isTrue);
      expect(store.people, 2);

      await store.bind(
        connection: connection,
        tree: const TreeAccess(name: 'other', role: TreeRole.member),
        language: 'ar',
        moduleVersion: '1.3.0',
        source: _OnePage(),
      );

      expect(store.isReadable, isFalse, reason: 'no copy of `other` yet');
      expect(store.people, 0);
      store.dispose();
    });

    test('is kept when nothing about the reader changed', () async {
      final store = build(network: [ConnectivityResult.wifi]);
      await bind(store, _OnePage());
      await store.catchUp();
      final first = store.store;

      await bind(store, _OnePage());

      expect(store.store, same(first), reason: 'rebinding must not rebuild');
      store.dispose();
    });
  });

  test('a store that can never hold anything says so', () async {
    final store = TreeStore.none();
    await bind(store, _OnePage());

    expect(store.phase, SyncPhase.unavailable);
    expect(store.isReadable, isFalse);
    store.dispose();
  });
}

/// One page with two people in it, and a count of how often it was asked for.
final class _OnePage implements SyncSource {
  int requests = 0;

  @override
  Future<RecordsPage> records(
    String tree, {
    required int offset,
    required int limit,
    String? since,
  }) async {
    requests++;
    return RecordsPage(
      token: 'w1',
      offset: offset,
      limit: limit,
      total: 2,
      hasMore: false,
      resync: false,
      sections: const ['facts'],
      chartClasses: const [],
      people: [
        for (final xref in ['I1', 'I2'])
          {
            'xref': xref,
            'name': 'Person $xref',
            'sex': 'M',
            'isDeceased': true,
            'families': const [],
          },
      ],
      deleted: const [],
    );
  }
}

/// A server that stops halfway, which is what eight chances to fail look like.
final class _Failing implements SyncSource {
  @override
  Future<RecordsPage> records(
    String tree, {
    required int offset,
    required int limit,
    String? since,
  }) async => throw const _Dropped();
}

final class _Dropped implements Exception {
  const _Dropped();
}

/// A network the test decides.
final class _FakeConnectivity implements Connectivity {
  _FakeConnectivity(this._now);

  List<ConnectivityResult> _now;
  final _changes =
      // Broadcast, like the real one: nothing replays to a late listener.
      Stream<List<ConnectivityResult>>.multi((controller) {
        _controllers.add(controller);
        controller.onCancel = () => _controllers.remove(controller);
      }).asBroadcastStream();

  static final _controllers =
      <MultiStreamController<List<ConnectivityResult>>>[];

  void becomes(List<ConnectivityResult> networks) {
    _now = networks;
    for (final controller in [..._controllers]) {
      controller.add(networks);
    }
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _now;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes;
}

/// A keystore that keeps what it is given, like a real one.
final class _Keyring implements SecretStore {
  final Map<String, String> _values = {};

  @override
  bool get isPersistent => true;

  @override
  Future<bool> contains(String key) async => _values.containsKey(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(
    String key,
    String value, {
    bool deviceOnly = false,
  }) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
