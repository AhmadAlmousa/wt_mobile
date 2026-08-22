import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:webtrees_mobile/core/webtrees_client.dart';

/// A canned HTTP response.
final class Canned {
  const Canned(
    this.status, {
    this.body = '',
    this.location,
    this.contentType = 'text/html; charset=UTF-8',
  });

  final int status;
  final String body;
  final String? location;
  final String contentType;
}

/// One recorded request, for assertions about what the app actually sent.
final class Sent {
  const Sent(
    this.method,
    this.route,
    this.fields,
    this.headers, {
    required this.ugly,
    required this.anonymous,
  });

  final String method;
  final String route;
  final Map<String, String> fields;
  final Map<String, String> headers;

  /// Whether the request was addressed in `index.php?route=` form. A site with
  /// pretty URLs redirects those; a site with ugly URLs serves them directly.
  final bool ugly;

  /// Whether the app sent this without a session, to ask what a visitor sees.
  final bool anonymous;
}

/// Stands in for a webtrees site inside unit tests.
///
/// Understands both URL styles, so the same handler table exercises a pretty
/// and an ugly instance without changes.
final class FakeWebtrees implements HttpClientAdapter {
  FakeWebtrees(this.handlers, {this.basePath = ''});

  /// Route (`/login`, `/ping`, ...) to responder.
  final Map<String, Canned Function(Sent request)> handlers;

  /// Path prefix for a site installed in a subdirectory, e.g. `/wt`.
  final String basePath;

  final List<Sent> requests = [];

  /// The routes that were requested, in order.
  List<String> get routes => requests.map((r) => r.route).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final route = _routeOf(options.uri);

    final request = Sent(
      options.method,
      route,
      _fieldsOf(options.data),
      options.headers.map((k, v) => MapEntry(k, '$v')),
      ugly: options.uri.queryParameters.containsKey('route'),
      anonymous: options.extra[anonymousRequest] == true,
    );
    requests.add(request);

    final handler = handlers[route];
    final canned = handler == null
        ? const Canned(404, body: 'Not found')
        : handler(request);

    return ResponseBody.fromString(
      canned.body,
      canned.status,
      headers: {
        'content-type': [canned.contentType],
        if (canned.location != null) 'location': [canned.location!],
      },
    );
  }

  /// Recovers the webtrees route from either URL style, discounting the
  /// subdirectory prefix and the `index.php` entry point.
  String _routeOf(Uri uri) {
    final ugly = uri.queryParameters['route'];
    if (ugly != null) return ugly;

    var path = uri.path;
    if (basePath.isNotEmpty && path.startsWith(basePath)) {
      path = path.substring(basePath.length);
    }
    return path.isEmpty ? '/' : path;
  }

  static Map<String, String> _fieldsOf(Object? data) {
    if (data is Map) {
      return data.map((k, v) => MapEntry('$k', '$v'));
    }
    if (data is String && data.isNotEmpty) {
      return Uri.splitQueryString(data);
    }
    return const {};
  }

  @override
  void close({bool force = false}) {}
}

/// A webtrees page carrying the meta tags the app reads.
String pageWith({
  String version = '2.2.6',
  String csrf = 'token-abcdefghijklmnopqrstuvwx',
  String? flash,
}) =>
    '''
<!DOCTYPE html>
<html><head>
<meta name="csrf" content="$csrf">
<meta name="generator" content="webtrees $version">
</head><body>
${flash == null ? '' : '<div class="alert alert-danger alert-dismissible" role="alert">$flash<button class="btn-close"></button></div>'}
<form method="post" action="/login">
<input type="hidden" name="_csrf" value="$csrf">
</form>
</body></html>
''';

/// The robots.txt webtrees serves, carrying its enforced blocklist.
String robotsTxt(List<String> blocked) => const LineSplitter()
    .convert(
      [
        '# robots.txt',
        ...blocked.map((agent) => 'User-agent: $agent'),
        'Disallow: /',
        'User-agent: *',
        'Crawl-delay: 10',
      ].join('\n'),
    )
    .join('\n');
