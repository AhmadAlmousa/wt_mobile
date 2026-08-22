import 'dart:convert';
import 'dart:developer' as developer;

import '../core/errors.dart';
import '../core/webtrees_client.dart';
import '../core/webtrees_url.dart';
import '../domain/instance.dart';
import '../domain/notice.dart';

/// Works out how to talk to a webtrees site, before anyone signs in.
///
/// The order of the checks matters: the URL style decides how every later
/// request is addressed, so it is settled first.
class InstanceProbe {
  const InstanceProbe(this._client);

  final WebtreesClient _client;

  /// Identifies the site at the client's configured address.
  ///
  /// Updates the client's [WebtreesClient.url] in place with the detected
  /// style and the server's own canonical address, so the caller can carry on
  /// using the same client afterwards.
  Future<WebtreesInstance> connect() async {
    final warnings = <Notice>[];

    await _detectUrlStyle(warnings);
    await _checkUserAgent(warnings);
    final health = await _checkHealth();
    final version = await _readVersion(warnings);

    return WebtreesInstance(
      url: _client.url,
      version: version,
      health: health,
      warnings: warnings,
    );
  }

  /// Asks for a deliberately ugly URL and reads the answer.
  ///
  /// A site with pretty URLs answers `308` and its `Location` is the canonical
  /// form, which also reveals the `base_url` the administrator configured. A
  /// site with ugly URLs simply answers `200`.
  Future<void> _detectUrlStyle(List<Notice> warnings) async {
    final typed = _client.url.base;
    _client.url = WebtreesUrl(base: typed, style: UrlStyle.ugly);

    final reply = await _client.get('/ping');

    if (reply.isOk) {
      developer.log('Ugly URLs', name: 'webtrees.connect');
      return;
    }

    final location = reply.location;
    if (reply.status == 308 && location != null) {
      final canonical = Uri.parse(location);
      final base = WebtreesUrl.rootOf(
        canonical,
        _stripSuffix(canonical.path, '/ping'),
      );
      _client.url = WebtreesUrl(base: base, style: UrlStyle.pretty);
      developer.log('Pretty URLs, canonical $base', name: 'webtrees.connect');

      if (base.host != typed.host || base.scheme != typed.scheme) {
        warnings.add(SiteRenamedItself(base));
      }
      return;
    }

    // A site that is offline or misconfigured answers 503 to everything,
    // including this probe. Report why rather than calling it "not webtrees".
    if (reply.status == 503) {
      _interpretHealth(reply);
    }

    throw NotWebtrees(typed.host);
  }

  /// Verifies this app's User-Agent against the list the site enforces.
  ///
  /// webtrees publishes its blocklist at `/robots.txt` and matches it as a
  /// case-sensitive substring, so a collision is silent and total: every
  /// request would answer 406. Better to say so plainly at connect time.
  Future<void> _checkUserAgent(List<Notice> warnings) async {
    final Reply reply;
    try {
      reply = await _client.get('/robots.txt');
    } on WebtreesError catch (error) {
      warnings.add(BlocklistUnchecked(error.message));
      return;
    }

    if (!reply.isOk) return;

    final collisions = <String>[];
    for (final line in const LineSplitter().convert(reply.body)) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('User-agent:')) continue;
      final agent = trimmed.substring('User-agent:'.length).trim();
      if (agent.isEmpty || agent == '*') continue;
      if (kUserAgent.contains(agent)) collisions.add(agent);
    }

    if (collisions.isNotEmpty) {
      throw BlockedAsBot('bad-ua: matches ${collisions.join(", ")}');
    }
  }

  Future<ServerHealth> _checkHealth() async =>
      _interpretHealth(await _client.get('/ping'));

  /// Reads a `/ping` response.
  ///
  /// The body is one of three literal words. `WARNING` means optional PHP
  /// extensions are missing and the site still works, so it is not an error.
  ServerHealth _interpretHealth(Reply reply) =>
      switch ((reply.status, reply.body.trim())) {
        (200, 'OK') => ServerHealth.ok,
        (200, 'WARNING') => ServerHealth.degraded,
        (503, 'ERROR') => throw const ServerUnhealthy(),
        // Maintenance mode intercepts every route, /ping included, and answers
        // 503 with an HTML page rather than the literal marker.
        (503, _) => throw const MaintenanceMode(),
        _ => throw NotWebtrees(_client.url.base.host),
      };

  /// Reads the version from the generator meta tag on the sign-in page.
  ///
  /// Every page built on the default layout carries it, including this one,
  /// which anonymous visitors can always reach.
  Future<String> _readVersion(List<Notice> warnings) async {
    final reply = await _client.get('/login');
    if (!reply.isOk) {
      warnings.add(const VersionUnreadable());
      return '';
    }

    if (reply.body.contains('Cookie check')) {
      throw const BlockedAsBot('cookie-challenge');
    }

    final version = RegExp(
      r'<meta name="generator" content="webtrees ([^"]+)"',
    ).firstMatch(reply.body)?.group(1);

    if (version == null) {
      warnings.add(const SiteUnidentified());
      return '';
    }
    return version;
  }

  static String _stripSuffix(String text, String suffix) =>
      text.endsWith(suffix)
      ? text.substring(0, text.length - suffix.length)
      : text;
}
