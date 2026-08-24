/// The store's life: when it opens, when it fills, and when it is destroyed.
///
/// Everything else in `data/local/` is a mechanism — a schema, a sync loop, a
/// transport. This is the policy, and it is separate for the reason
/// `sync_eval.md` §11 #1 names: two sources of truth turn every bug report
/// into *"is it stale or is it wrong?"*, and the only defence is one place
/// that can always say what the copy is, how old it is, and why it is or is
/// not being read from.
///
/// **Three rules it exists to keep.**
///
/// 1. **A store is one reader's view of one tree in one language, frozen.**
///    So it is opened under a key belonging to one connection, stamped, and
///    destroyed when the reader stops being that reader (`sync_eval.md` §6).
/// 2. **A partial copy is not a copy.** The composer may only read from a
///    store that finished filling; a half-filled one would answer "nobody" for
///    half a tree, which is worse than being offline.
/// 3. **Nobody's data plan is spent without being asked.** A first sync is
///    ~5 MB. On wifi it just happens; on a cellular network the reader is told
///    it is waiting, and can override.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../core/secret_store.dart';
import '../../domain/access.dart';
import '../credential_store.dart';
import '../transport.dart';
import 'local_records.dart';
import 'records_page.dart';
import 'store.dart';
import 'store_key.dart';
import 'store_open.dart';
import 'sync.dart';

/// Where the local copy has got to.
enum SyncPhase {
  /// No store, and no reason to make one yet — nobody is signed in, or this
  /// site has no module to sync from.
  unavailable,

  /// A copy could be made and the reader has not been asked yet.
  offered,

  /// Waiting for a network somebody is not paying by the megabyte.
  waitingForWifi,

  /// Filling, or catching up.
  syncing,

  /// Complete, and being read from.
  ready,

  /// The last attempt stopped early. Whatever arrived is kept — the sync is
  /// resumable and the next attempt continues rather than restarts.
  failed,
}

/// Opens, fills and destroys this device's copy of a tree.
class TreeStore extends ChangeNotifier {
  TreeStore(
    this._keys, {
    Connectivity? connectivity,
    @visibleForTesting Future<LocalStore> Function({required String key})? open,
    @visibleForTesting Future<void> Function()? destroy,
  }) : _connectivity = connectivity ?? Connectivity(),
       _open = open ?? openLocalStore,
       _destroyFile = destroy;

  final StoreKeys _keys;
  final Connectivity _connectivity;

  /// A store that can never hold anything.
  ///
  /// The state a device without a usable keystore is already in — see
  /// [StoreKeys.obtain] — named so it can be asked for directly. Widget tests
  /// that only need the app to build use it, and so does any screen that wants
  /// the type without the behaviour.
  factory TreeStore.none() => TreeStore(const StoreKeys(_NoSecrets()));

  final Future<LocalStore> Function({required String key}) _open;
  final Future<void> Function()? _destroyFile;

  static const String _log = 'webtrees.store';

  LocalStore? _store;
  StoreStamp? _stamp;
  SavedConnection? _connection;
  SyncPhase _phase = SyncPhase.unavailable;
  DateTime? _syncedAt;
  Object? _failure;
  int _people = 0;
  StreamSubscription<List<ConnectivityResult>>? _watchingNetwork;
  Future<void>? _running;
  SyncSource? _source;

  SyncPhase get phase => _phase;

  /// The store, or null while there is none open. Nothing outside this class
  /// should hold it across an await: sign-out closes it.
  LocalStore? get store => _store;

  /// When the copy was last written to. Every screen answered from the store
  /// owes the reader this (`sync_eval.md` §11 #1).
  DateTime? get syncedAt => _syncedAt;

  /// How many people the copy holds, for the sync screen.
  int get people => _people;

  /// Why the last attempt stopped, if it did.
  Object? get failure => _failure;

  /// Whether the composer may answer from the store right now.
  ///
  /// The whole of rule 2 above, in one place, because the alternative is every
  /// caller inventing its own answer.
  bool get isReadable => _store != null && _phase == SyncPhase.ready;

  /// A transport over the store, or null when there is nothing to read.
  LocalRecordsTransport? transportOver(RecordsTransportSource online) {
    final store = _store;
    if (store == null || !isReadable) return null;
    return LocalRecordsTransport(store: store, online: online());
  }

  /// Binds the store to whoever is signed in now.
  ///
  /// Called on sign-in and whenever the access summary is re-read. Doing both
  /// through one method is deliberate: a role change and a new account are the
  /// same event as far as the store is concerned — the copy belongs to
  /// somebody who no longer exists (`sync_eval.md` §6 #2).
  Future<void> bind({
    required SavedConnection connection,
    required TreeAccess tree,
    required String language,
    required String moduleVersion,
    required SyncSource source,
  }) async {
    final stamp = StoreStamp(
      tree: tree.name,
      username: connection.username,
      role: tree.role,
      language: language,
      moduleVersion: moduleVersion,
    );

    // The same reader, so the same file — but possibly a different *tree*
    // inside it, and one store holds several. Re-reading the state is what
    // stops a copy of tree A reporting itself readable while tree B is open,
    // which would answer every search in B with "nobody".
    if (_store != null && _stamp != null && _sameCopy(_stamp!, stamp)) {
      final movedTree = _stamp!.tree != stamp.tree;
      _stamp = stamp;
      _source = source;
      if (movedTree) await _readState();
      return;
    }

    await _close();

    final key = await _keys.obtain(connection.key);
    if (key == null) {
      // No keystore worth the name. `StoreKeys.obtain` explains why this is a
      // refusal rather than a fallback: an unencrypted store is exactly the
      // exposure §6 #3 is about, and a store keyed by a secret that will be
      // forgotten on restart is a file nothing can ever open again.
      developer.log(
        'No persistent keystore — this device will not keep a local copy.',
        name: _log,
        level: 900,
      );
      _set(SyncPhase.unavailable);
      return;
    }

    _connection = connection;
    _stamp = stamp;
    _source = source;
    _store = await _open(key: key);

    await _readState();
  }

  /// Opens whatever copy this device holds for [connection], with no network.
  ///
  /// The piece Phase 10c was missing, and the first offline test found it: the
  /// store was wired in *behind* a signed-in session, so an app with no signal
  /// could not reach it at all — every route in went through a sign-in that
  /// could not happen. Nothing about a copy actually needs the site, though.
  /// It is a file on this device, opened with a key from this device's
  /// keystore, and the row that says whose copy it is carries the account, the
  /// role, the language and the module version — the whole stamp. So the store
  /// can describe itself, and this is that.
  ///
  /// Returns the tree it opened, or null when there is nothing to open: no
  /// key, no file, no complete copy, or a copy belonging to somebody else.
  /// Null is the ordinary answer and means "ask them to sign in".
  Future<StoredTreeState?> bindOffline(SavedConnection connection) async {
    if (!await _keys.has(connection.key)) return null;

    final key = await _keys.obtain(connection.key);
    if (key == null) return null;

    await _close();
    final store = await _open(key: key);

    // Complete copies only, and only this account's. A half-filled one would
    // answer "nobody" for half a tree, and one belonging to another reader is
    // not ours to read — though in practice their key would not have opened
    // the file at all.
    final states = await store.select(store.storedTreeStates).get();
    final usable = states
        .where(
          (state) =>
              !state.filling &&
              state.token != null &&
              state.username == connection.username,
        )
        .toList();

    if (usable.isEmpty) {
      await store.close();
      _set(SyncPhase.unavailable);
      return null;
    }

    // Most recently synced, which with one tree is the only one and with
    // several is the one the reader was last looking at.
    usable.sort(
      (a, b) =>
          (b.syncedAt ?? DateTime(0)).compareTo(a.syncedAt ?? DateTime(0)),
    );
    final state = usable.first;

    _store = store;
    _connection = connection;
    _source = null;
    _stamp = StoreStamp(
      tree: state.tree,
      username: state.username,
      role: TreeRole.values.firstWhere(
        (candidate) => candidate.name == state.role,
        orElse: () => TreeRole.memberOrVisitor,
      ),
      language: state.language,
      moduleVersion: state.moduleVersion,
    );

    await _readState();
    return state;
  }

  /// The trees this device holds a complete copy of, for the account screen.
  Future<List<StoredTreeState>> storedTrees() async {
    final store = _store;
    if (store == null) return const [];
    return (store.select(
      store.storedTreeStates,
    )..where((row) => row.filling.equals(false))).get();
  }

  /// Points an already-open store at another tree it holds, with no network.
  Future<void> openStoredTree(String tree) async {
    final stamp = _stamp;
    if (_store == null || stamp == null || stamp.tree == tree) return;
    _stamp = StoreStamp(
      tree: tree,
      username: stamp.username,
      role: stamp.role,
      language: stamp.language,
      moduleVersion: stamp.moduleVersion,
    );
    await _readState();
  }

  /// Which tree the open copy is currently answering for.
  String? get tree => _stamp?.tree;

  /// Whether two stamps describe the same copy.
  ///
  /// The tree is not compared: one store holds several, and each carries its
  /// own row. Everything else is the reader's identity, and a change in any of
  /// it means the copy belongs to somebody else.
  static bool _sameCopy(StoreStamp a, StoreStamp b) =>
      a.username == b.username &&
      a.role == b.role &&
      a.language == b.language &&
      a.moduleVersion == b.moduleVersion;

  /// Decides whether to fill now, wait for wifi, or offer.
  ///
  /// The one place rule 3 lives. [force] is the reader pressing the button
  /// anyway, which always wins — the network check is advice, and advice that
  /// cannot be overruled is a lock.
  Future<void> catchUp({bool force = false}) async {
    if (_store == null || _stamp == null || _source == null) return;

    // Already filled once: a delta is a request and a handful of records, so
    // there is nothing to protect a data plan from.
    final incremental = _phase == SyncPhase.ready || _people > 0;

    if (!force && !incremental && !await _onCheapNetwork()) {
      _watchForWifi();
      _set(SyncPhase.waitingForWifi);
      return;
    }

    return _sync();
  }

  /// Runs one sync, and never two at once.
  Future<void> _sync() {
    final running = _running;
    if (running != null) return running;

    final started = _runSync();
    _running = started;
    return started.whenComplete(() => _running = null);
  }

  Future<void> _runSync() async {
    final store = _store;
    final stamp = _stamp;
    final source = _source;
    if (store == null || stamp == null || source == null) return;

    _failure = null;
    _set(SyncPhase.syncing);

    try {
      final report = await TreeSync(
        store: store,
        source: source,
        stamp: stamp,
      ).run();

      developer.log('Sync of ${stamp.tree}: $report', name: _log);
      await _readState();
      _set(report.complete ? SyncPhase.ready : SyncPhase.failed);
    } on Object catch (error, stack) {
      developer.log(
        'Sync of ${stamp.tree} stopped early',
        name: _log,
        level: 900,
        error: error,
        stackTrace: stack,
      );
      _failure = error;
      // Whatever arrived is kept: the cursor is saved per page, so the next
      // attempt resumes rather than restarts (`sync_eval.md` §11 #5).
      await _readState();
      _set(SyncPhase.failed);
    }
  }

  /// Reads back what the store now says about itself.
  Future<void> _readState() async {
    final store = _store;
    final stamp = _stamp;
    if (store == null || stamp == null) return;

    final state = await (store.select(
      store.storedTreeStates,
    )..where((row) => row.tree.equals(stamp.tree))).getSingleOrNull();

    _syncedAt = state?.syncedAt;
    _people =
        await (store.selectOnly(store.storedPeople)
              ..addColumns([store.storedPeople.xref.count()])
              ..where(store.storedPeople.tree.equals(stamp.tree)))
            .map((row) => row.read(store.storedPeople.xref.count()) ?? 0)
            .getSingle();

    // The same rule `LocalRecordsTransport.isComplete` keeps, asked of the
    // state directly: a store mid-walk holds part of a tree, which is fine to
    // add to and not fine to read as though it were the tree.
    if (state != null && !state.filling && state.token != null) {
      _set(SyncPhase.ready);
    } else if (_phase != SyncPhase.syncing) {
      _set(_people > 0 ? SyncPhase.failed : SyncPhase.offered);
    } else {
      // Mid-sync, so the phase is not ours to change — but the counts are
      // what a progress line reads, and they have just moved.
      notifyListeners();
    }
  }

  /// Wifi, ethernet, or anything else nobody meters by the megabyte.
  Future<bool> _onCheapNetwork() async {
    try {
      final networks = await _connectivity.checkConnectivity();
      return networks.any(_isCheap);
    } on Object catch (error) {
      // A platform that cannot say is not a platform to refuse on: the
      // reader's own site is already being talked to over *something*.
      developer.log('Cannot read the network type: $error', name: _log);
      return true;
    }
  }

  static bool _isCheap(ConnectivityResult network) => switch (network) {
    ConnectivityResult.wifi ||
    ConnectivityResult.ethernet ||
    ConnectivityResult.vpn => true,
    _ => false,
  };

  /// Starts the sync the moment an unmetered network appears.
  ///
  /// This is the promise in "it will download next time you are on wifi", and
  /// it is why the app watches rather than re-checking when a screen opens: a
  /// promise the reader has to come back and collect is not one.
  void _watchForWifi() {
    _watchingNetwork ??= _connectivity.onConnectivityChanged.listen((networks) {
      if (!networks.any(_isCheap)) return;
      _stopWatchingNetwork();
      unawaited(_sync());
    });
  }

  void _stopWatchingNetwork() {
    unawaited(_watchingNetwork?.cancel());
    _watchingNetwork = null;
  }

  /// Ends the session's copy, and destroys it.
  ///
  /// `sync_eval.md` §6 #2. Closing is not enough and neither is deleting the
  /// key: the first leaves the file, the second leaves ciphertext, and the
  /// section asks for the tree to be *gone* from the device.
  Future<void> destroy() async {
    final connection = _connection;
    await _close();

    if (connection != null) {
      final destroyFile = _destroyFile;
      if (destroyFile != null) {
        await destroyFile();
        await _keys.forget(connection.key);
      } else {
        await destroyLocalStore(_keys, connection.key);
      }
    }

    _connection = null;
    _syncedAt = null;
    _people = 0;
    _set(SyncPhase.unavailable);
  }

  Future<void> _close() async {
    _stopWatchingNetwork();
    final store = _store;
    _store = null;
    _stamp = null;
    _source = null;
    _syncedAt = null;
    _people = 0;
    await store?.close();
  }

  void _set(SyncPhase phase) {
    if (_phase == phase) return;
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopWatchingNetwork();
    unawaited(_store?.close());
    _store = null;
    super.dispose();
  }
}

/// Never persists anything, and says so — which is what makes
/// [TreeStore.none] inert rather than merely empty.
final class _NoSecrets implements SecretStore {
  const _NoSecrets();

  @override
  bool get isPersistent => false;

  @override
  Future<bool> contains(String key) async => false;

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(
    String key,
    String value, {
    bool deviceOnly = false,
  }) async {}

  @override
  Future<void> delete(String key) async {}
}

/// How the local transport reaches the things a store cannot hold — image
/// bytes and tree-level charts.
///
/// A function rather than a value because the client behind it is replaced
/// whenever the app reconnects, and a transport captured at bind time would go
/// on talking through a closed one.
typedef RecordsTransportSource = RecordsTransport Function();
