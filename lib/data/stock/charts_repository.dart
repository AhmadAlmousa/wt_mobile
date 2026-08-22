import 'dart:developer' as developer;

import '../../core/errors.dart';
import '../../core/response_status.dart';
import '../../core/webtrees_client.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import 'chart_parser.dart';

/// Fetches the charts a stock webtrees site draws, and reads their structure.
///
/// Nothing here builds a chart URL. The person's own page states which charts
/// the instance runs and at which address, including the number of
/// generations its administrator settled on — so the app asks for exactly what
/// it was offered, and a site with a chart switched off has no button for it.
final class ChartsRepository {
  ChartsRepository(this._client, {String? version})
    : _parser = ChartParser(version: version);

  final WebtreesClient _client;
  final ChartParser _parser;

  /// Reads the two charts either side of a person and hands back both.
  ///
  /// webtrees draws its own hourglass, but the app never asks for it: that
  /// page is a third layout of the same two families, and stitching the two
  /// charts it already knows how to read costs one request more and no new
  /// parser.
  Future<ChartData> hourglass({
    required String ancestorsUrl,
    required String descendantsUrl,
    required PersonRef subject,
  }) async {
    final up = await chart(ChartKind.ancestors, ancestorsUrl, subject: subject);
    final down = await chart(
      ChartKind.descendants,
      descendantsUrl,
      subject: subject,
    );

    return ChartData(
      kind: ChartKind.hourglass,
      subject: subject,
      ancestors: up.ancestors,
      descendants: down.descendants,
    );
  }

  /// Reads one chart for [subject], at the URL the site gave for it.
  Future<ChartData> chart(
    ChartKind kind,
    String url, {
    required PersonRef subject,
  }) async {
    // The hourglass is stitched from the other two rather than fetched.
    if (kind != ChartKind.ancestors && kind != ChartKind.descendants) {
      throw ParseFailure(
        parser: 'chart',
        expected: 'a chart this app can draw',
        version: _parser.version,
      );
    }

    final body = await _fragment(url, probe: 'drawing the ${kind.name} chart');

    return switch (kind) {
      ChartKind.ancestors => ChartData(
        kind: kind,
        subject: subject,
        ancestors: _parser.parseAncestors(body),
      ),
      _ => ChartData(
        kind: kind,
        subject: subject,
        descendants: _parser.parseDescendants(body),
      ),
    };
  }

  /// Reads how two people are related, along the site's own path between them.
  ///
  /// This is the one address the app *edits* rather than uses as it arrived.
  /// A relationship route ends `relationships-{ancestors}-{recursion}/{xref}`
  /// and takes an optional second xref after it, and the page only ever links
  /// to one person at a time — so the second is put there by the app. Every
  /// other part of the URL, the two settings included, is left exactly as the
  /// site wrote it.
  Future<List<RelationshipPath>> relationship(
    String url, {
    required String from,
    required String to,
  }) async {
    final route = _client.url.routeOf(url);
    final shape = RegExp(
      r'^(.*/relationships-[^/]+/)[^/]+(?:/[^/]+)?$',
    ).firstMatch(route);
    if (shape == null) {
      throw ParseFailure(
        parser: 'relationship chart',
        expected: 'a route ending relationships-{ancestors}-{recursion}/{xref}',
        version: _parser.version,
      );
    }

    final body = await _fragment(
      '${shape.group(1)}$from/$to',
      probe: 'reading how $from and $to are related',
    );
    return _parser.parseRelationships(body, from: from);
  }

  /// Whether a site's own settings keep this chart to blood relations.
  ///
  /// The first number in `relationships-{ancestors}-{recursion}` is that
  /// setting, and this project's own target has it on — so two people linked
  /// only by a marriage answer "no link", which is correct and would
  /// otherwise look like a failure.
  static bool bloodLinesOnly(String url) {
    final match = RegExp(
      r'/relationships-(\d+)-\d+',
    ).firstMatch(Uri.decodeFull(url));
    return match != null && match.group(1) != '0';
  }

  /// Fetches a chart, asking for the chart alone.
  ///
  /// Every chart route answers the whole page by default and the chart on its
  /// own when asked with `ajax=1` — which is what the site's own JavaScript
  /// does, because the page it would otherwise send holds a form, a menu and
  /// a footer the app has no use for.
  Future<String> _fragment(String url, {required String probe}) async {
    final route = _client.url.routeOf(url);
    final parsed = Uri.parse(Uri.decodeFull(url));

    var reply = await _client.get(
      route,
      query: {
        for (final entry in parsed.queryParameters.entries)
          if (entry.key != 'route') entry.key: entry.value,
        'ajax': '1',
      },
      headers: const {'X-Requested-With': 'XMLHttpRequest'},
    );

    // A chart URL carries the person's xref, so it has no slug to be
    // redirected to; a permanent redirect here is a site that moved, and
    // following it once costs nothing.
    if (reply.status == 301 || reply.status == 308) {
      final target = _client.url.routeOf(reply.location ?? '');
      if (target.isNotEmpty) reply = await _client.get(target);
    }

    if (!reply.isOk) {
      developer.log('Chart answered ${reply.status}', name: _log, level: 900);
      throw failureFrom(reply, probe: probe);
    }
    return reply.body;
  }

  static const String _log = 'webtrees.charts';
}
