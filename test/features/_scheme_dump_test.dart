import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/app/theme.dart';

String hex(Color c) =>
    '#${((c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(6, '0')}';

void main() {
  test('dump', () {
    for (final (name, theme) in [
      ('light', AppTheme.light(const Locale('en'))),
      ('dark', AppTheme.dark(const Locale('en'))),
    ]) {
      final s = theme.colorScheme;
      // ignore: avoid_print
      print(
        '$name surface=${hex(s.surface)} surfaceContainerLow=${hex(s.surfaceContainerLow)} '
        'primary=${hex(s.primary)} secondary=${hex(s.secondary)} tertiary=${hex(s.tertiary)} '
        'error=${hex(s.error)} outline=${hex(s.outline)} '
        'primaryContainer=${hex(s.primaryContainer)} onSurface=${hex(s.onSurface)}',
      );
    }
  });
}
