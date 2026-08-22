import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/records.dart';
import 'chart_canvas.dart';
import 'fan_layout.dart';

/// An ancestor chart drawn as a circle.
///
/// The same people as the pedigree, in the shape that shows a whole family
/// line at once: every generation a ring, every person's slice exactly half
/// their child's. Painted rather than built from widgets, because a fan is
/// arcs and rotated text — neither of which a box of widgets does well.
class FanCanvas extends StatelessWidget {
  const FanCanvas({required this.layout, required this.onTapPerson, super.key});

  final FanLayout layout;
  final void Function(PersonRef person) onTapPerson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ChartViewport(
      size: Size(layout.diameter, layout.diameter),
      child: GestureDetector(
        // The whole fan is one canvas, so which person was tapped is a
        // question of geometry: how far from the middle, and at what angle.
        onTapUp: (details) {
          final person = layout.at(
            details.localPosition.dx - layout.centre,
            details.localPosition.dy - layout.centre,
          );
          if (person != null) onTapPerson(person.person);
        },
        child: CustomPaint(
          size: Size(layout.diameter, layout.diameter),
          painter: _FanPainter(
            layout: layout,
            colors: theme.colorScheme,
            label: theme.textTheme.labelSmall!,
            // Arabic joins its letters and must not be tracked apart; the
            // theme has already made that decision for this locale.
            textDirection: Directionality.of(context),
          ),
        ),
      ),
    );
  }
}

class _FanPainter extends CustomPainter {
  const _FanPainter({
    required this.layout,
    required this.colors,
    required this.label,
    required this.textDirection,
  });

  final FanLayout layout;
  final ColorScheme colors;
  final TextStyle label;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(layout.centre, layout.centre);
    final edge = Paint()
      ..color = colors.surface
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final sector in layout.sectors) {
      final fill = Paint()..color = _fillFor(sector);

      if (sector.generation == 0) {
        canvas.drawCircle(centre, sector.outerRadius, fill);
        canvas.drawCircle(centre, sector.outerRadius, edge);
      } else {
        final path = _ringPath(centre, sector);
        canvas.drawPath(path, fill);
        canvas.drawPath(path, edge);
      }

      _drawName(canvas, centre, sector);
    }
  }

  Color _fillFor(FanSector sector) {
    if (sector.generation == 0) return colors.primaryContainer;
    // Rings alternate so the eye can follow one generation round the circle
    // without counting outwards from the middle.
    return sector.generation.isEven
        ? colors.surfaceContainerHigh
        : colors.surfaceContainerLow;
  }

  /// The slice of a ring one person occupies.
  Path _ringPath(Offset centre, FanSector sector) {
    // Angles are measured clockwise from twelve o'clock; Flutter measures
    // them clockwise from three, so every arc is turned a quarter back.
    final start = sector.startAngle - math.pi / 2;

    return Path()
      ..arcTo(
        Rect.fromCircle(center: centre, radius: sector.outerRadius),
        start,
        sector.sweep,
        true,
      )
      ..arcTo(
        Rect.fromCircle(center: centre, radius: sector.innerRadius),
        start + sector.sweep,
        -sector.sweep,
        false,
      )
      ..close();
  }

  /// A name, laid along the radius so long names have room to run.
  void _drawName(Canvas canvas, Offset centre, FanSector sector) {
    final painter = TextPainter(
      text: TextSpan(
        text: sector.node.person.name,
        style: label.copyWith(
          color: sector.generation == 0
              ? colors.onPrimaryContainer
              : colors.onSurface,
        ),
      ),
      textDirection: textDirection,
      maxLines: 2,
      ellipsis: '…',
    );

    if (sector.generation == 0) {
      painter.layout(maxWidth: sector.outerRadius * 1.6);
      painter.paint(
        canvas,
        centre - Offset(painter.width / 2, painter.height / 2),
      );
      return;
    }

    const padding = 6.0;
    painter.layout(
      maxWidth: sector.outerRadius - sector.innerRadius - padding * 2,
    );

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    // Turn so the radius through the middle of the slice runs along +x.
    canvas.rotate(sector.middleAngle - math.pi / 2);

    // On the left half of the circle that radius points backwards, and text
    // drawn along it would be upside down — so it is turned over and drawn
    // from the outside in.
    final upsideDown =
        sector.middleAngle > math.pi * 0.02 &&
        sector.middleAngle < math.pi * 1.98 &&
        math.cos(sector.middleAngle - math.pi / 2) < 0;
    if (upsideDown) {
      canvas.rotate(math.pi);
      painter.paint(
        canvas,
        Offset(-sector.outerRadius + padding, -painter.height / 2),
      );
    } else {
      painter.paint(
        canvas,
        Offset(sector.innerRadius + padding, -painter.height / 2),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FanPainter old) =>
      old.layout != layout || old.colors != colors;
}
