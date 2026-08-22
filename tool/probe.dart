// Phase 0 wire spike for the webtrees mobile client.
//
// Validates every assumption the app will rely on, against a real webtrees
// instance, before any app code depends on them. Deliberately dependency-free
// (dart:io only) so it exercises the raw HTTP wire with no library behaviour
// in between.
//
// Usage:
//   dart run tool/probe.dart --url https://tree.almou.sa --user NAME
//   dart run tool/probe.dart --url https://tree.almou.sa            (anonymous)
//
// The password is read from the terminal with echo disabled, or from stdin if
// piped. It is never logged, stored, or written to disk.

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = ProbeOptions.parse(args);
  if (options == null) {
    stderr.writeln(_usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  final probe = Probe(options);
  try {
    await probe.run();
  } finally {
    probe.close();
  }
  exitCode = probe.failed ? 1 : 0;
}

const String _usage = '''
Probe a webtrees instance and report what a mobile client can rely on.

  --url <base>    Base URL of the webtrees instance (required)
  --user <name>   Username or email. Omitted => anonymous checks only
  --tree <name>   Restrict role probing to one tree
  --ua <string>   Override the User-Agent (default: WebtreesMobile/0.1 (Dart))
''';

/// Parsed command-line options.
class ProbeOptions {
  ProbeOptions({
    required this.baseUrl,
    required this.username,
    required this.tree,
    required this.userAgent,
  });

  final String baseUrl;
  final String? username;
  final String? tree;
  final String userAgent;

  static ProbeOptions? parse(List<String> args) {
    final values = <String, String>{};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (!arg.startsWith('--')) return null;
      if (i + 1 >= args.length) return null;
      values[arg.substring(2)] = args[++i];
    }

    final url = values['url'];
    if (url == null || url.isEmpty) return null;

    return ProbeOptions(
      baseUrl: url,
      username: values['user'],
      tree: values['tree'],
      userAgent: values['ua'] ?? 'WebtreesMobile/0.1 (Dart)',
    );
  }
}

/// How a webtrees instance builds its URLs.
enum UrlStyle {
  /// `https://host/login` — requires `rewrite_urls=1` in config.ini.php.
  pretty,

  /// `https://host/index.php?route=/login` — the webtrees default.
  ugly,
}

/// A role a user may hold, ordered from least to most privileged.
enum Role {
  /// The tree is public, so read-only access proves nothing about the role:
  /// a Visitor and a Member see the same routes.
  memberOrVisitor,

  /// The tree is private. `TreeService::all()` only lists a private tree for
  /// users whose per-tree role is not Visitor, so being able to see it at all
  /// proves at least Member.
  member,

  editor,
  moderator,
  manager,
  administrator,
}

/// The outcome of one HTTP request, reduced to what the probe cares about.
class Reply {
  Reply(this.status, this.location, this.body, this.headers);

  final int status;
  final String? location;
  final String body;
  final HttpHeaders headers;
}

/// Runs the probe sequence and prints a report.
class Probe {
  Probe(this._options) : _client = HttpClient() {
    _client.userAgent = _options.userAgent;
    _client.connectionTimeout = const Duration(seconds: 15);
  }

  final ProbeOptions _options;
  final HttpClient _client;

  /// Session cookies, keyed by name. webtrees uses a scheme-dependent name
  /// (`__Secure-WT-ID` over https, `WT2_SESSION` over http), so we never
  /// hardcode it — we keep whatever the server sends.
  final Map<String, String> _cookies = {};

  late Uri _base;
  UrlStyle _style = UrlStyle.ugly;
  String? _version;
  String? _csrf;
  bool failed = false;

  void close() => _client.close(force: true);

  Future<void> run() async {
    _base = _normalizeBase(_options.baseUrl);
    _heading('webtrees mobile — Phase 0 wire spike');
    _kv('Base URL (normalized)', _base.toString());
    _kv('User-Agent', _options.userAgent);

    // URL style must be settled first: every later request is built from it.
    await _detectUrlStyle();
    await _checkUserAgent();
    await _checkReachable();
    await _loadLoginPage();

    if (_options.username == null) {
      _note('No --user given; stopping after anonymous checks.');
      return;
    }

    final password = _readPassword();
    if (password.isEmpty) {
      _fail('No password supplied.');
      return;
    }

    if (!await _login(_options.username!, password)) return;
    await _confirmSignedIn();

    final trees = await _discoverTrees();
    final isAdmin = await _probeAdministrator();
    await _reportRoles(trees, isAdmin);
  }

  // ---------------------------------------------------------------- steps

  /// webtrees blocks ~1400 User-Agent substrings, case-sensitively, and serves
  /// the enforced list at /robots.txt. Notoriously, `aa` is on it — so we check
  /// our own UA against the live list rather than guessing.
  Future<void> _checkUserAgent() async {
    _step('User-Agent is not on the server bad-bot list');
    final Reply reply;
    try {
      reply = await _get(_url('/robots.txt'));
    } on Object catch (error) {
      _warn('Could not fetch /robots.txt: $error');
      return;
    }

    if (reply.status != 200) {
      _warn('/robots.txt returned ${reply.status}; skipping check.');
      return;
    }

    final blocked = <String>[];
    for (final line in const LineSplitter().convert(reply.body)) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('User-agent:')) continue;
      final agent = trimmed.substring('User-agent:'.length).trim();
      if (agent.isEmpty || agent == '*') continue;
      if (_options.userAgent.contains(agent)) blocked.add(agent);
    }

    if (blocked.isEmpty) {
      _pass('no collision among the listed agents');
    } else {
      _fail('UA contains blocked substring(s): ${blocked.join(", ")}');
      _note('Every request will return 406. Pick a different --ua.');
    }
  }

  Future<void> _checkReachable() async {
    _step('Instance is reachable and healthy (/ping)');
    final Reply reply;
    try {
      reply = await _get(_url('/ping'));
    } on Object catch (error) {
      _fail('Cannot reach host: $error');
      return;
    }

    final body = reply.body.trim();
    switch ((reply.status, body)) {
      case (200, 'OK'):
        _pass('OK');
      case (200, 'WARNING'):
        _pass('WARNING — optional PHP extensions missing, site still works');
      case (503, 'ERROR'):
        _fail('ERROR — server is missing a required PHP extension or driver');
      case (503, _):
        _fail('503 with an HTML body — the site is in maintenance mode');
      default:
        _fail('unexpected ${reply.status}: ${_snippet(body)}');
        _note('This may not be a webtrees instance.');
    }
  }

  /// An ugly URL against a pretty-URL instance answers 308 and its Location
  /// reveals the server's configured base_url. Against an ugly-URL instance it
  /// simply answers 200.
  Future<void> _detectUrlStyle() async {
    _step('URL style');
    final probeUrl = _base.replace(
      path: _joinPath(_base.path, '/index.php'),
      queryParameters: {'route': '/ping'},
    );

    final reply = await _get(probeUrl);
    if (reply.status == 200) {
      _style = UrlStyle.ugly;
      _pass('ugly URLs (index.php?route=...) — the webtrees default');
      return;
    }

    if (reply.status == 308 && reply.location != null) {
      _style = UrlStyle.pretty;
      final canonical = Uri.parse(reply.location!);
      _pass('pretty URLs (308 -> ${reply.location})');

      final serverBase = _rootOf(
        canonical,
        _stripSuffix(canonical.path, '/ping'),
      );
      if (serverBase.host != _base.host || serverBase.scheme != _base.scheme) {
        _warn('Server canonical base is $serverBase, not $_base.');
        _note(
          'The session cookie Domain will track the server value. '
          'Prefer connecting via the canonical host.',
        );
      }
      _base = serverBase;
      return;
    }

    _fail('unexpected ${reply.status} probing URL style');
  }

  /// Fetches the login page for three things at once: the session cookie, the
  /// CSRF token, and the webtrees version.
  Future<void> _loadLoginPage() async {
    _step('Login page (cookie + CSRF token + version)');
    final reply = await _get(_url('/login'));

    if (reply.status != 200) {
      _fail('GET /login returned ${reply.status}');
      return;
    }

    if (reply.body.contains('Cookie check')) {
      _fail('Received the bot cookie-challenge stub instead of the login page');
      _note('Your UA looks like a browser. Do not include Chrome/ or Safari/.');
      return;
    }

    _version = _firstMatch(
      RegExp(r'<meta name="generator" content="webtrees ([^"]+)"'),
      reply.body,
    );
    _csrf =
        _firstMatch(
          RegExp(r'<meta name="csrf" content="([^"]+)"'),
          reply.body,
        ) ??
        _firstMatch(RegExp(r'name="_csrf"\s+value="([^"]+)"'), reply.body);

    if (_cookies.isEmpty) {
      _fail('No session cookie was set. Login will be refused by webtrees.');
    } else {
      _pass('session cookie: ${_cookies.keys.join(", ")}');
    }

    if (_version == null) {
      _warn('No generator meta tag found — is this webtrees?');
    } else {
      _pass('webtrees $_version');
    }

    if (_csrf == null) {
      _fail('No CSRF token found; cannot sign in.');
    } else {
      _pass('CSRF token acquired (${_csrf!.length} chars)');
    }
  }

  /// Both success and failure answer 302. The Location header discriminates:
  /// a route ending in /login with a `username=` parameter means the
  /// credentials were rejected; without it, the CSRF check failed.
  Future<bool> _login(String username, String password) async {
    _step('Sign in as "$username"');
    if (_csrf == null) {
      _fail('skipped — no CSRF token');
      return false;
    }

    // `url` is deliberately omitted so it defaults to the home page. Sending
    // our own value risks making success and failure indistinguishable.
    final reply = await _post(_url('/login'), {
      'username': username,
      'password': password,
      '_csrf': _csrf!,
    });

    if (reply.status != 302) {
      _fail('expected 302, got ${reply.status}');
      return false;
    }

    final location = reply.location ?? '';
    final route = _routeOf(location);
    if (route.endsWith('/login')) {
      if (location.contains('username=')) {
        _fail(
          'rejected — wrong username or password, account unverified, '
          'or awaiting administrator approval',
        );
      } else {
        _fail('rejected — CSRF or session failure');
      }
      return false;
    }

    _pass('accepted (302 -> $location)');
    return true;
  }

  /// The authoritative check. /my-account is guarded by AuthLoggedIn in both
  /// 2.2.x and 2.3, so it answers 200 when signed in and 302 when not.
  Future<void> _confirmSignedIn() async {
    _step('Confirm session via /my-account');
    final reply = await _get(_url('/my-account'));
    if (reply.status == 200) {
      _pass('signed in');
      _reportAccount(reply.body);
    } else {
      _fail('expected 200, got ${reply.status} — session did not stick');
    }
  }

  void _reportAccount(String html) {
    final fields = {
      'Username': RegExp(r'name="user_name"[^>]*value="([^"]*)"'),
      'Real name': RegExp(r'name="real_name"[^>]*value="([^"]*)"'),
      'Email': RegExp(r'name="email"[^>]*value="([^"]*)"'),
    };
    for (final entry in fields.entries) {
      final value = _firstMatch(entry.value, html);
      if (value != null && value.isNotEmpty) {
        _kv('  ${entry.key}', _unescape(value));
      }
    }
  }

  /// There is no machine-readable tree list. The post-login redirect reveals
  /// the default tree; the header menu and the search page reveal the rest,
  /// but only when ALLOW_CHANGE_GEDCOM=1 and more than one tree exists.
  Future<List<String>> _discoverTrees() async {
    _step('Discover trees');
    if (_options.tree != null) {
      _pass('using --tree ${_options.tree}');
      return [_options.tree!];
    }

    final found = <String>{};

    final home = await _get(_url('/'));
    final fromRedirect = _treeOf(home.location ?? '');
    if (fromRedirect != null) found.add(fromRedirect);

    final page = fromRedirect == null
        ? home
        : await _get(_url('/tree/$fromRedirect'));
    for (final match in RegExp(
      r'href="([^"]*)"[^>]*class="[^"]*menu-tree-\d+',
    ).allMatches(page.body)) {
      final tree = _treeOf(_unescape(match.group(1)!));
      if (tree != null) found.add(tree);
    }

    if (found.length <= 1 && fromRedirect != null) {
      final search = await _get(_url('/tree/$fromRedirect/search-general'));
      for (final match in RegExp(
        r'name="search_trees\[\]"[^>]*value="([^"]+)"',
      ).allMatches(search.body)) {
        found.add(_unescape(match.group(1)!));
      }
    }

    if (found.isEmpty) {
      _fail('no trees found — the account may have no tree access');
    } else {
      _pass('${found.length} tree(s): ${found.join(", ")}');
      if (found.length == 1) {
        _note(
          'A single result may mean ALLOW_CHANGE_GEDCOM is off rather '
          'than that only one tree exists.',
        );
      }
    }
    return found.toList();
  }

  Future<bool> _probeAdministrator() async {
    _step('Site administrator');
    final reply = await _get(_url('/admin'));
    switch (reply.status) {
      case 200:
        _pass('yes — implies Manager on every tree');
        return true;
      case 403:
        _pass('no');
        return false;
      default:
        _warn('unexpected ${reply.status}');
        return false;
    }
  }

  Future<void> _reportRoles(List<String> trees, bool isAdmin) async {
    if (trees.isEmpty) return;
    _heading('Per-tree access');
    for (final tree in trees) {
      final role = isAdmin ? Role.administrator : await _probeRole(tree);
      _kv(tree, _describe(role));
    }
  }

  /// Probes bottom-up and stops at the first denial, so the common case (a
  /// read-only member) costs one cheap request. Auth middleware runs before
  /// the controller, so a denial never renders a page.
  /// Probes bottom-up and stops at the first denial, so the common case (a
  /// read-only member) costs one cheap request. Auth middleware runs before
  /// the controller, so a denial never renders a page.
  Future<Role> _probeRole(String tree) async {
    final ladder = <(Role, String)>[
      (Role.editor, '/tree/$tree/autocomplete/place?query=zz'),
      (Role.moderator, '/tree/$tree/pending'),
      (Role.manager, '/tree/$tree/changes-log'),
    ];

    Role? role;
    for (final (candidate, path) in ladder) {
      final reply = await _get(_url(path));
      if (reply.status != 200) break;
      role = candidate;
    }
    if (role != null) return role;

    // No elevated role. If the tree is private, being able to see it at all
    // proves membership; if it is public, Member and Visitor look alike.
    return await _treeIsPrivate(tree) ? Role.member : Role.memberOrVisitor;
  }

  /// A tree is private when an anonymous request cannot resolve it: the route
  /// parameter fails to bind, so webtrees answers 404 rather than 403.
  Future<bool> _treeIsPrivate(String tree) async {
    final reply = await _get(_url('/tree/$tree'), anonymous: true);
    return reply.status != 200;
  }

  String _describe(Role role) => switch (role) {
    Role.administrator => 'Administrator (Manager on all trees)',
    Role.manager => 'Manager',
    Role.moderator => 'Moderator',
    Role.editor => 'Editor',
    Role.member => 'Member (read-only; proven by private-tree visibility)',
    Role.memberOrVisitor =>
      'Member or Visitor (read-only; tree is public, '
          'so the two are indistinguishable)',
  };

  // ------------------------------------------------------------ transport

  Uri _url(String path) {
    final split = path.indexOf('?');
    final route = split == -1 ? path : path.substring(0, split);
    final query = split == -1 ? '' : path.substring(split + 1);

    if (_style == UrlStyle.pretty) {
      return _base.replace(
        path: _joinPath(_base.path, route),
        query: query.isEmpty ? null : query,
      );
    }

    final parameters = {'route': route};
    if (query.isNotEmpty) parameters.addAll(Uri.splitQueryString(query));
    return _base.replace(
      path: _joinPath(_base.path, '/index.php'),
      queryParameters: parameters,
    );
  }

  Future<Reply> _get(Uri uri, {bool anonymous = false}) async {
    final request = await _client.getUrl(uri);
    _prepare(request, anonymous: anonymous);
    return _send(request, anonymous: anonymous);
  }

  Future<Reply> _post(Uri uri, Map<String, String> fields) async {
    final request = await _client.postUrl(uri);
    // Headers must be set before anything is written: the first write starts
    // sending the request and freezes them.
    _prepare(request);
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    final body = fields.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}='
              '${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    request.write(body);
    return _send(request);
  }

  /// Applies redirect policy and cookies. Must run before any body write.
  void _prepare(HttpClientRequest request, {bool anonymous = false}) {
    // Redirects must not be followed: the login response carries both the
    // pass/fail signal and a rotated session cookie.
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    if (!anonymous && _cookies.isNotEmpty) {
      request.headers.set(
        HttpHeaders.cookieHeader,
        _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      );
    }
  }

  Future<Reply> _send(
    HttpClientRequest request, {
    bool anonymous = false,
  }) async {
    final response = await request.close();
    // An anonymous probe starts a fresh server-side session and would
    // otherwise overwrite the authenticated cookie we are holding.
    if (!anonymous) {
      for (final cookie in response.cookies) {
        _cookies[cookie.name] = cookie.value;
      }
    }

    final body = await response
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    return Reply(
      response.statusCode,
      response.headers.value(HttpHeaders.locationHeader),
      body,
      response.headers,
    );
  }

  // --------------------------------------------------------------- helpers

  Uri _normalizeBase(String input) {
    var text = input.trim();
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.parse(text);
    var path = uri.path;
    if (path.endsWith('/index.php')) {
      path = path.substring(0, path.length - '/index.php'.length);
    }
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return _rootOf(uri, path);
  }

  /// Rebuilds [uri] with [path] and no query or fragment. `Uri.replace` with
  /// empty strings leaves a bare `?` and `#` behind, which breaks comparisons.
  Uri _rootOf(Uri uri, String path) => Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  );

  /// Extracts the webtrees route from a URL in either style.
  String _routeOf(String url) {
    if (url.isEmpty) return '';
    final uri = Uri.parse(url);
    final route = uri.queryParameters['route'];
    if (route != null) return route;
    return _stripPrefix(uri.path, _base.path);
  }

  /// Pulls the tree name out of a `/tree/{name}/...` URL in either style.
  String? _treeOf(String url) {
    if (url.isEmpty) return null;
    final match = RegExp(r'/tree/([^/?&#]+)').firstMatch(_routeOf(url));
    return match == null ? null : Uri.decodeComponent(match.group(1)!);
  }

  String _readPassword() {
    stdout.write('Password for ${_options.username}: ');
    if (!stdin.hasTerminal) return stdin.readLineSync() ?? '';

    final wasEchoing = stdin.echoMode;
    stdin.echoMode = false;
    try {
      return stdin.readLineSync() ?? '';
    } finally {
      stdin.echoMode = wasEchoing;
      stdout.writeln();
    }
  }

  // ---------------------------------------------------------------- output

  void _heading(String text) => stdout.writeln('\n=== $text ===');
  void _step(String text) => stdout.writeln('\n• $text');
  void _pass(String text) => stdout.writeln('  PASS  $text');
  void _warn(String text) => stdout.writeln('  WARN  $text');
  void _note(String text) => stdout.writeln('        $text');
  void _kv(String key, String value) => stdout.writeln('  $key: $value');

  void _fail(String text) {
    failed = true;
    stdout.writeln('  FAIL  $text');
  }
}

String? _firstMatch(RegExp pattern, String text) =>
    pattern.firstMatch(text)?.group(1);

String _snippet(String text) =>
    text.length <= 80 ? text : '${text.substring(0, 80)}...';

String _joinPath(String base, String path) {
  if (path == '/') return base.isEmpty ? '/' : base;
  return '$base$path';
}

String _stripPrefix(String text, String prefix) =>
    prefix.isNotEmpty && text.startsWith(prefix)
    ? text.substring(prefix.length)
    : text;

String _stripSuffix(String text, String suffix) => text.endsWith(suffix)
    ? text.substring(0, text.length - suffix.length)
    : text;

String _unescape(String text) => text
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'");
