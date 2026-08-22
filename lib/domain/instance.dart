import 'package:meta/meta.dart';

import '../core/webtrees_url.dart';
import 'notice.dart';

/// What `/ping` reports about the server's own configuration.
enum ServerHealth {
  /// Everything the site needs is present.
  ok,

  /// Optional PHP extensions are missing. The site still works.
  degraded,
}

/// A webtrees site the app has successfully connected to.
@immutable
final class WebtreesInstance {
  const WebtreesInstance({
    required this.url,
    required this.version,
    required this.health,
    this.warnings = const [],
  });

  /// Address and URL style, both settled during connection.
  final WebtreesUrl url;

  /// The version string from the site's generator meta tag, such as `2.2.6`
  /// or `2.3.0-dev`. Empty when the tag could not be read.
  final String version;

  final ServerHealth health;

  /// Non-fatal findings worth showing on a diagnostics screen — for example
  /// that the site's canonical address differs from the one that was typed.
  final List<Notice> warnings;

  /// The major.minor version as a comparable pair, or `null` if unreadable.
  ///
  /// Used to gate behaviour that differs across webtrees releases.
  (int, int)? get versionParts {
    final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(version);
    if (match == null) return null;
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  @override
  String toString() => 'webtrees $version at $url';
}
