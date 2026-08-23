import 'dart:io';

import 'package:flutter/services.dart';

/// Registers the fonts the app actually ships, for tests that look at pixels.
///
/// A test binding registers none: every glyph is a box of the right width and
/// nothing else. That is fine for asserting a string is present and useless
/// for anything that judges what a screen *looks like* — Arabic renders as
/// boxes, every icon renders as a box, and a golden of that proves nothing
/// about the app.
///
/// The icon font comes from the Flutter installation rather than from this
/// repository, because it is not ours to vendor. `FLUTTER_ROOT` is set by the
/// `flutter` tool; the fallback is only for a bare `dart test`.
Future<void> loadAppFonts() async {
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    await (FontLoader(
      'Cairo',
    )..addFont(_bytesOf('assets/fonts/Cairo-$weight.ttf'))).load();
  }

  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;

  await (FontLoader('MaterialIcons')..addFont(
        _bytesOf(
          '$root/bin/cache/artifacts/material_fonts/'
          'MaterialIcons-Regular.otf',
        ),
      ))
      .load();
}

Future<ByteData> _bytesOf(String path) =>
    File(path).readAsBytes().then((bytes) => ByteData.view(bytes.buffer));
