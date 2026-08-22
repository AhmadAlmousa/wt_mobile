import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/core/webtrees_client.dart';
import 'package:webtrees_mobile/core/webtrees_url.dart';
import 'package:webtrees_mobile/data/access_probe.dart';
import 'package:webtrees_mobile/domain/access.dart';
import 'package:webtrees_mobile/domain/notice.dart';

import '../support/fake_webtrees.dart';

void main() {
  late FakeWebtrees server;
  late AccessProbe probe;

  void serve(Map<String, Canned Function(Sent)> handlers) {
    server = FakeWebtrees(handlers);
    probe = AccessProbe(
      WebtreesClient(
        url: WebtreesUrl(
          base: Uri.parse('https://host'),
          style: UrlStyle.pretty,
        ),
        cookies: CookieJar(),
        dio: Dio()..httpClientAdapter = server,
      ),
    );
  }

  const accountPage = '''
<form method="post">
<input name="user_name" value="mobile">
<input name="real_name" value="Mobile Client">
<input name="email" value="someone@example.com">
</form>''';

  String treePage({String tree = 'main', bool withMyRecord = true}) =>
      '''
<html><body>
<a href="/tree/$tree" class="dropdown-item menu-tree-1">Main tree</a>
${withMyRecord ? '<a href="/tree/$tree/individual/X42/slug" class="menu-myrecord">My record</a>' : ''}
</body></html>''';

  /// A site with one private tree where the user is a plain member.
  Map<String, Canned Function(Sent)> memberSite({
    bool privateTree = true,
    bool administrator = false,
  }) => {
    '/my-account': (_) => const Canned(200, body: accountPage),
    '/admin': (_) => administrator
        ? const Canned(200, body: 'control panel')
        : const Canned(403),
    '/': (_) => const Canned(302, location: 'https://host/tree/main/my-page'),
    // A private tree is invisible to anonymous callers: the route parameter
    // fails to bind, so webtrees answers 404 rather than 403.
    '/tree/main': (request) => privateTree && request.anonymous
        ? const Canned(404)
        : Canned(200, body: treePage()),
    '/tree/main/autocomplete/place': (_) => const Canned(403),
    '/tree/main/pending': (_) => const Canned(403),
    '/tree/main/changes-log': (_) => const Canned(403),
  };

  group('account', () {
    test('is read from the account form', () async {
      serve(memberSite());

      final summary = await probe.describe();

      expect(summary.account.username, 'mobile');
      expect(summary.account.realName, 'Mobile Client');
      expect(summary.account.email, 'someone@example.com');
      expect(summary.account.displayName, 'Mobile Client');
    });

    test('falls back to the username when no real name is set', () async {
      serve({
        ...memberSite(),
        '/my-account': (_) =>
            const Canned(200, body: '<input name="user_name" value="mobile">'),
      });

      expect((await probe.describe()).account.displayName, 'mobile');
    });
  });

  group('roles', () {
    test('a private tree the user can see proves membership', () async {
      serve(memberSite());

      final summary = await probe.describe();

      expect(summary.trees.single.role, TreeRole.member);
      expect(summary.trees.single.role.canEdit, isFalse);
    });

    test('a public tree leaves member and visitor ambiguous', () async {
      serve(memberSite(privateTree: false));

      expect(
        (await probe.describe()).trees.single.role,
        TreeRole.memberOrVisitor,
      );
    });

    test('stops at the highest role that answers', () async {
      serve({
        ...memberSite(),
        '/tree/main/autocomplete/place': (_) => const Canned(200, body: '[]'),
        '/tree/main/pending': (_) => const Canned(200, body: 'pending'),
      });

      final role = (await probe.describe()).trees.single.role;

      expect(role, TreeRole.moderator);
      expect(role.canEdit, isTrue);
      expect(role.canModerate, isTrue);
      expect(role.canManage, isFalse);
    });

    test('a manager is detected when every rung answers', () async {
      serve({
        ...memberSite(),
        '/tree/main/autocomplete/place': (_) => const Canned(200, body: '[]'),
        '/tree/main/pending': (_) => const Canned(200, body: 'pending'),
        '/tree/main/changes-log': (_) => const Canned(200, body: 'log'),
      });

      expect((await probe.describe()).trees.single.role, TreeRole.manager);
    });

    test('an administrator skips the per-tree ladder entirely', () async {
      serve(memberSite(administrator: true));

      final summary = await probe.describe();

      expect(summary.isAdministrator, isTrue);
      expect(summary.trees.single.role, TreeRole.administrator);
      expect(summary.trees.single.role.canManage, isTrue);
      expect(server.routes, isNot(contains('/tree/main/pending')));
    });
  });

  group('tree discovery', () {
    test('reads the default tree from the sign-in redirect', () async {
      serve(memberSite());

      final summary = await probe.describe();

      expect(summary.trees.map((t) => t.name), ['main']);
      expect(summary.warnings.single, isA<OnlyOneTreeFound>());
    });

    test('reads every tree from the header menu', () async {
      serve({
        ...memberSite(),
        '/tree/main': (_) => const Canned(
          200,
          body: '''
<a href="/tree/main" class="dropdown-item menu-tree-1">Main</a>
<a href="/tree/other" class="dropdown-item menu-tree-2">Other</a>''',
        ),
        '/tree/other/autocomplete/place': (_) => const Canned(403),
        '/tree/other/pending': (_) => const Canned(403),
        '/tree/other/changes-log': (_) => const Canned(403),
        '/tree/other': (_) => const Canned(404),
      });

      final summary = await probe.describe();

      expect(summary.trees.map((t) => t.name), ['main', 'other']);
      expect(summary.warnings, isEmpty);
    });

    test('falls back to the search page checkboxes', () async {
      serve({
        ...memberSite(),
        '/tree/main': (_) => Canned(200, body: treePage()),
        '/tree/main/search-general': (_) => const Canned(
          200,
          body: '''
<input name="search_trees[]" value="main">
<input name="search_trees[]" value="archive">''',
        ),
        '/tree/archive/autocomplete/place': (_) => const Canned(403),
        '/tree/archive/pending': (_) => const Canned(403),
        '/tree/archive/changes-log': (_) => const Canned(403),
        '/tree/archive': (_) => const Canned(404),
      });

      expect(
        (await probe.describe()).trees.map((t) => t.name),
        containsAll(['main', 'archive']),
      );
    });

    test('warns when no tree is visible at all', () async {
      serve({
        '/my-account': (_) => const Canned(200, body: accountPage),
        '/admin': (_) => const Canned(403),
        '/': (_) => const Canned(200, body: 'no tree access'),
      });

      final summary = await probe.describe();

      expect(summary.trees, isEmpty);
      expect(summary.warnings.single, isA<NoTreesVisible>());
    });
  });

  group('own record', () {
    test('is taken from the My individual record menu link', () async {
      serve(memberSite());

      expect((await probe.describe()).trees.single.myXref, 'X42');
    });

    test('is null when the user is not linked to a record', () async {
      serve({
        ...memberSite(),
        '/tree/main': (_) => Canned(200, body: treePage(withMyRecord: false)),
      });

      expect((await probe.describe()).trees.single.myXref, isNull);
    });
  });

  group('refusing to guess from a status', () {
    test('an expired session is not a missing role', () async {
      // Every guarded route redirects once the session dies. Reading that as
      // "the account lacks these rights" would report a demotion that never
      // happened.
      serve({
        ...memberSite(),
        '/tree/main/autocomplete/place': (_) =>
            const Canned(302, location: 'https://host/login'),
      });

      await expectLater(probe.describe(), throwsA(isA<SessionExpired>()));
    });

    test('a failing server is not a missing role', () async {
      serve({
        ...memberSite(),
        // An editor, so the ladder climbs far enough to meet the fault.
        '/tree/main/autocomplete/place': (_) => const Canned(200, body: '[]'),
        '/tree/main/pending': (_) => const Canned(500),
      });

      await expectLater(probe.describe(), throwsA(isA<UnexpectedResponse>()));
    });

    test('a failing server is not proof of a private tree', () async {
      // Only an anonymous 404 proves privacy. A 500 proves nothing, and
      // claiming membership on the strength of it would be an invention.
      serve({
        ...memberSite(),
        '/tree/main': (request) => request.anonymous
            ? const Canned(500)
            : Canned(200, body: treePage()),
      });

      expect(
        (await probe.describe()).trees.single.role,
        TreeRole.memberOrVisitor,
      );
    });

    test('an expired session is not an ordinary account', () async {
      serve({
        ...memberSite(),
        '/admin': (_) => const Canned(302, location: 'https://host/login'),
      });

      await expectLater(probe.describe(), throwsA(isA<SessionExpired>()));
    });
  });
}
