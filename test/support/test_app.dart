import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:webtrees_mobile/core/secret_store.dart';
import 'package:webtrees_mobile/core/unlock_gate.dart';
import 'package:webtrees_mobile/core/webtrees_client.dart';
import 'package:webtrees_mobile/data/credential_store.dart';
import 'package:webtrees_mobile/data/session_manager.dart';
import 'package:webtrees_mobile/data/settings_store.dart';

import 'fake_webtrees.dart';

/// A settings store backed by in-memory preferences.
///
/// Widget tests need one that never touches the platform channel, and that
/// starts from a known locale: an English default keeps assertions about copy
/// stable regardless of the machine the suite runs on.
SettingsStore testSettings({Locale? locale, ThemeMode? theme}) {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  final settings = SettingsStore();
  if (locale != null) settings.setLocale(locale);
  if (theme != null) settings.setThemeMode(theme);
  return settings;
}

/// Builds a [SessionManager] wired to [server] instead of the network.
SessionManager sessionManagerFor(
  FakeWebtrees server, {
  SecretStore? secrets,
  UnlockGate gate = const OpenGate(),
  SettingsStore? settings,
}) => SessionManager(
  CredentialStore(secrets ?? MemorySecretStore(), gate),
  clientFactory: clientFactoryFor(server),
  // Wired the same way the composition root wires it, so a test can prove the
  // app tells the server which language to render in.
  contentLanguage: settings == null
      ? null
      : () => SettingsStore.webtreesLanguageTag(
          settings.resolve(const Locale('en')),
        ),
  // Keep-alive is exercised separately; a live timer would outlast the
  // widget tree and trip the test binding's pending-timer check.
  keepAliveInterval: Duration.zero,
);

/// A keystore that behaves like a real one.
///
/// [MemorySecretStore] deliberately reports itself as non-persistent, since in
/// production it only ever stands in for a keystore that is missing — so the
/// app correctly declines to store a password in it. Tests about remembering
/// passwords need something that says it will keep them.
final class FakeKeystore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  bool get isPersistent => true;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<bool> contains(String key) async => _values.containsKey(key);
}

/// Builds clients that talk to [server] rather than the network.
ClientFactory clientFactoryFor(FakeWebtrees server) =>
    (url, cookies) => WebtreesClient(
      url: url,
      cookies: cookies,
      dio: Dio()..httpClientAdapter = server,
    );

/// A complete, healthy webtrees site with one private tree and a member.
///
/// Mirrors `tree.almou.sa`: pretty URLs, webtrees 2.2.6, tree `main`.
Map<String, Canned Function(Sent)> workingSite({
  String username = 'mobile',
  String password = 'correct',
  String realName = 'Mobile Client',
  bool administrator = false,
}) {
  const accountPage = '''
<form method="post">
<input name="user_name" value="mobile">
<input name="real_name" value="Mobile Client">
<input name="email" value="mobile@example.com">
</form>''';

  // The tree's own page carries the links to whatever a site publishes about
  // the tree as a whole — its statistics among them.
  const treeHome = '''
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

  var signedIn = false;

  return {
    '/ping': (request) => request.ugly
        ? const Canned(308, location: 'https://host/ping')
        : const Canned(200, body: 'OK'),
    '/robots.txt': (_) => Canned(200, body: robotsTxt(['SomeBadBot'])),
    '/login': (request) {
      if (request.method != 'POST') return Canned(200, body: pageWith());
      if (request.fields['username'] == username &&
          request.fields['password'] == password) {
        signedIn = true;
        return const Canned(302, location: 'https://host/');
      }
      return const Canned(302, location: 'https://host/login?username=x&url=');
    },
    '/logout': (_) {
      signedIn = false;
      return const Canned(204);
    },
    // Exempt from the CSRF check in both supported versions, and answers 204.
    // What the app sent is read back from the recorded requests.
    for (final tag in const ['ar', 'en-GB', 'en-US'])
      '/language/$tag': (_) => const Canned(204),
    '/my-account': (_) => signedIn
        ? const Canned(200, body: accountPage)
        : const Canned(302, location: 'https://host/login'),
    '/admin': (_) => administrator && signedIn
        ? const Canned(200, body: 'control panel')
        : const Canned(403),
    '/': (_) => const Canned(302, location: 'https://host/tree/main/my-page'),
    '/tree/main': (request) => request.anonymous
        ? const Canned(404) // private tree
        : const Canned(200, body: treeHome),
    '/tree/main/autocomplete/place': (_) => const Canned(403),
    '/tree/main/pending': (_) => const Canned(403),
    '/tree/main/changes-log': (_) => const Canned(403),
  };
}
