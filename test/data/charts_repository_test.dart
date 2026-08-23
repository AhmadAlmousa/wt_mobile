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

  group('what the app offers to draw', () {
    test('only what this site runs', () {
      // A site that has switched a chart module off never links to it, and
      // the app has nothing to offer for it either.
      expect(ChartKind.drawnFrom({ChartKind.ancestors: '/a'}), [
        ChartKind.ancestors,
      ]);
      expect(ChartKind.drawnFrom(const {}), isEmpty);
    });

    test('and not an hourglass with only one half', () {
      // The hourglass is stitched from the two charts either side of a
      // person, so the site running the hourglass module is not enough.
      expect(
        ChartKind.drawnFrom({
          ChartKind.hourglass: '/h',
          ChartKind.ancestors: '/a',
        }),
        [ChartKind.ancestors],
      );
      expect(
        ChartKind.drawnFrom({
          ChartKind.hourglass: '/h',
          ChartKind.ancestors: '/a',
          ChartKind.descendants: '/d',
        }),
        containsAll(<ChartKind>[ChartKind.hourglass]),
      );
    });

    test('never a chart it has no way to draw', () {
      // Maps, statistics and reports are all things a site offers; none of
      // them is a shape this app knows how to redraw.
      expect(
        ChartKind.drawnFrom({
          ChartKind.statistics: '/s',
          ChartKind.pedigreeMap: '/m',
        }),
        isEmpty,
      );
    });
  });

  group('reading an hourglass', () {
    test('is the two charts either side of a person, stitched', () async {
      serve(site());

      final chart = await charts.hourglass(
        ancestorsUrl: '/tree/main/ancestors-tree-4/X42',
        descendantsUrl: '/tree/main/descendants-tree-3/X42',
        subject: subject,
      );

      expect(chart.kind, ChartKind.hourglass);
      expect(chart.ancestors?.person.xref, 'X42');
      expect(chart.descendants?.person.xref, 'X42');
      // webtrees draws its own hourglass; asking for it would be a third
      // rendering of the same two families and a third parser to keep.
      expect(server.routes, hasLength(2));
    });
  });

  group('reading the statistics', () {
    Map<String, Canned Function(Sent)> withStatistics() => {
      ...site(),
      '/module/statistics_chart/Chart/main': (_) => const Canned(
        200,
        body:
            '<div id="statistics-tabs"><ul class="nav nav-tabs">'
            '<li><a class="nav-link" href="#tab-1" '
            'data-wt-href="/module/statistics_chart/Individuals/main">أفراد</a>'
            '</li>'
            '<li><a class="nav-link" href="#tab-2" '
            'data-wt-href="/module/statistics_chart/Custom/main">مخصص</a></li>'
            '</ul></div>',
      ),
      '/module/statistics_chart/Individuals/main': (_) =>
          Canned(200, body: fixture('v2_2_6', 'statistics_individuals.html')),
      // webtrees offers a tab for *building* a chart, which holds a form and
      // no figures at all.
      '/module/statistics_chart/Custom/main': (_) =>
          const Canned(200, body: '<form><select></select></form>'),
    };

    test('follows the page to the fragments that hold the numbers', () async {
      serve(withStatistics());

      final statistics = await charts.statistics(
        '/module/statistics_chart/Chart/main',
      );

      expect(statistics.parts.single.title, 'أفراد');
      expect(statistics.parts.single.sections.first.total, '١٬٤٦٣');
      expect(
        server.routes,
        containsAll(<String>[
          '/module/statistics_chart/Chart/main',
          '/module/statistics_chart/Individuals/main',
        ]),
      );
    });

    test('drops a tab that turned out to hold no figures', () async {
      serve(withStatistics());

      final statistics = await charts.statistics(
        '/module/statistics_chart/Chart/main',
      );

      // Read and found wanting, rather than skipped by its name: the app has
      // no business knowing what a site calls its tabs.
      expect(statistics.parts, hasLength(1));
      expect(server.routes, contains('/module/statistics_chart/Custom/main'));
    });
  });

  group('reading a relationship', () {
    Map<String, Canned Function(Sent)> withRelationships() => {
      ...site(),
      '/tree/main/relationships-1-3/X42/X20': (_) =>
          Canned(200, body: fixture('v2_2_6', 'relationship_ancestors.html')),
    };

    test('puts the second person into the address the site gave', () async {
      // The one URL the app edits. A relationship route takes an optional
      // second xref, and a site only ever links to one person at a time — so
      // the second is put there by the app, and everything else about the
      // address, both settings included, is left alone.
      serve(withRelationships());

      final paths = await charts.relationship(
        '/tree/main/relationships-1-3/X42',
        from: 'X42',
        to: 'X20',
      );

      expect(
        server.requests.single.route,
        '/tree/main/relationships-1-3/X42/X20',
      );
      expect(paths.single.steps.map((step) => step.person.xref), ['X7', 'X20']);
    });

    test('replaces a second person the site had already chosen', () async {
      // Where the account has a record of its own, webtrees links to the
      // relationship with *that* person already in the URL.
      serve(withRelationships());

      await charts.relationship(
        '/tree/main/relationships-1-3/X42/X99',
        from: 'X42',
        to: 'X20',
      );

      expect(
        server.requests.single.route,
        '/tree/main/relationships-1-3/X42/X20',
      );
    });

    test('knows when a site searches blood lines only', () {
      // The first number in `relationships-{ancestors}-{recursion}` is that
      // setting. With it on, two people linked only by a marriage answer "no
      // link" — which is correct, and looks like a failure unless the app
      // says why.
      expect(
        ChartsRepository.bloodLinesOnly('/tree/main/relationships-1-3/X42'),
        isTrue,
      );
      expect(
        ChartsRepository.bloodLinesOnly('/tree/main/relationships-0-99/X42'),
        isFalse,
      );
      expect(ChartsRepository.bloodLinesOnly('/tree/main/whatever'), isFalse);
    });

    test('refuses an address it does not recognise', () async {
      serve(withRelationships());

      await expectLater(
        charts.relationship(
          '/tree/main/something-else/X42',
          from: 'X42',
          to: 'X20',
        ),
        throwsA(isA<ParseFailure>()),
      );
      expect(server.routes, isEmpty);
    });
  });

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

      expect(chart.descendants?.families.first.children, hasLength(2));
      expect(chart.descendants?.families.last.children, hasLength(1));
      expect(chart.ancestors, isNull);
      expect(chart.size, 5);
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

  group('asking for a different depth', () {
    test('replaces the generations the site put in its own link', () {
      // The route ends `{kind}-{style}-{generations}/{xref}`, and webtrees
      // reads that segment straight off the route with `isBetween(2, 63)` —
      // no tree preference narrows it — so this is a request the server
      // means to answer rather than a trick played on it.
      expect(
        ChartsRepository.withGenerations(
          '/tree/main/ancestors-tree-4/X42',
          7,
        ),
        '/tree/main/ancestors-tree-7/X42',
      );
      expect(
        ChartsRepository.withGenerations(
          '/tree/main/descendants-tree-3/X42',
          10,
        ),
        '/tree/main/descendants-tree-10/X42',
      );
    });

    test('works on an ugly URL too', () {
      // The two URL styles differ only in how the slashes are written, and
      // the segment itself appears verbatim in both.
      expect(
        ChartsRepository.withGenerations(
          '/index.php?route=%2Ftree%2Fmain%2Fancestors-tree-4%2FX42',
          6,
        ),
        '/index.php?route=%2Ftree%2Fmain%2Fancestors-tree-6%2FX42',
      );
    });

    test('leaves the drawing style the administrator chose alone', () {
      expect(
        ChartsRepository.withGenerations(
          '/tree/main/ancestors-individuals-4/X42',
          5,
        ),
        '/tree/main/ancestors-individuals-5/X42',
      );
    });

    test('keeps the site’s own number when nothing was asked for', () {
      expect(
        ChartsRepository.withGenerations(
          '/tree/main/ancestors-tree-4/X42',
          null,
        ),
        '/tree/main/ancestors-tree-4/X42',
      );
    });

    test('leaves an address it does not recognise exactly as it was', () {
      // A site whose links look different keeps the number its administrator
      // chose, which is the right answer rather than a failure.
      const odd = '/tree/main/some-other-chart/X42';
      expect(ChartsRepository.withGenerations(odd, 8), odd);
    });

    test('asks the server for the depth the reader chose', () async {
      serve({
        ...site(),
        '/tree/main/ancestors-tree-6/X42': (_) =>
            Canned(200, body: fixture('v2_2_6', 'chart_ancestors.html')),
      });

      await charts.chart(
        ChartKind.ancestors,
        '/tree/main/ancestors-tree-4/X42',
        subject: subject,
        generations: 6,
      );

      expect(server.routes, contains('/tree/main/ancestors-tree-6/X42'));
    });
  });

  group('asking the relationship question differently', () {
    /// The site's own link, with its preference baked in: blood lines only.
    const offered = '/tree/main/relationships-1-99/X42';

    test('leaves the site’s own setting alone by default', () async {
      serve({
        ...site(),
        '/tree/main/relationships-1-99/X42/X43': (_) =>
            Canned(200, body: fixture('v2_2_6', 'relationship_sibling.html')),
      });

      await charts.relationship(offered, from: 'X42', to: 'X43');

      expect(server.routes, contains('/tree/main/relationships-1-99/X42/X43'));
    });

    test('can ask for any relationship on a blood-only site', () async {
      // The handler reads `ancestors` straight off the route; the tree's
      // preference only fills in the form on the page it does not send. This
      // is the only way a link through a marriage is ever found.
      serve({
        ...site(),
        '/tree/main/relationships-0-99/X42/X43': (_) =>
            Canned(200, body: fixture('v2_2_6', 'relationship_sibling.html')),
      });

      await charts.relationship(
        offered,
        from: 'X42',
        to: 'X43',
        bloodLinesOnly: false,
      );

      expect(server.routes, contains('/tree/main/relationships-0-99/X42/X43'));
    });

    test('can ask for blood lines only on a site that allows anything',
        () async {
      serve({
        ...site(),
        '/tree/main/relationships-1-99/X42/X43': (_) =>
            Canned(200, body: fixture('v2_2_6', 'relationship_sibling.html')),
      });

      await charts.relationship(
        '/tree/main/relationships-0-99/X42',
        from: 'X42',
        to: 'X43',
        bloodLinesOnly: true,
      );

      expect(server.routes, contains('/tree/main/relationships-1-99/X42/X43'));
    });

    test('never touches the recursion beside it', () async {
      // That one *is* clamped by the tree, and it is what stops a deep search
      // costing the server a minute.
      serve({
        ...site(),
        '/tree/main/relationships-0-3/X42/X43': (_) =>
            Canned(200, body: fixture('v2_2_6', 'relationship_sibling.html')),
      });

      await charts.relationship(
        '/tree/main/relationships-1-3/X42',
        from: 'X42',
        to: 'X43',
        bloodLinesOnly: false,
      );

      expect(server.routes, contains('/tree/main/relationships-0-3/X42/X43'));
    });
  });
}
