import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/transport.dart';
import '../../domain/records.dart';
import '../browse/authenticated_image.dart';
import '../shared/bidi.dart';
import 'chart_layout.dart';
import 'chart_options.dart';

/// The window a chart is looked at through.
///
/// Pan and zoom rather than scroll: a pedigree is wider than a phone by its
/// nature, and a reader following one line up a tree should not have to
/// choose between seeing a name and seeing where it sits.
///
/// **Fitting the whole chart is not always the right opening.** Six
/// generations scaled to a phone is a picture of a tree rather than a tree
/// anybody can read. So the viewport fits the chart only while the names stay
/// legible, and otherwise opens at the smallest legible scale with the person
/// the reader asked about in the middle — the rest is a pan away, and pinching
/// out still reaches the whole thing.
class ChartViewport extends StatefulWidget {
  const ChartViewport({
    required this.size,
    required this.child,
    this.focus,
    this.smallestText = 11,
    this.captureKey,
    super.key,
  });

  final Size size;
  final Widget child;

  /// Marks the chart at its **natural size** so it can be exported whole.
  ///
  /// Inside the viewport rather than around it. A boundary around the window
  /// captures a picture of the window — the part of the family that happened
  /// to be on screen, at whatever the reader had pinched to — because that is
  /// all the window is. A boundary around the content captures the content,
  /// however far the view has been panned away from it.
  final GlobalKey? captureKey;

  /// Where to centre when the whole chart cannot be shown legibly. The person
  /// the chart was drawn for; null centres the chart itself.
  final Offset? focus;

  /// The size the smallest text on a box is drawn at, which is what decides
  /// how far the chart can be scaled down and still be read.
  final double smallestText;

  /// Room around the chart so the outermost boxes are not against the edge.
  static const double margin = 24;

  /// Below this, text stops being text. Nine logical pixels is around the
  /// point at which a name becomes a grey smudge on a phone.
  static const double legibleText = 9;

  @override
  State<ChartViewport> createState() => _ChartViewportState();
}

class _ChartViewportState extends State<ChartViewport> {
  final TransformationController _view = TransformationController();

  /// The viewport the opening position was worked out for, so a rotation or a
  /// change of chart recomputes it and an ordinary rebuild does not.
  Size? _settledFor;
  double _fitScale = 1;

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  /// The scale below which the smallest text stops being readable.
  double get _legibleScale => ChartViewport.legibleText / widget.smallestText;

  void _settle(Size window) {
    if (_settledFor == window) return;
    _settledFor = window;

    final whole = Size(
      widget.size.width + ChartViewport.margin * 2,
      widget.size.height + ChartViewport.margin * 2,
    );
    final fit = math.min(
      window.width / whole.width,
      window.height / whole.height,
    );
    // Never magnify: a chart of three people should not fill the screen with
    // two names.
    _fitScale = math.min(fit, 1.0);

    final scale = math.max(_fitScale, math.min(_legibleScale, 1.0));
    final focus =
        (widget.focus ??
            Offset(widget.size.width / 2, widget.size.height / 2)) +
        const Offset(ChartViewport.margin, ChartViewport.margin);

    // Centre on the focus, then pull back inside the content so the opening
    // view is not half empty space beyond the edge of the chart.
    double x = window.width / 2 - focus.dx * scale;
    double y = window.height / 2 - focus.dy * scale;
    final overflowX = whole.width * scale - window.width;
    final overflowY = whole.height * scale - window.height;
    x = overflowX <= 0
        ? (window.width - whole.width * scale) / 2
        : x.clamp(-overflowX, 0.0);
    y = overflowY <= 0
        ? (window.height - whole.height * scale) / 2
        : y.clamp(-overflowY, 0.0);

    _view.value = Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final window = Size(constraints.maxWidth, constraints.maxHeight);
      // After the frame, so setting the controller does not rebuild the
      // viewer in the middle of laying it out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _settle(window);
      });

      return InteractiveViewer(
        transformationController: _view,
        constrained: false,
        // The whole chart is always reachable by pinching out, however far in
        // the opening view had to start.
        minScale: math.min(_fitScale, _legibleScale),
        maxScale: 6,
        boundaryMargin: const EdgeInsets.all(ChartViewport.margin * 2),
        child: RepaintBoundary(
          key: widget.captureKey,
          child: SizedBox(
            width: widget.size.width + ChartViewport.margin * 2,
            height: widget.size.height + ChartViewport.margin * 2,
            child: Padding(
              padding: const EdgeInsets.all(ChartViewport.margin),
              child: widget.child,
            ),
          ),
        ),
      );
    },
  );
}

/// A family chart drawn as boxes and joining lines.
class ChartCanvas extends StatelessWidget {
  const ChartCanvas({
    required this.layout,
    required this.records,
    required this.onTapPerson,
    this.options = const ChartOptions(),
    this.captureKey,
    super.key,
  });

  final ChartLayout layout;
  final RecordsTransport records;
  final void Function(PersonRef person) onTapPerson;

  /// How the reader asked for this to be drawn.
  final ChartOptions options;

  /// Where an export reads the chart from — see [ChartViewport.captureKey].
  final GlobalKey? captureKey;

  @override
  Widget build(BuildContext context) {
    final metrics = layout.metrics;

    return ChartViewport(
      size: layout.size,
      captureKey: captureKey,
      focus: layout.subject == null
          ? null
          : Offset(
              layout.subject!.centreX,
              layout.subject!.topLeft.dy + metrics.boxHeight / 2,
            ),
      child: chartOnly(context),
    );
  }

  /// The chart itself, at its natural size and outside any viewport.
  ///
  /// Separated so it can be captured whole for an export: a picture of the
  /// window would be a picture of whatever happened to be on screen.
  Widget chartOnly(BuildContext context) {
    final metrics = layout.metrics;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _JoiningLines(
              layout: layout,
              color: Theme.of(context).colorScheme.outlineVariant,
              coupleColor: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        for (final placement in layout.people)
          Positioned(
            left: placement.topLeft.dx,
            top: placement.topLeft.dy,
            width: placement.width,
            height: metrics.boxHeight,
            child: _PersonBox(
              placement: placement,
              records: records,
              options: options,
              onTap: () => onTapPerson(placement.person),
            ),
          ),

        // Above the boxes, because a caption sits on the line it names and
        // the line is painted underneath everything.
        for (final edge in layout.edges)
          if (edge.label case final label?)
            Positioned(
              // Centred on the middle of the line, which is where the elbow
              // turns and where a straight run has most room.
              left: (edge.from.dx + edge.to.dx) / 2 - _EdgeLabel.width / 2,
              top: (edge.from.dy + edge.to.dy) / 2 - _EdgeLabel.height / 2,
              width: _EdgeLabel.width,
              height: _EdgeLabel.height,
              child: _EdgeLabel(label),
            ),
      ],
    );
  }
}

/// What a joining line is called, drawn on the line.
///
/// Only a relationship path has these: a descent chart's shape is its own
/// caption, and a path is a route that has to say `father` at each turn or it
/// is a row of boxes. The word is the site's own and takes its direction from
/// itself — a kinship term is written in the site's language, not the
/// reader's.
class _EdgeLabel extends StatelessWidget {
  const _EdgeLabel(this.text);

  final String text;

  /// Fixed, and centred on the line rather than laid out against it: the
  /// arithmetic that places every box is in `chart_layout.dart` and knows
  /// nothing about fonts, so a caption that could resize would move the
  /// picture out from under it.
  static const double width = 108;
  static const double height = 26;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(100),
          border: BoxBorder.all(color: colors.surface, width: 2),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          textDirection: directionOf(text),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

/// The lines joining a person to their family.
///
/// Elbows rather than diagonals, turning in whichever direction the chart
/// runs: a diagonal through a crowded pedigree is hard to follow, and a line
/// that turns says plainly which box it came from.
class _JoiningLines extends CustomPainter {
  const _JoiningLines({
    required this.layout,
    required this.color,
    required this.coupleColor,
  });

  final ChartLayout layout;
  final Color color;

  /// Straight lines are drawn in a stronger colour than descent: a couple,
  /// because the difference between a marriage and a divorce is carried by
  /// that line and has to survive being looked at from across a whole chart;
  /// a same-generation link on a relationship path, because it is a step the
  /// reader is following rather than a family it can see the shape of.
  final Color coupleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final brush = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final couple = Paint()
      ..color = coupleColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final edge in layout.edges) {
      if (edge.isStraight) {
        if (edge.kind == EdgeKind.divorce) {
          _drawParted(canvas, edge, couple);
        } else {
          canvas.drawLine(edge.from, edge.to, couple);
        }
        continue;
      }

      final path = Path()..moveTo(edge.from.dx, edge.from.dy);
      if (layout.flow == ChartFlow.sideways) {
        final middle = (edge.from.dx + edge.to.dx) / 2;
        path
          ..lineTo(middle, edge.from.dy)
          ..lineTo(middle, edge.to.dy);
      } else {
        final middle = (edge.from.dy + edge.to.dy) / 2;
        path
          ..lineTo(edge.from.dx, middle)
          ..lineTo(edge.to.dx, middle);
      }
      path.lineTo(edge.to.dx, edge.to.dy);
      canvas.drawPath(path, brush);
    }
  }

  /// A couple whose marriage ended: the line runs from each of them and stops
  /// short, with two small strokes across the gap between.
  ///
  /// The mark genealogists have used on paper for a century, and the reason
  /// it beats a dash pattern here is that it survives being shrunk — a dashed
  /// line at a quarter scale is a solid line.
  void _drawParted(Canvas canvas, ChartEdge edge, Paint brush) {
    final span = (edge.to - edge.from).distance;
    final along = span == 0 ? const Offset(1, 0) : (edge.to - edge.from) / span;
    final across = Offset(-along.dy, along.dx);

    // Near the spouse rather than halfway along. A family pushed sideways to
    // reach its own children can be a long way from the person it belongs to,
    // and a mark stranded in the middle of that line says nothing about which
    // couple it is about.
    final mark = edge.to - along * math.min(span / 2, 20);
    final gap = (span * 0.34).clamp(3.0, 7.0);

    canvas
      ..drawLine(edge.from, mark - along * gap, brush)
      ..drawLine(mark + along * gap, edge.to, brush);

    // The two strokes, leaning the way the convention draws them.
    for (final offset in [-gap / 2, gap / 2]) {
      final at = mark + along * offset;
      canvas.drawLine(at - across * 4 - along * 2, at + across * 4, brush);
    }
  }

  @override
  bool shouldRepaint(_JoiningLines old) =>
      old.layout != layout ||
      old.color != color ||
      old.coupleColor != coupleColor;
}

/// One person on a chart.
class _PersonBox extends StatelessWidget {
  const _PersonBox({
    required this.placement,
    required this.records,
    required this.onTap,
    required this.options,
  });

  final ChartPlacement placement;
  final RecordsTransport records;
  final VoidCallback onTap;
  final ChartOptions options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final person = placement.person;

    // The person the chart was drawn for is the one the reader is looking
    // for; a spouse married in rather than descended is quieter than either.
    // Colouring by sex takes over the fill, so the subject keeps a heavier
    // border to stay findable when it does.
    final (background, border) = options.colourBySex
        ? (
            PersonColors.of(context).forSex(person.sex).$1,
            placement.isSubject ? colors.primary : colors.outlineVariant,
          )
        : switch (placement) {
            ChartPlacement(isSubject: true) => (
              colors.primaryContainer,
              colors.primary,
            ),
            ChartPlacement(isSpouse: true) => (
              colors.surfaceContainerLow,
              colors.outlineVariant,
            ),
            _ => (colors.surfaceContainerHigh, colors.outlineVariant),
          };

    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.shapeMedium),
        side: BorderSide(color: border, width: placement.isSubject ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // A chart without photographs draws more of the family in the
              // same space, and a name is what the reader came for.
              if (options.showPhotos) ...[
                AuthenticatedImage(
                  url: person.thumbnailUrl,
                  records: records,
                  name: person.name,
                  // The same face, in the same colours, with the same ribbon
                  // as everywhere else: a chart is where a reader most needs
                  // to tell a son from a daughter at a glance.
                  sex: person.sex,
                  deceased: person.isDeceased,
                  size: 40,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                    if (options.showDates && person.lifespan != null)
                      Text(
                        // All digits and a dash: without an isolate the
                        // Arabic layout reverses it and the person dies
                        // before they are born.
                        ltrRun(person.lifespan),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
