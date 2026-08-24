import 'dart:developer' as developer;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Somewhere to keep small secrets.
///
/// Abstracted so the data layer stays testable, and so the app can carry on
/// without a keystore when the platform has none.
abstract interface class SecretStore {
  Future<String?> read(String key);

  /// Stores [value] under [key].
  ///
  /// [deviceOnly] asks the platform to keep the secret off backups and out of
  /// a transfer to a new phone. It exists for one secret: the key to the local
  /// store (`data/local/store_key.dart`). Encrypting the tree on disk buys
  /// nothing if the key rides the same iCloud backup as the ciphertext, and a
  /// key restored onto a *different* device is worse than useless — it would
  /// open a copy of somebody's family on hardware they never put it on.
  ///
  /// The password is deliberately **not** device-only: restoring a phone and
  /// finding the app still signed in is the behaviour a reader expects, and a
  /// password is a secret they can retype. A tree is not.
  Future<void> write(String key, String value, {bool deviceOnly = false});

  Future<void> delete(String key);

  /// Whether a value is stored, without retrieving it.
  ///
  /// Callers that gate access behind device authentication need to know
  /// whether there is anything worth asking about before they ask, and must
  /// not pull the secret into memory to find out.
  Future<bool> contains(String key);

  /// Whether values survive restarting the app.
  ///
  /// False for the in-memory fallback, which lets the interface tell the user
  /// the truth instead of silently forgetting their password.
  bool get isPersistent;
}

/// The platform keystore: Keychain on iOS, EncryptedSharedPreferences on
/// Android, libsecret on Linux.
final class PlatformSecretStore implements SecretStore {
  const PlatformSecretStore(this._storage);

  final FlutterSecureStorage _storage;

  /// Opens the platform keystore, falling back to memory if it is unusable.
  ///
  /// Linux needs libsecret and a running keyring; a headless development
  /// machine often has neither, and that should degrade rather than crash.
  static Future<SecretStore> open() async {
    // Defaults are already the encrypted ones on every platform: Keychain on
    // Apple systems, KeyStore-backed AES/GCM on Android, libsecret on Linux.
    const storage = FlutterSecureStorage();
    try {
      // A round trip, not just a read: a keyring can be readable and still
      // refuse to store anything, and the app would then promise to remember
      // a password it silently drops.
      await storage.write(key: _probeKey, value: 'ok');
      final echoed = await storage.read(key: _probeKey);
      await storage.delete(key: _probeKey);
      if (echoed != 'ok') throw StateError('keystore did not retain a value');
      return const PlatformSecretStore(storage);
    } on Object catch (error) {
      developer.log(
        'No usable keystore; passwords will not be remembered: $error',
        name: 'webtrees.secrets',
        level: 900,
      );
      return MemorySecretStore();
    }
  }

  static const String _probeKey = 'webtrees.probe';

  @override
  bool get isPersistent => true;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value, {bool deviceOnly = false}) =>
      _storage.write(
        key: key,
        value: value,
        iOptions: deviceOnly
            // Keychain items with the default accessibility travel in an
            // encrypted iCloud backup and can be restored onto another
            // device. `ThisDevice` is what stops that.
            ? const IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              )
            : IOSOptions.defaultOptions,
      );

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<bool> contains(String key) => _storage.containsKey(key: key);
}

/// A store that forgets everything when the process ends.
///
/// Used in tests, and as the fallback when no platform keystore is available.
final class MemorySecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  bool get isPersistent => false;

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

  @override
  Future<bool> contains(String key) async => _values.containsKey(key);
}
