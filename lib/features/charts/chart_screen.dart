import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../data/session_manager.dart';
import '../../data/stock/charts_repository.dart';
import '../../data/stock/records_repository.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import '../../l10n/app_localizations.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import 'chart_canvas.dart';
import 'chart_layout.dart';
import 'fan_canvas.dart';
import 'fan_layout.dart';

/// One chart, drawn for one person.
///
/// The site decides which charts exist and how many generations they hold —
/// its own links carry both — and the app decides how to draw them, because
/// webtrees' rendering is HTML for a wide screen with the reading direction
/// built into its stylesheet.
class ChartScreen extends StatefulWidget {
  const ChartScreen({
    required this.session,
    required this.records,
    required this.charts,
    required this.tree,
    required this.xref,
    required this.kind,
    required this.onOpenPerson,
    required this.onOpenChart,
    super.key,
  });

  final SessionManager session;
  final RecordsRepository records;
  final ChartsRepository charts;
  final String tree;
  final String xref;
  final ChartKind kind;

  final void Function(String xref) onOpenPerson;

  /// Draws the same chart for somebody else — how a reader walks a tree
  /// without leaving the chart they are reading.
  final void Function(String xref) onOpenChart;

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

/// The ways one chart can be drawn.
///
/// Not different charts: webtrees offers an ancestors chart, a fan chart and
/// a compact chart, and all three describe the same people. Fetching the
/// shape once and drawing it three ways is both less work for the site and
/// less waiting for the reader.
enum ChartView { tree, circle, compact }

class _ChartScreenState extends State<ChartScreen> {
  late Future<ChartData> _chart;

  ChartView _view = ChartView.tree;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ChartScreen old) {
    super.didUpdateWidget(old);
    if (old.xref != widget.xref || old.kind != widget.kind) _load();
  }

  void _load() {
    setState(() {
      _chart = widget.session.withSession(_fetch);
    });
  }

  /// Reads the person, then the chart their page offered.
  ///
  /// The address of a chart is the site's to give: it carries the generations
  /// its administrator settled on, and a site running the module at all is
  /// the only reason there is a chart to draw.
  Future<ChartData> _fetch() async {
    final person = await widget.records.individual(widget.tree, widget.xref);
    final subject = PersonRef(
      xref: person.xref,
      name: person.name,
      thumbnailUrl: person.thumbnailUrl,
      sex: person.sex,
    );

    if (widget.kind == ChartKind.hourglass) {
      final up = person.charts[ChartKind.ancestors];
      final down = person.charts[ChartKind.descendants];
      if (up == null || down == null) throw const NotFound();

      return widget.charts.hourglass(
        ancestorsUrl: up,
        descendantsUrl: down,
        subject: subject,
      );
    }

    final url = person.charts[widget.kind];
    if (url == null) throw const NotFound();

    return widget.charts.chart(widget.kind, url, subject: subject);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(chartTitle(widget.kind, text)),
        actions: [
          // Only an ancestor chart has other shapes to take: a fan is a
          // pedigree bent round a circle, and there is no such thing as a
          // fan of descendants.
          if (widget.kind == ChartKind.ancestors)
            PopupMenuButton<ChartView>(
              icon: const Icon(Icons.donut_small_outlined),
              tooltip: text.chartView,
              initialValue: _view,
              onSelected: (view) => setState(() => _view = view),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: ChartView.tree,
                  child: Text(text.chartViewTree),
                ),
                PopupMenuItem(
                  value: ChartView.circle,
                  child: Text(text.chartViewCircle),
                ),
                PopupMenuItem(
                  value: ChartView.compact,
                  child: Text(text.chartViewCompact),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: text.reload,
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<ChartData>(
          future: _chart,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final error = snapshot.error;
            if (error != null) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: MessagePanel.error(
                  error is WebtreesError
                      ? error.localized(text)
                      : text.chartFailed,
                ),
              );
            }

            final chart = snapshot.data!;
            if (chart.size <= 1) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    text.chartEmpty,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }

            final ancestors = chart.ancestors;
            if (ancestors != null &&
                _view == ChartView.circle &&
                widget.kind == ChartKind.ancestors) {
              return FanCanvas(
                layout: layoutFan(ancestors),
                onTapPerson: _onTapPerson,
              );
            }

            return ChartCanvas(
              layout: _layoutFor(chart, context),
              records: widget.records,
              compact: _view == ChartView.compact,
              onTapPerson: _onTapPerson,
            );
          },
        ),
      ),
    );
  }

  ChartLayout _layoutFor(ChartData chart, BuildContext context) {
    // A compact chart trades the photographs for smaller boxes, which is what
    // makes five generations fit on a screen somebody is holding in one hand.
    const compact = ChartMetrics(
      boxWidth: 120,
      boxHeight: 44,
      generationGap: 28,
      siblingGap: 8,
    );
    final metrics = _view == ChartView.compact ? compact : const ChartMetrics();

    final ancestors = chart.ancestors;
    final descendants = chart.descendants;
    final layout = switch (chart.kind) {
      ChartKind.hourglass => layoutHourglass(
        ancestors!,
        descendants!,
        metrics: metrics,
      ),
      ChartKind.ancestors => layoutAncestors(ancestors!, metrics: metrics),
      _ => layoutDescendants(descendants!, metrics: metrics),
    };

    // Arabic reads the other way, and so does its chart: generations march
    // away from the reader's starting corner, not towards it.
    return Directionality.of(context) == TextDirection.rtl
        ? layout.mirrored()
        : layout;
  }

  /// Asks what to do with the person just tapped.
  ///
  /// Two things are worth doing and neither is obviously the default: read
  /// them, or make them the middle of the chart. A sheet says both out loud
  /// rather than hiding one behind a long press nobody tries.
  void _onTapPerson(PersonRef person) {
    final text = AppText.of(context);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                person.name,
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
              subtitle: person.lifespan == null ? null : Text(person.lifespan!),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(text.openThisPerson),
              onTap: () {
                Navigator.of(sheet).pop();
                widget.onOpenPerson(person.xref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(text.chartFromHere),
              onTap: () {
                Navigator.of(sheet).pop();
                widget.onOpenChart(person.xref);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// What to call a chart, in the reader's language.
///
/// Only the charts the app draws for itself have names here; the rest are
/// never offered, so a site that runs them is not misrepresented.
String chartTitle(ChartKind kind, AppText text) => switch (kind) {
  ChartKind.ancestors => text.chartAncestors,
  ChartKind.descendants => text.chartDescendants,
  ChartKind.hourglass => text.chartHourglass,
  _ => text.charts,
};
