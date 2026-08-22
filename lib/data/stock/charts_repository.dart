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

  /// Reads one chart for [subject], at the URL the site gave for it.
  Future<ChartData> chart(
    ChartKind kind,
    String url, {
    required PersonRef subject,
  }) async {
    if (!ChartKind.drawable.contains(kind)) {
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
