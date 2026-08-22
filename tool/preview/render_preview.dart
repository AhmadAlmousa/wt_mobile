import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/app/app.dart';
import 'package:webtrees_mobile/data/settings_store.dart';

import '../../test/support/fake_webtrees.dart';
import '../../test/support/test_app.dart';

/// Renders real screens to PNG files so the interface can be looked at.
///
/// Not an assertion: widget tests prove a string is present, not that the type
/// scale, colour and mirroring add up to something a person would want to use.
/// When there is no desktop toolchain to run the app on, this is the only way
/// to see it before it reaches a device.
///
/// Lives outside `test/` and is not named `*_test.dart`, so a normal
/// `flutter test` does not collect it — it writes files and asserts nothing.
///
/// ```
/// flutter test tool/preview/render_preview.dart --update-goldens
/// ```
Future<void> main() async {
  const output = 'build/preview';

  setUpAll(() async {
    // A test binding registers no fonts at all. Without the app's own family
    // the Arabic renders as boxes, and without the icon font every icon does
    // — which would make the whole exercise misleading rather than merely
    // incomplete.
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      await (FontLoader('Cairo')..addFont(
        _bytesOf('assets/fonts/Cairo-$weight.ttf'),
      )).load();
    }
    await (FontLoader('MaterialIcons')..addFont(
      _bytesOf(
        '${Platform.environment['FLUTTER_ROOT'] ?? '/home/ahmad/flutter'}'
        '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    )).load();

    Directory(output).createSync(recursive: true);
  });

  /// Renders one screen, reached by driving the interface rather than the
  /// session directly: a future started outside the pump loop never completes.
  Future<void> capture(
    WidgetTester tester,
    String name, {
    required Locale locale,
    required ThemeMode theme,
    int steps = 0,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final server = FakeWebtrees(workingSite());
    final session = sessionManagerFor(server);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      WebtreesMobileApp(
        session: session,
        settings: testSettings(locale: locale, theme: theme),
      ),
    );
    await tester.pumpAndSettle();

    // Buttons are found by type, not by their label: the label is translated
    // and this runs in both languages.
    if (steps >= 1) {
      await tester.enterText(find.byType(TextFormField), 'host');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
    }
    if (steps >= 2) {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'mobile');
      await tester.enterText(fields.at(1), 'correct');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
    }
    if (steps >= 3) {
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
    }

    await expectLater(
      find.byType(WebtreesMobileApp),
      matchesGoldenFile('../../$output/$name.png'),
    );
  }

  for (final locale in SettingsStore.supportedLocales) {
    final tag = locale.languageCode;
    for (final (theme, mode) in [
      (ThemeMode.light, 'light'),
      (ThemeMode.dark, 'dark'),
    ]) {
      testWidgets('connect $tag $mode', (tester) async {
        await capture(tester, 'connect-$tag-$mode',
            locale: locale, theme: theme);
      });

      testWidgets('sign-in $tag $mode', (tester) async {
        await capture(tester, 'signin-$tag-$mode',
            locale: locale, theme: theme, steps: 1);
      });

      testWidgets('access $tag $mode', (tester) async {
        await capture(tester, 'access-$tag-$mode',
            locale: locale, theme: theme, steps: 2);
      });

      testWidgets('settings $tag $mode', (tester) async {
        await capture(tester, 'settings-$tag-$mode',
            locale: locale, theme: theme, steps: 3);
      });
    }
  }
}

Future<ByteData> _bytesOf(String path) =>
    File(path).readAsBytes().then((bytes) => ByteData.view(bytes.buffer));
