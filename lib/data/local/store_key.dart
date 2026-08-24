/// The key the local store is encrypted with, and where it lives.
///
/// `sync_eval.md` §6 #3 is the reason this file exists, and it is worth
/// restating because it is the one risk in Phase 10 that could harm somebody:
/// until now the app held only what it had fetched, in RAM, and a lost phone
/// gave up nothing. A store holds the **whole visible tree**, durably. So the
/// file is encrypted, and the key is kept where the password already is.
///
/// **One key per connection**, where a connection is a site *and* an account
/// (`SavedConnection.key`). Two consequences, both wanted:
///
/// - Signing in as somebody else produces a key that cannot open the file that
///   is there, which is exactly `sync_eval.md` §6 #1 — *a user who signs in as
///   somebody else gets a new store, not a filtered one*. The stamp catches
///   the same thing one layer up; this catches it even if the stamp is wrong.
/// - Losing the key — a reinstalled app, a cleared keystore — is not a
///   failure to recover from but a resync, because every byte in the store
///   came from a server that still has it.
library;

import 'dart:math';

import 'package:meta/meta.dart';

import '../../core/secret_store.dart';
import 'store_cipher.dart';

/// Reads, mints and destroys the key for one device's store.
final class StoreKeys {
  const StoreKeys(this._secrets, {this.entropy});

  final SecretStore _secrets;

  /// Injectable so a test can be deterministic. Null means [Random.secure],
  /// which is the only acceptable source on a device — resolved per call
  /// rather than held, because a `Random` in a field would make the default
  /// shared state.
  @visibleForTesting
  final Random? entropy;

  /// Namespaced so it cannot collide with a stored password.
  static String _keyFor(String connection) => 'webtrees.store.key|$connection';

  /// 256 bits. Long enough that the key is never the weak part, short enough
  /// to be a keystore value rather than a file.
  static const int _bytes = 32;

  /// The key for [connection], minting one the first time it is asked for.
  ///
  /// Returns null when there is no keystore worth the name: a
  /// [SecretStore.isPersistent] of false means the fallback in-memory store,
  /// where a key would be forgotten on restart and the file left permanently
  /// unreadable. Refusing to write a store at all is the honest answer —
  /// better than a store that is encrypted with a secret nobody kept.
  Future<String?> obtain(String connection) async {
    if (!_secrets.isPersistent) return null;

    final name = _keyFor(connection);
    final existing = await _secrets.read(name);
    if (existing != null && existing.length == _bytes * 2) return existing;

    final minted = _mint();
    // Never off this device. A key that travels with a backup would let the
    // ciphertext be restored and read somewhere the reader never put it, which
    // would make the encryption ceremonial.
    await _secrets.write(name, minted, deviceOnly: true);
    return minted;
  }

  /// Whether a key already exists, without minting one.
  ///
  /// Asked before offering to sync: "there is already a store" and "there
  /// could be one" are different questions, and only the first should make
  /// the app go looking for a file.
  Future<bool> has(String connection) => _secrets.contains(_keyFor(connection));

  /// Destroys the key.
  ///
  /// Called with — never instead of — deleting the file. On its own this
  /// leaves ciphertext nothing can read, which is close to destruction but is
  /// not it, and `sync_eval.md` §6 #2 asks for the data to be gone rather than
  /// merely locked.
  Future<void> forget(String connection) =>
      _secrets.delete(_keyFor(connection));

  String _mint() {
    final random = entropy ?? Random.secure();
    return [
      for (var i = 0; i < _bytes; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  /// The key as SQLite's `PRAGMA key` wants it.
  ///
  /// Delegates to `store_cipher.dart`, which is deliberately Flutter-free: a
  /// plain Dart tool must be able to open an encrypted store, and this class
  /// cannot help it because reading a key means the platform keystore.
  static String pragmaFor(String key) => storeKeyPragma(key);
}
