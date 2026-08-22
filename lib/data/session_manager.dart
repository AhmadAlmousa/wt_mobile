import 'dart:async';
import 'dart:developer' as developer;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../core/webtrees_client.dart';
import '../core/webtrees_url.dart';
import '../domain/instance.dart';
import 'credential_store.dart';
import 'instance_probe.dart';
import 'session.dart';

/// Where the app is in the connect-and-sign-in journey.
enum ConnectionStage {
  /// No site chosen yet.
  disconnected,

  /// Identifying the site.
  connecting,

  /// The site is known; nobody is signed in.
  signedOut,

  /// Credentials are being submitted.
  signingIn,

  signedIn,
}

/// Builds the HTTP client for a site.
///
/// Injectable so tests can supply a transport that never touches the network.
typedef ClientFactory =
    WebtreesClient Function(WebtreesUrl url, CookieJar cookies);

/// Owns the connection to one webtrees site and the signed-in session.
///
/// Exposes state through [ChangeNotifier] so the interface can rebuild from a
/// [ListenableBuilder], per the project's state-management convention.
class SessionManager extends ChangeNotifier {
  SessionManager(
    this._credentials, {
    CookieJar? cookies,
    ClientFactory? clientFactory,
    this.contentLanguage,
    this.keepAliveInterval = const Duration(minutes: 10),
    this.signInBackoff = const Duration(seconds: 2),
  }) : _cookies = cookies ?? CookieJar(),
       _clientFactory = clientFactory ?? _defaultClient;

  static WebtreesClient _defaultClient(WebtreesUrl url, CookieJar cookies) =>
      WebtreesClient(url: url, cookies: cookies);

  final CredentialStore _credentials;
  final CookieJar _cookies;
  final ClientFactory _clientFactory;

  /// The webtrees language tag the server should render in, asked for fresh
  /// each time because the reader can change it while signed in.
  ///
  /// A function rather than a value so the session never has to be told about
  /// a settings change it would otherwise have to subscribe to.
  final String Function()? contentLanguage;

  /// How often to refresh the server's idle timer.
  ///
  /// webtrees expires a session after PHP's `gc_maxlifetime`, 24 minutes by
  /// default, so ten minutes leaves generous headroom. A non-positive value
  /// switches keep-alive off, which tests rely on.
  final Duration keepAliveInterval;

  /// How long to wait before retrying after credentials were rejected.
  ///
  /// Doubles with each consecutive rejection, up to sixteen times this value.
  /// Injectable so tests need not actually wait.
  final Duration signInBackoff;

  ConnectionStage _stage = ConnectionStage.disconnected;
  WebtreesInstance? _instance;
  WebtreesClient? _client;
  WebtreesSession? _session;
  SavedConnection? _connection;
  WebtreesError? _error;
  Timer? _keepAlive;
  bool _busy = false;

  ConnectionStage get stage => _stage;
  WebtreesInstance? get instance => _instance;
  SavedConnection? get connection => _connection;

  /// The most recent failure, cleared whenever an operation starts.
  WebtreesError? get error => _error;

  /// True while an operation is in flight, for disabling controls.
  bool get isBusy => _busy;

  bool get isSignedIn => _stage == ConnectionStage.signedIn;

  /// Whether a password can be stored for next time.
  bool get canRemember => _credentials.canRemember;

  /// Whether device authentication actually guards a stored password.
  ///
  /// False on platforms with no biometric or device-credential support — Linux
  /// among them — where the gate opens for anyone holding the machine. The
  /// interface says so rather than implying a protection that is not there.
  bool get isGated => _credentials.isGated;

  /// Whether [saved] has a password stored, so the interface can offer to
  /// resume rather than asking again.
  Future<bool> hasStoredPassword(SavedConnection saved) =>
      _credentials.hasPassword(saved);

  /// The signed-in client, for repositories to use.
  ///
  /// Throws if nobody is signed in, which is a programming error rather than a
  /// condition to handle.
  WebtreesClient get client {
    final client = _client;
    if (client == null || !isSignedIn) {
      throw StateError('No signed-in session.');
    }
    return client;
  }

  /// Identifies the site at [address] and prepares to sign in.
  Future<bool> connect(String address) async {
    return _guard(ConnectionStage.connecting, () async {
      final Uri base;
      try {
        base = WebtreesUrl.normalize(address);
      } on FormatException catch (problem) {
        throw UnreachableHost(address, detail: problem.message);
      }

      // Everything about the previous site goes before the new one is tried.
      // Leaving the old instance in place while the new client is installed
      // would describe a site the client is no longer talking to, and a failed
      // probe would then strand the app in that contradiction.
      _disposeClient();
      _instance = null;
      _connection = null;

      final client = _clientFactory(
        WebtreesUrl(base: base, style: UrlStyle.ugly),
        _cookies,
      );
      _client = client;
      _session = WebtreesSession(client);

      try {
        _instance = await InstanceProbe(client).connect();
      } on WebtreesError {
        // A client for a site that turned out not to be usable is worse than
        // no client: later calls would quietly aim at the wrong address.
        _disposeClient();
        rethrow;
      }
      _stage = ConnectionStage.signedOut;
      return true;
    });
  }

  /// Signs in, optionally storing the password for next time.
  Future<bool> signIn(
    String username,
    String password, {
    bool remember = true,
  }) async {
    final session = _session;
    final instance = _instance;
    if (session == null || instance == null) {
      throw StateError('Connect to a site before signing in.');
    }

    return _guard(ConnectionStage.signingIn, () async {
      await _submit(session, username, password);

      final saved = SavedConnection(
        base: instance.url.base,
        style: instance.url.style,
        username: username,
        version: instance.version,
        // Carried over so signing in again does not blank the label the
        // connection list already shows.
        displayName: await _knownNameFor(instance.url.base, username),
      );
      _connection = saved;
      await _credentials.remember(
        saved,
        password: remember && _credentials.canRemember ? password : null,
      );

      _stage = ConnectionStage.signedIn;
      await _applyContentLanguage();
      _startKeepAlive();
      return true;
    });
  }

  /// Reconnects and signs in using a stored password.
  ///
  /// Returns false when nothing is stored or the unlock was declined, which
  /// means the interface should ask for the password.
  Future<bool> resume(SavedConnection saved) async {
    final password = await _credentials.password(
      saved,
      reason: 'Sign in to ${saved.base.host}',
    );
    if (password == null) return false;

    if (!await connect(saved.base.toString())) return false;
    if (await signIn(saved.username, password)) return true;

    // The stored password no longer works. Drop it, or every future launch
    // would fail the same way with no route back to the sign-in form.
    if (_error is SignInRejected) {
      developer.log('Discarding a rejected stored password', name: _log);
      await _credentials.forgetPassword(saved);
    }
    return false;
  }

  /// Signs back in to the site used last, without asking anything.
  ///
  /// The point of the app remembering a password is that the second launch
  /// costs nothing: no address to type, no list to choose from. Returns false
  /// when there is nothing to resume, the unlock was declined, or the stored
  /// password no longer works — all of which mean the interface should ask.
  Future<bool> resumeLastUsed() async {
    final saved = await _credentials.connections();
    if (saved.isEmpty) return false;

    // The list is kept most-recent-first, so this is the site the user was
    // last signed in to.
    final last = saved.first;
    if (!await _credentials.hasPassword(last)) return false;
    return resume(last);
  }

  /// Tells the server which language to render in, if anything is listening.
  ///
  /// Safe to call whenever the reader changes language; it does nothing when
  /// nobody is signed in, and the next sign-in will carry the new choice.
  Future<void> syncContentLanguage() async {
    if (!isSignedIn) return;
    await _applyContentLanguage();
  }

  /// Runs [action], signing in again once if the session has expired.
  ///
  /// webtrees sessions die on a server-side idle timer with no warning, so
  /// every data request needs this. The retry happens only when a password is
  /// stored; otherwise the expiry surfaces for the interface to handle.
  Future<T> withSession<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SessionExpired {
      developer.log(
        'Session expired; attempting silent re-sign-in',
        name: _log,
      );
      if (!await _resignIn()) {
        _stage = ConnectionStage.signedOut;
        _stopKeepAlive();
        notifyListeners();
        rethrow;
      }
      return action();
    }
  }

  /// Ends the session, keeping the site and any stored password.
  Future<void> signOut() async {
    _stopKeepAlive();
    await _session?.signOut();
    _stage = _instance == null
        ? ConnectionStage.disconnected
        : ConnectionStage.signedOut;
    notifyListeners();
  }

  /// Ends the session and discards the stored password.
  Future<void> forgetThisSite() async {
    final saved = _connection;
    await signOut();
    if (saved != null) await _credentials.forget(saved);
    _connection = null;
    _instance = null;
    _disposeClient();
    _stage = ConnectionStage.disconnected;
    notifyListeners();
  }

  Future<List<SavedConnection>> savedConnections() =>
      _credentials.connections();

  /// Records the account holder's real name against the saved connection.
  ///
  /// It is only knowable once the account page has been read, which happens
  /// after sign-in, so the connection list can only show it from the second
  /// visit onwards. Stored without touching the password.
  Future<void> noteAccountName(String? realName) async {
    final saved = _connection;
    if (saved == null || realName == null || realName.isEmpty) return;
    if (saved.displayName == realName) return;

    final updated = saved.copyWith(displayName: realName);
    _connection = updated;
    await _credentials.rename(updated);
  }

  // --------------------------------------------------------------- internals

  static const String _log = 'webtrees.session';

  /// Aligns the server's rendering language with the app's.
  ///
  /// webtrees renders dates, month names and fact labels in the language held
  /// in its own session, seeded from the account's preference — so without
  /// this an Arabic interface still shows English dates. A failure here is not
  /// worth failing a sign-in over: the app would merely read a little of the
  /// record in the wrong language.
  Future<void> _applyContentLanguage() async {
    final tag = contentLanguage?.call();
    final session = _session;
    if (tag == null || session == null) return;

    try {
      await session.useLanguage(tag);
    } on WebtreesError catch (problem) {
      developer.log(
        'Could not set the server language: ${problem.message}',
        name: _log,
        level: 900,
      );
    }
  }

  /// The real name already recorded for this account, if any.
  Future<String?> _knownNameFor(Uri base, String username) async {
    for (final saved in await _credentials.connections()) {
      if (saved.base == base && saved.username == username) {
        return saved.displayName;
      }
    }
    return null;
  }

  /// Posts the sign-in form, waiting out any backoff and retrying once if the
  /// token turns out to have expired.
  ///
  /// Both the interactive and the silent path go through here. They used to
  /// differ: only the interactive one retried, so a session that expired
  /// naturally — the one case silent re-login exists for — signed the user out
  /// instead of recovering.
  Future<void> _submit(
    WebtreesSession session,
    String username,
    String password,
  ) async {
    await _waitOutBackoff();
    try {
      await session.signIn(username, password);
      _rejections = 0;
    } on StaleSignIn {
      // The token expired between fetching the form and posting it. One retry
      // with a fresh one is the intended recovery.
      developer.log('Retrying sign-in with a fresh token', name: _log);
      await session.signIn(username, password);
      _rejections = 0;
    } on SignInRejected {
      _rejections++;
      _lastRejection = DateTime.now();
      rethrow;
    }
  }

  /// Delays a retry after rejected credentials.
  ///
  /// webtrees does not rate-limit sign-in at all, so nothing on the server
  /// stops a stored password that has quietly stopped working from filling an
  /// administrator's authentication log. The restraint has to live here.
  Future<void> _waitOutBackoff() async {
    final since = _lastRejection;
    if (_rejections == 0 || since == null) return;

    // Doubles per rejection, counted from the last failure rather than from
    // now, so time the user spent typing already counts towards the wait.
    final penalty = signInBackoff * (1 << (_rejections - 1).clamp(0, 4));
    final waited = DateTime.now().difference(since);
    if (waited >= penalty) return;

    final remaining = penalty - waited;
    developer.log(
      'Holding sign-in for ${remaining.inSeconds}s after $_rejections '
      'rejected attempt(s)',
      name: _log,
    );
    await Future<void>.delayed(remaining);
  }

  int _rejections = 0;
  DateTime? _lastRejection;

  /// Re-signs in, sharing one attempt between every caller that needs it.
  ///
  /// When several requests are in flight and the session dies, they all fail
  /// at once. Without this each would raise its own biometric prompt and post
  /// its own sign-in, so the user would be asked repeatedly to authorise what
  /// is really a single recovery.
  Future<bool> _resignIn() {
    return _reauthentication ??= _reauthenticate().whenComplete(() {
      _reauthentication = null;
    });
  }

  Future<bool>? _reauthentication;

  Future<bool> _reauthenticate() async {
    final saved = _connection;
    final session = _session;
    if (saved == null || session == null) return false;

    final password = await _credentials.password(
      saved,
      reason: 'Sign in again to ${saved.base.host}',
    );
    if (password == null) return false;

    try {
      // The old token died with the session it lived in, so start from a
      // fresh one rather than spending a round trip proving it is stale.
      session.invalidateCsrf();
      await _submit(session, saved.username, password);
      await _applyContentLanguage();
      _startKeepAlive();
      return true;
    } on WebtreesError catch (problem) {
      developer.log(
        'Silent re-sign-in failed: ${problem.message}',
        name: _log,
        level: 900,
      );
      // A stored password that no longer works will fail on every request;
      // drop it so the user is asked once rather than repeatedly.
      if (problem is SignInRejected) {
        await _credentials.forgetPassword(saved);
      }
      return false;
    }
  }

  void _startKeepAlive() {
    _stopKeepAlive();
    if (keepAliveInterval <= Duration.zero) return;
    _keepAlive = Timer.periodic(keepAliveInterval, (_) async {
      final session = _session;
      if (session == null) return;
      try {
        if (!await session.keepAlive() && !await _resignIn()) {
          _stage = ConnectionStage.signedOut;
          _stopKeepAlive();
          notifyListeners();
        }
      } on WebtreesError catch (problem) {
        // A transient network failure must not sign the user out.
        developer.log('Keep-alive failed: ${problem.message}', name: _log);
      }
    });
  }

  void _stopKeepAlive() {
    _keepAlive?.cancel();
    _keepAlive = null;
  }

  /// Runs [action] with busy/error bookkeeping and a single notification.
  Future<bool> _guard(
    ConnectionStage working,
    Future<bool> Function() action,
  ) async {
    _busy = true;
    _error = null;
    _stage = working;
    notifyListeners();

    try {
      return await action();
    } on WebtreesError catch (problem) {
      _error = problem;
      _stage = _instance == null
          ? ConnectionStage.disconnected
          : ConnectionStage.signedOut;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _disposeClient() {
    _client?.close();
    _client = null;
    _session = null;
  }

  @override
  void dispose() {
    _stopKeepAlive();
    _disposeClient();
    super.dispose();
  }
}
