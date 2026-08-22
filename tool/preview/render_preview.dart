import 'dart:convert';
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
/// A site with enough content to photograph the browsing screens.
///
/// The fixtures are the same ones the parser tests run against, so what these
/// pictures show is what the parsers actually produce.
Map<String, Canned Function(Sent)> _browsableSite() {
  String fixture(String name) =>
      File('test/fixtures/v2_2_6/$name').readAsStringSync();

  return {
    ...workingSite(),
    '/tree/main/tom-select-individual': (request) => Canned(
      200,
      contentType: 'application/json',
      body: jsonEncode({
        'data': [
          {
            'value': 'X42',
            'text':
                '<span class="NAME" dir="auto">عبد الله '
                '<span class="SURN">الموسى</span></span>, 1901–1974',
          },
        ],
        'nextUrl': null,
      }),
    ),
    '/tree/main/individual/X42': (_) =>
        Canned(200, body: fixture('individual_page.html')),
    '/module/personal_facts/Tab/main': (_) =>
        Canned(200, body: fixture('tab_personal_facts.html')),
    '/module/relatives/Tab/main': (_) =>
        Canned(200, body: fixture('tab_relatives.html')),
    '/module/notes/Tab/main': (_) =>
        Canned(200, body: fixture('tab_notes.html')),
    '/module/sources_tab/Tab/main': (_) =>
        Canned(200, body: fixture('tab_sources.html')),
    '/module/media/Tab/main': (_) =>
        Canned(200, body: fixture('tab_media.html')),
  };
}

Future<void> main() async {
  const output = 'build/preview';

  setUpAll(() async {
    // A test binding registers no fonts at all. Without the app's own family
    // the Arabic renders as boxes, and without the icon font every icon does
    // — which would make the whole exercise misleading rather than merely
    // incomplete.
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      await (FontLoader(
        'Cairo',
      )..addFont(_bytesOf('assets/fonts/Cairo-$weight.ttf'))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          _bytesOf(
            '${Platform.environment['FLUTTER_ROOT'] ?? '/home/ahmad/flutter'}'
            '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
        ))
        .load();

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
    double scroll = 0,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final server = FakeWebtrees(_browsableSite());
    final settings = testSettings(locale: locale, theme: theme);
    final session = sessionManagerFor(server, settings: settings);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      WebtreesMobileApp(session: session, settings: settings),
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
    // Signing in lands in the tree, because this account can reach exactly
    // one — so the account screen is a step further in, not a step back.
    if (steps >= 3) {
      await tester.enterText(find.byType(TextField), 'الموسى');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('عبد الله الموسى'));
      await tester.pumpAndSettle();
    }
    if (steps >= 4) {
      // The Android back gesture, which is how anyone actually leaves this
      // screen. `pageBack()` hunts for a back button and finds none here.
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      await WidgetsBinding.instance.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
    }
    if (steps >= 5) {
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
    }

    // A person's page is longer than a phone screen, and the family, photos,
    // notes and sources all live below the fold — the parts most worth
    // looking at before they reach a device.
    if (scroll > 0) {
      await tester.drag(find.byType(Scrollable).first, Offset(0, -scroll));
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
        await capture(
          tester,
          'connect-$tag-$mode',
          locale: locale,
          theme: theme,
        );
      });

      testWidgets('sign-in $tag $mode', (tester) async {
        await capture(
          tester,
          'signin-$tag-$mode',
          locale: locale,
          theme: theme,
          steps: 1,
        );
      });

      testWidgets('tree $tag $mode', (tester) async {
        await capture(
          tester,
          'tree-$tag-$mode',
          locale: locale,
          theme: theme,
          steps: 2,
        );
      });

      testWidgets('person $tag $mode', (tester) async {
        await capture(
          tester,
          'person-$tag-$mode',
          locale: locale,
          theme: theme,
          steps: 3,
        );
      });

      testWidgets('person, further down $tag $mode', (tester) async {
        await capture(
          tester,
          'person-family-$tag-$mode',
          locale: locale,
          theme: theme,
          steps: 3,
          scroll: 1100,
        );
      });

      testWidgets('access $tag $mode', (tester) async {
        await capture(
          tester,
          'access-$tag-$mode',
          locale: locale,
          theme: theme,
          steps: 4,
        );
      });

      testWidgets('settings $tag $mode', (tester) async {
        await capture(
          tester,
          'settings-$tag-$mode',
          locale: locale,
          theme: theme,
          steps: 5,
        );
      });
    }
  }
}

Future<ByteData> _bytesOf(String path) =>
    File(path).readAsBytes().then((bytes) => ByteData.view(bytes.buffer));
