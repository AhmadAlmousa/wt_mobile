/// One page of the sync wire, and where a page comes from.
///
/// The wire is `GET /tree/{t}/mobile-api/v1/records` (module 1.3.0 and later).
/// Its contract is stated in the module's own README and the three rules a
/// client cannot be made to keep are repeated here, next to the code that
/// keeps them.
library;

import 'dart:convert';

import '../../core/errors.dart';
import '../module/module_api.dart';

/// A page of records, or the server refusing to describe a path from where the
/// client is.
final class RecordsPage {
  const RecordsPage({
    required this.token,
    required this.offset,
    required this.limit,
    required this.total,
    required this.hasMore,
    required this.resync,
    required this.sections,
    required this.chartClasses,
    required this.people,
    required this.deleted,
  });

  /// The server's fingerprint of the tree **as it is now**, which is not
  /// necessarily as it was when the walk started. Opaque: stored, sent back,
  /// compared for equality, never read into.
  final String token;

  final int offset;
  final int limit;

  /// How many records this walk is about: the tree's own count of individuals
  /// on a full walk — before privacy, so an upper bound — and the exact number
  /// of affected people on a delta. [hasMore] is the precise statement in both.
  final int total;

  final bool hasMore;

  /// Start again with no `since`. Not an error: the client's fingerprint names
  /// a state this tree can no longer describe a path from, which is almost
  /// always a re-import.
  final bool resync;

  /// Which tabs this site runs and which charts it offers — stated once for
  /// the page because they describe the tree and not anybody in it.
  final List<String> sections;
  final List<String> chartClasses;

  /// Each person's record, exactly as it arrived. Not decoded here: the store
  /// keeps these bytes, and decoding them is the reader's job.
  final List<Map<String, Object?>> people;

  /// Records gone from the tree, or no longer visible to this reader — for one
  /// reader's copy of a tree the same instruction. Whole rather than paged, so
  /// applying it twice is the same as applying it once.
  final List<String> deleted;

  static RecordsPage fromJson(Map<String, Object?> json) => RecordsPage(
    token: json['token'] is String ? json['token'] as String : '',
    offset: _int(json['offset']) ?? 0,
    limit: _int(json['limit']) ?? 0,
    total: _int(json['total']) ?? 0,
    hasMore: json['hasMore'] == true,
    resync: json['resync'] == true,
    sections: _strings(json['sections']),
    chartClasses: _strings(json['charts']),
    people: [
      for (final person
          in json['people'] is List ? json['people'] as List : const [])
        if (person is Map<String, Object?>) person,
    ],
    deleted: _strings(json['deleted']),
  );

  static List<String> _strings(Object? value) => [
    for (final item in value is List ? value : const [])
      if (item is String) item,
  ];

  static int? _int(Object? value) => switch (value) {
    final int number => number,
    final num number => number.toInt(),
    final String text => int.tryParse(text),
    _ => null,
  };
}

/// Where pages come from.
///
/// An interface with one method, for one reason: a sync engine tested against
/// a real server is tested once a day, and a sync engine tested against a fake
/// one is tested on every commit. The behaviour worth testing — resuming,
/// tombstones, a fingerprint the server refuses — is all in the engine.
abstract interface class SyncSource {
  Future<RecordsPage> records(
    String tree, {
    required int offset,
    required int limit,
    String? since,
  });
}

/// The module's own sync endpoint.
final class ModuleSyncSource implements SyncSource {
  const ModuleSyncSource(this._api, {this.thumbnailSize = 160});

  final ModuleApi _api;

  /// The size of portrait to have signed. Stored URLs outlive the sync — the
  /// signature has no expiry — so this is the size the app will show for as
  /// long as the store lives.
  final int thumbnailSize;

  @override
  Future<RecordsPage> records(
    String tree, {
    required int offset,
    required int limit,
    String? since,
  }) async {
    final body = await _api.tree(
      tree,
      '/records',
      query: {
        'offset': '$offset',
        'limit': '$limit',
        'thumb': '$thumbnailSize',
        if (since != null && since.isNotEmpty) 'since': since,
      },
      probe: 'syncing $tree',
    );

    return RecordsPage.fromJson(body);
  }
}

/// The bytes of one record, as they will be stored.
///
/// `jsonEncode` of what arrived, which is not quite the bytes that arrived —
/// key order survives, but whitespace and escaping are Dart's. That is the
/// right trade: what has to be preserved is the *value*, and re-encoding it
/// through one function means a stored record and a fetched one decode
/// identically.
String payloadOf(Map<String, Object?> person) => jsonEncode(person);

/// Reads a stored payload back.
Map<String, Object?> personFromPayload(String payload) {
  final decoded = jsonDecode(payload);

  if (decoded is! Map<String, Object?>) {
    throw ParseFailure(parser: 'a stored record', expected: 'a JSON object');
  }

  return decoded;
}
