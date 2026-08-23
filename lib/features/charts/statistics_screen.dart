import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../data/session_manager.dart';
import '../../data/transport.dart';
import '../../domain/charts.dart';
import '../../domain/statistics.dart';
import '../../l10n/app_localizations.dart';
import '../shared/bidi.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import 'statistics_charts.dart';

/// What a site says about a whole family tree.
///
/// The counts are shown as webtrees rendered them, numerals and all. The
/// charts are redrawn: the site hands its own drawing library a dataset in
/// plain numbers, and those numbers make a better bar on a phone than a pie
/// built for a mouse.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({
    required this.session,
    required this.records,
    required this.charts,
    required this.tree,
    super.key,
  });

  final SessionManager session;
  final RecordsTransport records;
  final ChartsTransport charts;
  final String tree;

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late Future<TreeStatistics> _statistics;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _statistics = widget.session.withSession(_fetch);
    });
  }

  /// Finds the statistics page this site offers, then reads it.
  ///
  /// The address comes from the tree's own page, because statistics belong to
  /// a whole database rather than to anybody in it — so no person's page links
  /// to them.
  Future<TreeStatistics> _fetch() async {
    final offered = await widget.records.treeCharts(widget.tree);
    final url = offered[ChartKind.statistics];
    if (url == null) return TreeStatistics(parts: const []);

    return widget.charts.statistics(url);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(text.statistics),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: text.reload,
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<TreeStatistics>(
          future: _statistics,
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

            final parts = snapshot.data!.parts;
            if (parts.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: MessagePanel.warning(text.statisticsEmpty),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                for (final part in parts) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      part.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  for (final section in part.sections)
                    _Section(section: section),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section});

  final StatisticSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counted = section.items.where((item) => item.value != null).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                section.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            if (section.total != null)
              Text(
                // A count webtrees rendered, in the numerals it chose.
                isolatedRun(section.total),
                style: theme.textTheme.titleMedium,
              ),
          ],
        ),
        const SizedBox(height: 10),

        // A handful of headline numbers is a row of figures, not a chart:
        // drawing four bars to say four numbers reads slower than the numbers.
        if (counted.isNotEmpty)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final item in counted) _Figure(item: item)],
          ),

        for (final dataset in section.datasets)
          if (dataset.hasData) ...[
            const SizedBox(height: 16),
            Text(
              dataset.title,
              style: theme.textTheme.labelLarge,
              textDirection: directionOf(dataset.title),
            ),
            const SizedBox(height: 10),
            // Parts of a whole get one bar cut into pieces; a count per
            // category gets a bar each. Both beat a pie on a phone, and the
            // second is what webtrees itself draws as a column chart.
            if (dataset.shape == StatisticShape.pie && dataset.rows.length <= 4)
              ShareBar(dataset: dataset)
            else
              MagnitudeBars(dataset: dataset),
          ],
      ],
    );
  }
}

/// One figure: what it counts, and how many.
class _Figure extends StatelessWidget {
  const _Figure({required this.item});

  final StatisticItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isolatedRun(item.value),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            textDirection: directionOf(item.label),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
