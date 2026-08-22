import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/secret_store.dart';
import 'core/unlock_gate.dart';
import 'data/credential_store.dart';
import 'data/session_manager.dart';

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

  runApp(
    WebtreesMobileApp(session: SessionManager(CredentialStore(secrets, gate))),
  );
}
