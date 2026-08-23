/// What the app needs from a webtrees instance, said once, without saying how.
///
/// Two implementations answer these: `data/stock/`, which reads the HTML any
/// instance already publishes, and `data/module/`, which reads JSON from the
/// optional `webtrees-mobile-api` module. **Neither is privileged.** The stock
/// path is the floor and stays permanently — the first constraint in this
/// project is that the app works against an untouched instance — and the
/// module is a faster, more truthful road over the same ground.
///
/// Selection happens per *capability*, not globally: a site running an older
/// module still gets the fast path for whatever it does implement, and the
/// stock path answers the rest. `data/capabilities.dart` does the composing.
library;

import 'dart:typed_data';

import '../domain/access.dart';
import '../domain/charts.dart';
import '../domain/records.dart';
import '../domain/statistics.dart';

/// One page of search results, and whether more exist.
final class SearchPage {
  const SearchPage({required this.people, required this.hasMore});

  final List<PersonRef> people;

  /// Exact rather than inferred from a full page: both transports are asked
  /// in a way that answers it — webtrees' autocomplete states it, and the
  /// module fetches one row beyond the page.
  final bool hasMore;
}

/// Reading people, and the pictures of them.
abstract interface class RecordsTransport {
  /// Finds people in [tree] by name or xref, 50 or so at a time from [page].
  Future<SearchPage> search(String tree, String query, {int page = 1});

  /// The charts this site offers for the tree as a whole, by kind.
  ///
  /// The values are **handles**, not addresses the app composes. For the stock
  /// transport a handle is the URL the site itself wrote, settings and all;
  /// for the module it is a module endpoint. Either way the app passes it back
  /// unread, which is what lets one set of screens drive both.
  Future<Map<ChartKind, String>> treeCharts(String tree);

  /// Everything one person's record says.
  Future<IndividualRecord> individual(String tree, String xref);

  /// The bytes behind a signed image URL, fetched through the session.
  ///
  /// Not a capability either transport can drop: a thumbnail URL is
  /// HMAC-signed with a server-side key, and `MediaFileThumbnail` checks the
  /// viewer's own permission *before* validating the signature and picks
  /// watermarking from the same answer. The module can mint a URL at any size;
  /// the bytes still come back this way.
  Future<Uint8List> image(String url);
}

/// Reading the shapes a site draws: pedigrees, paths, scales and counts.
///
/// Every method takes a handle from [RecordsTransport.treeCharts] or from
/// [IndividualRecord.charts]. Nothing here builds one.
abstract interface class ChartsTransport {
  /// One chart, at [handle], drawn around [subject].
  ///
  /// [generations] asks for a different depth than the site offered. Null
  /// takes what was offered, which for the stock transport means the number
  /// the administrator settled on.
  Future<ChartData> chart(
    ChartKind kind,
    String handle, {
    required PersonRef subject,
    int? generations,
  });

  /// Ancestors and descendants of one person, stitched at the middle.
  Future<ChartData> hourglass({
    required String ancestorsHandle,
    required String descendantsHandle,
    required PersonRef subject,
    int? generations,
  });

  /// Every way [from] and [to] are related.
  ///
  /// [bloodLinesOnly] overrides the site's own setting; null leaves it alone.
  Future<List<RelationshipPath>> relationship(
    String handle, {
    required String from,
    required String to,
    bool? bloodLinesOnly,
  });

  /// Whether this site's own settings keep a relationship to blood lines.
  ///
  /// Worth asking rather than assuming: with it on, two people linked only by
  /// a marriage answer *no link found*, which is correct and looks exactly
  /// like a failure unless the reader is told.
  bool bloodLinesOnly(String handle);

  /// What a site says about the whole tree.
  Future<TreeStatistics> statistics(String handle);

  /// A life against a scale of years.
  Future<TimelineChart> timeline(String handle);
}

/// Who is signed in, and what they may do.
abstract interface class AccessTransport {
  Future<AccessSummary> describe();
}
