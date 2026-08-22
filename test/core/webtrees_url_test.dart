import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/webtrees_url.dart';

void main() {
  group('WebtreesUrl.normalize', () {
    test('assumes https when no scheme is given', () {
      expect(
        WebtreesUrl.normalize('tree.example.com').toString(),
        'https://tree.example.com',
      );
    });

    test('keeps an explicit http scheme', () {
      expect(
        WebtreesUrl.normalize('http://192.168.1.10:8080').toString(),
        'http://192.168.1.10:8080',
      );
    });

    test('strips trailing slashes', () {
      expect(
        WebtreesUrl.normalize('https://tree.example.com///').toString(),
        'https://tree.example.com',
      );
    });

    test('strips a pasted index.php', () {
      expect(
        WebtreesUrl.normalize('https://host/wt/index.php').toString(),
        'https://host/wt',
      );
    });

    test('preserves a subdirectory prefix', () {
      expect(
        WebtreesUrl.normalize('https://host/genealogy/').toString(),
        'https://host/genealogy',
      );
    });

    test('leaves no empty query or fragment behind', () {
      final uri = WebtreesUrl.normalize('https://host/wt?a=1#top');
      expect(uri.hasQuery, isFalse);
      expect(uri.hasFragment, isFalse);
      expect(uri.toString(), 'https://host/wt');
    });

    test('rejects blank, hostless and non-http input', () {
      expect(() => WebtreesUrl.normalize('   '), throwsFormatException);
      expect(() => WebtreesUrl.normalize('https://'), throwsFormatException);
      expect(
        () => WebtreesUrl.normalize('ftp://host/wt'),
        throwsFormatException,
      );
    });
  });

  group('route building', () {
    final pretty = WebtreesUrl(
      base: Uri.parse('https://host'),
      style: UrlStyle.pretty,
    );
    final ugly = WebtreesUrl(
      base: Uri.parse('https://host'),
      style: UrlStyle.ugly,
    );
    final subdir = WebtreesUrl(
      base: Uri.parse('https://host/wt'),
      style: UrlStyle.ugly,
    );

    test('pretty style appends the route to the path', () {
      expect(pretty('/login').toString(), 'https://host/login');
    });

    test('ugly style puts the route in a query parameter', () {
      expect(
        ugly('/login').toString(),
        'https://host/index.php?route=%2Flogin',
      );
    });

    test('the root route keeps a single trailing slash', () {
      expect(pretty('/').toString(), 'https://host/');
      final nested = WebtreesUrl(
        base: Uri.parse('https://host/wt'),
        style: UrlStyle.pretty,
      );
      expect(nested('/').toString(), 'https://host/wt/');
    });

    test('extra parameters survive both styles', () {
      expect(
        pretty('/tree/main/pending', {'page': '2'}).toString(),
        'https://host/tree/main/pending?page=2',
      );
      final result = ugly('/tree/main/pending', {'page': '2'});
      expect(result.queryParameters['route'], '/tree/main/pending');
      expect(result.queryParameters['page'], '2');
    });

    test('a subdirectory prefix is applied once', () {
      expect(subdir('/ping').path, '/wt/index.php');
      expect(subdir('/ping').queryParameters['route'], '/ping');
    });
  });

  group('routeOf', () {
    final subdir = WebtreesUrl(
      base: Uri.parse('https://host/wt'),
      style: UrlStyle.pretty,
    );

    test('reads a pretty URL and strips the prefix', () {
      expect(subdir.routeOf('https://host/wt/my-account'), '/my-account');
    });

    test('reads an ugly URL regardless of the configured style', () {
      expect(
        subdir.routeOf('https://host/wt/index.php?route=/my-account'),
        '/my-account',
      );
    });

    test('tolerates empty and unparseable input', () {
      expect(subdir.routeOf(''), '');
    });
  });

  group('treeOf', () {
    final url = WebtreesUrl(
      base: Uri.parse('https://host'),
      style: UrlStyle.pretty,
    );

    test('extracts the tree from a record URL', () {
      expect(url.treeOf('https://host/tree/main/individual/X1'), 'main');
    });

    test('extracts the tree from an ugly URL', () {
      expect(
        url.treeOf('https://host/index.php?route=/tree/main/pending'),
        'main',
      );
    });

    test('decodes a percent-encoded tree name', () {
      expect(url.treeOf('https://host/tree/my%20tree'), 'my tree');
    });

    test('returns null when there is no tree segment', () {
      expect(url.treeOf('https://host/my-account'), isNull);
      expect(url.treeOf('https://host/'), isNull);
    });
  });
}
