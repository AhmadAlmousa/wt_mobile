/// Where the store lives on a device, and what unlocks it.
///
/// The one file in `data/local/` that needs Flutter, kept apart for that
/// reason: `store.dart` is a schema and a schema should be openable by
/// anything, including a plain Dart tool with no engine
/// (`tool/live_check.dart` fills a real store to check the sync).
///
/// Phase 10c added the lock. `pubspec.yaml` selects the SQLite3MultipleCiphers
/// build of `package:sqlite3` through its build hooks, so every database this
/// process opens *can* be encrypted; this file is where one actually is.
library;

import 'dart:developer' as developer;
import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'store.dart';
import 'store_cipher.dart';
import 'store_key.dart';

const String _log = 'webtrees.store';

/// The name of the one store file. Singular on purpose: the device keeps one
/// reader's copy of one site at a time, and a second account signing in
/// replaces it rather than joining it (`sync_eval.md` §6 #1).
const String kStoreName = 'webtrees_tree';

/// Opens this device's copy of the tree, encrypted with [key].
///
/// `driftDatabase` puts the file where each platform keeps application
/// support data and opens it with `NativeDatabase.createInBackground`, so
/// every statement runs on its own isolate. That matters more here than in
/// most apps: a first sync writes 1,463 records, and the isolate is what keeps
/// that off the thread drawing the screen.
///
/// [key] is the hex string `StoreKeys.obtain` mints. A file the key cannot open
/// is **deleted** before drift ever sees it — see [_clearIfUnreadable].
Future<LocalStore> openLocalStore({required String key}) async {
  final file = await storeFile();
  await _clearIfUnreadable(file, key);

  final pragma = storeKeyPragma(key);

  return LocalStore(
    driftDatabase(
      name: kStoreName,
      native: DriftNativeOptions(
        // Runs on the isolate that actually opens the connection, before
        // drift issues a statement of its own. A closure over one String is
        // sendable, which is the constraint `DriftNativeOptions.setup`
        // documents.
        setup: (database) => database.execute(pragma),
      ),
    ),
  );
}

/// Where the file is, whether or not it exists.
///
/// Kept public because deleting the store is a lifecycle operation that
/// happens when nothing is open — on sign-out — and it needs the path without
/// opening anything.
Future<File> storeFile() async => File(
  p.join((await getApplicationDocumentsDirectory()).path, '$kStoreName.sqlite'),
);

/// Deletes the whole store, key included.
///
/// `sync_eval.md` §6 #2: a store makes yesterday's permissions durable, so the
/// answer is not to keep them. Both halves matter — a deleted key leaves
/// ciphertext nobody can read, which is close to destruction and is not it.
Future<void> destroyLocalStore(StoreKeys keys, String connection) async {
  await keys.forget(connection);

  final file = await storeFile();
  for (final path in [file.path, '${file.path}-wal', '${file.path}-shm']) {
    final companion = File(path);
    if (companion.existsSync()) {
      try {
        await companion.delete();
      } on FileSystemException catch (error) {
        developer.log('Could not delete $path: $error', name: _log, level: 900);
      }
    }
  }
}

/// Throws away a file this key cannot read.
///
/// Three ordinary ways to arrive here, none of them an error:
///
/// - **Another account signed in.** Their key is not this one, and the file is
///   theirs. This is the mechanism behind `sync_eval.md` §6 #1.
/// - **The keystore lost the key** — a reinstall, a restored backup, a cleared
///   keyring. The ciphertext is now permanently unreadable by anybody.
/// - **The file is truncated**, from a device that ran out of space mid-sync.
///
/// In all three the honest answer is the same: there is no copy here, and the
/// next sync will make one. Nothing is lost that the server does not still
/// have, which is the one property that makes deleting the right move rather
/// than a drastic one.
///
/// Probed here, on this isolate, rather than left to fail inside a query on
/// drift's: the failure would otherwise surface as `SqliteException(26): file
/// is not a database` at whatever screen happened to read first.
Future<void> _clearIfUnreadable(File file, String key) async {
  if (!file.existsSync()) return;

  Database? probe;
  try {
    probe = sqlite3.open(file.path);
    probe.execute(storeKeyPragma(key));
    // The cheapest statement that has to decrypt page 1. `PRAGMA key` itself
    // does not read anything, so it succeeds against a file it cannot open.
    probe.select('SELECT count(*) FROM sqlite_master;');
    return;
  } on Object catch (error) {
    developer.log(
      'The store on this device cannot be opened with this key '
      '($error) — discarding it. The next sync will rebuild it.',
      name: _log,
    );
  } finally {
    probe?.close();
  }

  for (final path in [file.path, '${file.path}-wal', '${file.path}-shm']) {
    final stale = File(path);
    if (stale.existsSync()) {
      try {
        await stale.delete();
      } on FileSystemException catch (error) {
        // Nothing useful is left to do: the open that follows will fail, and
        // it will say so with a better message than this could.
        developer.log('Could not delete $path: $error', name: _log, level: 900);
      }
    }
  }
}
