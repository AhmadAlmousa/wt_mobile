import 'package:meta/meta.dart';

/// How a webtrees instance renders its URLs.
///
/// webtrees ships with `rewrite_urls="0"`, so [ugly] is the default for a
/// fresh install. Sites that enable pretty URLs answer an ugly request with a
/// `308 Permanent Redirect` to the pretty form.
enum UrlStyle {
  /// `https://host/tree/main/individual/X1` — needs `rewrite_urls=1`.
  pretty,

  /// `https://host/index.php?route=/tree/main/individual/X1` — the default.
  ugly,
}

/// Addresses routes on one webtrees instance.
///
/// A single instance may be served from a subdirectory (`https://host/wt`), so
/// [base] can carry a path prefix. All webtrees routes are expressed
/// prefix-free (`/login`, `/tree/{tree}/pending`) and [route] applies both the
/// prefix and the instance's [UrlStyle].
@immutable
final class WebtreesUrl {
  const WebtreesUrl({required this.base, required this.style});

  /// Scheme, host, optional port and optional path prefix. Never has a
  /// trailing slash, a query, or a fragment.
  final Uri base;

  final UrlStyle style;

  /// Cleans up whatever the user typed into a connectable base URL.
  ///
  /// Assumes `https` when no scheme is given, and tolerates the two things
  /// people paste most often: a trailing slash, and a full URL ending in
  /// `/index.php`.
  ///
  /// ```dart
  /// WebtreesUrl.normalize('tree.example.com/wt/index.php')
  ///   // https://tree.example.com/wt
  /// ```
  static Uri normalize(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      throw const FormatException('Enter the address of your webtrees site.');
    }
    if (!text.contains('://')) {
      text = 'https://$text';
    }

    final Uri parsed;
    try {
      parsed = Uri.parse(text);
    } on FormatException {
      throw const FormatException('That does not look like a web address.');
    }

    if (parsed.host.isEmpty) {
      throw const FormatException('That address is missing a host name.');
    }
    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      throw FormatException('Unsupported address type "${parsed.scheme}".');
    }

    var path = parsed.path;
    if (path.endsWith('/index.php')) {
      path = path.substring(0, path.length - '/index.php'.length);
    }
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    return rootOf(parsed, path);
  }

  /// Rebuilds [uri] with [path] and no query or fragment.
  ///
  /// `Uri.replace(query: '')` leaves a bare `?` behind, which breaks equality
  /// comparisons against a freshly parsed URL.
  static Uri rootOf(Uri uri, String path) => Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  );

  /// Builds an absolute URL for a webtrees [route] such as `/tree/main`.
  ///
  /// Extra [query] parameters are placed correctly for the instance's
  /// [UrlStyle]; in [UrlStyle.ugly] they sit alongside the `route` parameter.
  Uri call(String route, [Map<String, String> query = const {}]) {
    assert(route.startsWith('/'), 'Routes are absolute: $route');
    assert(
      !route.contains('?'),
      'Pass parameters as `query`, not in the route: $route',
    );

    if (style == UrlStyle.pretty) {
      return base.replace(
        path: _join(base.path, route),
        queryParameters: query.isEmpty ? null : query,
      );
    }

    return base.replace(
      path: _join(base.path, '/index.php'),
      queryParameters: {'route': route, ...query},
    );
  }

  /// Recovers the webtrees route from an absolute or relative [url].
  ///
  /// Works for both URL styles, so it can read a `Location` header without
  /// knowing how the server that produced it is configured.
  String routeOf(String url) {
    if (url.isEmpty) return '';

    final Uri parsed;
    try {
      parsed = Uri.parse(url);
    } on FormatException {
      return '';
    }

    final ugly = parsed.queryParameters['route'];
    if (ugly != null) return ugly;

    final path = parsed.path;
    return base.path.isNotEmpty && path.startsWith(base.path)
        ? path.substring(base.path.length)
        : path;
  }

  /// Extracts the tree name from a `/tree/{name}/...` [url], if it has one.
  String? treeOf(String url) {
    final match = RegExp(r'^/tree/([^/?&#]+)').firstMatch(routeOf(url));
    if (match == null) return null;
    try {
      return Uri.decodeComponent(match.group(1)!);
    } on ArgumentError {
      return match.group(1);
    }
  }

  WebtreesUrl withStyle(UrlStyle newStyle) =>
      WebtreesUrl(base: base, style: newStyle);

  WebtreesUrl withBase(Uri newBase) => WebtreesUrl(base: newBase, style: style);

  /// The home route keeps its slash so a subdirectory install addresses
  /// `/wt/` rather than `/wt`, matching the session cookie's path.
  static String _join(String prefix, String route) =>
      route == '/' ? '$prefix/' : '$prefix$route';

  @override
  bool operator ==(Object other) =>
      other is WebtreesUrl && other.base == base && other.style == style;

  @override
  int get hashCode => Object.hash(base, style);

  @override
  String toString() => '$base (${style.name} URLs)';
}
