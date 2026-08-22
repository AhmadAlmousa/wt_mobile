import 'dart:developer' as developer;

import '../core/errors.dart';
import '../core/response_status.dart';
import '../core/webtrees_client.dart';

/// Signs in to a webtrees site and keeps the session alive.
///
/// webtrees has no API and no tokens: authentication is a form post that
/// yields a PHP session cookie. Two behaviours shape everything here.
///
/// * A sign-in must be preceded by a page fetch. webtrees refuses any attempt
///   that arrives without a cookie already set.
/// * Success and failure both answer `302`. Only the `Location` distinguishes
///   them, so redirects must not be followed automatically.
class WebtreesSession {
  WebtreesSession(this._client);

  final WebtreesClient _client;

  String? _csrf;

  /// The CSRF token for the current session, fetched on demand.
  ///
  /// The token survives sign-in — webtrees regenerates the session id without
  /// discarding its contents — but not sign-out.
  Future<String> csrfToken() async {
    final cached = _csrf;
    if (cached != null) return cached;

    final reply = await _client.get('/login');
    final token = _extractCsrf(reply.body);
    if (token == null) {
      throw const CannotRead('the sign-in form');
    }
    return _csrf = token;
  }

  /// Discards the cached CSRF token.
  ///
  /// The token lives inside the PHP session, so it dies with it. After an
  /// expiry the cached copy is not merely stale but certain to be rejected,
  /// and posting it would waste a round trip to learn what is already known.
  void invalidateCsrf() => _csrf = null;

  /// Authenticates with [username] (a username or an email address).
  ///
  /// Throws [SignInRejected] if the credentials, verification state or
  /// approval state were not accepted, and [StaleSignIn] if the token had
  /// expired — the latter is worth one automatic retry.
  Future<void> signIn(String username, String password) async {
    // Fetching the form both establishes the cookie webtrees insists on and
    // supplies the token.
    final token = await csrfToken();

    // `url` is deliberately omitted. It defaults to the home page, which keeps
    // the success redirect distinguishable from the failure redirect back to
    // the sign-in page.
    final reply = await _client.postForm('/login', {
      'username': username,
      'password': password,
      '_csrf': token,
    });

    if (!reply.isRedirect) {
      throw UnexpectedResponse(
        reply.status,
        detail: 'The sign-in form did not behave as expected.',
      );
    }

    final location = reply.location ?? '';
    if (_client.url.routeOf(location).endsWith('/login')) {
      // webtrees echoes the attempted username back only when it reached the
      // credential check; without it, the request failed the CSRF gate first.
      if (location.contains('username=')) {
        _csrf = null;
        throw SignInRejected(serverMessage: await _readFlashMessage());
      }
      _csrf = null;
      throw const StaleSignIn();
    }

    if (!await isSignedIn()) {
      throw const SessionExpired();
    }
    developer.log('Signed in as $username', name: 'webtrees.auth');
  }

  /// Whether the session is still authenticated.
  ///
  /// `/my-account` is guarded by webtrees' logged-in middleware in every
  /// supported version, so it answers 200 when signed in and redirects when
  /// not. Fetching it also refreshes the server's idle timer.
  ///
  /// Only those two answers are meaningful. A `5xx` says the server failed,
  /// which must not be reported as "signed out" — that would trigger a
  /// pointless re-login against a site that is already struggling — so it
  /// throws instead.
  Future<bool> isSignedIn() async {
    final reply = await _client.get('/my-account');
    if (reply.isOk) return true;
    if (reply.isRedirect) {
      // The session is gone, and its CSRF token went with it. Dropping the
      // cached copy means the next sign-in fetches a usable one.
      _csrf = null;
      return false;
    }
    throw failureFrom(reply, probe: 'checking whether you are still signed in');
  }

  /// Refreshes the server-side idle timer.
  ///
  /// webtrees expires a session after PHP's `gc_maxlifetime` — 24 minutes by
  /// default — and stamps activity at most once a minute, so calling this
  /// every ten minutes while the app is in use is ample.
  ///
  /// Returns false when the session has already gone.
  Future<bool> keepAlive() => isSignedIn();

  /// Asks the server to render in [languageTag] from now on.
  ///
  /// webtrees decides the language of everything it renders — fact labels,
  /// month names, even the numerals — from a value in *its own* session, which
  /// [Login] seeds from the account's stored preference. `Accept-Language` is
  /// consulted only before that value exists, so an app in Arabic keeps
  /// receiving English dates until it says otherwise.
  ///
  /// The route is CSRF-exempt in both supported versions, and answers `204`.
  ///
  /// **This also writes the account's own language preference**, because
  /// `SelectLanguage` sets both — so the website will greet this user in the
  /// same language next time. There is no stock route that changes only the
  /// session.
  Future<void> useLanguage(String languageTag) async {
    final reply = await _client.postForm('/language/$languageTag', const {});
    if (reply.status != 204 && !reply.isOk && !reply.isRedirect) {
      throw failureFor(reply.status, probe: 'setting the language');
    }
    developer.log('Server language set to $languageTag', name: 'webtrees.auth');
  }

  /// Ends the session.
  ///
  /// Sign-out is exempt from the CSRF check, and the `XMLHttpRequest` header
  /// makes webtrees answer `204` instead of redirecting to the home page.
  Future<void> signOut() async {
    try {
      await _client.postForm(
        '/logout',
        const {},
        headers: const {'X-Requested-With': 'XMLHttpRequest'},
      );
    } on WebtreesError catch (error) {
      // A failed sign-out must not strand the user in a signed-in state.
      developer.log(
        'Sign-out request failed: ${error.message}',
        name: 'webtrees.auth',
        level: 900,
      );
    } finally {
      _csrf = null;
      await _client.clearCookies();
    }
  }

  /// Reads the message webtrees queued for the next page render.
  ///
  /// The text is already translated into the site's language, which makes it
  /// better to show than anything the app could invent — it distinguishes a
  /// wrong password from an unverified or unapproved account, which the
  /// redirect alone cannot. Reading it consumes it, so this runs only after a
  /// sign-in has already failed.
  Future<String?> _readFlashMessage() async {
    try {
      final reply = await _client.get('/login');
      final match = RegExp(
        r'<div class="alert alert-danger[^"]*"[^>]*>(.*?)</div>',
        dotAll: true,
      ).firstMatch(reply.body);
      if (match == null) return null;

      final text = match
          .group(1)!
          .replaceAll(RegExp(r'<button.*?</button>', dotAll: true), '')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return text.isEmpty ? null : _unescape(text);
    } on WebtreesError {
      return null;
    }
  }

  static String? _extractCsrf(String html) =>
      RegExp(
        r'<meta name="csrf" content="([^"]+)"',
      ).firstMatch(html)?.group(1) ??
      RegExp(r'name="_csrf"\s+value="([^"]+)"').firstMatch(html)?.group(1);

  static String _unescape(String text) => text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&nbsp;', ' ');
}
