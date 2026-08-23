import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/core/webtrees_client.dart';
import 'package:webtrees_mobile/core/webtrees_url.dart';
import 'package:webtrees_mobile/data/module/module_records.dart';
import 'package:webtrees_mobile/data/stock/records_repository.dart';
import 'package:webtrees_mobile/data/transport.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/dates.dart';
import 'package:webtrees_mobile/domain/records.dart';

import '../support/fake_webtrees.dart';

/// One suite, run against both transports.
///
/// This is the check `PROJECT.md` §13 asks for and the only one that keeps the
/// two honest. Every screen has to behave identically whether it is reading
/// HTML or JSON, and a difference between them is not a bug in one of the
/// parsers — it is a difference the *interface* was supposed to hide.
///
/// The two fixture sets describe the same sanitized family, so an assertion
/// that holds for one and not the other is a real divergence.
///
/// Assertions here are deliberately about *meaning* rather than about wire
/// detail: how many requests a transport made, or what a URL looked like,
/// belongs in that transport's own test.
void main() {
  late FakeWebtrees server;

  String fixture(String path) => File('test/fixtures/$path').readAsStringSync();

  WebtreesClient clientFor(Map<String, Canned Function(Sent)> handlers) {
    server = FakeWebtrees(handlers);
    return WebtreesClient(
      url: WebtreesUrl(base: Uri.parse('https://host'), style: UrlStyle.pretty),
      cookies: CookieJar(),
      dio: Dio()..httpClientAdapter = server,
    );
  }

  Canned json(String name) => Canned(
    200,
    body: fixture('module/$name'),
    contentType: 'application/json',
  );

  /// The stock transport, reading the HTML fixtures captured from 2.2.6.
  RecordsTransport stock() {
    String tab(String module) => '/module/$module/Tab/main';

    return RecordsRepository(
      clientFor({
        '/tree/main/tom-select-individual': (_) => Canned(
          200,
          body: fixture('module/tom_select.json'),
          contentType: 'application/json',
        ),
        '/tree/main/individual/X42': (_) =>
            Canned(200, body: fixture('v2_2_6/individual_page.html')),
        tab('personal_facts'): (_) =>
            Canned(200, body: fixture('v2_2_6/tab_personal_facts.html')),
        tab('relatives'): (_) =>
            Canned(200, body: fixture('v2_2_6/tab_relatives.html')),
        tab('notes'): (_) =>
            Canned(200, body: fixture('v2_2_6/tab_notes.html')),
        tab('sources_tab'): (_) =>
            Canned(200, body: fixture('v2_2_6/tab_sources.html')),
        tab('media'): (_) =>
            Canned(200, body: fixture('v2_2_6/tab_media.html')),
      }),
      version: '2.2.6',
    );
  }

  /// The module transport, reading the JSON fixtures.
  RecordsTransport module() => ModuleRecordsTransport(
    clientFor({
      '/tree/main/mobile-api/v1/individuals': (_) => json('individuals.json'),
      '/tree/main/mobile-api/v1/individual/X42': (_) =>
          json('individual_X42.json'),
    }),
  );

  final transports = <String, RecordsTransport Function()>{
    'stock': stock,
    'module': module,
  };

  transports.forEach((name, build) {
    group('$name transport', () {
      test('finds people, and says whether there are more', () async {
        final page = await build().search('main', 'الموسى');

        expect(page.people.map((person) => person.xref), ['X42', 'X43']);
        expect(page.people.first.name, 'عبد الله الموسى');
        expect(page.hasMore, isFalse);
      });

      test('an empty query costs nothing and answers nothing new', () async {
        // The stock path refuses locally, because webtrees' autocomplete
        // answers an empty collection for an empty term. The module enumerates
        // instead. Both must answer *something* rather than throwing, which is
        // the contract a search box depends on.
        final page = await build().search('main', '   ');

        expect(page.people, isA<List<PersonRef>>());
      });

      test('names a person, both ways round', () async {
        final person = await build().individual('main', 'X42');

        expect(person.xref, 'X42');
        expect(person.name, 'عبد الله الموسى');
        expect(person.alternateName, 'Abdullah Almousa');
      });

      test('states the sex, the years and the death', () async {
        // On a stock instance none of this is on the individual page in a form
        // that survives translation — it is lifted from the person's own chart
        // box on the relatives tab. The module simply says it.
        final person = await build().individual('main', 'X42');

        expect(person.sex, Sex.male);
        expect(person.lifespan, '1901–1974');
        expect(person.isDeceased, isTrue);
      });

      test('reads the facts webtrees shows first', () async {
        final person = await build().individual('main', 'X42');

        expect(
          person.primaryFacts.map((fact) => fact.label),
          contains('الميلاد'),
        );
      });

      test('keeps a relative’s event out of the main list', () async {
        final person = await build().individual('main', 'X42');

        final secondary = person.facts.where((fact) => fact.isSecondary);

        expect(secondary, isNotEmpty);
        expect(secondary.first.about, isNotNull);
      });

      test('names the family a person belongs to, and how', () async {
        final person = await build().individual('main', 'X42');

        expect(person.parents.map((p) => p.xref), ['X7', 'X8']);
        expect(person.children.map((p) => p.xref), ['X60', 'X61', 'X62']);
        // Two marriages, and both are his. A transport that read only the
        // first family would look right on most records and wrong on this one.
        expect(person.spouses.map((p) => p.xref), ['X50', 'X51']);
      });

      test('keeps a date exactly as the server wrote it', () async {
        final person = await build().individual('main', 'X42');
        final birth = person.facts.firstWhere(
          (fact) => fact.label == 'الميلاد',
        );

        // Never a DateTime, and never re-formatted: the server has already
        // applied the tree's calendar, the reader's language and its own
        // numerals.
        expect(birth.date, isNotNull);
        expect(birth.date!.text, contains('١٩٠١'));
      });

      test('can drop a calendar the reader did not ask for', () async {
        final person = await build().individual('main', 'X42');
        final birth = person.facts.firstWhere(
          (fact) => fact.label == 'الميلاد',
        );

        // The whole point of keeping the structure: showing one calendar
        // without converting anything.
        final hijri = birth.date!.display(CalendarView.hijri);

        expect(hijri, contains('١٣١٨'));
        expect(hijri, isNot(contains('١٩٠١')));
      });

      test('publishes the notes, sources and photographs a site has', () async {
        final person = await build().individual('main', 'X42');

        expect(person.notes.first.text, startsWith('هاجر إلى الكويت'));
        expect(person.sources.first.title, 'سجل قيد العائلة');
        expect(person.media.first.thumbnailUrl, contains('M11'));
      });

      test('says which sections the site offered', () async {
        final person = await build().individual('main', 'X42');

        expect(person.sections, contains('relatives'));
      });

      test('offers the charts this site actually runs', () async {
        final person = await build().individual('main', 'X42');

        // The values differ — one is the site's own chart URL, the other a
        // module endpoint — but they are handles either way, and the app
        // passes them back unread.
        expect(person.charts.keys, contains(ChartKind.ancestors));
        expect(person.charts[ChartKind.ancestors], isNotEmpty);
      });

      test('a lifespan is years or nothing, never an ellipsis', () async {
        // `Individual::lifespan()` always writes something — `…–` for someone
        // with no dates at all — because the chart layout wants every box the
        // same height. Shown as-is that puts an ellipsis under every undated
        // person in the tree. Both transports answer null instead, and a real
        // tree is where they first disagreed about it.
        final person = await build().individual('main', 'X42');
        final everyone = [
          person.asReference,
          ...person.parents,
          ...person.children,
        ];
        final digit = RegExp(r'\p{Nd}', unicode: true);

        for (final one in everyone) {
          expect(
            one.lifespan,
            anyOf(isNull, matches(digit)),
            reason: '${one.xref} carries a lifespan with no years in it',
          );
        }
      });

      test('a second recorded name is a second recorded name', () async {
        // Not `GedcomRecord::alternateName()`, which answers only when the two
        // names differ by *character set* — so a person recorded twice in the
        // same script has none by that rule and one by the accordion's. A real
        // tree had exactly that, and the transports disagreed.
        final person = await build().individual('main', 'X42');

        expect(person.alternateName, 'Abdullah Almousa');
      });

      test('a record that is not there is not an empty one', () async {
        await expectLater(
          build().individual('main', 'X999'),
          throwsA(isA<WebtreesError>()),
        );
      });
    });
  });
}
