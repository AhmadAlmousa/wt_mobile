import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../domain/statistics.dart';
import 'dom.dart';

/// Reads a webtrees statistics page.
///
/// Two things are worth taking, and they arrive by different roads. The counts
/// are in the markup, rendered by the server in the reader's own numerals. The
/// data behind each chart is in a `<script>` beside it, written as JSON for a
/// JavaScript charting library — plain numbers, because nobody was meant to
/// read them. The app draws its own charts from the second and shows the first
/// as it arrived.
final class StatisticsParser {
  const StatisticsParser();

  /// Reads one tab of the statistics page.
  List<StatisticSection> parseSections(String fragment) {
    final document = html.parseFragment(fragment);
    final sections = <StatisticSection>[];

    var title = '';
    String? total;
    var items = <StatisticItem>[];
    var datasets = <StatisticDataset>[];

    void finish() {
      final section = StatisticSection(
        title: title,
        total: total,
        items: items,
        datasets: datasets,
      );
      if (title.isNotEmpty && !section.isEmpty) sections.add(section);
      items = [];
      datasets = [];
      total = null;
    }

    for (final element in document.querySelectorAll('h4, h5, script')) {
      switch (element.localName) {
        case 'h4':
          // A heading starts a section, and often carries the figure for the
          // whole of it — "Total individuals 1,463".
          finish();
          title = _labelOf(element) ?? '';
          total = _badgeOf(element);
        case 'h5':
          final label = _labelOf(element);
          if (label != null) {
            items.add(StatisticItem(label: label, value: _badgeOf(element)));
          }
        case 'script':
          datasets.addAll(_datasetsIn(element.text));
      }
    }
    finish();

    return sections;
  }

  /// A heading's words, without the count webtrees pins to the end of it.
  String? _labelOf(Element heading) => textWithout(heading, const ['.badge']);

  String? _badgeOf(Element heading) => textOf(heading.querySelector('.badge'));

  /// Every dataset a script hands to the site's charting library.
  ///
  /// The call is `statistics.drawPieChart("id", [[…]], {…})`, and both of the
  /// interesting arguments are JSON — so they are read as JSON rather than
  /// picked apart with a pattern.
  List<StatisticDataset> _datasetsIn(String script) {
    final datasets = <StatisticDataset>[];

    for (final call in RegExp(
      r'statistics\.draw(\w+?)Chart\s*\(',
    ).allMatches(script)) {
      final arguments = _argumentsAt(script, call.end);
      if (arguments.length < 2) continue;

      final Object? data;
      try {
        data = jsonDecode(arguments[1]);
      } on FormatException {
        continue;
      }
      if (data is! List || data.isEmpty) continue;

      // The data is always JSON; the options beside it are not. webtrees
      // writes some of them by hand, comments and unquoted keys included, so
      // the title is looked for rather than decoded — and a chart whose
      // options cannot be read is still a chart worth drawing.
      final title = arguments.length > 2 ? _titleIn(arguments[2]) : null;

      final columns = [
        for (final cell in data.first is List ? data.first as List : const [])
          '$cell',
      ];
      final rows = <StatisticRow>[];
      for (final row in data.skip(1)) {
        if (row is! List || row.isEmpty) continue;
        rows.add(
          StatisticRow(
            label: _cellLabel(row.first),
            values: [
              for (final cell in row.skip(1))
                if (cell is num) cell.toDouble(),
            ],
          ),
        );
      }

      datasets.add(
        StatisticDataset(
          title: title ?? (columns.isEmpty ? '' : columns.first),
          shape: StatisticShape.fromCall(call.group(1)!),
          columns: columns,
          rows: rows,
        ),
      );
    }
    return datasets;
  }

  /// What a data cell calls itself.
  ///
  /// Usually a string. A map chart names each place twice — `{"v": "KW", "f":
  /// "الكويت"}` — the code it plots by and the name it shows, and it is the
  /// name a reader wants.
  static String _cellLabel(Object? cell) {
    if (cell is Map) return '${cell['f'] ?? cell['v'] ?? ''}';
    return '$cell';
  }

  /// The chart's own title, however its options were written.
  String? _titleIn(String options) {
    try {
      final decoded = jsonDecode(options);
      if (decoded is Map && decoded['title'] is String) {
        return decoded['title'] as String;
      }
    } on FormatException {
      // Hand-written options: read the title the way it was typed.
    }

    final match = RegExp(
      r'"?title"?\s*:\s*"((?:[^"\\]|\\.)*)"',
    ).firstMatch(options);
    if (match == null) return null;
    // The value is a JSON string wherever it came from, so it is unescaped
    // as one — `\u0645` and all.
    try {
      return jsonDecode('"${match.group(1)}"') as String;
    } on FormatException {
      return match.group(1);
    }
  }

  /// The arguments of a call, split where the commas between them are.
  ///
  /// Written by hand because the arguments are JSON values that contain both
  /// commas and brackets of their own — a pattern that stopped at the first
  /// comma would cut a dataset in half.
  List<String> _argumentsAt(String script, int start) {
    final arguments = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    var quoted = false;
    var escaped = false;

    for (var index = start; index < script.length; index++) {
      final character = script[index];

      if (escaped) {
        buffer.write(character);
        escaped = false;
        continue;
      }
      if (quoted) {
        buffer.write(character);
        if (character == r'\') escaped = true;
        if (character == '"') quoted = false;
        continue;
      }

      switch (character) {
        case '"':
          quoted = true;
          buffer.write(character);
        case '[' || '{':
          depth++;
          buffer.write(character);
        case ']' || '}':
          depth--;
          buffer.write(character);
        case ',' when depth == 0:
          arguments.add(buffer.toString().trim());
          buffer.clear();
        case ')' when depth == 0:
          final last = buffer.toString().trim();
          if (last.isNotEmpty) arguments.add(last);
          return arguments;
        default:
          buffer.write(character);
      }
    }
    return arguments;
  }
}
