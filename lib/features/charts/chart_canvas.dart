import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/stock/records_repository.dart';
import '../../domain/records.dart';
import '../browse/authenticated_image.dart';
import '../shared/bidi.dart';
import 'chart_layout.dart';

/// A family chart, drawn from the shape a webtrees site described.
///
/// Pan and zoom rather than scroll: a pedigree is wider than a phone by its
/// nature, and a reader following one line up a tree should not have to
/// choose between seeing a name and seeing where it sits.
/// The window a chart is looked at through.
///
/// The whole chart first, a closer look after. A pedigree is wider than a
/// phone, and the corner an unfitted canvas opens in is the wrong one in half
/// the world's languages: in Arabic the chart is mirrored, so the person the
/// reader asked about would start off the right-hand edge. Fitting the content
/// rather than driving a transformation controller keeps that decision out of
/// the build, where changing it would rebuild the viewer mid-frame.
class ChartViewport extends StatelessWidget {
  const ChartViewport({required this.size, required this.child, super.key});

  final Size size;
  final Widget child;

  /// Room around the chart so the outermost boxes are not against the edge.
  static const double margin = 24;

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    minScale: 1,
    maxScale: 6,
    child: Center(
      child: FittedBox(
        // Contain, but never magnify: a chart of three people should not fill
        // the screen with two names.
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: size.width + margin * 2,
          height: size.height + margin * 2,
          child: Padding(padding: const EdgeInsets.all(margin), child: child),
        ),
      ),
    ),
  );
}

/// A family chart drawn as boxes and joining lines.
class ChartCanvas extends StatelessWidget {
  const ChartCanvas({
    required this.layout,
    required this.records,
    required this.onTapPerson,
    this.compact = false,
    super.key,
  });

  final ChartLayout layout;
  final RecordsRepository records;
  final void Function(PersonRef person) onTapPerson;

  /// Draws more people in the same space, at the cost of the photographs.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final metrics = layout.metrics;

    return ChartViewport(
      size: layout.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _JoiningLines(
                layout: layout,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          for (final placement in layout.people)
            Positioned(
              left: placement.topLeft.dx,
              top: placement.topLeft.dy,
              width: metrics.boxWidth,
              height: metrics.boxHeight,
              child: _PersonBox(
                placement: placement,
                records: records,
                compact: compact,
                onTap: () => onTapPerson(placement.person),
              ),
            ),
        ],
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
  const _JoiningLines({required this.layout, required this.color});

  final ChartLayout layout;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final brush = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final edge in layout.edges) {
      final path = Path()..moveTo(edge.from.dx, edge.from.dy);
      if (edge.isCouple) {
        path.lineTo(edge.to.dx, edge.to.dy);
        canvas.drawPath(path, brush);
        continue;
      }
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

  @override
  bool shouldRepaint(_JoiningLines old) =>
      old.layout != layout || old.color != color;
}

/// One person on a chart.
class _PersonBox extends StatelessWidget {
  const _PersonBox({
    required this.placement,
    required this.records,
    required this.onTap,
    this.compact = false,
  });

  final ChartPlacement placement;
  final RecordsRepository records;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // The person the chart was drawn for is the one the reader is looking
    // for; a spouse married in rather than descended is quieter than either.
    final (background, border) = switch (placement) {
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
        side: BorderSide(color: border, width: placement.isSubject ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // A compact chart drops the photographs rather than the names:
              // more of the family fits, and a name is what the reader came
              // for.
              if (!compact) ...[
                AuthenticatedImage(
                  url: placement.person.thumbnailUrl,
                  records: records,
                  name: placement.person.name,
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
                      placement.person.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                    if (placement.person.lifespan != null)
                      Text(
                        // All digits and a dash: without an isolate the
                        // Arabic layout reverses it and the person dies
                        // before they are born.
                        ltrRun(placement.person.lifespan),
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
