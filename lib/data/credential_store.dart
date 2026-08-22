import 'dart:convert';

import 'package:meta/meta.dart';

import '../core/secret_store.dart';
import '../core/unlock_gate.dart';
import '../core/webtrees_url.dart';

/// A webtrees site the app has signed in to before.
@immutable
final class SavedConnection {
  const SavedConnection({
    required this.base,
    required this.style,
    required this.username,
    this.displayName,
    this.version,
  });

  final Uri base;
  final UrlStyle style;
  final String username;

  /// The account holder's real name, for the connection list.
  final String? displayName;

  final String? version;

  WebtreesUrl get url => WebtreesUrl(base: base, style: style);

  /// Identifies this connection in storage.
  ///
  /// Two accounts on the same site are distinct connections, so the key
  /// includes both.
  String get key => '$base|$username';

  SavedConnection copyWith({String? displayName, String? version}) =>
      SavedConnection(
        base: base,
        style: style,
        username: username,
        displayName: displayName ?? this.displayName,
        version: version ?? this.version,
      );

  Map<String, Object?> toJson() => {
    'base': base.toString(),
    'style': style.name,
    'username': username,
    if (displayName != null) 'displayName': displayName,
    if (version != null) 'version': version,
  };

  static SavedConnection fromJson(Map<String, Object?> json) => SavedConnection(
    base: Uri.parse(json['base']! as String),
    style: UrlStyle.values.byName(json['style']! as String),
    username: json['username']! as String,
    displayName: json['displayName'] as String?,
    version: json['version'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is SavedConnection &&
      other.base == base &&
      other.username == username;

  @override
  int get hashCode => Object.hash(base, username);
}

/// Remembers which sites the user signs in to, and their passwords.
///
/// webtrees issues no refresh token and has no concept of an app password, so
/// staying signed in means keeping the real password and replaying it when the
/// session expires. It lives in the platform keystore and is only handed back
/// after [UnlockGate] is satisfied.
class CredentialStore {
  const CredentialStore(this._secrets, this._gate);

  final SecretStore _secrets;
  final UnlockGate _gate;

  static const String _indexKey = 'webtrees.connections';

  /// Whether a stored password will survive restarting the app.
  bool get canRemember => _secrets.isPersistent;

  /// Whether reading a password requires the device owner to identify
  /// themselves.
  bool get isGated => _gate.isEnforcing;

  /// Every site the user has signed in to, most recently used first.
  Future<List<SavedConnection>> connections() async {
    final raw = await _secrets.read(_indexKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final list = jsonDecode(raw) as List<Object?>;
      return list
          .cast<Map<String, Object?>>()
          .map(SavedConnection.fromJson)
          .toList();
    } on Object {
      // Corrupt or written by an incompatible version: start over rather than
      // leaving the app unable to open.
      await _secrets.delete(_indexKey);
      return const [];
    }
  }

  /// Records [connection] and, when given, its [password].
  ///
  /// The connection moves to the front of the list, so the most recent site is
  /// offered first next time.
  /// Passing no [password] **removes** any password already stored for this
  /// connection. Turning "stay signed in" off has to withdraw the secret, not
  /// merely stop refreshing it.
  Future<void> remember(SavedConnection connection, {String? password}) async {
    final others = await _othersThan(connection);
    await _writeIndex([connection, ...others]);

    if (password == null) {
      await forgetPassword(connection);
    } else {
      await _secrets.write(_passwordKey(connection), password);
    }
  }

  /// Returns the stored password, after the device owner identifies themselves.
  ///
  /// Returns null when nothing is stored or the unlock was refused — the
  /// caller should then ask for the password instead.
  Future<String?> password(
    SavedConnection connection, {
    required String reason,
  }) async {
    // Nothing is read out of the keystore until the device owner has
    // identified themselves. Reading first and gating afterwards would leave
    // the password in this process's memory whether or not the gate was
    // passed, which is the opposite of what the gate is for.
    if (!await hasPassword(connection)) return null;
    if (!await _gate.unlock(reason)) return null;
    return _secrets.read(_passwordKey(connection));
  }

  /// Whether a password is stored, without unlocking or retrieving anything.
  Future<bool> hasPassword(SavedConnection connection) =>
      _secrets.contains(_passwordKey(connection));

  /// Updates the stored details of a connection already in the list.
  ///
  /// Distinct from [remember], which owns the password; this only rewrites the
  /// entry, so it is safe to call whenever something about the account becomes
  /// known.
  Future<void> rename(SavedConnection connection) async {
    final existing = await connections();
    if (!existing.contains(connection)) return;
    await _writeIndex([
      for (final c in existing) c == connection ? connection : c,
    ]);
  }

  /// Discards the stored password but keeps the connection listed.
  Future<void> forgetPassword(SavedConnection connection) =>
      _secrets.delete(_passwordKey(connection));

  /// Removes the connection and its password entirely.
  Future<void> forget(SavedConnection connection) async {
    await forgetPassword(connection);
    await _writeIndex(await _othersThan(connection));
  }

  /// Every stored connection except [connection], as a fresh mutable list.
  Future<List<SavedConnection>> _othersThan(SavedConnection connection) async =>
      (await connections()).where((c) => c != connection).toList();

  Future<void> _writeIndex(List<SavedConnection> connections) => _secrets.write(
    _indexKey,
    jsonEncode(connections.map((c) => c.toJson()).toList()),
  );

  static String _passwordKey(SavedConnection connection) =>
      'webtrees.password.${connection.key}';
}
