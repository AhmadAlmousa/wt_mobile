import 'fake_webtrees.dart';

/// A webtrees site that actually keeps a session, for tests about staying
/// signed in.
///
/// The simpler [workingSite] fixture flips a boolean and ignores the CSRF
/// token, which is fine for testing what a screen shows but useless for
/// testing recovery: it cannot reproduce the one case silent re-login exists
/// for, an idle session dying on the server. This one models what webtrees
/// actually does — the token lives inside the session, so expiry invalidates
/// both together — and so can tell a working recovery from a broken one.
final class FakeSite {
  FakeSite({
    this.username = 'mobile',
    this.password = 'correct',
    this.realName = 'Mobile Client',
  });

  String username;
  String password;
  String realName;

  /// The token the server will accept, rotated whenever the session dies.
  String csrf = 'token-1';

  bool signedIn = false;

  /// The language webtrees would render in, which decides the wording of
  /// every date, month name and fact label it sends.
  ///
  /// Seeded from the account's stored preference at sign-in, exactly as
  /// `Login::doLogin` does — which is why an app in Arabic gets English dates
  /// until it says otherwise.
  String accountLanguage = 'en-US';
  String? language;

  /// Every credential submission that reached the password check.
  int signInAttempts = 0;

  /// Submissions rejected because the token had gone stale.
  int staleTokenAttempts = 0;

  int _generation = 1;

  /// Ends the session the way an idle timeout does.
  ///
  /// The app still holds a cookie, but the server has forgotten what was in
  /// it — the CSRF token included, which is why a cached token cannot be
  /// reused to sign back in.
  void expire() {
    signedIn = false;
    csrf = 'token-${++_generation}';
  }

  Map<String, Canned Function(Sent)> get handlers => {
    '/ping': (request) => request.ugly
        ? const Canned(308, location: 'https://host/ping')
        : const Canned(200, body: 'OK'),
    '/robots.txt': (_) => Canned(200, body: robotsTxt(['SomeBadBot'])),
    '/login': _login,
    '/logout': (_) {
      signedIn = false;
      return const Canned(204);
    },
    // CSRF-exempt in both supported versions, and answers 204.
    for (final tag in const ['ar', 'en-GB', 'en-US'])
      '/language/$tag': (request) {
        if (request.method != 'POST') return const Canned(405);
        language = tag;
        return const Canned(204);
      },
    '/my-account': (_) => signedIn
        ? Canned(200, body: _accountPage)
        : const Canned(302, location: 'https://host/login'),
    '/admin': (_) => const Canned(403),
    '/': (_) => const Canned(302, location: 'https://host/tree/main/my-page'),
    '/tree/main': (request) =>
        request.anonymous ? const Canned(404) : Canned(200, body: _treeHome),
    '/tree/main/autocomplete/place': (_) => const Canned(403),
    '/tree/main/pending': (_) => const Canned(403),
    '/tree/main/changes-log': (_) => const Canned(403),
  };

  Canned _login(Sent request) {
    if (request.method != 'POST') {
      return Canned(200, body: pageWith(csrf: csrf));
    }

    // webtrees checks the token before the credentials, and answers a failed
    // check by redirecting to the sign-in page *without* echoing the username.
    // That absence is the app's only signal that the token, not the password,
    // was the problem.
    if (request.fields['_csrf'] != csrf) {
      staleTokenAttempts++;
      return const Canned(302, location: 'https://host/login?url=');
    }

    signInAttempts++;
    if (request.fields['username'] == username &&
        request.fields['password'] == password) {
      signedIn = true;
      language = accountLanguage;
      return const Canned(302, location: 'https://host/');
    }
    return const Canned(302, location: 'https://host/login?username=x&url=');
  }

  String get _accountPage =>
      '''
<form method="post">
<input name="user_name" value="$username">
<input name="real_name" value="$realName">
<input name="email" value="mobile@example.com">
</form>''';

  static const String _treeHome = '''
<html><body>
<h1 class="col wt-site-title">Family tree</h1>
<a href="/tree/main" class="dropdown-item menu-tree-1">Family tree</a>
<a href="/tree/main/individual/X42/slug" class="menu-myrecord">My record</a>
<nav class="col wt-primary-navigation"><ul class="nav wt-genealogy-menu">
<li class="nav-item dropdown menu-chart">
<a href="#" class="nav-link dropdown-toggle" data-bs-toggle="dropdown">Charts</a>
<div class="dropdown-menu">
<a class="dropdown-item menu-chart-statistics" href="/module/statistics_chart/Chart/main">Statistics</a>
</div>
</li>
</ul></nav>
</body></html>''';
}
