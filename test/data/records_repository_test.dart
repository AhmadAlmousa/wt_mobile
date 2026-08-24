import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/core/webtrees_client.dart';
import 'package:webtrees_mobile/core/webtrees_url.dart';
import 'package:webtrees_mobile/data/stock/records_repository.dart';
import 'package:webtrees_mobile/domain/notice.dart';
import 'package:webtrees_mobile/domain/records.dart';

import '../support/fake_webtrees.dart';

String fixture(String version, String name) =>
    File('test/fixtures/$version/$name').readAsStringSync();

/// A tom-select reply in the shape webtrees actually sends.
///
/// **Captured from a running 2.2.6**, not transcribed, and the difference is
/// the whole reason the app can filter these rows at all: a lifespan is not
/// the text `1901–1974` but two spans, each carrying the *place* and the full
/// date of that event in its `title` — separated from the place by the
/// Unicode isolates webtrees wraps every rendered date in. The transcribed
/// version of this fixture said none of that, and a filter written against it
/// would have found nothing on a real site.
String searchJson({required bool more}) => jsonEncode({
  'data': [
    {
      'value': 'X42',
      'text':
          '<img src="/tree/main/media-thumbnail/M11/1?s=aa" width="30">&nbsp;'
          '<span class="NAME" dir="auto" translate="no">عبد الله '
          '<span class="SURN">الموسى</span></span>, '
          '<span title="الكويت، الكويت \u2068حوالي ١٩٠١\u2069">١٩٠١</span>'
          '–<span title="مكة، السعودية \u2068١٩٧٤\u2069">١٩٧٤</span>',
    },
    {
      'value': 'X43',
      'text':
          '<span class="NAME" dir="auto" translate="no">نورة '
          '<span class="SURN">الموسى</span></span>, '
          // Nothing recorded but the years, which is the ordinary shape: the
          // place half of the title is empty and the app must read no place
          // rather than an empty one.
          '<span title=" \u2068١٩٠٣\u2069">١٩٠٣</span>'
          '–<span title=" \u2068١٩٨٠\u2069">١٩٨٠</span>',
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
    tabRoute('media'): (_) =>
        Canned(200, body: fixture(version, 'tab_media.html')),
    tabRoute('notes'): (_) =>
        Canned(200, body: fixture(version, 'tab_notes.html')),
    tabRoute('sources_tab'): (_) =>
        Canned(200, body: fixture(version, 'tab_sources.html')),
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

    test('reads the years out of the lifespan the site printed', () async {
      serve(site());
      final page = await records.search('main', 'الموسى');

      // In the site's own numerals, which is what a stock instance sends —
      // and which is why the app reads a number rather than parsing a string.
      expect(page.people.first.lifespan, '١٩٠١–١٩٧٤');
      expect(page.people.first.birthYear, 1901);
      expect(page.people.first.deathYear, 1974);
      expect(page.people.last.birthYear, 1903);
    });

    test('reads the birthplace out of the title nobody looks at', () async {
      serve(site());
      final page = await records.search('main', 'الموسى');

      // `Individual::lifespan()` writes the title as the place, a space, and
      // then the date wrapped in Unicode isolates — so the place is
      // everything before the opening isolate, and it is the one thing a
      // stock search row says beyond a name and two years.
      expect(page.people.first.birthPlace, 'الكويت، الكويت');
    });

    test('a row that records no place says none, not an empty one', () async {
      serve(site());
      final page = await records.search('main', 'الموسى');

      // The title is still there, and still has the isolate in it — what is
      // missing is the place before it, and a filter must treat that as
      // "unstated" rather than as a place whose name is nothing.
      expect(page.people.last.birthPlace, isNull);
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
        expect(person.children.map((p) => p.xref), ['X60', 'X61', 'X62']);
        expect(person.warnings, isEmpty);
      });

      test('reads the subject’s own sex, years and death', () async {
        serve(site(version: version));

        final person = await records.individual('main', 'X42');

        // None of this is on the individual page in a form that survives
        // translation — the page states the sex as the *word* for it. It is
        // lifted from the person's own chart box on the relatives tab, where
        // they appear like anybody else.
        expect(person.sex, Sex.male);
        expect(person.lifespan, '1901–1974');
        expect(person.isDeceased, isTrue);
      });

      test(
        'a record with no relatives tab claims nothing about the person',
        () async {
          final withoutRelatives = site(version: version)
            ..remove(tabRoute('relatives'));
          serve(withoutRelatives);

          final person = await records.individual('main', 'X42');

          // The one place those facts are stated is gone, so the honest answer
          // is silence — not a guess from the page title's years.
          expect(person.sex, Sex.unknown);
          expect(person.isDeceased, isFalse);
          expect(person.warnings, isNotEmpty);
        },
      );

      test('asks for each tab at the URL the page gave it', () async {
        serve(site(version: version));
        await records.individual('main', 'X42');

        for (final module in const [
          'personal_facts',
          'relatives',
          'notes',
          'sources_tab',
          'media',
        ]) {
          expect(server.routes, contains(tabRoute(module)));
        }
      });

      test('reads the notes, sources and photos a site publishes', () async {
        serve(site(version: version));

        final person = await records.individual('main', 'X42');

        expect(person.notes.first.text, startsWith('هاجر إلى الكويت'));
        expect(person.sources.first.title, 'سجل قيد العائلة');
        expect(person.media.first.thumbnailUrl, contains('M11'));
        expect(person.warnings, isEmpty);
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
      serve({...site(), tabRoute('relatives'): (_) => const Canned(403)});

      final person = await records.individual('main', 'X42');

      // A tree can restrict or disable a tab. Losing the person entirely over
      // it would be a worse answer than losing their relatives.
      expect(person.name, 'عبد الله الموسى');
      expect(person.primaryFacts, isNotEmpty);
      expect(person.families, isEmpty);
      expect(
        person.warnings.single,
        isA<SectionUnavailable>().having(
          (notice) => notice.module,
          'module',
          'relatives',
        ),
      );
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
      expect(
        person.warnings.single,
        isA<SectionUnavailable>().having(
          (notice) => notice.module,
          'module',
          'relatives',
        ),
      );
    });
  });

  group('a module the site does not run', () {
    test('is not a missing section', () async {
      // Notes, sources and media are optional modules. This project's own
      // target runs none of the three, so treating their absence as a fault
      // would put a warning on every record it ever shows.
      final page = fixture('v2_2_6', 'individual_page.html')
          .replaceAll('href="#notes"', 'href="#none"')
          .replaceAll('href="#sources_tab"', 'href="#nothing"')
          .replaceAll('href="#media"', 'href="#neither"');
      serve({
        ...site(),
        '/tree/main/individual/X42': (_) => Canned(200, body: page),
      });

      final person = await records.individual('main', 'X42');

      expect(person.notes, isEmpty);
      expect(person.sources, isEmpty);
      expect(person.media, isEmpty);
      expect(person.warnings, isEmpty);
      expect(server.routes, isNot(contains(tabRoute('notes'))));
    });

    test('but one that fails to load still says so', () async {
      serve({...site(), tabRoute('notes'): (_) => const Canned(500)});

      final person = await records.individual('main', 'X42');

      // Offered and broken is a different thing from never offered, and the
      // reader is owed the difference: something is missing from this page.
      expect(person.notes, isEmpty);
      expect(
        person.warnings.single,
        isA<SectionUnavailable>().having(
          (notice) => notice.module,
          'module',
          'notes',
        ),
      );
    });
  });

  group('paging', () {
    test('asks for the page it was given', () async {
      serve({
        ...site(),
        '/tree/main/tom-select-individual': tomSelect(more: true),
      });

      await records.search('main', 'الموسى', page: 3);

      // webtrees pages by number from one. Its own `nextUrl` cannot be
      // followed: it is built from the tree, `at` and the page only, dropping
      // the query, so a client that trusted it would search for nothing.
      expect(server.requests.single.query['page'], '3');
      expect(server.requests.single.query['query'], 'الموسى');
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
