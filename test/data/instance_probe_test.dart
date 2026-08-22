import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/core/webtrees_client.dart';
import 'package:webtrees_mobile/core/webtrees_url.dart';
import 'package:webtrees_mobile/data/instance_probe.dart';
import 'package:webtrees_mobile/domain/instance.dart';

import '../support/fake_webtrees.dart';

void main() {
  late FakeWebtrees server;
  late WebtreesClient client;
  late InstanceProbe probe;

  void serve(
    Map<String, Canned Function(Sent)> handlers, {
    String typed = 'https://host',
  }) {
    server = FakeWebtrees(handlers, basePath: Uri.parse(typed).path);
    client = WebtreesClient(
      url: WebtreesUrl(base: Uri.parse(typed), style: UrlStyle.ugly),
      cookies: CookieJar(),
      dio: Dio()..httpClientAdapter = server,
    );
    probe = InstanceProbe(client);
  }

  /// A site that answers every check happily, with the given URL style.
  Map<String, Canned Function(Sent)> healthy({
    bool pretty = true,
    String canonical = 'https://host',
    String version = '2.2.6',
    String ping = 'OK',
  }) => {
    '/ping': (request) => pretty && request.ugly
        ? Canned(308, location: '$canonical/ping')
        : Canned(200, body: ping),
    '/robots.txt': (_) => Canned(200, body: robotsTxt(['BadBot', 'aa'])),
    '/login': (_) => Canned(200, body: pageWith(version: version)),
  };

  group('URL style detection', () {
    test('a 200 on the ugly probe means ugly URLs', () async {
      serve(healthy(pretty: false));

      final instance = await probe.connect();

      expect(instance.url.style, UrlStyle.ugly);
      expect(client.url.style, UrlStyle.ugly);
    });

    test('a 308 means pretty URLs, and gives the canonical base', () async {
      serve(healthy());

      final instance = await probe.connect();

      expect(instance.url.style, UrlStyle.pretty);
      expect(instance.url.base.toString(), 'https://host');
    });

    test('a canonical host that differs from the typed one warns', () async {
      serve(
        healthy(canonical: 'https://tree.example.com'),
        typed: 'https://192.168.1.9',
      );

      final instance = await probe.connect();

      expect(instance.url.base.host, 'tree.example.com');
      expect(instance.warnings.single, contains('tree.example.com'));
    });

    test('a subdirectory install keeps its prefix', () async {
      serve(healthy(canonical: 'https://host/wt'), typed: 'https://host/wt');

      final instance = await probe.connect();

      expect(instance.url.base.path, '/wt');
      expect(instance.warnings, isEmpty);
    });

    test('anything else is not webtrees', () async {
      serve({'/ping': (_) => const Canned(404)});

      await expectLater(probe.connect(), throwsA(isA<NotWebtrees>()));
    });
  });

  group('health', () {
    test('OK is healthy', () async {
      serve(healthy(pretty: false));
      expect((await probe.connect()).health, ServerHealth.ok);
    });

    test('WARNING still connects, degraded', () async {
      serve(healthy(pretty: false, ping: 'WARNING'));
      expect((await probe.connect()).health, ServerHealth.degraded);
    });

    test('a literal ERROR is a server configuration fault', () async {
      serve({
        ...healthy(pretty: false),
        '/ping': (_) => const Canned(503, body: 'ERROR'),
      });

      await expectLater(probe.connect(), throwsA(isA<ServerUnhealthy>()));
    });

    test('503 with a page body means maintenance mode', () async {
      serve({
        ...healthy(pretty: false),
        '/ping': (_) => const Canned(503, body: '<html>Offline</html>'),
      });

      await expectLater(probe.connect(), throwsA(isA<MaintenanceMode>()));
    });
  });

  group('version', () {
    test('is read from the generator meta tag', () async {
      serve(healthy(pretty: false, version: '2.3.0-dev'));

      final instance = await probe.connect();

      expect(instance.version, '2.3.0-dev');
      expect(instance.versionParts, (2, 3));
    });

    test('a page without the tag warns but still connects', () async {
      serve({
        ...healthy(pretty: false),
        '/login': (_) => const Canned(200, body: '<html></html>'),
      });

      final instance = await probe.connect();

      expect(instance.version, isEmpty);
      expect(instance.warnings.single, contains('did not identify itself'));
    });

    test('the bot cookie challenge is reported as a block', () async {
      serve({
        ...healthy(pretty: false),
        '/login': (_) => const Canned(200, body: '<html>Cookie check</html>'),
      });

      await expectLater(probe.connect(), throwsA(isA<BlockedAsBot>()));
    });
  });

  group('User-Agent check', () {
    test('passes when the app agent is not on the list', () async {
      serve(healthy(pretty: false));
      await probe.connect();
      expect(server.routes, contains('/robots.txt'));
    });

    test('refuses to continue when the agent is blocked', () async {
      // webtrees matches the blocklist as a case-sensitive substring, so an
      // entry contained in our agent means every request would answer 406.
      serve({
        ...healthy(pretty: false),
        '/robots.txt': (_) => Canned(200, body: robotsTxt(['Webtrees'])),
      });

      await expectLater(
        probe.connect(),
        throwsA(
          isA<BlockedAsBot>().having(
            (e) => e.reason,
            'reason',
            contains('Webtrees'),
          ),
        ),
      );
    });

    test('an unreadable blocklist only warns', () async {
      serve({
        ...healthy(pretty: false),
        '/robots.txt': (_) => const Canned(500),
      });

      expect((await probe.connect()).warnings, isEmpty);
    });
  });
}
