import '../../core/errors.dart';
import '../../core/webtrees_client.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import '../../domain/statistics.dart';
import '../transport.dart';
import 'module_api.dart';
import 'module_decode.dart';

/// Reading the shapes a site draws, through the module.
///
/// A handle here is a module endpoint rather than one of the site's own chart
/// URLs, so nothing in this file rewrites an address to change a setting. A
/// generations count is a query parameter, not a segment of a path that also
/// carries the drawing style an administrator chose.
final class ModuleChartsTransport implements ChartsTransport {
  ModuleChartsTransport(WebtreesClient client, {this.thumbnailSize = 160})
    : _api = ModuleApi(client);

  final ModuleApi _api;
  final int thumbnailSize;

  @override
  Future<ChartData> chart(
    ChartKind kind,
    String handle, {
    required PersonRef subject,
    int? generations,
  }) async {
    if (kind != ChartKind.ancestors && kind != ChartKind.descendants) {
      throw const ParseFailure(
        parser: 'chart',
        expected: 'a chart this app can draw',
      );
    }

    final body = await _api.get(
      handle,
      query: {
        if (generations != null) 'generations': '$generations',
        'thumb': '$thumbnailSize',
      },
      probe: 'drawing the ${kind.name} chart',
    );

    return switch (kind) {
      ChartKind.ancestors => ChartData(
        kind: kind,
        subject: subject,
        ancestors: ancestorFrom(body['tree']),
      ),
      _ => ChartData(
        kind: kind,
        subject: subject,
        descendants: descendantFrom(body['tree']),
      ),
    };
  }

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

  @override
  Future<List<RelationshipPath>> relationship(
    String handle, {
    required String from,
    required String to,
    bool? bloodLinesOnly,
  }) async {
    // The handle names the subject; the other person is appended, exactly as
    // the stock path appends them to the site's own relationship URL.
    final body = await _api.get(
      '$handle/$to',
      query: {
        if (bloodLinesOnly != null) 'ancestors': bloodLinesOnly ? '1' : '0',
        'thumb': '$thumbnailSize',
      },
      probe: 'reading how $from and $to are related',
    );

    // The site's own answer to "does this instance search blood lines only",
    // echoed back so the app can say *why* an empty result is empty rather
    // than showing an unexplained blank screen.
    _lastBloodLinesOnly[handle] = _settingsSay(body);

    final subject = _person(body['from']) ?? PersonRef(xref: from, name: from);

    return [
      for (final path in listOf(body['paths']))
        if (path is Map<String, Object?>)
          RelationshipPath(
            // One phrase for the whole relationship, written by the site —
            // which no app should compose, because Arabic separates an older
            // brother from a younger one and English has no word for it.
            description: stringOf(path['description']) ?? '',
            from: subject,
            steps: [
              for (final step in listOf(path['steps']))
                if (step is Map<String, Object?>)
                  if (_person(step['person']) case final person?)
                    RelationshipStep(
                      relationship: stringOf(step['relationship']) ?? '',
                      person: person,
                      // Absent from module 1.1.1 and older, which answers
                      // [StepDirection.unknown] and draws the path flat
                      // rather than wrongly.
                      direction: StepDirection.fromName(
                        stringOf(step['direction']),
                      ),
                    ),
            ],
          ),
    ];
  }

  /// Whether this site searches blood lines only.
  ///
  /// The module states it in `settings`, so this is a fact once a request has
  /// been made. Before then the honest answer is the site's default, which is
  /// off — and the first request corrects it.
  @override
  bool bloodLinesOnly(String handle) => _lastBloodLinesOnly[handle] ?? false;

  final Map<String, bool> _lastBloodLinesOnly = {};

  @override
  Future<TreeStatistics> statistics(String handle) async {
    final body = await _api.get(handle, probe: 'reading the statistics');

    return statisticsFrom(body);
  }

  @override
  Future<TimelineChart> timeline(String handle) async {
    final body = await _api.get(handle, probe: 'reading the timeline');

    return timelineFrom(body);
  }

  static bool _settingsSay(Map<String, Object?> body) {
    final settings = body['settings'];
    return settings is Map<String, Object?> &&
        settings['bloodLinesOnly'] == true;
  }

  static PersonRef? _person(Object? value) =>
      value is Map<String, Object?> ? personFrom(value) : null;
}
