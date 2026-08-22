import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/app/app.dart';
import 'package:webtrees_mobile/app/theme.dart';
import 'package:webtrees_mobile/core/errors.dart';
import 'package:webtrees_mobile/data/settings_store.dart';
import 'package:webtrees_mobile/domain/notice.dart';
import 'package:webtrees_mobile/features/shared/bidi.dart';
import 'package:webtrees_mobile/features/shared/messages.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';

import '../support/fake_webtrees.dart';
import '../support/test_app.dart';

void main() {
  group('Arabic', () {
    testWidgets('lays the interface out right to left', (tester) async {
      final server = FakeWebtrees(workingSite());
      final session = sessionManagerFor(server);
      addTearDown(session.dispose);

      await tester.pumpWidget(
        WebtreesMobileApp(
          session: session,
          settings: testSettings(locale: const Locale('ar')),
        ),
      );
      await tester.pumpAndSettle();

      // The whole point of supporting Arabic: the layout mirrors. Asserting
      // on the translated copy alone would pass on an interface that read
      // Arabic words in Latin order.
      final direction = Directionality.of(
        tester.element(find.byType(Scaffold).first),
      );
      expect(direction, TextDirection.rtl);
    });

    testWidgets('shows Arabic copy, not English', (tester) async {
      final server = FakeWebtrees(workingSite());
      final session = sessionManagerFor(server);
      addTearDown(session.dispose);

      await tester.pumpWidget(
        WebtreesMobileApp(
          session: session,
          settings: testSettings(locale: const Locale('ar')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('اتّصل بشجرة عائلتك'), findsOne);
      expect(find.text('Connect to your family tree'), findsNothing);
    });

    testWidgets('keeps the site address left to right', (tester) async {
      final server = FakeWebtrees(workingSite());
      final session = sessionManagerFor(server);
      addTearDown(session.dispose);

      await tester.pumpWidget(
        WebtreesMobileApp(
          session: session,
          settings: testSettings(locale: const Locale('ar')),
        ),
      );
      await tester.pumpAndSettle();

      // A hostname is Latin whichever way the page reads; letting it inherit
      // RTL puts the dots and any port in the wrong visual order.
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.textDirection, TextDirection.ltr);
    });

    testWidgets('English stays left to right', (tester) async {
      final server = FakeWebtrees(workingSite());
      final session = sessionManagerFor(server);
      addTearDown(session.dispose);

      await tester.pumpWidget(
        WebtreesMobileApp(
          session: session,
          settings: testSettings(locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        Directionality.of(tester.element(find.byType(Scaffold).first)),
        TextDirection.ltr,
      );
    });
  });

  group('isolating a Latin run', () {
    test('a lifespan keeps its order inside Arabic text', () {
      // Every character of "1875–1940" is a digit or a dash, so the
      // bidirectional algorithm takes its direction from the paragraph around
      // it. In Arabic that renders as 1940–1875, and the person appears to
      // have died before they were born.
      final isolated = ltrRun('1875–1940');
      expect(isolated, startsWith('\u2066'));
      expect(isolated, endsWith('\u2069'));
      expect(isolated, contains('1875–1940'));
    });

    test('a name is left to find its own direction', () {
      // A second recorded name may be Arabic or romanized, and only the text
      // itself can say which.
      expect(isolatedRun('Abdullah'), startsWith('\u2068'));
    });

    test('nothing is wrapped around nothing', () {
      expect(ltrRun(null), isEmpty);
      expect(isolatedRun(''), isEmpty);
    });
  });

  group('the type scale', () {
    // letterSpacing pushes glyphs apart. Arabic letters join, so tracking that
    // sharpens a Latin headline visibly breaks Arabic words into pieces.
    test('drops letter spacing for Arabic', () {
      final arabic = AppTheme.light(const Locale('ar')).textTheme;
      final english = AppTheme.light(const Locale('en')).textTheme;

      expect(arabic.displayLarge!.letterSpacing, 0);
      expect(arabic.bodyMedium!.letterSpacing, 0);
      expect(english.displayLarge!.letterSpacing, isNot(0));
    });

    test('gives Arabic more leading', () {
      final arabic = AppTheme.light(const Locale('ar')).textTheme;
      final english = AppTheme.light(const Locale('en')).textTheme;

      expect(
        arabic.bodyMedium!.height,
        greaterThan(english.bodyMedium!.height!),
      );
    });

    test('uses the bundled family that covers both scripts', () {
      expect(
        AppTheme.light(const Locale('ar')).textTheme.bodyMedium!.fontFamily,
        'Cairo',
      );
    });
  });

  group('semantic colours', () {
    /// WCAG 2.1 relative luminance, so the contrast rule is checked rather
    /// than eyeballed.
    double contrast(Color a, Color b) {
      double channel(double value) => value <= 0.03928
          ? value / 12.92
          : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
      double luminance(Color c) =>
          0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);

      final first = luminance(a);
      final second = luminance(b);
      final lighter = first > second ? first : second;
      final darker = first > second ? second : first;
      return (lighter + 0.05) / (darker + 0.05);
    }

    test('a warning is legible in both themes', () {
      for (final semantic in [SemanticColors.light, SemanticColors.dark]) {
        expect(
          contrast(semantic.onWarningContainer, semantic.warningContainer),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('a warning does not borrow a role the scheme may recolour', () {
      // `DynamicSchemeVariant.expressive` rotates hues far from the seed, and
      // put `tertiaryContainer` on cyan — which reads as information, not
      // caution. Caution has to be fixed, not generated.
      final theme = AppTheme.light(const Locale('en'));
      final semantic = theme.extension<SemanticColors>()!;

      expect(
        semantic.warningContainer,
        isNot(theme.colorScheme.tertiaryContainer),
      );
    });

    test('both themes register the extension', () {
      expect(
        AppTheme.light(const Locale('en')).extension<SemanticColors>(),
        SemanticColors.light,
      );
      expect(
        AppTheme.dark(const Locale('en')).extension<SemanticColors>(),
        SemanticColors.dark,
      );
    });
  });

  group('settings', () {
    test('follow the device until a language is chosen', () {
      final settings = testSettings();

      expect(settings.locale, isNull);
      expect(settings.resolve(const Locale('ar')), const Locale('ar'));
      expect(settings.resolve(const Locale('en')), const Locale('en'));
      // A language the app is not translated into falls back rather than
      // rendering half an interface.
      expect(settings.resolve(const Locale('fr')), const Locale('en'));
    });

    test('a chosen language overrides the device', () async {
      final settings = testSettings();
      await settings.setLocale(const Locale('ar'));

      expect(settings.resolve(const Locale('en')), const Locale('ar'));
    });

    test('choosing null follows the device again', () async {
      final settings = testSettings();
      await settings.setLocale(const Locale('ar'));
      await settings.setLocale(null);

      expect(settings.resolve(const Locale('en')), const Locale('en'));
    });

    test('theme mode defaults to following the device', () {
      expect(testSettings().themeMode, ThemeMode.system);
    });
  });

  group('every message has words in both languages', () {
    // The sealed switches in messages.dart make this a compile-time guarantee
    // for coverage; these check the wiring actually produces Arabic.
    const errors = <WebtreesError>[
      UnreachableHost('example.com'),
      NotWebtrees('example.com'),
      MaintenanceMode(),
      ServerUnhealthy(),
      BlockedAsBot('agent'),
      SignInRejected(),
      StaleSignIn(),
      SessionExpired(),
      NotPermitted(),
      NotFound(),
      UnexpectedResponse(500),
      CannotRead('the page'),
      ParseFailure(parser: 'facts', expected: 'a table'),
    ];

    const notices = <Notice>[
      BlocklistUnchecked('timeout'),
      VersionUnreadable(),
      SiteUnidentified(),
      NoTreesVisible(),
      OnlyOneTreeFound(),
      SectionUnavailable('personal_facts'),
      SectionUnavailable('relatives'),
      SectionUnavailable('notes'),
      SectionUnavailable('sources_tab'),
      SectionUnavailable('media'),
      // A module this app has never heard of, which a site may still offer.
      SectionUnavailable('_vytux_cousins_'),
    ];

    for (final locale in SettingsStore.supportedLocales) {
      test('in ${locale.languageCode}', () async {
        final text = await AppText.delegate.load(locale);

        for (final error in errors) {
          expect(
            error.localized(text),
            isNotEmpty,
            reason: '$error has no words in $locale',
          );
        }
        for (final notice in notices) {
          expect(
            notice.localized(text),
            isNotEmpty,
            reason: '$notice has no words in $locale',
          );
        }
      });
    }

    test('Arabic really is Arabic, not the English fallback', () async {
      final text = await AppText.delegate.load(const Locale('ar'));

      expect(
        const SessionExpired().localized(text),
        isNot(equals('Your session ended. Sign in again.')),
      );
      expect(const NoTreesVisible().localized(text), contains('شجرة'));
    });

    test('a site’s own rejection message is preferred over ours', () async {
      final text = await AppText.delegate.load(const Locale('ar'));

      // webtrees answers a wrong password, an unverified email and an
      // unapproved account differently. Its sentence is more specific than
      // anything this app could translate, so it wins.
      expect(
        const SignInRejected(
          serverMessage: 'الحساب بانتظار الموافقة',
        ).localized(text),
        'الحساب بانتظار الموافقة',
      );
    });
  });
  group('text a tree wrote, on a screen in another language', () {
    test('takes its direction from what it says', () {
      // A tree records its notes and places in the family's language, not the
      // reader's. An Arabic note on an English screen belongs on the right of
      // its card, with its full stop at the left end — which is what webtrees
      // itself does with `dir="auto"` on the same content.
      expect(directionOf('هاجر إلى الكويت'), TextDirection.rtl);
      expect(directionOf('Merchant'), TextDirection.ltr);
      // Latin punctuation ahead of Arabic does not make it English.
      expect(directionOf('"سجل قيد العائلة"'), TextDirection.rtl);
    });

    test('leaves a run with no letters to the screen around it', () {
      // A bare year or a record id says nothing about direction, and forcing
      // one would mirror a line that is fine as it is.
      expect(directionOf('1901–1974'), isNull);
      expect(directionOf(''), isNull);
      expect(directionOf(null), isNull);
    });
  });
}
