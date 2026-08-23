import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/core/webtrees_client.dart';
import 'package:webtrees_mobile/core/webtrees_url.dart';
import 'package:webtrees_mobile/data/capabilities.dart';
import 'package:webtrees_mobile/data/module/module_access.dart';
import 'package:webtrees_mobile/data/module/module_api.dart';
import 'package:webtrees_mobile/data/module/module_charts.dart';
import 'package:webtrees_mobile/data/module/module_records.dart';
import 'package:webtrees_mobile/data/transport.dart';
import 'package:webtrees_mobile/domain/access.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/records.dart';
import 'package:webtrees_mobile/domain/statistics.dart';

import '../support/fake_webtrees.dart';

/// What only the module can be asked, and what happens when it cannot answer.
///
/// The contract suite covers what both transports must agree about. This
/// covers the rest: the probe that decides whether a module is used at all,
/// the capability composition that keeps adoption per-endpoint, and the error
/// envelope — which is the reason a client stops having to guess whether a
/// `302` meant "signed out" or "moved".
void main() {
  late FakeWebtrees server;

  String fixture(String name) =>
      File('test/fixtures/module/$name').readAsStringSync();

  Canned json(String name) =>
      Canned(200, body: fixture(name), contentType: 'application/json');

  WebtreesClient clientFor(Map<String, Canned Function(Sent)> handlers) {
    server = FakeWebtrees(handlers);
    return WebtreesClient(
      url: WebtreesUrl(base: Uri.parse('https://host'), style: UrlStyle.pretty),
      cookies: CookieJar(),
      dio: Dio()..httpClientAdapter = server,
    );
  }

  group('the capability probe', () {
    test('reads what a site running the module can do', () async {
      final client = clientFor({
        '/mobile-api/v1/capabilities': (_) => json('capabilities.json'),
      });

      final found = await ModuleCapabilities.probe(client);

      expect(found.isPresent, isTrue);
      expect(found.moduleVersion, '1.0.0');
      expect(found.has(Capability.individual), isTrue);
      expect(found.languages, contains('ar'));
      expect(found.maxPageSize, 200);
    });

    test('a site without the module is not an error', () async {
      // The ordinary case. Every instance this app was designed for answers
      // exactly this, and it must cost one 404 and no complaint.
      final client = clientFor({});

      final found = await ModuleCapabilities.probe(client);

      expect(found.isPresent, isFalse);
      expect(found.features, isEmpty);
    });

    test('neither is a proxy answering HTML', () async {
      final client = clientFor({
        '/mobile-api/v1/capabilities': (_) =>
            const Canned(200, body: '<html>Sign in</html>'),
      });

      expect((await ModuleCapabilities.probe(client)).isPresent, isFalse);
    });

    test('refuses a module speaking a different version', () async {
      // The endpoints could have the same names and different meanings, and
      // reading one wrongly is worse than reading HTML correctly.
      final client = clientFor({
        '/mobile-api/v1/capabilities': (_) => const Canned(
          200,
          body: '{"api": 2, "module": "2.0.0", "features": ["individual"]}',
          contentType: 'application/json',
        ),
      });

      expect((await ModuleCapabilities.probe(client)).isPresent, isFalse);
    });
  });

  group('errors', () {
    test('are stated, not inferred from a redirect', () async {
      // The whole reason `core/response_status.dart` exists on the stock path:
      // webtrees answers 302 to the sign-in page for an unauthenticated
      // request, so a client cannot tell a dead session from a moved page.
      final records = ModuleRecordsTransport(
        clientFor({
          '/tree/main/mobile-api/v1/individual/X42': (_) => const Canned(
            401,
            body:
                '{"error":"not_signed_in","message":"Not signed in.",'
                '"detail":null}',
            contentType: 'application/json',
          ),
        }),
      );

      await expectLater(
        records.individual('main', 'X42'),
        throwsA(isA<SessionExpired>()),
      );
    });

    test('a refusal is a refusal', () async {
      final records = ModuleRecordsTransport(
        clientFor({
          '/tree/main/mobile-api/v1/individual/X42': (_) => const Canned(
            403,
            body:
                '{"error":"forbidden","message":"Not a member.",'
                '"detail":null}',
            contentType: 'application/json',
          ),
        }),
      );

      await expectLater(
        records.individual('main', 'X42'),
        throwsA(isA<NotPermitted>()),
      );
    });

    test('an HTML 404 still means not found', () async {
      // webtrees 2.2 hands a route whose `{tree}` fails to bind to its own
      // not-found handler *before* module middleware runs, so the body is a
      // page rather than the envelope. The status still means what it says.
      final records = ModuleRecordsTransport(
        clientFor({
          '/tree/main/mobile-api/v1/individual/X42': (_) =>
              const Canned(404, body: '<html>Not found</html>'),
        }),
      );

      await expectLater(
        records.individual('main', 'X42'),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('access', () {
    test('states the role instead of probing for it', () async {
      // The stock ladder costs 4 + 3·N requests and still cannot tell a
      // Member from a Visitor on a public tree.
      final access = ModuleAccessTransport(
        clientFor({'/mobile-api/v1/access': (_) => json('access.json')}),
      );

      final summary = await access.describe();

      expect(summary.account.username, 'mobile');
      expect(summary.isAdministrator, isFalse);
      expect(summary.trees.single.role, TreeRole.member);
      expect(summary.trees.single.title, 'الموسى الصائغ');
      expect(summary.trees.single.myXref, 'X42');
      expect(server.requests, hasLength(1));
    });
  });

  group('search', () {
    test('enumerates a tree when no query is given', () async {
      // The thing no stock route can do: `whereSearch` applies no filter for
      // an empty term array, so the same call walks a tree in name order.
      final records = ModuleRecordsTransport(
        clientFor({
          '/tree/main/mobile-api/v1/individuals': (_) =>
              json('individuals.json'),
        }),
      );

      final page = await records.search('main', '');

      expect(page.people, hasLength(2));
      expect(server.requests.single.query.containsKey('q'), isFalse);
    });

    test('pages by offset, not by page number', () async {
      final records = ModuleRecordsTransport(
        clientFor({
          '/tree/main/mobile-api/v1/individuals': (_) =>
              json('individuals.json'),
        }),
        pageSize: 25,
      );

      await records.search('main', 'الموسى', page: 3);

      expect(server.requests.single.query['offset'], '50');
      expect(server.requests.single.query['limit'], '25');
    });

    test('states the sex a search result has, which HTML never does', () async {
      final records = ModuleRecordsTransport(
        clientFor({
          '/tree/main/mobile-api/v1/individuals': (_) =>
              json('individuals.json'),
        }),
      );

      final page = await records.search('main', 'الموسى');

      expect(page.people.first.sex, Sex.male);
      expect(page.people.last.sex, Sex.female);
    });
  });

  group('a family on a person’s page', () {
    test('shows what happened to the couple, not who is in it', () async {
      // `HUSB`, `WIFE` and `CHIL` are facts like any other to webtrees, and a
      // module that hands a family's facts over unfiltered answers a marriage
      // *and* one pointer per member — which reached the screen as the word
      // "son" repeated once per son. The module filters them now; the app
      // drops them again on the way in, because which version of the module a
      // site runs is the site's choice.
      final records = ModuleRecordsTransport(
        clientFor({
          '/tree/main/mobile-api/v1/individual/X42': (_) => Canned(
            200,
            contentType: 'application/json',
            body: '''
            {
              "xref": "X42", "name": "عبد الله", "sex": "male",
              "facts": [], "notes": [], "sources": [], "media": [],
              "sections": [], "charts": [], "warnings": [],
              "families": [{
                "xref": "F1", "kind": "parents", "label": "الوالدان",
                "spouses": [{"xref": "X1", "name": "محمد"},
                            {"xref": "X2", "name": "فاطمة"}],
                "children": [{"xref": "X42", "name": "عبد الله"}],
                "endedInDivorce": false,
                "facts": [
                  {"tag": "MARR", "label": "زواج"},
                  {"tag": "HUSB", "label": "زوج"},
                  {"tag": "WIFE", "label": "زوجة"},
                  {"tag": "CHIL", "label": "مولود"},
                  {"tag": "CHIL", "label": "مولود"}
                ]
              }]
            }
            ''',
          ),
        }),
      );

      final person = await records.individual('main', 'X42');
      final family = person.families.single;

      expect(family.facts.map((fact) => fact.tag), ['MARR']);
      // And the people themselves are still there, where they belong.
      expect(family.spouses.length, 2);
      expect(family.children.single.xref, 'X42');
    });
  });

  group('charts', () {
    test('turns the site’s own chart classes into module endpoints', () {
      final handles = ModuleRecordsTransport.chartHandles('main', 'X42', const [
        'menu-chart-ancestry',
        'menu-chart-descendants',
        'menu-chart-fanchart',
      ]);

      expect(
        handles[ChartKind.ancestors],
        '/tree/main/mobile-api/v1/ancestors/X42',
      );
      // A fan chart is not fetched — it is the ancestors data bent round a
      // circle — so the module offers no endpoint for it.
      expect(handles.containsKey(ChartKind.fan), isFalse);
      // An hourglass is offered exactly when both of its halves are.
      expect(handles.containsKey(ChartKind.hourglass), isTrue);
    });

    test('a chart a site has switched off is not offered', () {
      // The module could compute it, but a manager said not to.
      final handles = ModuleRecordsTransport.chartHandles('main', 'X42', const [
        'menu-chart-ancestry',
      ]);

      expect(handles.containsKey(ChartKind.descendants), isFalse);
      expect(handles.containsKey(ChartKind.hourglass), isFalse);
    });

    test('says whether the site searches blood lines only', () async {
      final charts = ModuleChartsTransport(
        clientFor({
          '/tree/main/mobile-api/v1/relationship/X42/X99': (_) => const Canned(
            200,
            body:
                '{"from":{"xref":"X42","name":"A"},'
                '"to":{"xref":"X99","name":"B"},'
                '"settings":{"ancestors":1,"recursion":0,'
                '"clampedRecursion":0,"bloodLinesOnly":true},'
                '"paths":[]}',
            contentType: 'application/json',
          ),
        }),
      );

      const handle = '/tree/main/mobile-api/v1/relationship/X42';
      await charts.relationship(handle, from: 'X42', to: 'X99');

      // Not a guess from a URL: the module echoes the setting, so an empty
      // answer can be explained rather than looking like a failure.
      expect(charts.bloodLinesOnly(handle), isTrue);
    });

    test('reads a relationship path the site named', () async {
      final charts = ModuleChartsTransport(
        clientFor({
          '/tree/main/mobile-api/v1/relationship/X42/X60': (_) => const Canned(
            200,
            body:
                '{"from":{"xref":"X42","name":"عبد الله"},'
                '"to":{"xref":"X60","name":"محمد"},'
                '"settings":{"bloodLinesOnly":false},'
                '"paths":[{"description":"القرابة: إبن","steps":['
                '{"relationship":"إبن","person":{"xref":"X60","name":"محمد"},'
                '"via":{"family":"F2"}}]}]}',
            contentType: 'application/json',
          ),
        }),
      );

      final paths = await charts.relationship(
        '/tree/main/mobile-api/v1/relationship/X42',
        from: 'X42',
        to: 'X60',
      );

      // The site's own wording, which no app should compose: Arabic separates
      // an older brother from a younger one and English has no word for it.
      expect(paths.single.description, 'القرابة: إبن');
      expect(paths.single.steps.single.relationship, 'إبن');
      expect(paths.single.to?.xref, 'X60');
    });
  });

  group('composition', () {
    test('a capability the module lacks falls back to HTML', () async {
      // Adoption is per capability, not per release: a site running an older
      // module still gets the fast path for what it does implement.
      final stock = _RecordingTransport('stock');
      final module = _RecordingTransport('module');

      final composed = CapabilityRecordsTransport(
        stock: stock,
        module: module,
        capabilities: ModuleCapabilities(
          apiVersion: 1,
          moduleVersion: '0.9.0',
          webtreesVersion: '2.2.6',
          features: const {Capability.individual},
          languages: const {},
        ),
      );

      await composed.individual('main', 'X42');
      await composed.search('main', 'x');

      expect(module.calls, ['individual']);
      expect(stock.calls, ['search']);
    });

    test('with no module at all, everything is HTML', () async {
      final stock = _RecordingTransport('stock');

      final composed = CapabilityRecordsTransport(
        stock: stock,
        module: null,
        capabilities: ModuleCapabilities.none,
      );

      await composed.individual('main', 'X42');
      await composed.search('main', 'x');

      expect(stock.calls, ['individual', 'search']);
    });

    test('a chart is read by whichever transport minted its handle', () async {
      // The handle decides, not the capability list: a record fetched by one
      // transport carries chart addresses only that one can read.
      final stock = _RecordingCharts('stock');
      final module = _RecordingCharts('module');
      final composed = CapabilityChartsTransport(stock: stock, module: module);

      const subject = PersonRef(xref: 'X42', name: 'A');
      await composed.chart(
        ChartKind.ancestors,
        '/tree/main/ancestors-tree-4/X42',
        subject: subject,
      );
      await composed.chart(
        ChartKind.ancestors,
        '/tree/main/mobile-api/v1/ancestors/X42',
        subject: subject,
      );

      expect(stock.calls, hasLength(1));
      expect(module.calls, hasLength(1));
    });
  });
}

final class _RecordingTransport implements RecordsTransport {
  _RecordingTransport(this.name);

  final String name;
  final List<String> calls = [];

  @override
  Future<SearchPage> search(String tree, String query, {int page = 1}) async {
    calls.add('search');
    return const SearchPage(people: [], hasMore: false);
  }

  @override
  Future<IndividualRecord> individual(String tree, String xref) async {
    calls.add('individual');
    return IndividualRecord(xref: xref, name: '', facts: [], families: []);
  }

  @override
  Future<Map<ChartKind, String>> treeCharts(String tree) async {
    calls.add('treeCharts');
    return const {};
  }

  @override
  Future<Uint8List> image(String url) async {
    calls.add('image');
    return Uint8List(0);
  }
}

final class _RecordingCharts implements ChartsTransport {
  _RecordingCharts(this.name);

  final String name;
  final List<String> calls = [];

  @override
  Future<ChartData> chart(
    ChartKind kind,
    String handle, {
    required PersonRef subject,
    int? generations,
  }) async {
    calls.add(handle);
    return ChartData(kind: kind, subject: subject);
  }

  @override
  Future<ChartData> hourglass({
    required String ancestorsHandle,
    required String descendantsHandle,
    required PersonRef subject,
    int? generations,
  }) async {
    calls.add(ancestorsHandle);
    return ChartData(kind: ChartKind.hourglass, subject: subject);
  }

  @override
  Future<List<RelationshipPath>> relationship(
    String handle, {
    required String from,
    required String to,
    bool? bloodLinesOnly,
  }) async {
    calls.add(handle);
    return const [];
  }

  @override
  bool bloodLinesOnly(String handle) => false;

  @override
  Future<TreeStatistics> statistics(String handle) async {
    calls.add(handle);
    return TreeStatistics(parts: const <StatisticPart>[]);
  }

  @override
  Future<TimelineChart> timeline(String handle) async {
    calls.add(handle);
    return TimelineChart(ticks: const [], events: const []);
  }
}
