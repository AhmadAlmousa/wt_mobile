import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../data/session_manager.dart';
import '../../data/stock/charts_repository.dart';
import '../../data/stock/records_repository.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import '../../l10n/app_localizations.dart';
import '../shared/bidi.dart';
import '../shared/chart_header_title.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import 'timeline_layout.dart';

/// A person's life against a scale of years.
///
/// The site works out where every event falls; the app keeps those positions
/// in proportion and draws them down the screen, where a phone can scroll
/// through a life rather than squint at a wide one.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    required this.session,
    required this.records,
    required this.charts,
    required this.tree,
    required this.xref,
    super.key,
  });

  final SessionManager session;
  final RecordsRepository records;
  final ChartsRepository charts;
  final String tree;
  final String xref;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  late Future<TimelineChart> _timeline;

  /// Whose life this is. The record has to be fetched anyway — it is what
  /// carries the timeline's address — so naming the person in the bar costs
  /// nothing more than remembering them.
  PersonRef? _subject;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _timeline = widget.session.withSession(_fetch);
    });
  }

  Future<TimelineChart> _fetch() async {
    final person = await widget.records.individual(widget.tree, widget.xref);
    if (mounted) setState(() => _subject = person.asReference);

    final url = person.charts[ChartKind.timeline];
    if (url == null) throw const NotFound();

    return widget.charts.timeline(url);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        title: ChartHeaderTitle(
          title: text.chartTimeline,
          person: _subject,
          records: widget.records,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: text.reload,
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<TimelineChart>(
          future: _timeline,
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
            if (chart.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    text.timelineEmpty,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }

            return _Timeline(layout: layoutTimeline(chart));
          },
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.layout});

  final TimelineLayout layout;

  /// How much of the leading edge the year scale takes.
  static const double _gutter = 52;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: SizedBox(
        height: layout.height + 40,
        child: Stack(
          children: [
            // The scale, on the edge the reader starts from.
            for (final tick in layout.ticks)
              PositionedDirectional(
                start: 0,
                top: tick.at,
                child: SizedBox(
                  width: _gutter,
                  child: Text(
                    // Years are Latin whichever way the page reads.
                    ltrRun('${tick.year}'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

            PositionedDirectional(
              start: _gutter,
              top: 0,
              bottom: 0,
              child: Container(
                width: 2,
                color: theme.colorScheme.outlineVariant,
              ),
            ),

            for (final placed in layout.events) ...[
              // The dot marks when it happened; the card may have been nudged
              // down to make room, so a line joins the two.
              PositionedDirectional(
                start: _gutter - 3,
                top: placed.at - 3,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              if ((placed.cardTop - placed.at).abs() > 1)
                PositionedDirectional(
                  start: _gutter + 1,
                  top: placed.at,
                  child: SizedBox(
                    height: (placed.cardTop - placed.at).clamp(0, 400) + 1,
                    child: VerticalDivider(
                      width: 12,
                      thickness: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),
              PositionedDirectional(
                start: _gutter + 14,
                end: 0,
                top: placed.cardTop,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    placed.event.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    // The site wrote this in the tree's language, which need
                    // not be the reader's.
                    textDirection: directionOf(placed.event.label),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
