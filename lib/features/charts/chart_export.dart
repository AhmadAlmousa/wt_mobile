import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// What a chart can be handed to somebody else as.
enum ChartFormat {
  /// One picture, which is what most people send each other.
  image('png', 'image/png'),

  /// The same picture on a page, for printing and for anyone who would rather
  /// receive a document.
  pdf('pdf', 'application/pdf');

  const ChartFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
}

/// A chart could not be turned into a file.
class ChartExportFailed implements Exception {
  const ChartExportFailed(this.reason);

  /// Why, for the log. What the reader is told is chosen by the screen.
  final String reason;

  /// Whether the chart was simply too large to draw into one picture.
  bool get isTooLarge => reason == _tooLarge;

  static const String _tooLarge = 'too large';

  @override
  String toString() => 'ChartExportFailed($reason)';
}

/// Turns the chart behind [boundary] into a file and offers it to the reader.
///
/// The boundary wraps the chart at its **natural size**, outside the viewport
/// it is being looked at through, so what is captured is the whole family
/// rather than the part of it that happened to be on screen.
///
/// [title] names the file and the share sheet; [origin] is where the sharing
/// sheet should appear from on the platforms that anchor it to a widget.
Future<void> shareChart({
  required GlobalKey boundary,
  required ChartFormat format,
  required String title,
  Rect? origin,
}) async {
  final image = await _capture(boundary);
  final bytes = switch (format) {
    ChartFormat.image => image.bytes,
    ChartFormat.pdf => await _pageOf(image, title: title),
  };

  final directory = await getTemporaryDirectory();
  final file = File(
    '${directory.path}/${_fileName(title)}.${format.extension}',
  );
  await file.writeAsBytes(bytes);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: format.mimeType)],
      subject: title,
      sharePositionOrigin: origin,
    ),
  );
}

/// A rendered chart, and how large it came out.
class _Captured {
  const _Captured(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final double width;
  final double height;
}

/// The largest picture worth trying to make.
///
/// A deep descendants chart is thousands of points wide, and asking the GPU
/// for a texture beyond its limit fails at capture time with nothing useful
/// to say. Refusing early, with a sentence the reader can act on, is better
/// than a crash halfway through a share sheet.
const double _widestPicture = 8000;

/// What a chart is drawn at, when there is room for it.
///
/// Twice the logical size, so a chart looks like a picture rather than a
/// screenshot when somebody opens it on a laptop.
const double _preferredDetail = 2;

Future<_Captured> _capture(GlobalKey boundary) async {
  final object = boundary.currentContext?.findRenderObject();
  if (object is! RenderRepaintBoundary || object.size.isEmpty) {
    throw const ChartExportFailed('nothing to capture');
  }
  final size = object.size;

  final detail = [
    _preferredDetail,
    _widestPicture / size.width,
    _widestPicture / size.height,
  ].reduce((a, b) => a < b ? a : b);
  if (detail <= 0.5) {
    // Even at half size it would not fit, which no amount of patience fixes.
    throw const ChartExportFailed(ChartExportFailed._tooLarge);
  }

  final ui.Image rendered = await object.toImage(pixelRatio: detail);
  try {
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw const ChartExportFailed('nothing to encode');
    return _Captured(
      data.buffer.asUint8List(),
      size.width,
      size.height,
    );
  } finally {
    rendered.dispose();
  }
}

/// The picture on a page shaped to fit it.
///
/// A page sized to the chart rather than to A4: a pedigree is far wider than
/// it is tall, and a landscape chart shrunk into a portrait page is mostly
/// margin. Nothing is typeset — the only thing on the page is the image the
/// app already rendered — which is what keeps Arabic shaping out of a
/// library that would have to reimplement it.
Future<Uint8List> _pageOf(_Captured chart, {required String title}) async {
  final document = pw.Document(title: title);
  final page = PdfPageFormat(
    chart.width + 48,
    chart.height + 48,
    marginAll: 24,
  );

  document.addPage(
    pw.Page(
      pageFormat: page,
      build: (context) => pw.FittedBox(
        child: pw.Image(pw.MemoryImage(chart.bytes)),
      ),
    ),
  );
  return document.save();
}

/// A file name that will survive being sent somewhere.
///
/// Arabic names are perfectly good file names on the platforms this app runs
/// on, but they do not survive every service they may be forwarded through —
/// so anything that is not plainly safe becomes an underscore, and a name
/// that reduces to nothing falls back to a word.
String _fileName(String title) {
  final safe = title
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), '_');
  return safe.isEmpty ? 'chart' : safe;
}
