/// How a key is handed to SQLite.
///
/// One function, in a file of its own, and the reason is the lesson Phase 10b
/// wrote down: **the store must be openable by something with no Flutter
/// engine.** `tool/live_check.dart` fills a real store from a real server to
/// diff it against the other two transports, and it runs on the Dart VM.
///
/// [StoreKeys] cannot live here, because reading a key means the platform
/// keystore and that means Flutter. This does not — it is a string — so a tool
/// that has a key by some other route can still open an encrypted store.
library;

/// The key as SQLite's `PRAGMA key` wants it.
///
/// `x'…'` is a blob literal, which passes the 32 bytes through as *bytes*
/// rather than as a passphrase to be stretched. That is the point: the key is
/// already uniformly random, so a KDF over it would add cost and no entropy,
/// and a passphrase-shaped key would invite somebody to substitute a
/// human-chosen one later.
///
/// [key] is 64 hex characters, as [StoreKeys.obtain] mints them.
String storeKeyPragma(String key) => 'PRAGMA key = "x\'$key\'";';
