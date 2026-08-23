/// Talking to the optional `webtrees-mobile-api` module.
///
/// The module is never required. Nothing in this file is reached unless
/// [ModuleCapabilities.probe] found one, and every capability it advertises
/// still has a stock path behind it — see `data/capabilities.dart`.
library;

import 'dart:convert';
import 'dart:developer' as developer;

import '../../core/errors.dart';
import '../../core/response_status.dart';
import '../../core/webtrees_client.dart';

/// The version of the wire contract this app was written against.
///
/// A module answering a different major version is not used at all: the
/// endpoints may have the same names and different meanings, and reading one
/// wrongly is worse than reading HTML correctly.
const int kModuleApiVersion = 1;

/// Where the module lives, if it lives anywhere.
const String kModuleBase = '/mobile-api/v1';

/// What one installation's module says it can do.
///
/// The `features` list is the point. Selecting per capability rather than per
/// release is what lets an old module and a new app agree about everything
/// they both implement, instead of the app refusing the module outright over
/// one endpoint it has not got.
final class ModuleCapabilities {
  ModuleCapabilities({
    required this.apiVersion,
    required this.moduleVersion,
    required this.webtreesVersion,
    required Set<String> features,
    required Set<String> languages,
    this.maxPageSize = 50,
    this.maxGenerations = 10,
    this.maxImage = 800,
  }) : features = Set.unmodifiable(features),
       languages = Set.unmodifiable(languages);

  /// A site with no module, or one this app will not talk to.
  static final ModuleCapabilities none = ModuleCapabilities(
    apiVersion: 0,
    moduleVersion: '',
    webtreesVersion: '',
    features: const {},
    languages: const {},
  );

  final int apiVersion;
  final String moduleVersion;

  /// What the module reports the server to be. Only ever diagnostic — the app
  /// does not change behaviour on it, which is the whole point of `features`.
  final String webtreesVersion;

  final Set<String> features;

  /// Every language tag this site can render in.
  ///
  /// Worth having: the module honours `?lang=` for one request without
  /// writing the account's stored preference, which no stock route can do.
  final Set<String> languages;

  final int maxPageSize;
  final int maxGenerations;
  final int maxImage;

  bool get isPresent => apiVersion == kModuleApiVersion && features.isNotEmpty;

  bool has(String feature) => isPresent && features.contains(feature);

  /// Asks a site what it can do, before signing in.
  ///
  /// Deliberately forgiving. A site with no module answers `404`, an older
  /// module may answer a shape this app has never seen, and a proxy may
  /// answer HTML — none of those is an error, they are all just "no module".
  /// Only the transport failing is worth reporting, and it will be reported
  /// again by the very next request anyway.
  static Future<ModuleCapabilities> probe(WebtreesClient client) async {
    final Reply reply;
    try {
      reply = await client.get('$kModuleBase/capabilities');
    } on WebtreesError catch (problem) {
      developer.log('Module probe failed: $problem', name: _log);
      return none;
    }

    if (!reply.isOk || !reply.isJson) return none;

    final Object? decoded;
    try {
      decoded = jsonDecode(reply.body);
    } on FormatException {
      return none;
    }

    if (decoded is! Map<String, Object?>) return none;

    final capabilities = ModuleCapabilities(
      apiVersion: _int(decoded['api']) ?? 0,
      moduleVersion: _string(decoded['module']) ?? '',
      webtreesVersion: _string(decoded['webtrees']) ?? '',
      features: _strings(decoded['features']),
      languages: _strings(decoded['languages']),
      maxPageSize: _int(_limit(decoded, 'maxPageSize')) ?? 50,
      maxGenerations: _int(_limit(decoded, 'maxGenerations')) ?? 10,
      maxImage: _int(_limit(decoded, 'maxImage')) ?? 800,
    );

    if (capabilities.apiVersion != kModuleApiVersion) {
      developer.log(
        'Module speaks v${capabilities.apiVersion}, app speaks '
        'v$kModuleApiVersion — using the stock transport',
        name: _log,
      );
      return none;
    }

    developer.log(
      'Module ${capabilities.moduleVersion} offers '
      '${capabilities.features.length} capabilities',
      name: _log,
    );
    return capabilities;
  }

  static Object? _limit(Map<String, Object?> body, String name) {
    final limits = body['limits'];
    return limits is Map<String, Object?> ? limits[name] : null;
  }

  static const String _log = 'webtrees.module';
}

/// Fetches and decodes one module endpoint.
///
/// The module states its own status and its own error shape, so unlike the
/// stock transport there is nothing to infer here: a `403` is a refusal, not
/// possibly an expired session redirected to a sign-in page.
final class ModuleApi {
  const ModuleApi(this.client);

  final WebtreesClient client;

  /// A tree-scoped endpoint: `/tree/{tree}/mobile-api/v1/...`.
  Future<Map<String, Object?>> tree(
    String tree,
    String path, {
    Map<String, String> query = const {},
    required String probe,
  }) => get('/tree/$tree$kModuleBase$path', query: query, probe: probe);

  Future<Map<String, Object?>> get(
    String route, {
    Map<String, String> query = const {},
    required String probe,
  }) async {
    final reply = await client.get(route, query: query);

    if (!reply.isOk) throw _failure(reply, probe);

    final Object? decoded;
    try {
      decoded = jsonDecode(reply.body);
    } on FormatException catch (problem) {
      developer.log('Module sent non-JSON: ${problem.message}', name: _log);
      throw ParseFailure(parser: probe, expected: 'a JSON object');
    }

    if (decoded is! Map<String, Object?>) {
      throw ParseFailure(parser: probe, expected: 'a JSON object');
    }

    return decoded;
  }

  /// The module's own error envelope, where it sent one.
  ///
  /// `{"error": "forbidden", "message": "…", "detail": null}` — one shape for
  /// every endpoint, and never a redirect. On webtrees 2.2 a tree that fails
  /// to bind is answered by webtrees' own not-found page instead, so the body
  /// may be HTML; the status still means what it says.
  WebtreesError _failure(Reply reply, String probe) {
    if (reply.isJson) {
      try {
        final body = jsonDecode(reply.body);
        if (body is Map<String, Object?>) {
          final detail = _string(body['message']);
          return switch (_string(body['error'])) {
            'not_signed_in' => const SessionExpired(),
            'forbidden' => NotPermitted(detail: detail),
            'not_found' => NotFound(detail: detail),
            _ => UnexpectedResponse(reply.status, detail: detail),
          };
        }
      } on FormatException {
        // Fall through to the status-only reading below.
      }
    }

    return failureFrom(reply, probe: probe);
  }

  static const String _log = 'webtrees.module';
}

int? _int(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  final String text => int.tryParse(text),
  _ => null,
};

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

Set<String> _strings(Object? value) => value is List
    ? {
        for (final item in value)
          if (item is String) item,
      }
    : const {};
