import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/core/webtrees_client.dart';
import 'package:webtrees_mobile/core/webtrees_url.dart';
import 'package:webtrees_mobile/data/stock/records_repository.dart';

import '../support/fake_webtrees.dart';

String fixture(String version, String name) =>
    File('test/fixtures/$version/$name').readAsStringSync();

/// A tom-select reply in the shape webtrees actually sends.
String searchJson({required bool more}) => jsonEncode({
  'data': [
    {
      'value': 'X42',
      'text':
          '<img src="/tree/main/media-thumbnail/M11/1?s=aa" width="30">&nbsp;'
          '<span class="NAME" dir="auto" translate="no">عبد الله '
          '<span class="SURN">الموسى</span></span>, 1901–1974',
    },
    {
      'value': 'X43',
      'text':
          '<span class="NAME" dir="auto" translate="no">نورة '
          '<span class="SURN">الموسى</span></span>, 1903–1980',
    },
  ],
  'nextUrl': more ? '/tree/main/tom-select-individual?page=2' : null,
});

/// Answers like the real `AbstractTomSelectHandler`.
///
/// `at` is validated with `isInArray(['', '@'])->string('at')` and has no
/// default, so a request that omits it is a 400 — not an empty result. The
/// fake enforces that because the earlier one did not, and a live search
/// against 2.2.6 failed while every test passed.
Canned Function(Sent) tomSelect({required bool more}) => (request) {
  final at = request.query['at'];
  if (at != '' && at != '@') {
    return const Canned(400, body: 'The parameter \u201cat\u201d is missing.');
  }
  return Canned(
    200,
    body: searchJson(more: more),
    contentType: 'application/json',
  );
};

void main() {
  late FakeWebtrees server;
  late RecordsRepository records;

  void serve(Map<String, Canned Function(Sent)> handlers) {
    server = FakeWebtrees(handlers);
    records = RecordsRepository(
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

  /// Both supported versions route a tab as `/module/{m}/Tab/{tree}` — 2.2.6
  /// declares that shape first as `module-tree`, and a live 2.2.6 emits it.
  /// The app never builds this URL, so the shape is the fixture's business
  /// rather than the parser's; `follows a tab URL shaped as a query string`
  /// covers the alternative `module-no-tree` route.
  String tabRoute(String module) => '/module/$module/Tab/main';

  Map<String, Canned Function(Sent)> site({String version = 'v2_2_6'}) => {
    '/tree/main/tom-select-individual': tomSelect(more: false),
    '/tree/main/individual/X42': (_) =>
        Canned(200, body: fixture(version, 'individual_page.html')),
    tabRoute('personal_facts'): (_) =>
        Canned(200, body: fixture(version, 'tab_personal_facts.html')),
    tabRoute('relatives'): (_) =>
        Canned(200, body: fixture(version, 'tab_relatives.html')),
    tabRoute('media'): (_) => const Canned(200, body: '<div></div>'),
  };

  group('search', () {
    test('finds people by name', () async {
      serve(site());

      final page = await records.search('main', 'الموسى');

      expect(page.people.map((p) => p.xref), ['X42', 'X43']);
      expect(page.people.first.name, 'عبد الله الموسى');
      expect(page.hasMore, isFalse);
    });

    test('reads the thumbnail only where one exists', () async {
      serve(site());
      final page = await records.search('main', 'الموسى');

      // The rendered row carries an image only for someone with a highlighted
      // media file, so absence is normal rather than a parse failure.
      expect(page.people.first.thumbnailUrl, contains('media-thumbnail'));
      expect(page.people.last.thumbnailUrl, isNull);
    });

    test('reports a further page when the server offers one', () async {
      serve({
        ...site(),
        '/tree/main/tom-select-individual': tomSelect(more: true),
      });

      expect((await records.search('main', 'a')).hasMore, isTrue);
    });

    test('sends the `at` parameter webtrees requires', () async {
      serve(site());
      await records.search('main', 'الموسى');

      // Without this the live server answers 400, not an empty result: `at`
      // has no default and the validator rejects a missing value.
      expect(server.requests.single.query['at'], '');
    });

    test('answers an empty query without asking the server', () async {
      serve(site());

      final page = await records.search('main', '   ');

      // webtrees returns nothing for an empty query — this endpoint searches,
      // it does not enumerate — so the request would be pure waste.
      expect(page.people, isEmpty);
      expect(server.routes, isEmpty);
    });

    test('a server fault is not an empty result', () async {
      serve({
        ...site(),
        '/tree/main/tom-select-individual': (_) => const Canned(500),
      });

      await expectLater(
        records.search('main', 'x'),
        throwsA(isA<UnexpectedResponse>()),
      );
    });

    test('names itself when the reply is not the JSON expected', () async {
      serve({
        ...site(),
        '/tree/main/tom-select-individual': (_) =>
            const Canned(200, body: '<html>maintenance</html>'),
      });

      await expectLater(
        records.search('main', 'x'),
        throwsA(
          isA<ParseFailure>().having(
            (e) => e.diagnostic,
            'diagnostic',
            contains('search results'),
          ),
        ),
      );
    });
  });

  for (final version in ['v2_2_6', 'v2_3']) {
    group('$version individual', () {
      test('reads names, photo, facts and relatives', () async {
        serve(site(version: version));

        final person = await records.individual('main', 'X42');

        expect(person.name, 'عبد الله الموسى');
        expect(person.alternateName, 'Abdullah Almousa');
        expect(person.thumbnailUrl, contains('media-thumbnail/M11/1'));
        expect(person.primaryFacts.map((f) => f.label), contains('الميلاد'));
        expect(person.parents.map((p) => p.xref), ['X7', 'X8']);
        expect(person.children.map((p) => p.xref), ['X60', 'X61']);
        expect(person.warnings, isEmpty);
      });

      test('asks for each tab at the URL the page gave it', () async {
        serve(site(version: version));
        await records.individual('main', 'X42');

        expect(server.routes, contains(tabRoute('personal_facts')));
        expect(server.routes, contains(tabRoute('relatives')));
        // The media tab was offered but not needed for this slice.
        expect(server.routes, isNot(contains(tabRoute('media'))));
      });

      test('marks fragment requests as such', () async {
        serve(site(version: version));
        await records.individual('main', 'X42');

        final tab = server.requests.firstWhere(
          (r) => r.route == tabRoute('relatives'),
        );
        // Only fragment routes may carry this. Elsewhere webtrees uses it to
        // turn a 4xx into a 200 holding an error page.
        expect(tab.headers['X-Requested-With'], 'XMLHttpRequest');
      });
    });
  }

  group('a record URL', () {
    test('follows the canonical redirect a bare xref provokes', () async {
      // `/individual/{xref}{/slug}` compares the slug against the one it
      // derives from the record's name, so an xref-only URL — all a search
      // result gives us — answers 301, not the page. Live 2.2.6 confirmed.
      const slugged = '/tree/main/individual/X42/abd-allh-almwsy';
      serve({
        ...site(),
        '/tree/main/individual/X42': (_) =>
            const Canned(301, location: 'https://host$slugged'),
        slugged: (_) =>
            Canned(200, body: fixture('v2_2_6', 'individual_page.html')),
      });

      final person = await records.individual('main', 'X42');

      expect(person.name, 'عبد الله الموسى');
      expect(server.routes, contains(slugged));
    });

    test('treats a 302 as an expired session, not a canonical move', () async {
      // Middleware bounces an unauthenticated caller with 302. Following it
      // would parse the sign-in page as a person.
      serve({
        ...site(),
        '/tree/main/individual/X42': (_) =>
            const Canned(302, location: 'https://host/login'),
      });

      await expectLater(
        records.individual('main', 'X42'),
        throwsA(isA<SessionExpired>()),
      );
    });
  });

  group('a tab URL', () {
    test('follows a tab URL shaped as a query string', () async {
      // 2.2.6 also declares `module-no-tree` (`/module/{m}/{action}`), so a
      // tab URL can carry the tree in the query instead of the path. The app
      // must follow whatever the page printed rather than reshaping it.
      final page = fixture('v2_2_6', 'individual_page.html').replaceAll(
        '/module/personal_facts/Tab/main?xref=X42',
        '/module/personal_facts/Tab?tree=main&amp;xref=X42',
      );
      serve({
        ...site(),
        '/tree/main/individual/X42': (_) => Canned(200, body: page),
        '/module/personal_facts/Tab': (_) =>
            Canned(200, body: fixture('v2_2_6', 'tab_personal_facts.html')),
      });

      final person = await records.individual('main', 'X42');

      expect(person.primaryFacts, isNotEmpty);
      expect(person.warnings, isEmpty);
    });
  });

  group('a missing tab', () {
    test('costs that section and says so, not the whole record', () async {
      serve({
        ...site(),
        tabRoute('relatives'): (_) => const Canned(403),
      });

      final person = await records.individual('main', 'X42');

      // A tree can restrict or disable a tab. Losing the person entirely over
      // it would be a worse answer than losing their relatives.
      expect(person.name, 'عبد الله الموسى');
      expect(person.primaryFacts, isNotEmpty);
      expect(person.families, isEmpty);
      expect(person.warnings.single, contains('Family members'));
    });

    test('is not invented when the site never offered it', () async {
      final page = fixture('v2_3', 'individual_page.html')
          .replaceAll('href="#relatives"', 'href="#other"')
          .replaceAll('id="relatives"', 'id="other"');
      serve({
        ...site(version: 'v2_3'),
        '/tree/main/individual/X42': (_) => Canned(200, body: page),
      });

      final person = await records.individual('main', 'X42');

      expect(server.routes, isNot(contains(tabRoute('relatives'))));
      expect(person.warnings.single, contains('Family members'));
    });
  });

  group('images', () {
    test('travel over the signed-in session', () async {
      serve({
        ...site(),
        '/tree/main/media-thumbnail/M11/1': (_) =>
            const Canned(200, body: 'PNGDATA', contentType: 'image/png'),
      });

      final bytes = await records.image(
        '/tree/main/media-thumbnail/M11/1?w=200&h=260&fit=crop&s=6f1c9a0b2e',
      );

      expect(bytes, isNotEmpty);
      // The signature stops arbitrary resizing; it is not an access token.
      // webtrees still checks this user's permission, so the request has to be
      // the authenticated one.
      final sent = server.requests.last;
      expect(sent.anonymous, isFalse);
      expect(sent.route, '/tree/main/media-thumbnail/M11/1');
    });

    test('a refusal is reported, not returned as broken bytes', () async {
      serve({
        ...site(),
        '/tree/main/media-thumbnail/M11/1': (_) => const Canned(403),
      });

      await expectLater(
        records.image('/tree/main/media-thumbnail/M11/1?s=x'),
        throwsA(isA<NotPermitted>()),
      );
    });
  });
}
