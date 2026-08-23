/// What a site says about a whole family tree.
///
/// webtrees renders this as a page of cards and Google Charts: counts in the
/// markup, and the data behind each chart written into a `<script>` beside it
/// as JSON. The counts are the site's own rendering — its numerals included —
/// while the chart data arrives as plain numbers, because it was written for
/// a JavaScript library rather than for a reader.
library;

import 'package:meta/meta.dart';

/// One figure: what it counts, and how many.
@immutable
final class StatisticItem {
  const StatisticItem({required this.label, this.value});

  /// What was counted, in the site's own words.
  final String label;

  /// The count as webtrees rendered it — `١٬٤٦٣` in Arabic — kept as text
  /// for the same reason dates are: the server has already decided which
  /// numerals and which separators this reader uses.
  final String? value;
}

/// How a dataset was meant to be drawn.
enum StatisticShape {
  /// Parts of a whole: sexes, record kinds.
  pie,

  /// A quantity per category: births by century.
  column,

  /// Something this app does not draw — a map, or a shape webtrees added
  /// after this was written. Its numbers are still read, so it can be shown
  /// as a list rather than dropped.
  other;

  /// Reads the shape a site named, however it named it.
  ///
  /// 2.2.x writes it into a call — `statistics.drawPieChart(…)` — and 2.3 into
  /// a `data-wt-chart-type` attribute. The vocabulary is nearly the same, and
  /// where it differs the answer is the same: a bar, a column, a combo and a
  /// line are all "a quantity per category" to a reader.
  static StatisticShape fromCall(String name) => switch (name.toLowerCase()) {
    'pie' || 'doughnut' => StatisticShape.pie,
    'column' || 'combo' || 'bar' || 'line' => StatisticShape.column,
    _ => StatisticShape.other,
  };
}

/// One row of a dataset: what it is, and its numbers.
@immutable
final class StatisticRow {
  StatisticRow({required this.label, required List<double> values})
    : values = List.unmodifiable(values);

  final String label;
  final List<double> values;

  double get value => values.isEmpty ? 0 : values.first;
}

/// The data behind one of a site's charts.
@immutable
final class StatisticDataset {
  StatisticDataset({
    required this.title,
    required this.shape,
    required List<String> columns,
    required List<StatisticRow> rows,
  }) : columns = List.unmodifiable(columns),
       rows = List.unmodifiable(rows);

  /// The chart's own title, as the site set it.
  final String title;

  final StatisticShape shape;

  /// The names of the columns, the first being the category itself.
  final List<String> columns;

  final List<StatisticRow> rows;

  /// Whether there is anything worth drawing.
  bool get hasData => rows.any((row) => row.value != 0);

  double get total => rows.fold(0, (sum, row) => sum + row.value);
}

/// One heading of a statistics page, and everything under it.
@immutable
final class StatisticSection {
  StatisticSection({
    required this.title,
    this.total,
    List<StatisticItem> items = const [],
    List<StatisticDataset> datasets = const [],
  }) : items = List.unmodifiable(items),
       datasets = List.unmodifiable(datasets);

  final String title;

  /// The figure webtrees puts beside the heading itself.
  final String? total;

  final List<StatisticItem> items;
  final List<StatisticDataset> datasets;

  /// Whether the heading turned out to have nothing under it.
  ///
  /// A heading with a figure of its own is not empty: "Total individuals
  /// 1,463" is the single most useful line on the page.
  bool get isEmpty => items.isEmpty && datasets.isEmpty && total == null;
}

/// A whole statistics page, one part per tab the site offers.
@immutable
final class TreeStatistics {
  TreeStatistics({required List<StatisticPart> parts})
    : parts = List.unmodifiable(parts);

  final List<StatisticPart> parts;
}

/// One tab of the statistics page — individuals, families, everything else.
@immutable
final class StatisticPart {
  StatisticPart({required this.title, required List<StatisticSection> sections})
    : sections = List.unmodifiable(sections);

  /// The tab's own label, already translated.
  final String title;

  final List<StatisticSection> sections;
}
