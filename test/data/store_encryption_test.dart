import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:webtrees_mobile/core/secret_store.dart';
import 'package:webtrees_mobile/data/local/store.dart';
import 'package:webtrees_mobile/data/local/store_key.dart';

/// The lock on the store, and the key to it.
///
/// This file exists because of one paragraph. `sync_eval.md` §6 #3 calls
/// putting the tree on a device *"a real change in exposure"* — until Phase 10
/// the app held only what it had fetched, in RAM, and a lost or backed-up
/// phone gave up nothing — and it says encryption at rest is *"a decision to
/// take before the first byte is written, not after"*. That decision gated the
/// whole of Phase 10c (`PROJECT.md` §9 #29).
///
/// So these tests are not about SQLite working. They are the evidence that the
/// gate is shut, and they assert the three things a reader would actually want
/// checked: that a name in the tree is **not on the disk in the clear**, that
/// the file **cannot be opened without the key**, and that a device which has
/// somehow ended up with a file it cannot read **throws it away** rather than
/// failing at whatever screen reads first.
///
/// Everything runs against a real encrypted file, because a mock of a cipher
/// proves nothing at all.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late Directory scratch;

  setUp(() => scratch = Directory.systemTemp.createTempSync('webtrees_store'));
  tearDown(() => scratch.deleteSync(recursive: true));

  File fileIn(Directory directory) => File('${directory.path}/tree.sqlite');

  /// Opens a store over [file] under [key], exactly as `store_open.dart` does:
  /// a `PRAGMA key` in drift's `setup`, before any other statement.
  LocalStore openWith(File file, String key) => LocalStore(
    NativeDatabase(
      file,
      setup: (database) => database.execute(StoreKeys.pragmaFor(key)),
    ),
  );

  Future<void> writeAPerson(LocalStore store, String name) => store
      .into(store.storedPeople)
      .insert(
        StoredPeopleCompanion.insert(
          tree: 'main',
          xref: 'I1',
          name: name,
          nameFold: name.toLowerCase(),
          sortName: name,
          sex: 'male',
          deceased: true,
          private: false,
          payload: '{"xref":"I1","name":"$name"}',
        ),
      );

  const key =
      '00112233445566778899aabbccddeeff'
      '00112233445566778899aabbccddeeff';

  group('a store on disk', () {
    test('does not carry a name in the clear', () async {
      final file = fileIn(scratch);
      final store = openWith(file, key);
      // A name nothing else would produce, so finding it in the bytes can only
      // mean the row itself was written unencrypted.
      await writeAPerson(store, 'Zaqxswcdevfrbgt');
      await store.close();

      final bytes = file.readAsBytesSync();
      expect(bytes, isNotEmpty);
      expect(
        String.fromCharCodes(bytes).contains('Zaqxswcdevfrbgt'),
        isFalse,
        reason: 'the row is on the disk in plain text',
      );
      // An unencrypted SQLite file starts with this, and the header is the
      // first thing anybody looking at a stolen phone would check.
      expect(String.fromCharCodes(bytes.take(15)), isNot('SQLite format 3'));
    });

    test('cannot be opened with no key at all', () async {
      final file = fileIn(scratch);
      final store = openWith(file, key);
      await writeAPerson(store, 'Someone');
      await store.close();

      final plain = sqlite3.open(file.path);
      addTearDown(plain.close);
      expect(
        () => plain.select('SELECT * FROM stored_people;'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('cannot be opened with the wrong key', () async {
      final file = fileIn(scratch);
      final store = openWith(file, key);
      await writeAPerson(store, 'Someone');
      await store.close();

      final wrong = sqlite3.open(file.path);
      addTearDown(wrong.close);
      wrong.execute(StoreKeys.pragmaFor('ff' * 32));
      expect(
        () => wrong.select('SELECT * FROM stored_people;'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('reads back under the key that wrote it', () async {
      final file = fileIn(scratch);
      final first = openWith(file, key);
      await writeAPerson(first, 'عبد الله الموسى');
      await first.close();

      // A second open of the same file, as a later launch of the app would.
      final again = openWith(file, key);
      addTearDown(again.close);

      final rows = await again.select(again.storedPeople).get();
      expect(rows.single.name, 'عبد الله الموسى');
    });
  });

  group('a file this device cannot read', () {
    // The recovery `store_open.dart` performs before drift ever sees the file.
    // Asserted through the same two statements it uses, because the property
    // being checked is that the failure is *detectable up front* rather than
    // at whatever screen happens to read first.
    test('fails on the first statement, not on the open', () async {
      final file = fileIn(scratch);
      final store = openWith(file, key);
      await writeAPerson(store, 'Someone');
      await store.close();

      final probe = sqlite3.open(file.path);
      addTearDown(probe.close);

      // `PRAGMA key` reads nothing, so it succeeds against a file it cannot
      // open — which is exactly why the probe has to run a real statement.
      probe.execute(StoreKeys.pragmaFor('ab' * 32));
      expect(
        () => probe.select('SELECT count(*) FROM sqlite_master;'),
        throwsA(isA<SqliteException>()),
        reason: 'the probe would not detect an unreadable file',
      );
    });
  });

  group('the key', () {
    test('is minted once and then returned', () async {
      final keys = StoreKeys(_Keyring());

      final first = await keys.obtain('https://tree.example.com|mobile');
      final second = await keys.obtain('https://tree.example.com|mobile');

      expect(first, isNotNull);
      expect(first, hasLength(64));
      expect(second, first);
    });

    test('differs per connection, which is what replaces one reader\'s copy '
        'with another\'s', () async {
      final keys = StoreKeys(_Keyring());

      final mine = await keys.obtain('https://tree.example.com|mobile');
      final theirs = await keys.obtain('https://tree.example.com|someone');

      expect(mine, isNot(theirs));
    });

    test('is refused where it could not be kept', () async {
      // The in-memory fallback: a device with no keystore. A key minted here
      // is forgotten on restart, which would leave the file permanently
      // unreadable — so the honest answer is to write no store at all.
      final keys = StoreKeys(_Forgetful());
      expect(await keys.obtain('https://tree.example.com|mobile'), isNull);
    });

    test('is destroyed when asked', () async {
      final keys = StoreKeys(_Keyring());
      const connection = 'https://tree.example.com|mobile';

      await keys.obtain(connection);
      expect(await keys.has(connection), isTrue);

      await keys.forget(connection);
      expect(await keys.has(connection), isFalse);
    });

    test('is 256 bits of the entropy it was given', () async {
      // Deterministic only because the source is injected; on a device it is
      // `Random.secure`, which is the whole point of the seam.
      final keys = StoreKeys(_Keyring(), entropy: Random(7));
      final key = await keys.obtain('a|b');

      expect(key, hasLength(64));
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('is passed to SQLite as bytes, not as a passphrase', () {
      // `x'…'` is a blob literal. A bare string would be stretched by a KDF,
      // which would add cost and no entropy over an already-random key.
      expect(StoreKeys.pragmaFor('ab' * 32), contains("x'"));
      expect(StoreKeys.pragmaFor('ab' * 32), startsWith('PRAGMA key ='));
    });
  });

  test('a store keyed by one connection is unreadable by another', () async {
    final keys = StoreKeys(_Keyring());
    final file = fileIn(scratch);

    final mine = (await keys.obtain('https://tree.example.com|mobile'))!;
    final store = openWith(file, mine);
    await writeAPerson(store, 'Someone');
    await store.close();

    // The mechanism behind `sync_eval.md` §6 #1 — *a user who signs in as
    // somebody else gets a new store, not a filtered one*. The stamp catches
    // the same thing one layer up; this catches it even if the stamp is wrong.
    final theirs = (await keys.obtain('https://tree.example.com|someone'))!;
    final other = sqlite3.open(file.path);
    addTearDown(other.close);
    other.execute(StoreKeys.pragmaFor(theirs));

    expect(
      () => other.select('SELECT * FROM stored_people;'),
      throwsA(isA<SqliteException>()),
    );
  });
}

/// A keystore that keeps what it is given, like a real one.
///
/// `MemorySecretStore` will not do: it reports [SecretStore.isPersistent] as
/// false, which is exactly the condition [StoreKeys.obtain] refuses on.
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

/// A keystore that accepts writes and keeps nothing — the shape of a platform
/// with no usable keyring.
final class _Forgetful implements SecretStore {
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
