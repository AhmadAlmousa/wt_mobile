import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'errors.dart';
import 'webtrees_url.dart';

/// The app's version, as it appears to site administrators.
///
/// Kept in step with `version:` in `pubspec.yaml`. It reaches every webtrees
/// log this app writes to, so a build that misreports itself makes those logs
/// misleading to the person reading them.
const String kAppVersion = '0.21.0';

/// The User-Agent this app identifies itself with.
///
/// webtrees blocks about 1,400 User-Agent substrings, case-sensitively, and
/// two rules make the choice delicate:
///
/// * Very short entries are on the list — `aa` among them — so an innocuous
///   product name can be blocked outright.
/// * Any agent containing `Chrome/`, `Firefox/`, `Safari/` or `Opera/` is
///   served a cookie-challenge stub instead of the page it asked for, so
///   impersonating a browser actively breaks sign-in.
///
/// The enforced list is public at `/robots.txt`; [BotListCheck] verifies this
/// string against the live one when connecting.
const String kUserAgent = 'WebtreesMobile/$kAppVersion (Flutter)';

/// Marks a request that deliberately carries no session.
const String anonymousRequest = 'webtrees.anonymous';

/// One HTTP response, reduced to what the app interprets.
final class Reply {
  const Reply({
    required this.status,
    required this.body,
    required this.location,
    required this.contentType,
  });

  final int status;
  final String body;

  /// The `Location` header, present on the 3xx responses webtrees uses to
  /// signal sign-in success, sign-in failure and access denial.
  final String? location;

  final String? contentType;

  bool get isOk => status == 200;
  bool get isRedirect => status >= 300 && status < 400;
  bool get isJson => contentType?.contains('application/json') ?? false;
}

/// A binary response, for media.
final class BytesReply {
  const BytesReply({
    required this.status,
    required this.bytes,
    required this.contentType,
  });

  final int status;
  final Uint8List bytes;
  final String? contentType;

  bool get isOk => status == 200;
  bool get isRedirect => status >= 300 && status < 400;
}

/// Talks HTTP to one webtrees instance.
///
/// Redirects are never followed automatically. webtrees encodes meaning in
/// them — a sign-in answers 302 whether it succeeded or failed, and the
/// success response also carries a rotated session cookie that would be lost
/// if the client chased the redirect itself.
class WebtreesClient {
  WebtreesClient({
    required this.url,
    required CookieJar cookies,
    Dio? dio,
    String userAgent = kUserAgent,
  }) : _cookies = cookies,
       _userAgent = userAgent,
       _dio = dio ?? Dio() {
    _dio.options = _optionsFor(userAgent);
    _dio.interceptors.add(CookieManager(cookies));
  }

  /// The instance address and URL style. Replaced once the style is detected.
  WebtreesUrl url;

  final Dio _dio;
  final CookieJar _cookies;
  final String _userAgent;

  static BaseOptions _optionsFor(String userAgent) => BaseOptions(
    followRedirects: false,
    // 3xx and 4xx are meaningful answers here, not transport failures.
    validateStatus: (_) => true,
    responseType: ResponseType.plain,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'User-Agent': userAgent, 'Accept': '*/*'},
  );

  Future<Reply> get(
    String route, {
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
  }) => _send(
    () => _dio.getUri<String>(
      url(route, query),
      options: Options(headers: headers.isEmpty ? null : headers),
    ),
  );

  /// Fetches binary content — an image — through the signed-in session.
  ///
  /// Separate from [get] because the response must not be decoded as text.
  /// Media is the one thing this app fetches that is not markup, and it still
  /// has to travel over the authenticated session: webtrees checks the current
  /// user's permission on every thumbnail, signed URL or not.
  Future<BytesReply> getBytes(
    String route, {
    Map<String, String> query = const {},
  }) async {
    final Response<List<int>> response;
    try {
      response = await _dio.getUri<List<int>>(
        url(route, query),
        options: Options(responseType: ResponseType.bytes),
      );
    } on DioException catch (error) {
      throw _asWebtreesError(error);
    }

    return BytesReply(
      status: response.statusCode ?? 0,
      bytes: Uint8List.fromList(response.data ?? const []),
      contentType: response.headers.value('content-type'),
    );
  }

  /// Submits an `application/x-www-form-urlencoded` body.
  ///
  /// Every webtrees POST except sign-out, language and theme is CSRF-checked,
  /// so [fields] normally carries a `_csrf` value.
  Future<Reply> postForm(
    String route,
    Map<String, String> fields, {
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
  }) => _send(
    () => _dio.postUri<String>(
      url(route, query),
      data: fields,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: headers.isEmpty ? null : headers,
      ),
    ),
  );

  /// Issues a request that carries no session cookie and keeps none.
  ///
  /// Used to ask what an anonymous visitor can see — for instance whether a
  /// tree is private. A shared jar would let the server's fresh anonymous
  /// session overwrite the signed-in one, so this runs on its own client.
  Future<Reply> getAnonymous(
    String route, {
    Map<String, String> query = const {},
  }) async {
    // Same transport, minus the cookie interceptor: the point is to drop the
    // session, not to change how bytes travel. Sharing the adapter is safe —
    // cookies live in the interceptor, not the connection pool — and it keeps
    // this path exercisable by a test double.
    //
    // This wrapper must never be closed: `Dio.close()` closes the adapter it
    // holds, which here belongs to the main client and is still in use.
    final dio = Dio(_optionsFor(_userAgent))
      ..httpClientAdapter = _dio.httpClientAdapter;

    return _send(
      () => dio.getUri<String>(
        url(route, query),
        // Never transmitted; lets a test double recognise the intent.
        options: Options(extra: const {anonymousRequest: true}),
      ),
    );
  }

  Future<void> clearCookies() => _cookies.deleteAll();

  void close() => _dio.close(force: true);

  Future<Reply> _send(Future<Response<String>> Function() request) async {
    final Response<String> response;
    try {
      response = await request();
    } on DioException catch (error) {
      throw _asWebtreesError(error);
    }

    final reply = Reply(
      status: response.statusCode ?? 0,
      body: response.data ?? '',
      location: response.headers.value('location'),
      contentType: response.headers.value('content-type'),
    );

    _guardBotBlock(reply);
    return reply;
  }

  /// webtrees answers 406 with a body of `Not acceptable: <reason>` when its
  /// bad-bot filter fires. That is never a per-route problem, so it is raised
  /// here rather than left for each caller to notice.
  void _guardBotBlock(Reply reply) {
    if (reply.status != 406) return;
    const prefix = 'Not acceptable:';
    if (!reply.body.startsWith(prefix)) return;

    final reason = reply.body.substring(prefix.length).trim();
    developer.log(
      'Blocked by bad-bot filter: $reason',
      name: 'webtrees.http',
      level: 900,
    );
    throw BlockedAsBot(reason);
  }

  WebtreesError _asWebtreesError(DioException error) {
    final host = url.base.host;
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => UnreachableHost(
        host,
        detail: 'The site took too long to respond',
      ),
      DioExceptionType.badCertificate => UnreachableHost(
        host,
        detail: 'Its security certificate could not be verified',
      ),
      DioExceptionType.connectionError || DioExceptionType.unknown =>
        UnreachableHost(host, detail: _summarize(error)),
      DioExceptionType.cancel => const UnreachableHost('the site'),
      DioExceptionType.badResponse => UnexpectedResponse(
        error.response?.statusCode ?? 0,
      ),
    };
  }

  static String? _summarize(DioException error) {
    final cause = error.error;
    if (cause == null) return null;
    final text = cause.toString();
    final match = RegExp(r'\(OS Error: ([^,)]+)').firstMatch(text);
    return match?.group(1);
  }
}
