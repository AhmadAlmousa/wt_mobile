import 'dart:developer' as developer;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Somewhere to keep small secrets.
///
/// Abstracted so the data layer stays testable, and so the app can carry on
/// without a keystore when the platform has none.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
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
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

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
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<bool> contains(String key) async => _values.containsKey(key);
}
