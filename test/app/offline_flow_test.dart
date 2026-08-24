import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/app/app.dart';
import 'package:webtrees_mobile/core/unlock_gate.dart';
import 'package:webtrees_mobile/core/webtrees_client.dart';
import 'package:webtrees_mobile/core/webtrees_url.dart';
import 'package:webtrees_mobile/data/credential_store.dart';
import 'package:webtrees_mobile/data/local/records_page.dart';
import 'package:webtrees_mobile/data/local/store.dart';
import 'package:webtrees_mobile/data/local/store_key.dart';
import 'package:webtrees_mobile/data/local/sync.dart';
import 'package:webtrees_mobile/data/local/tree_store.dart';
import 'package:webtrees_mobile/data/session_manager.dart';
import 'package:webtrees_mobile/domain/access.dart';

import '../support/fake_webtrees.dart';
import '../support/test_app.dart';

/// Starting with no network at all.
///
/// The gap the first real test of 0.21.0 found, reported in one sentence:
/// *"I shut off wifi and data and it said login failed."* Which it did, and
/// the reasoning was wrong rather than the code — the store was wired in
/// behind a signed-in session, so every route into the app went through a
/// sign-in that could not happen. A copy of the tree sat on the device,
/// encrypted, complete, and unreachable.
///
/// What these tests pin down is the distinction that was missing: **"we do not
/// know who you are" and "the train went into a tunnel" are different
/// answers.** Only the first is a reason to show a sign-in form.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late LocalStore store;
  late FakeKeystore keystore;

  const connection = 'https://tree.example.com|mobile';

  final saved = SavedConnection(
    base: Uri.parse('https://tree.example.com'),
    style: UrlStyle.pretty,
    username: 'mobile',
  );

  setUp(() async {
    store = LocalStore.forTesting(NativeDatabase.memory());
    keystore = FakeKeystore();
  });

  tearDown(() => store.close());

  /// A store with two people in it, filled as a real sync would fill it.
  Future<void> fillStore() async {
    await StoreKeys(keystore).obtain(connection);
    await TreeSync(
      store: store,
      source: _TwoPeople(),
      stamp: const StoreStamp(
        tree: 'main',
        username: 'mobile',
        role: TreeRole.member,
        language: 'en',
        moduleVersion: '1.3.0',
      ),
    ).run();
  }

  TreeStore treeStoreOver(LocalStore opened) => TreeStore(
    StoreKeys(keystore),
    open: ({required String key}) async => opened,
  );

  /// The app, wired to a network that is simply not there.
  Future<SessionManager> unreachableSession() async {
    final credentials = CredentialStore(keystore, const OpenGate());
    await credentials.remember(saved, password: 'secret');

    return SessionManager(
      credentials,
      clientFactory: (url, cookies) =>
          WebtreesClient(url: url, cookies: cookies, dio: _offlineDio()),
      keepAliveInterval: Duration.zero,
    );
  }

  testWidgets('opens this device\'s copy instead of failing to sign in', (
    tester,
  ) async {
    await fillStore();
    final session = await unreachableSession();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      WebtreesMobileApp(
        session: session,
        settings: testSettings(),
        treeStore: treeStoreOver(store),
      ),
    );
    await tester.pumpAndSettle();

    // The reported failure, asserted as absent.
    expect(find.textContaining('Sign in'), findsNothing);
    expect(find.textContaining('Could not reach'), findsNothing);

    // And what should be there instead: the tree, and a plain statement of
    // where the answers are coming from.
    expect(session.isOffline, isTrue);
    expect(find.textContaining('reading this device'), findsOne);
  });

  testWidgets('searches the copy with no site to ask', (tester) async {
    await fillStore();
    final session = await unreachableSession();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      WebtreesMobileApp(
        session: session,
        settings: testSettings(),
        treeStore: treeStoreOver(store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Musa');
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Abdullah Musa'), findsOne);
    expect(find.text('Khalid Musa'), findsOne);
  });

  testWidgets('still asks for a sign-in when there is no copy', (tester) async {
    // Nothing was ever synced, so there is genuinely nothing to show. The old
    // behaviour is the right behaviour here.
    final session = await unreachableSession();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      WebtreesMobileApp(
        session: session,
        settings: testSettings(),
        treeStore: treeStoreOver(store),
      ),
    );
    await tester.pumpAndSettle();

    expect(session.isOffline, isFalse);
    expect(find.byType(TextFormField), findsWidgets);
  });

  testWidgets('offers the copy to a reader who never saved a password', (
    tester,
  ) async {
    // The other half of the same complaint. Without a stored password there is
    // nothing to resume, so the launch screen hands over to the sign-in form —
    // and the reader is looking at a form they cannot possibly submit while a
    // complete copy of the tree sits on the device. Submitting it once, and
    // failing to reach the site, is enough to say so.
    await fillStore();

    final credentials = CredentialStore(keystore, const OpenGate());
    await credentials.remember(saved);

    final session = SessionManager(
      credentials,
      clientFactory: (url, cookies) =>
          WebtreesClient(url: url, cookies: cookies, dio: _offlineDio()),
      keepAliveInterval: Duration.zero,
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      WebtreesMobileApp(
        session: session,
        settings: testSettings(),
        treeStore: treeStoreOver(store),
      ),
    );
    await tester.pumpAndSettle();

    // The connect screen, as expected: with no password there is nothing to
    // resume, and with no reachable site there is no version to have read, so
    // the app cannot even claim to be connected.
    expect(session.isOffline, isFalse);
    await tester.enterText(
      find.byType(TextFormField).first,
      'tree.example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();

    expect(session.isOffline, isTrue);
    expect(find.textContaining('reading this device'), findsOne);
  });

  testWidgets('a rejected password is not treated as a tunnel', (tester) async {
    // The other half of the distinction. A site that answers and says no is
    // not an offline situation, even with a copy on the device: the reader's
    // access may have been revoked, and `sync_eval.md` §6 #2 is emphatic that
    // a stale copy is stale in the *permissive* direction.
    await fillStore();

    final credentials = CredentialStore(keystore, const OpenGate());
    await credentials.remember(saved, password: 'secret');

    // A site that answers and refuses. Not a tunnel.
    final server = FakeWebtrees(workingSite(password: 'something-else'));
    final session = SessionManager(
      credentials,
      clientFactory: clientFactoryFor(server),
      keepAliveInterval: Duration.zero,
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      WebtreesMobileApp(
        session: session,
        settings: testSettings(),
        treeStore: treeStoreOver(store),
      ),
    );
    await tester.pumpAndSettle();

    expect(session.isOffline, isFalse);
  });
}

Dio _offlineDio() => Dio()..httpClientAdapter = _NoNetwork();

/// An adapter for a device with no connection at all.
final class _NoNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => throw DioException(
    requestOptions: options,
    type: DioExceptionType.connectionError,
    error: 'Network is unreachable',
  );

  @override
  void close({bool force = false}) {}
}

/// One page, two people, shaped as the sync endpoint states them.
final class _TwoPeople implements SyncSource {
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
    total: 2,
    hasMore: false,
    resync: false,
    sections: const ['facts'],
    chartClasses: const [],
    people: const [
      {
        'xref': 'X42',
        'name': 'Abdullah Musa',
        'sex': 'male',
        'isDeceased': true,
        'families': [],
      },
      {
        'xref': 'X60',
        'name': 'Khalid Musa',
        'sex': 'male',
        'isDeceased': true,
        'families': [],
      },
    ],
    deleted: const [],
  );
}
