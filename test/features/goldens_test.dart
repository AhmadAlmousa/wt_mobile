@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/app/theme.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/records.dart';
import 'package:webtrees_mobile/features/browse/authenticated_image.dart';
import 'package:webtrees_mobile/features/charts/chart_canvas.dart';
import 'package:webtrees_mobile/features/charts/chart_layout.dart';
import 'package:webtrees_mobile/features/charts/chart_options.dart';
import 'package:webtrees_mobile/features/shared/message_panel.dart';
import 'package:webtrees_mobile/features/shared/person_tile.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';

import '../support/fonts.dart';
import '../support/no_records.dart';

/// Pictures of the parts a person judges rather than asserts on.
///
/// Everything else in this suite answers "is this value right". These answer
/// "does this still look like what somebody signed off", which is a different
/// question and the one four bugs in §7 of `PROJECT.md` turned out to need —
/// a mourning ribbon that read as a smudge, a chart export that photographed
/// the window.
///
/// **A golden catches a change, not a mistake.** The first picture is only as
/// good as the eye that approved it, so a failure here is an instruction to
/// *look*: run `flutter test --update-goldens` and read the diff before
/// accepting it.
///
/// Deliberately small and component-level rather than whole screens. A screen
/// golden fails whenever anything on the screen moves, which trains everyone
/// to accept the diff without reading it; these fail for one reason each.
/// Whole screens are still rendered — `tool/preview/render_preview.dart` —
/// but as pictures to look at, not as assertions.
void main() {
  setUpAll(loadAppFonts);

  /// Renders [child] on a surface exactly the size it asks for.
  Future<void> shot(
    WidgetTester tester,
    String name, {
    required Widget child,
    required Brightness brightness,
    required TextDirection direction,
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final locale = direction == TextDirection.rtl
        ? const Locale('ar')
        : const Locale('en');

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        theme: brightness == Brightness.light
            ? AppTheme.light(locale)
            : AppTheme.dark(locale),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(padding: const EdgeInsets.all(12), child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  /// Every combination of the two things an avatar has to say without words.
  Widget avatars() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final deceased in [false, true])
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (sex, name) in const [
              (Sex.male, 'محمد'),
              (Sex.female, 'نورة'),
              (Sex.unknown, 'Q'),
            ])
              Padding(
                padding: const EdgeInsets.all(8),
                child: AuthenticatedImage(
                  url: null,
                  records: const NoRecords(),
                  name: name,
                  sex: sex,
                  deceased: deceased,
                  size: 56,
                ),
              ),
          ],
        ),
    ],
  );

  PersonRef person(
    String name, {
    String? alternate,
    String? lifespan,
    Sex sex = Sex.male,
    bool deceased = false,
  }) => PersonRef(
    xref: 'X1',
    name: name,
    alternateName: alternate,
    lifespan: lifespan,
    sex: sex,
    isDeceased: deceased,
  );

  Widget tiles() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      PersonTile(
        person: person(
          'عبد الله الموسى',
          alternate: 'Abdullah Almousa',
          lifespan: '1901–1974',
          deceased: true,
        ),
        records: const NoRecords(),
        onOpen: () {},
      ),
      PersonTile(
        person: person('نورة الموسى', sex: Sex.female),
        records: const NoRecords(),
        dense: true,
        onOpen: () {},
      ),
      PersonTile(
        person: person('خالد الموسى', lifespan: '1926–2001', deceased: true),
        records: const NoRecords(),
        relationship: 'الإبن',
        onOpen: () {},
      ),
    ],
  );

  /// A couple whose marriage ended, and their child.
  ///
  /// Three boxes and two kinds of line: the parted-couple mark is a
  /// hand-drawn convention that has to survive being shrunk, and nothing but
  /// a picture can say whether it still does.
  Widget chart({required bool colourBySex}) {
    final layout = layoutDescendants(
      DescendantNode(
        person: person(
          'عبد الله الموسى',
          lifespan: '1901–1974',
          deceased: true,
        ),
        number: '1',
        families: [
          DescendantFamily(
            xref: 'F1',
            spouse: person('سارة القحطاني', sex: Sex.female, deceased: true),
            endedInDivorce: true,
            children: [
              DescendantNode(
                person: person('خالد الموسى', lifespan: '1926–'),
                number: '1.1',
              ),
            ],
          ),
        ],
      ),
    );

    final canvas = ChartCanvas(
      layout: layout,
      records: const NoRecords(),
      options: ChartOptions(colourBySex: colourBySex),
      onTapPerson: (_) {},
    );

    // `chartOnly` is the chart outside its viewport — the same thing an
    // export captures — so this draws exactly what a shared picture holds.
    return SizedBox(
      width: layout.size.width,
      height: layout.size.height,
      child: Builder(builder: canvas.chartOnly),
    );
  }

  Widget panels() => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      MessagePanel.error('The site is offline for maintenance.'),
      SizedBox(height: 8),
      MessagePanel.warning('Photos could not be loaded for this person.'),
    ],
  );

  for (final (brightness, mode) in const [
    (Brightness.light, 'light'),
    (Brightness.dark, 'dark'),
  ]) {
    for (final (direction, way) in const [
      (TextDirection.ltr, 'ltr'),
      (TextDirection.rtl, 'rtl'),
    ]) {
      testWidgets('an avatar says sex and death $way $mode', (tester) async {
        await shot(
          tester,
          'avatars-$way-$mode',
          child: avatars(),
          brightness: brightness,
          direction: direction,
          size: const Size(280, 190),
        );
      });

      testWidgets('a person in a list $way $mode', (tester) async {
        await shot(
          tester,
          'person-tile-$way-$mode',
          child: SizedBox(width: 360, child: tiles()),
          brightness: brightness,
          direction: direction,
          size: const Size(400, 300),
        );
      });
    }

    testWidgets('a family whose marriage ended $mode', (tester) async {
      await shot(
        tester,
        'chart-parted-$mode',
        child: chart(colourBySex: false),
        brightness: brightness,
        direction: TextDirection.ltr,
        size: const Size(560, 260),
      );
    });

    testWidgets('a chart coloured by sex $mode', (tester) async {
      await shot(
        tester,
        'chart-by-sex-$mode',
        child: chart(colourBySex: true),
        brightness: brightness,
        direction: TextDirection.ltr,
        size: const Size(560, 260),
      );
    });

    testWidgets('something went wrong $mode', (tester) async {
      await shot(
        tester,
        'message-panel-$mode',
        child: SizedBox(width: 360, child: panels()),
        brightness: brightness,
        direction: TextDirection.ltr,
        size: const Size(400, 220),
      );
    });
  }
}
