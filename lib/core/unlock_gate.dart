import 'dart:developer' as developer;

import 'package:local_auth/local_auth.dart';

/// Guards access to a stored password.
abstract interface class UnlockGate {
  /// Asks the person to prove they are the device owner.
  ///
  /// [reason] is shown in the system prompt. Returns false if they cancel or
  /// fail; returns true when no gate is available, so an unsupported platform
  /// does not lock anyone out of their own account.
  Future<bool> unlock(String reason);

  /// Whether this gate actually challenges. False means [unlock] always
  /// succeeds, which the interface should disclose rather than imply
  /// protection that is not there.
  bool get isEnforcing;
}

/// Face ID, Touch ID, fingerprint or device PIN.
final class BiometricGate implements UnlockGate {
  const BiometricGate(this._auth);

  final LocalAuthentication _auth;

  /// Opens a gate if the device can challenge, otherwise an open one.
  ///
  /// `local_auth` has no Linux implementation, so desktop development always
  /// takes the open path.
  static Future<UnlockGate> open() async {
    final auth = LocalAuthentication();
    try {
      if (await auth.isDeviceSupported()) {
        return BiometricGate(auth);
      }
    } on Object catch (error) {
      developer.log(
        'Device authentication unavailable: $error',
        name: 'webtrees.auth',
      );
    }
    return const OpenGate();
  }

  @override
  bool get isEnforcing => true;

  @override
  Future<bool> unlock(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // Survive the app being backgrounded by the system prompt itself.
        persistAcrossBackgrounding: true,
      );
    } on Object catch (error) {
      developer.log(
        'Device authentication failed: $error',
        name: 'webtrees.auth',
        level: 900,
      );
      return false;
    }
  }
}

/// A gate that never challenges.
final class OpenGate implements UnlockGate {
  const OpenGate();

  @override
  bool get isEnforcing => false;

  @override
  Future<bool> unlock(String reason) async => true;
}
