import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../data/session_manager.dart';
import '../../data/settings_store.dart';
import '../../data/transport.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import '../../l10n/app_localizations.dart';
import '../shared/chart_header_title.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import 'chart_canvas.dart';
import 'chart_export.dart';
import 'chart_layout.dart';
import 'chart_options.dart';
import 'chart_options_sheet.dart';
import 'chart_pdf.dart';
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
    required this.settings,
    required this.tree,
    required this.xref,
    required this.kind,
    required this.onOpenPerson,
    required this.onOpenChart,
    super.key,
  });

  final SessionManager session;
  final RecordsTransport records;
  final ChartsTransport charts;
  final SettingsStore settings;
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

class _ChartScreenState extends State<ChartScreen> {
  late Future<ChartData> _chart;

  /// Whose chart this is, once the record it was read from has arrived.
  ///
  /// Held rather than taken from the future's result so the bar keeps naming
  /// the person while a redraw is in flight.
  PersonRef? _subject;

  /// Lets the chart be captured whole, at its natural size, rather than
  /// photographed through the window it is being looked at.
  final GlobalKey _capture = GlobalKey();

  /// How many generations the chart on screen was fetched with, so a change
  /// to that one option costs a request and the rest do not.
  int? _fetchedGenerations;

  @override
  void initState() {
    super.initState();
    _fetchedGenerations = widget.settings.chartOptions.generations;
    widget.settings.addListener(_onSettingsChanged);
    _load();
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(ChartScreen old) {
    super.didUpdateWidget(old);
    if (old.xref != widget.xref || old.kind != widget.kind) _load();
  }

  /// Only a change of depth reaches the server; everything else is a redraw
  /// of a shape the app already has.
  void _onSettingsChanged() {
    final asked = widget.settings.chartOptions.generations;
    if (asked == _fetchedGenerations) return;
    _fetchedGenerations = asked;
    _load();
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
    final subject = person.asReference;
    if (mounted) setState(() => _subject = subject);

    if (widget.kind == ChartKind.hourglass) {
      final up = person.charts[ChartKind.ancestors];
      final down = person.charts[ChartKind.descendants];
      if (up == null || down == null) throw const NotFound();

      return widget.charts.hourglass(
        ancestorsHandle: up,
        descendantsHandle: down,
        subject: subject,
        generations: _fetchedGenerations,
      );
    }

    final url = person.charts[widget.kind];
    if (url == null) throw const NotFound();

    return widget.charts.chart(
      widget.kind,
      url,
      subject: subject,
      generations: _fetchedGenerations,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        title: ChartHeaderTitle(
          title: chartTitle(widget.kind, text),
          person: _subject,
          records: widget.records,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: text.chartOptions,
            onPressed: () => ChartOptionsSheet.show(
              context,
              widget.settings,
              // Only an ancestors chart has other shapes to take.
              offersShape: widget.kind == ChartKind.ancestors,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: text.chartShare,
            onPressed: _share,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: text.reload,
            onPressed: _load,
          ),
        ],
      ),
      // Rebuilt whenever the reader changes how charts are drawn, so a switch
      // thrown in the sheet is answered by the chart behind it.
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.settings,
          builder: (context, _) => _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final text = AppText.of(context);

    return FutureBuilder<ChartData>(
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
              error is WebtreesError ? error.localized(text) : text.chartFailed,
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
            _options.shape == ChartShape.circle &&
            widget.kind == ChartKind.ancestors) {
          return FanCanvas(
            layout: layoutFan(ancestorsShowing(ancestors, _options.show)),
            captureKey: _capture,
            onTapPerson: _onTapPerson,
          );
        }

        return ChartCanvas(
          layout: _layoutFor(chart, context),
          records: widget.records,
          options: _options,
          captureKey: _capture,
          onTapPerson: _onTapPerson,
        );
      },
    );
  }

  ChartOptions get _options => widget.settings.chartOptions;

  /// How big the boxes are, which is the one thing the shape decides for
  /// itself.
  ///
  /// A compact chart trades the photographs for smaller boxes, which is what
  /// makes five generations fit on a screen somebody is holding in one hand.
  ChartMetrics get _metrics => _options.shape == ChartShape.compact
      ? const ChartMetrics(
          boxWidth: 120,
          boxHeight: 44,
          generationGap: 28,
          siblingGap: 8,
        )
      : const ChartMetrics();

  ChartLayout _layoutFor(ChartData chart, BuildContext context) => _layoutWith(
    chart,
    widthOf: _measured(context),
    mirrored: Directionality.of(context) == TextDirection.rtl,
  );

  /// The same layout, from measurements taken earlier.
  ///
  /// Separated so a page can be drawn after the sheet that asked for it has
  /// closed and there is no context left to measure with.
  ChartLayout _layoutWith(
    ChartData chart, {
    required BoxWidth? widthOf,
    required bool mirrored,
  }) {
    final metrics = _metrics;

    // Hiding a sex cuts every branch reached through it, which is what a
    // reader asking for the male line means — see [ShowPeople].
    final ancestors = chart.ancestors == null
        ? null
        : ancestorsShowing(chart.ancestors!, _options.show);
    final descendants = chart.descendants == null
        ? null
        : descendantsShowing(chart.descendants!, _options.show);

    final layout = switch (chart.kind) {
      ChartKind.hourglass => layoutHourglass(
        ancestors!,
        descendants!,
        metrics: metrics,
        widthOf: widthOf,
      ),
      ChartKind.ancestors => layoutAncestors(
        ancestors!,
        metrics: metrics,
        widthOf: widthOf,
      ),
      _ => layoutDescendants(descendants!, metrics: metrics, widthOf: widthOf),
    };

    // Arabic reads the other way, and so does its chart: generations march
    // away from the reader's starting corner, not towards it.
    return mirrored ? layout.mirrored() : layout;
  }

  /// The name measurer this chart is drawn with, or null when boxes are all
  /// one width.
  BoxWidth? _measured(BuildContext context) =>
      _options.fitToName ? _measurer(context, _metrics) : null;

  /// The chart drawn again as shapes, for a PDF worth printing.
  ///
  /// Not the captured picture on a page: a family chart is the kind of
  /// document somebody prints large, and a screenshot at any resolution has
  /// already decided how large that can be.
  Future<Uint8List> _drawPage({
    required String title,
    required ChartInk ink,
    required BoxWidth? widthOf,
    required bool mirrored,
  }) async {
    final chart = await _chart;

    final ancestors = chart.ancestors;
    if (ancestors != null &&
        _options.shape == ChartShape.circle &&
        widget.kind == ChartKind.ancestors) {
      return fanChartPage(
        layout: layoutFan(ancestorsShowing(ancestors, _options.show)),
        ink: ink,
        title: title,
      );
    }

    final layout = _layoutWith(chart, widthOf: widthOf, mirrored: mirrored);

    return boxChartPage(
      layout: layout,
      options: _options,
      ink: ink,
      title: title,
      rightToLeft: mirrored,
      photos: await _photos(layout),
    );
  }

  /// The faces already on screen, for the page to embed.
  ///
  /// Best-effort and one at a time: a photograph that will not come back is
  /// an ordinary thing on a tree, and the initial stands in for it exactly as
  /// it does on the chart itself.
  Future<Map<String, Uint8List>> _photos(ChartLayout layout) async {
    if (!_options.showPhotos) return const {};

    final urls = {
      for (final placement in layout.people)
        if (placement.person.thumbnailUrl != null)
          placement.person.thumbnailUrl!,
    };
    final photos = <String, Uint8List>{};

    for (final url in urls) {
      try {
        photos[url] = await widget.records.image(url);
      } on Object catch (problem) {
        developer.log('No photo for the page: $problem', name: _log);
      }
    }
    return photos;
  }

  /// A box wide enough for the name in it.
  ///
  /// Measured here rather than in `chart_layout.dart`, which is deliberately
  /// free of widgets: only the interface knows the font, and only the layout
  /// knows what to do with the answer.
  ///
  /// Clamped at both ends. Too narrow and a chart becomes a column of stubs;
  /// too wide and one long name pushes a whole generation off the screen —
  /// so a name past the limit is still cut, as it was before.
  BoxWidth _measurer(BuildContext context, ChartMetrics metrics) {
    final style = Theme.of(context).textTheme.labelMedium;
    final direction = Directionality.of(context);
    final photo = _options.showPhotos ? 48.0 : 0.0;
    final widest = metrics.boxWidth * 1.9;

    return (person) {
      final painter = TextPainter(
        text: TextSpan(text: person.name, style: style),
        textDirection: direction,
        maxLines: 1,
      )..layout();

      return (painter.width + photo + 24).clamp(metrics.boxWidth * 0.7, widest);
    };
  }

  /// Offers the chart as a picture or as a page.
  ///
  /// The sheet asks which; the chart itself is captured at its natural size
  /// from the boundary around it, so what is shared is the whole family and
  /// not the part of it the reader happened to be looking at.
  Future<void> _share() async {
    final text = AppText.of(context);
    final chosen = await showModalBottomSheet<ChartFormat>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(text.chartShareImage),
              onTap: () => Navigator.of(sheet).pop(ChartFormat.image),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(text.chartSharePdf),
              onTap: () => Navigator.of(sheet).pop(ChartFormat.pdf),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final title = text.chartShareSubject(
      _subject?.name ?? widget.xref,
      chartTitle(widget.kind, text),
    );
    // A large chart takes a moment to draw at full size, and a share sheet
    // that appears out of nowhere seconds later is worse than being told.
    messenger.showSnackBar(
      SnackBar(
        content: Text(text.chartSharing),
        duration: const Duration(seconds: 2),
      ),
    );

    // The ink is read now, while there is still a context to read it from:
    // the page is built after the sheet that asked for it has closed.
    final ink = ChartInk(
      colors: Theme.of(context).colorScheme,
      people: PersonColors.of(context),
    );
    final metrics = _measured(context);
    final mirrored = Directionality.of(context) == TextDirection.rtl;

    try {
      await shareChart(
        boundary: _capture,
        format: chosen,
        title: title,
        page: () => _drawPage(
          title: title,
          ink: ink,
          widthOf: metrics,
          mirrored: mirrored,
        ),
        origin: _shareOrigin(),
      );
    } on ChartExportFailed catch (problem) {
      developer.log('Sharing the chart failed: $problem', name: _log);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            problem.isTooLarge
                ? text.chartTooBigToShare
                : text.chartShareFailed,
          ),
        ),
      );
    } on Exception catch (problem) {
      developer.log('Sharing the chart failed: $problem', name: _log);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(text.chartShareFailed)));
    }
  }

  /// Where an iPad anchors its share sheet. Harmless everywhere else.
  Rect? _shareOrigin() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
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

const String _log = 'webtrees.charts';

/// What to call a chart, in the reader's language.
///
/// Only the charts the app draws for itself have names here; the rest are
/// never offered, so a site that runs them is not misrepresented.
String chartTitle(ChartKind kind, AppText text) => switch (kind) {
  ChartKind.ancestors => text.chartAncestors,
  ChartKind.descendants => text.chartDescendants,
  ChartKind.hourglass => text.chartHourglass,
  ChartKind.relationship => text.chartRelationship,
  ChartKind.timeline => text.chartTimeline,
  _ => text.charts,
};
