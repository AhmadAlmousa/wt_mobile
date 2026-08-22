import 'dart:developer' as developer;

import '../core/errors.dart';
import '../core/response_status.dart';
import '../core/webtrees_client.dart';
import '../domain/access.dart';

/// Works out which trees the signed-in user can reach, and their role in each.
///
/// Stock webtrees exposes no API, so nothing here can simply be asked for. The
/// technique is to use webtrees' own access middleware as the oracle: it runs
/// before any controller, so a route the user may not have answers `403`
/// without rendering anything. A `200` means the role is held.
class AccessProbe {
  const AccessProbe(this._client);

  final WebtreesClient _client;

  /// Routes that are guarded by exactly one role, ordered least to most
  /// privileged. The URLs are identical across webtrees 2.2 and 2.3.
  ///
  /// The editor probe is an autocomplete endpoint that returns a few bytes of
  /// JSON, which keeps the common case cheap.
  static const List<(TreeRole, String, Map<String, String>)> _ladder = [
    (TreeRole.editor, '/autocomplete/place', {'query': 'zz'}),
    (TreeRole.moderator, '/pending', <String, String>{}),
    (TreeRole.manager, '/changes-log', <String, String>{}),
  ];

  /// Gathers the account details, the visible trees and the role in each.
  Future<AccessSummary> describe() async {
    final warnings = <String>[];

    final account = await _readAccount();
    final isAdministrator = await _isAdministrator();
    final names = await _discoverTrees(warnings);

    final trees = <TreeAccess>[];
    for (final name in names) {
      trees.add(
        TreeAccess(
          name: name,
          role: isAdministrator
              ? TreeRole.administrator
              : await _probeRole(name),
          myXref: await _myXref(name),
        ),
      );
    }

    if (trees.isEmpty) {
      warnings.add(
        'This account cannot see any family tree. Its administrator may '
        'still need to grant access.',
      );
    }

    return AccessSummary(
      account: account,
      trees: trees,
      isAdministrator: isAdministrator,
      warnings: warnings,
    );
  }

  /// Reads the account page, whose fields are ordinary form inputs.
  Future<Account> _readAccount() async {
    final reply = await _client.get('/my-account');
    if (!reply.isOk) throw failureFrom(reply, probe: 'reading your account');

    return Account(
      username: _field(reply.body, 'user_name') ?? '',
      realName: _field(reply.body, 'real_name'),
      email: _field(reply.body, 'email'),
    );
  }

  Future<bool> _isAdministrator() async {
    final reply = await _client.get('/admin');
    return grantsAccess(reply, probe: 'checking for administrator rights');
  }

  /// Probes bottom-up and stops at the first refusal.
  ///
  /// Most people are read-only members, so the usual cost is a single small
  /// request. Only an actual manager pays for three.
  Future<TreeRole> _probeRole(String tree) async {
    TreeRole? held;
    for (final (role, path, query) in _ladder) {
      final reply = await _client.get('/tree/$tree$path', query: query);
      // Throws rather than returning on an expired session or a server fault,
      // so a transport problem is never recorded as a lesser role.
      if (!grantsAccess(reply, probe: 'checking $role rights on $tree')) break;
      held = role;
    }
    if (held != null) return held;

    // No elevated role. Whether this is a Member or a mere Visitor is only
    // decidable when the tree is provably private.
    return switch (await _visibilityOf(tree)) {
      TreeVisibility.private => TreeRole.member,
      TreeVisibility.public || TreeVisibility.unknown =>
        TreeRole.memberOrVisitor,
    };
  }

  /// Whether the tree is hidden from anonymous visitors.
  ///
  /// webtrees resolves the `{tree}` route parameter against the trees the
  /// caller may see, so a private tree fails to bind and answers `404` rather
  /// than `403`. The request must carry no session cookie, and must not keep
  /// the one it receives.
  Future<TreeVisibility> _visibilityOf(String tree) async {
    try {
      return TreeVisibility.of(await _client.getAnonymous('/tree/$tree'));
    } on WebtreesError catch (error) {
      developer.log(
        'Could not test tree privacy: ${error.message}',
        name: 'webtrees.access',
      );
      return TreeVisibility.unknown;
    }
  }

  /// Finds the trees this user can reach.
  ///
  /// There is no machine-readable list. Three sources are tried in order of
  /// reliability: the post-sign-in redirect names the default tree; the header
  /// menu lists them all, but only when the site allows switching trees; the
  /// search page repeats the list as checkboxes.
  Future<List<String>> _discoverTrees(List<String> warnings) async {
    final found = <String>{};

    final home = await _client.get('/');
    final fromRedirect = _client.url.treeOf(home.location ?? '');
    if (fromRedirect != null) found.add(fromRedirect);

    final page = fromRedirect == null
        ? home
        : await _client.get('/tree/$fromRedirect');
    found.addAll(_treesInMenu(page.body));

    if (found.length <= 1 && fromRedirect != null) {
      final search = await _client.get('/tree/$fromRedirect/search-general');
      found.addAll(
        RegExp(
          r'name="search_trees\[\]"[^>]*value="([^"]+)"',
        ).allMatches(search.body).map((m) => _unescape(m.group(1)!)),
      );
    }

    if (found.length == 1) {
      warnings.add(
        'Only one family tree was found. If this site has more, its '
        'administrator may have turned off switching between trees.',
      );
    }
    return found.toList();
  }

  /// Reads the tree links from the header menu.
  ///
  /// Each carries a `menu-tree-{id}` class, which distinguishes them from
  /// every other link on the page.
  Iterable<String> _treesInMenu(String html) sync* {
    final pattern = RegExp(
      r'<a[^>]*href="([^"]*)"[^>]*class="[^"]*menu-tree-\d+',
    );
    for (final match in pattern.allMatches(html)) {
      final tree = _client.url.treeOf(_unescape(match.group(1)!));
      if (tree != null) yield tree;
    }
  }

  /// Finds the individual record this user is linked to within [tree].
  ///
  /// The account page renders it in a disabled control with no value, so the
  /// only place the XREF appears is the "My individual record" menu link.
  Future<String?> _myXref(String tree) async {
    try {
      final reply = await _client.get('/tree/$tree');
      final match = RegExp(
        r'<a[^>]*href="([^"]*)"[^>]*class="[^"]*menu-myrecord',
      ).firstMatch(reply.body);
      if (match == null) return null;

      final route = _client.url.routeOf(_unescape(match.group(1)!));
      return RegExp(r'/individual/([^/?&#]+)').firstMatch(route)?.group(1);
    } on WebtreesError {
      return null;
    }
  }

  static String? _field(String html, String name) {
    final match = RegExp('name="$name"[^>]*value="([^"]*)"').firstMatch(html);
    final value = match?.group(1);
    return (value == null || value.isEmpty) ? null : _unescape(value);
  }

  static String _unescape(String text) => text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'");
}
