import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/core/webtrees_client.dart';
import 'package:webtrees_mobile/core/webtrees_url.dart';
import 'package:webtrees_mobile/data/stock/charts_repository.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/records.dart';

import '../support/fake_webtrees.dart';

String fixture(String version, String name) =>
    File('test/fixtures/$version/$name').readAsStringSync();

void main() {
  late FakeWebtrees server;
  late ChartsRepository charts;

  const subject = PersonRef(xref: 'X42', name: 'عبد الله الموسى');

  void serve(Map<String, Canned Function(Sent)> handlers) {
    server = FakeWebtrees(handlers);
    charts = ChartsRepository(
      WebtreesClient(
        url: WebtreesUrl(
          base: Uri.parse('https://host'),
          style: UrlStyle.pretty,
        ),
        cookies: CookieJar(),
        dio: Dio()..httpClientAdapter = server,
      ),
      version: '2.2.6',
    );
  }

  Map<String, Canned Function(Sent)> site({String version = 'v2_2_6'}) => {
    '/tree/main/ancestors-tree-4/X42': (_) =>
        Canned(200, body: fixture(version, 'chart_ancestors.html')),
    '/tree/main/descendants-tree-3/X42': (_) =>
        Canned(200, body: fixture(version, 'chart_descendants.html')),
  };

  group('reading a chart', () {
    test('asks for the chart rather than the page around it', () async {
      serve(site());

      await charts.chart(
        ChartKind.ancestors,
        '/tree/main/ancestors-tree-4/X42',
        subject: subject,
      );

      // Every chart route answers a whole page — a form, a menu, a footer —
      // unless asked the way the site's own JavaScript asks.
      final sent = server.requests.single;
      expect(sent.query['ajax'], '1');
      expect(sent.headers['X-Requested-With'], 'XMLHttpRequest');
      expect(sent.route, '/tree/main/ancestors-tree-4/X42');
    });

    test('keeps the settings the site put in the URL', () async {
      // `ancestors-tree-4` is four generations, chosen by this site's
      // administrator. Anything that rebuilt the URL would overrule them.
      serve({
        ...site(),
        '/tree/main/ancestors-tree-9/X42': (_) =>
            Canned(200, body: fixture('v2_2_6', 'chart_ancestors.html')),
      });

      await charts.chart(
        ChartKind.ancestors,
        '/tree/main/ancestors-tree-9/X42?param=kept',
        subject: subject,
      );

      expect(server.requests.single.route, '/tree/main/ancestors-tree-9/X42');
      expect(server.requests.single.query['param'], 'kept');
    });

    test('reads the shape of an ancestors chart', () async {
      serve(site());

      final chart = await charts.chart(
        ChartKind.ancestors,
        '/tree/main/ancestors-tree-4/X42',
        subject: subject,
      );

      expect(chart.kind, ChartKind.ancestors);
      expect(chart.ancestors?.person.xref, 'X42');
      expect(chart.descendants, isNull);
      expect(chart.size, 5);
    });

    test('reads the shape of a descendants chart', () async {
      serve(site());

      final chart = await charts.chart(
        ChartKind.descendants,
        '/tree/main/descendants-tree-3/X42',
        subject: subject,
      );

      expect(chart.descendants?.families.single.children, hasLength(2));
      expect(chart.ancestors, isNull);
      expect(chart.size, 4);
    });

    test('a refusal is reported, not drawn as an empty chart', () async {
      serve({
        ...site(),
        '/tree/main/ancestors-tree-4/X42': (_) => const Canned(403),
      });

      await expectLater(
        charts.chart(
          ChartKind.ancestors,
          '/tree/main/ancestors-tree-4/X42',
          subject: subject,
        ),
        throwsA(isA<NotPermitted>()),
      );
    });

    test('an expired session is not a broken chart', () async {
      serve({
        ...site(),
        '/tree/main/ancestors-tree-4/X42': (_) =>
            const Canned(302, location: 'https://host/login'),
      });

      await expectLater(
        charts.chart(
          ChartKind.ancestors,
          '/tree/main/ancestors-tree-4/X42',
          subject: subject,
        ),
        throwsA(isA<SessionExpired>()),
      );
    });

    test(
      'refuses a chart it cannot draw rather than half-drawing it',
      () async {
        // A site offers maps, statistics and reports too. The app never offers
        // those, and asking for one here is a bug rather than a request.
        serve(site());

        await expectLater(
          charts.chart(
            ChartKind.statistics,
            '/module/statistics_chart/Chart/main',
            subject: subject,
          ),
          throwsA(isA<ParseFailure>()),
        );
        expect(server.routes, isEmpty);
      },
    );
  });
}
