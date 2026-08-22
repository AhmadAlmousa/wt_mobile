import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/core/webtrees_client.dart';
import 'package:webtrees_mobile/core/webtrees_url.dart';
import 'package:webtrees_mobile/data/session.dart';

import '../support/fake_webtrees.dart';

void main() {
  late FakeWebtrees server;
  late WebtreesClient client;
  late WebtreesSession session;

  /// Builds a session against [handlers], defaulting to a healthy site whose
  /// sign-in succeeds.
  void serve(Map<String, Canned Function(Sent)> handlers) {
    server = FakeWebtrees(handlers);
    final dio = Dio()..httpClientAdapter = server;
    client = WebtreesClient(
      url: WebtreesUrl(base: Uri.parse('https://host'), style: UrlStyle.pretty),
      cookies: CookieJar(),
      dio: dio,
    );
    session = WebtreesSession(client);
  }

  Canned loginPage(Sent _) => Canned(200, body: pageWith());

  group('signIn', () {
    test('accepts a redirect away from the sign-in page', () async {
      serve({
        '/login': (request) => request.method == 'POST'
            ? const Canned(302, location: 'https://host/')
            : Canned(200, body: pageWith()),
        '/my-account': (_) => const Canned(200, body: 'account'),
      });

      await session.signIn('mobile', 'secret');

      // The form must be fetched first: webtrees refuses a sign-in that
      // arrives without an existing session cookie.
      expect(server.routes.first, '/login');
      final post = server.requests.firstWhere((r) => r.method == 'POST');
      expect(post.fields['username'], 'mobile');
      expect(post.fields['password'], 'secret');
      expect(post.fields['_csrf'], isNotEmpty);
      // Omitting `url` is what keeps success distinguishable from failure.
      expect(post.fields.containsKey('url'), isFalse);
    });

    test('reports rejection, quoting the site in its own language', () async {
      serve({
        '/login': (request) => request.method == 'POST'
            ? const Canned(
                302,
                location: 'https://host/login?username=mobile&url=',
              )
            : Canned(
                200,
                body: pageWith(flash: 'This account has not been approved.'),
              ),
      });

      await expectLater(
        session.signIn('mobile', 'wrong'),
        throwsA(
          isA<SignInRejected>().having(
            (e) => e.message,
            'message',
            'This account has not been approved.',
          ),
        ),
      );
    });

    test('falls back to a generic message when no flash is rendered', () async {
      serve({
        '/login': (request) => request.method == 'POST'
            ? const Canned(302, location: 'https://host/login?username=x')
            : Canned(200, body: pageWith()),
      });

      await expectLater(
        session.signIn('x', 'wrong'),
        throwsA(
          isA<SignInRejected>().having(
            (e) => e.message,
            'message',
            contains('not accepted'),
          ),
        ),
      );
    });

    test('a redirect without a username means the token was stale', () async {
      serve({
        '/login': (request) => request.method == 'POST'
            // CSRF failure redirects to the posted URI, with no username.
            ? const Canned(302, location: 'https://host/login')
            : Canned(200, body: pageWith()),
      });

      await expectLater(
        session.signIn('mobile', 'secret'),
        throwsA(isA<StaleSignIn>()),
      );
    });

    test('discriminates correctly on an ugly-URL instance', () async {
      serve({
        '/login': (request) => request.method == 'POST'
            ? const Canned(
                302,
                location:
                    'https://host/index.php?route=%2Flogin&username=mobile',
              )
            : Canned(200, body: pageWith()),
      });
      client.url = client.url.withStyle(UrlStyle.ugly);

      await expectLater(
        session.signIn('mobile', 'wrong'),
        throwsA(isA<SignInRejected>()),
      );
    });

    test('a non-redirect answer is surfaced as unexpected', () async {
      serve({
        '/login': (request) => request.method == 'POST'
            ? const Canned(200)
            : Canned(200, body: pageWith()),
      });

      await expectLater(
        session.signIn('mobile', 'secret'),
        throwsA(isA<UnexpectedResponse>()),
      );
    });

    test('a redirect that does not stick is treated as expiry', () async {
      serve({
        '/login': (request) => request.method == 'POST'
            ? const Canned(302, location: 'https://host/')
            : Canned(200, body: pageWith()),
        '/my-account': (_) => const Canned(302, location: 'https://host/login'),
      });

      await expectLater(
        session.signIn('mobile', 'secret'),
        throwsA(isA<SessionExpired>()),
      );
    });

    test('a missing sign-in form is reported as unreadable', () async {
      serve({'/login': (_) => const Canned(200, body: '<html></html>')});

      await expectLater(
        session.signIn('mobile', 'secret'),
        throwsA(isA<CannotRead>()),
      );
    });
  });

  group('csrfToken', () {
    test('reads the meta tag and caches it', () async {
      serve({'/login': loginPage});

      expect(await session.csrfToken(), 'token-abcdefghijklmnopqrstuvwx');
      expect(await session.csrfToken(), 'token-abcdefghijklmnopqrstuvwx');
      expect(server.routes.where((r) => r == '/login'), hasLength(1));
    });

    test('falls back to the hidden form field', () async {
      serve({
        '/login': (_) => const Canned(
          200,
          body: '<form><input name="_csrf" value="from-field"></form>',
        ),
      });

      expect(await session.csrfToken(), 'from-field');
    });
  });

  group('session state', () {
    test('isSignedIn follows the guarded route', () async {
      serve({'/my-account': (_) => const Canned(200, body: 'account')});
      expect(await session.isSignedIn(), isTrue);

      serve({
        '/my-account': (_) => const Canned(302, location: 'https://host/login'),
      });
      expect(await session.isSignedIn(), isFalse);
    });

    test('signOut needs no token and discards the cached one', () async {
      serve({'/login': loginPage, '/logout': (_) => const Canned(204)});
      await session.csrfToken();

      await session.signOut();

      final post = server.requests.firstWhere((r) => r.route == '/logout');
      expect(post.method, 'POST');
      expect(post.fields.containsKey('_csrf'), isFalse);
      // Asking again must re-fetch rather than reuse the dead token.
      await session.csrfToken();
      expect(server.routes.where((r) => r == '/login'), hasLength(2));
    });

    test('signOut still clears local state when the server fails', () async {
      serve({'/login': loginPage, '/logout': (_) => const Canned(500)});
      await session.csrfToken();

      await session.signOut();

      await session.csrfToken();
      expect(server.routes.where((r) => r == '/login'), hasLength(2));
    });
  });

  group('bot blocking', () {
    test('a 406 is raised wherever it happens', () async {
      serve({
        '/my-account': (_) => const Canned(
          406,
          body: 'Not acceptable: routing',
          contentType: 'text/html',
        ),
      });

      await expectLater(
        session.isSignedIn(),
        throwsA(
          isA<BlockedAsBot>().having((e) => e.reason, 'reason', 'routing'),
        ),
      );
    });
  });
}
