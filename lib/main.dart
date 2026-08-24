import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/secret_store.dart';
import 'core/unlock_gate.dart';
import 'data/credential_store.dart';
import 'data/local/store_key.dart';
import 'data/local/tree_store.dart';
import 'data/session_manager.dart';
import 'data/settings_store.dart';

/// Composition root.
///
/// Dependencies are built here and passed down by constructor, so nothing in
/// the app reaches for a global.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Both of these degrade rather than fail: a device without a keystore or
  // without biometrics still gets a working app, and says what it cannot do.
  final secrets = await PlatformSecretStore.open();
  final gate = await BiometricGate.open();

  // Read before the first frame: the sign-in screen has to be drawn in the
  // right language and reading direction, not corrected a moment later.
  final settings = SettingsStore();
  await settings.load();

  runApp(
    WebtreesMobileApp(
      session: SessionManager(
        CredentialStore(secrets, gate),
        // webtrees renders every date, month name and fact label in the
        // language held in its own session — so the app has to ask for the
        // one it is reading in, or an Arabic screen fills with English dates.
        // Read on each sign-in rather than captured, because the reader can
        // change it at any time.
        contentLanguage: () => SettingsStore.webtreesLanguageTag(
          settings.resolve(PlatformDispatcher.instance.locale),
        ),
      ),
      settings: settings,
      // The tree, on the device. Nothing is written until a reader opens a
      // tree on a site that runs the sync wire, and nothing is written at all
      // without a keystore to hold the key — `StoreKeys.obtain` refuses rather
      // than falling back, because an unencrypted copy of somebody's whole
      // family is exactly the exposure `sync_eval.md` §6 #3 is about.
      treeStore: TreeStore(StoreKeys(secrets)),
    ),
  );
}
