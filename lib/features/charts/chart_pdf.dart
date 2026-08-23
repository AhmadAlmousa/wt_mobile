/// A chart on a page as shapes and text, rather than as a photograph of one.
///
/// The first version of the export put the rendered picture on a sized page.
/// That is a screenshot: it is fixed at whatever resolution it was captured
/// at, so a pedigree printed at A2 or opened on a laptop is soft, and none of
/// it can be searched, selected or scaled. A family chart is exactly the kind
/// of document somebody prints large and keeps.
///
/// So the page is drawn again here, from the same layout the screen drew from
/// — rounded boxes, joining lines, ring slices and text, all as vectors. The
/// only raster on the page is a photograph, which was a photograph to begin
/// with.
///
/// **Arabic is why this is not obvious.** PDF has no shaping engine: text is
/// glyphs at positions, so a library has to join the letters itself before it
/// writes them. `package:pdf` does — it runs the bidirectional algorithm and
/// substitutes presentation forms — and the app's own Cairo face carries them,
/// which is what makes an Arabic family tree a real document rather than a
/// picture of one.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui show TextDirection;

import 'package:flutter/material.dart' show Color, ColorScheme, Offset, Size;
import 'package:flutter/services.dart' show rootBundle;
import 'package:meta/meta.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/theme.dart';
import '../../domain/records.dart';
import '../shared/bidi.dart';
import 'chart_layout.dart';
import 'chart_options.dart';
import 'fan_layout.dart';

/// Room around the chart, so the outermost boxes are not against the trim.
const double _margin = 24;

/// The colours a chart is drawn in.
///
/// Carried rather than read from a `BuildContext`, because a page is built
/// after the sheet that asked for it has already closed.
@immutable
class ChartInk {
  const ChartInk({required this.colors, required this.people});

  final ColorScheme colors;
  final PersonColors people;
}

/// A pedigree, a descendancy or an hourglass, drawn as shapes.
///
/// [photos] is keyed by thumbnail URL. A face that could not be fetched is
/// simply absent, and the initial takes its place — the same fallback the
/// screen uses, for the same reason.
Future<Uint8List> boxChartPage({
  required ChartLayout layout,
  required ChartOptions options,
  required ChartInk ink,
  required String title,
  bool rightToLeft = false,
  Map<String, Uint8List> photos = const {},
}) async {
  final size = layout.size;

  return _page(
    title: title,
    ink: ink,
    size: size,
    body: pw.Stack(
      children: [
        pw.Positioned(
          left: 0,
          top: 0,
          child: pw.CustomPaint(
            size: PdfPoint(size.width, size.height),
            painter: (canvas, box) => _paintJoins(canvas, box, layout, ink),
          ),
        ),
        for (final placement in layout.people)
          pw.Positioned(
            left: placement.topLeft.dx,
            top: placement.topLeft.dy,
            child: _personBox(
              placement,
              layout.metrics,
              options,
              ink,
              photos,
              rightToLeft: rightToLeft,
            ),
          ),
      ],
    ),
  );
}

/// The same ancestors bent round a circle.
Future<Uint8List> fanChartPage({
  required FanLayout layout,
  required ChartInk ink,
  required String title,
}) async {
  final size = Size(layout.diameter, layout.diameter);

  return _page(
    title: title,
    ink: ink,
    size: size,
    body: pw.Stack(
      children: [
        pw.Positioned(
          left: 0,
          top: 0,
          child: pw.CustomPaint(
            size: PdfPoint(size.width, size.height),
            painter: (canvas, box) => _paintRings(canvas, box, layout, ink),
          ),
        ),
        for (final sector in layout.sectors) _fanName(sector, layout, ink),
      ],
    ),
  );
}

/// One page shaped to the chart on it.
///
/// Sized to the drawing rather than to A4: a pedigree is far wider than it is
/// tall, and a landscape chart on a portrait page is mostly margin.
Future<Uint8List> _page({
  required String title,
  required ChartInk ink,
  required Size size,
  required pw.Widget body,
}) async {
  final document = pw.Document(title: title, theme: await _theme());

  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(
        size.width + _margin * 2,
        size.height + _margin * 2,
        marginAll: _margin,
      ),
      // The reader's own surface, so a chart looked at in the dark and a
      // chart sent to somebody are recognisably the same drawing.
      build: (context) => pw.Container(
        color: _pdf(ink.colors.surface),
        child: pw.SizedBox(width: size.width, height: size.height, child: body),
      ),
    ),
  );

  return document.save();
}

/// The app's own face, embedded once per document.
///
/// The same file the interface is set in, so a name that fits a box on screen
/// fits the same box on the page — and, more importantly, so Arabic has
/// glyphs to be shaped into at all.
pw.ThemeData? _cached;

Future<pw.ThemeData> _theme() async {
  Future<pw.Font> face(String weight) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-$weight.ttf'));

  return _cached ??= pw.ThemeData.withFont(
    base: await face('Regular'),
    bold: await face('SemiBold'),
  );
}

/// One person, drawn the way the chart draws them.
pw.Widget _personBox(
  ChartPlacement placement,
  ChartMetrics metrics,
  ChartOptions options,
  ChartInk ink,
  Map<String, Uint8List> photos, {
  required bool rightToLeft,
}) {
  final colors = ink.colors;
  final person = placement.person;

  final (background, border) = options.colourBySex
      ? (
          ink.people.forSex(person.sex).$1,
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

  final lifespan = person.lifespan;
  // A name hugs the edge the reading starts from, whatever script it is in.
  final edge = rightToLeft ? pw.TextAlign.right : pw.TextAlign.left;

  return pw.Container(
    width: placement.width,
    height: metrics.boxHeight,
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: pw.BoxDecoration(
      color: _pdf(background),
      borderRadius: pw.BorderRadius.circular(AppTheme.shapeMedium),
      border: pw.Border.all(
        color: _pdf(border),
        width: placement.isSubject ? 2 : 1,
      ),
    ),
    // The page library has no directionality of its own, so the row is turned
    // round here: in Arabic the face belongs on the right, where the reading
    // starts, exactly as it does on screen.
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        for (final piece in _ordered(
          face: options.showPhotos
              ? _face(person, ink, photos, rightToLeft: rightToLeft)
              : null,
          text: pw.Expanded(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: rightToLeft
                  ? pw.CrossAxisAlignment.end
                  : pw.CrossAxisAlignment.start,
              children: [
                _line(
                  person.name,
                  size: 13,
                  color: colors.onSurface,
                  maxLines: 2,
                  align: edge,
                ),
                if (options.showDates && lifespan != null)
                  _line(
                    lifespan,
                    size: 11,
                    color: colors.onSurfaceVariant,
                    // All digits and a dash, and nothing in it says which way
                    // to read: stated here rather than isolated with a control
                    // character, because a page states the direction of every
                    // run it draws.
                    direction: pw.TextDirection.ltr,
                    align: edge,
                  ),
              ],
            ),
          ),
          rightToLeft: rightToLeft,
        ))
          piece,
      ],
    ),
  );
}

/// A face and a name, in the order the reader's script puts them.
List<pw.Widget> _ordered({
  required pw.Widget? face,
  required pw.Widget text,
  required bool rightToLeft,
}) {
  if (face == null) return [text];
  final gap = pw.SizedBox(width: 8);
  return rightToLeft ? [text, gap, face] : [face, gap, text];
}

/// A photograph, or the initial that stands in for one.
pw.Widget _face(
  PersonRef person,
  ChartInk ink,
  Map<String, Uint8List> photos, {
  required bool rightToLeft,
}) {
  const size = 40.0;
  final url = person.thumbnailUrl;
  final bytes = url == null ? null : photos[url];
  final (background, foreground) = ink.people.forSex(person.sex);
  final radius = pw.BorderRadius.circular(8);

  final portrait = bytes == null
      ? pw.Container(
          width: size,
          height: size,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            color: _pdf(background),
            borderRadius: radius,
            border: pw.Border.all(
              color: _pdf(foreground.withValues(alpha: 0.14)),
            ),
          ),
          child: _line(
            _initialOf(person.name) ?? '',
            size: size * 0.42,
            color: foreground,
            direction: pw.TextDirection.ltr,
          ),
        )
      : pw.ClipRRect(
          horizontalRadius: 8,
          verticalRadius: 8,
          child: pw.Image(
            pw.MemoryImage(bytes),
            width: size,
            height: size,
            fit: pw.BoxFit.cover,
          ),
        );

  if (!person.isDeceased) return portrait;

  // The mourning ribbon, drawn rather than photographed like everything else
  // here. It is the one mark on a chart that says something the names do not.
  return pw.Stack(
    children: [
      portrait,
      pw.Positioned(
        left: 0,
        top: 0,
        child: pw.CustomPaint(
          size: const PdfPoint(size, size),
          painter: (canvas, box) =>
              _paintRibbon(canvas, box, fromTheStart: !rightToLeft),
        ),
      ),
    ],
  );
}

/// One run of text, in the direction its own script asks for.
pw.Widget _line(
  String text, {
  required double size,
  required Color color,
  int maxLines = 1,
  pw.TextDirection? direction,
  pw.TextAlign? align,
}) => pw.Text(
  text,
  maxLines: maxLines,
  overflow: pw.TextOverflow.clip,
  textAlign: align,
  textDirection: direction ?? _directionOf(text),
  style: pw.TextStyle(
    fontSize: size,
    color: _pdf(color),
    fontWeight: pw.FontWeight.bold,
  ),
);

/// The lines joining a person to their family, in the chart's own geometry.
void _paintJoins(
  PdfGraphics canvas,
  PdfPoint box,
  ChartLayout layout,
  ChartInk ink,
) {
  // PDF measures upwards from the bottom of the page and the layout measures
  // downwards from the top, so every y is turned over on the way through.
  double up(double y) => box.y - y;

  void stroke(Color color, double width, void Function() path) {
    canvas
      ..setStrokeColor(_pdf(color))
      ..setLineWidth(width);
    path();
    canvas.strokePath();
  }

  for (final edge in layout.edges) {
    if (edge.isCouple) {
      if (edge.kind == EdgeKind.divorce) {
        _paintParted(canvas, edge, up, ink);
      } else {
        stroke(ink.colors.outline, 2, () {
          canvas
            ..moveTo(edge.from.dx, up(edge.from.dy))
            ..lineTo(edge.to.dx, up(edge.to.dy));
        });
      }
      continue;
    }

    stroke(ink.colors.outlineVariant, 1.5, () {
      canvas.moveTo(edge.from.dx, up(edge.from.dy));
      if (layout.flow == ChartFlow.sideways) {
        final middle = (edge.from.dx + edge.to.dx) / 2;
        canvas
          ..lineTo(middle, up(edge.from.dy))
          ..lineTo(middle, up(edge.to.dy));
      } else {
        final middle = (edge.from.dy + edge.to.dy) / 2;
        canvas
          ..lineTo(edge.from.dx, up(middle))
          ..lineTo(edge.to.dx, up(middle));
      }
      canvas.lineTo(edge.to.dx, up(edge.to.dy));
    });
  }
}

/// A couple whose marriage ended, marked the way it is on paper.
void _paintParted(
  PdfGraphics canvas,
  ChartEdge edge,
  double Function(double) up,
  ChartInk ink,
) {
  final span = (edge.to - edge.from).distance;
  final along = span == 0 ? const Offset(1, 0) : (edge.to - edge.from) / span;
  final across = Offset(-along.dy, along.dx);
  final mark = edge.to - along * math.min(span / 2, 20);
  final gap = (span * 0.34).clamp(3.0, 7.0);

  void line(Offset from, Offset to) {
    canvas
      ..moveTo(from.dx, up(from.dy))
      ..lineTo(to.dx, up(to.dy));
  }

  canvas
    ..setStrokeColor(_pdf(ink.colors.outline))
    ..setLineWidth(2);

  line(edge.from, mark - along * gap);
  line(mark + along * gap, edge.to);
  for (final offset in [-gap / 2, gap / 2]) {
    final at = mark + along * offset;
    line(at - across * 4 - along * 2, at + across * 4);
  }
  canvas.strokePath();
}

/// The rings of a fan, one slice per person.
void _paintRings(
  PdfGraphics canvas,
  PdfPoint box,
  FanLayout layout,
  ChartInk ink,
) {
  final centre = layout.centre;
  final cy = box.y - centre;

  for (final sector in layout.sectors) {
    final fill = sector.generation == 0
        ? ink.colors.primaryContainer
        : sector.generation.isEven
        ? ink.colors.surfaceContainerHigh
        : ink.colors.surfaceContainerLow;

    canvas
      ..setFillColor(_pdf(fill))
      ..setStrokeColor(_pdf(ink.colors.surface))
      ..setLineWidth(1.5);

    if (sector.generation == 0) {
      canvas.drawEllipse(centre, cy, sector.outerRadius, sector.outerRadius);
    } else {
      _slice(canvas, centre, cy, sector);
    }
    canvas.fillPath();

    if (sector.generation == 0) {
      canvas.drawEllipse(centre, cy, sector.outerRadius, sector.outerRadius);
    } else {
      _slice(canvas, centre, cy, sector);
    }
    canvas.strokePath();
  }
}

/// The slice of a ring one person occupies.
void _slice(PdfGraphics canvas, double cx, double cy, FanSector sector) {
  final from = sector.startAngle;
  final to = sector.startAngle + sector.sweep;

  _arc(canvas, cx, cy, sector.outerRadius, from, to, move: true);
  _arc(canvas, cx, cy, sector.innerRadius, to, from, move: false);
  canvas.closePath();
}

/// An arc of a circle, as cubic segments no longer than a quarter turn each.
///
/// Angles are the fan's own: radians clockwise from twelve o'clock. PDF puts
/// its origin at the bottom of the page, so clockwise on screen is
/// anticlockwise here and the conversion is done once, in [_at].
void _arc(
  PdfGraphics canvas,
  double cx,
  double cy,
  double radius,
  double from,
  double to, {
  required bool move,
}) {
  final start = _at(cx, cy, radius, from);
  if (move) {
    canvas.moveTo(start.dx, start.dy);
  } else {
    canvas.lineTo(start.dx, start.dy);
  }

  final steps = math.max(1, ((to - from).abs() / (math.pi / 2)).ceil());
  final step = (to - from) / steps;
  // The classic control-point length for a cubic approximation of an arc.
  final handle = 4 / 3 * math.tan(step / 4);

  var angle = from;
  for (var index = 0; index < steps; index++) {
    final next = angle + step;
    final a = _at(cx, cy, radius, angle);
    final b = _at(cx, cy, radius, next);
    // The tangent at each end, turned the same way the arc runs.
    final ta = _tangent(radius, angle) * handle;
    final tb = _tangent(radius, next) * handle;

    canvas.curveTo(
      a.dx + ta.dx,
      a.dy + ta.dy,
      b.dx - tb.dx,
      b.dy - tb.dy,
      b.dx,
      b.dy,
    );
    angle = next;
  }
}

/// A point on a circle, in page coordinates.
Offset _at(double cx, double cy, double radius, double angle) =>
    Offset(cx + radius * math.sin(angle), cy + radius * math.cos(angle));

/// The direction of travel at [angle], in page coordinates.
Offset _tangent(double radius, double angle) =>
    Offset(radius * math.cos(angle), -radius * math.sin(angle));

/// A name laid along the radius of its slice.
pw.Widget _fanName(FanSector sector, FanLayout layout, ChartInk ink) {
  final centre = layout.centre;
  final colors = ink.colors;

  if (sector.generation == 0) {
    final width = sector.outerRadius * 1.6;
    return pw.Positioned(
      left: centre - width / 2,
      top: centre - 20,
      child: pw.SizedBox(
        width: width,
        height: 40,
        child: pw.Center(
          child: _line(
            sector.node.person.name,
            size: 11,
            color: colors.onPrimaryContainer,
            maxLines: 2,
          ),
        ),
      ),
    );
  }

  const padding = 6.0;
  final run = sector.outerRadius - sector.innerRadius - padding * 2;
  final middle = sector.middleAngle;
  final radius = (sector.innerRadius + sector.outerRadius) / 2;

  // Where the middle of the name sits, measured the way the layout measures.
  final at = Offset(
    centre + radius * math.sin(middle),
    centre - radius * math.cos(middle),
  );

  // Turn so the radius runs along the text. On the left half of the circle
  // that radius points backwards and the name would be upside down, so it is
  // turned over — which is what the screen does too.
  var angle = math.pi / 2 - middle;
  if (math.sin(middle) < 0) angle += math.pi;

  // Room for two lines, which is what a family name often needs.
  const height = 34.0;

  return pw.Positioned(
    left: at.dx - run / 2,
    top: at.dy - height / 2,
    child: pw.Transform.rotate(
      angle: angle,
      child: pw.SizedBox(
        width: run,
        height: height,
        child: pw.Center(
          child: _line(
            sector.node.person.name,
            size: 11,
            color: colors.onSurface,
            maxLines: 2,
          ),
        ),
      ),
    ),
  );
}

/// The mourning ribbon across a portrait's leading corner.
///
/// Drawn, not photographed, like everything else on this page — and drawn
/// past the portrait on both sides so the clip, rather than the path, decides
/// where it meets the border.
void _paintRibbon(
  PdfGraphics canvas,
  PdfPoint box, {
  required bool fromTheStart,
}) {
  const outer = 0.30;
  const inner = 0.54;
  final side = math.min(box.x, box.y);
  final beyond = box.x + box.y;

  // A cut across the top-left corner at distance `reach` along each edge is
  // the line `x + y = reach` measured from that corner. This page measures y
  // upwards from the bottom, which turns it into a line of slope one — and
  // mirroring it for the top-right corner turns the slope over.
  double edge(double x, double reach) =>
      fromTheStart ? x - reach + box.y : box.x - x - reach + box.y;

  canvas
    ..saveContext()
    ..drawRRect(0, 0, box.x, box.y, 8, 8)
    ..clipPath()
    ..setFillColor(const PdfColor.fromInt(0xFF16161A))
    ..moveTo(-beyond, edge(-beyond, side * outer))
    ..lineTo(beyond, edge(beyond, side * outer))
    ..lineTo(beyond, edge(beyond, side * inner))
    ..lineTo(-beyond, edge(-beyond, side * inner))
    ..fillPath()
    ..restoreContext();
}

/// The first letter of a name, skipping anything that would draw as nothing.
String? _initialOf(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;

  for (final rune in trimmed.runes) {
    final character = String.fromCharCode(rune);
    if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(character)) {
      return character.toUpperCase();
    }
  }
  return null;
}

/// The direction [text] reads in, as the page library names it.
pw.TextDirection _directionOf(String text) =>
    switch (directionOf(text) ?? ui.TextDirection.ltr) {
      ui.TextDirection.rtl => pw.TextDirection.rtl,
      ui.TextDirection.ltr => pw.TextDirection.ltr,
    };

PdfColor _pdf(Color color) => PdfColor.fromInt(color.toARGB32());
