import 'dart:developer' as developer;

import 'package:html/parser.dart' as html;

import '../../core/errors.dart';
import '../../core/response_status.dart';
import '../../core/webtrees_client.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import '../../domain/statistics.dart';
import '../transport.dart';
import 'chart_parser.dart';
import 'dom.dart';
import 'statistics_parser.dart';

/// Fetches the charts a stock webtrees site draws, and reads their structure.
///
/// Nothing here builds a chart URL. The person's own page states which charts
/// the instance runs and at which address, including the number of
/// generations its administrator settled on — so the app asks for exactly what
/// it was offered, and a site with a chart switched off has no button for it.
final class ChartsRepository implements ChartsTransport {
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
  @override
  Future<ChartData> hourglass({
    required String ancestorsHandle,
    required String descendantsHandle,
    required PersonRef subject,
    int? generations,
  }) async {
    final up = await chart(
      ChartKind.ancestors,
      ancestorsHandle,
      subject: subject,
      generations: generations,
    );
    final down = await chart(
      ChartKind.descendants,
      descendantsHandle,
      subject: subject,
      generations: generations,
    );

    return ChartData(
      kind: ChartKind.hourglass,
      subject: subject,
      ancestors: up.ancestors,
      descendants: down.descendants,
    );
  }

  /// Reads one chart for [subject], at the URL the site gave for it.
  ///
  /// [generations] replaces the number the site's own link carries — see
  /// [withGenerations]. Null asks for exactly what was offered.
  @override
  Future<ChartData> chart(
    ChartKind kind,
    String url, {
    required PersonRef subject,
    int? generations,
  }) async {
    // The hourglass is stitched from the other two rather than fetched.
    if (kind != ChartKind.ancestors && kind != ChartKind.descendants) {
      throw ParseFailure(
        parser: 'chart',
        expected: 'a chart this app can draw',
        version: _parser.version,
      );
    }

    final body = await _fragment(
      withGenerations(url, generations),
      probe: 'drawing the ${kind.name} chart',
    );

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
  /// A relationship route ends `relationships-{ancestors}-{recursion}/{xref}`
  /// and takes an optional second xref after it, and the page only ever links
  /// to one person at a time — so the second is put there by the app.
  ///
  /// [bloodLinesOnly] replaces the first of those two numbers. It is worth
  /// changing because the handler reads it **straight off the route**:
  /// `Validator::attributes(...)->integer('ancestors')`, with the tree's
  /// own `RELATIONSHIP_ANCESTORS` preference used only to fill in the form on
  /// the page it does not send. So a site set to search blood lines only —
  /// which this project's own target is — can still be asked "any
  /// relationship", and that is the only way a link through a marriage can be
  /// found at all.
  ///
  /// Null leaves the site's own setting alone. The recursion beside it is
  /// never touched: that one *is* clamped, by `min(recursion,
  /// max_recursion)`, and it is what stops a deep search costing the server a
  /// minute.
  @override
  Future<List<RelationshipPath>> relationship(
    String url, {
    required String from,
    required String to,
    bool? bloodLinesOnly,
  }) async {
    final route = _client.url.routeOf(url);
    final shape = RegExp(
      r'^(.*/relationships-)(\d+)(-\d+/)[^/]+(?:/[^/]+)?$',
    ).firstMatch(route);
    if (shape == null) {
      throw ParseFailure(
        parser: 'relationship chart',
        expected: 'a route ending relationships-{ancestors}-{recursion}/{xref}',
        version: _parser.version,
      );
    }

    final ancestors = switch (bloodLinesOnly) {
      null => shape.group(2)!,
      true => '1',
      false => '0',
    };

    final body = await _fragment(
      '${shape.group(1)}$ancestors${shape.group(3)}$from/$to',
      probe: 'reading how $from and $to are related',
    );
    return _parser.parseRelationships(body, from: from);
  }

  /// Reads a site's statistics page: its counts, and the data behind its own
  /// charts.
  ///
  /// The page itself holds nothing but tabs; each one names a fragment where
  /// the numbers actually are, exactly as a record's tabs do. A tab that
  /// yields no sections — webtrees offers one for *building* a chart rather
  /// than showing one — simply contributes nothing.
  @override
  Future<TreeStatistics> statistics(String url) async {
    final page = await _fragment(url, probe: 'reading the statistics');
    final document = html.parse(page);

    final parts = <StatisticPart>[];
    for (final tab in document.querySelectorAll('a[data-wt-href]')) {
      final href = tab.attributes['data-wt-href'];
      if (href == null) continue;

      final body = await _fragment(href, probe: 'reading the statistics');
      final sections = const StatisticsParser().parseSections(body);
      if (sections.isEmpty) continue;

      parts.add(StatisticPart(title: textOf(tab) ?? '', sections: sections));
    }
    return TreeStatistics(parts: parts);
  }

  /// Reads a timeline: a person's events against a scale of years.
  ///
  /// The address comes from the page as every other does, and already carries
  /// the person it is for — webtrees' own menu link puts them in the query as
  /// `xrefs[0]`, because a timeline can hold several people at once.
  @override
  Future<TimelineChart> timeline(String url) async {
    final body = await _fragment(url, probe: 'reading the timeline');
    return _parser.parseTimeline(body);
  }

  /// [url] with its generations count replaced.
  ///
  /// An ancestors or descendants route ends
  /// `{kind}-{style}-{generations}/{xref}`, and webtrees reads that segment
  /// straight off the route — `isBetween(2, 63)`, with no tree preference
  /// narrowing it — so asking for a different depth is a legitimate request
  /// rather than a trick. Everything else in the address, the drawing style
  /// the administrator chose included, is left exactly as the site wrote it.
  ///
  /// Rewritten in the address itself rather than in the decoded route,
  /// because the two URL styles differ only in how the *slashes* are written:
  /// `ancestors-tree-4` appears verbatim in both `/tree/main/ancestors-tree-4/X42`
  /// and `index.php?route=%2Ftree%2Fmain%2Fancestors-tree-4%2FX42`, so one
  /// rule serves both and nothing else in the address is disturbed.
  ///
  /// Answers [url] unchanged when [generations] is null or the address is not
  /// that shape: a site whose links look different keeps the number its
  /// administrator chose, which is the right answer rather than a failure.
  static String withGenerations(String url, int? generations) {
    if (generations == null) return url;
    return url.replaceFirstMapped(
      _generationsSegment,
      (match) => '${match.group(1)}$generations',
    );
  }

  static final RegExp _generationsSegment = RegExp(
    r'((?:ancestors|descendants|pedigree|hourglass)-[A-Za-z0-9_]+-)\d+',
  );

  /// Whether a site's own settings keep this chart to blood relations.
  ///
  /// The first number in `relationships-{ancestors}-{recursion}` is that
  /// setting, and this project's own target has it on — so two people linked
  /// only by a marriage answer "no link", which is correct and would
  /// otherwise look like a failure.
  @override
  bool bloodLinesOnly(String url) {
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
