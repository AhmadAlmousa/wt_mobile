import 'package:flutter/material.dart';

import '../domain/records.dart';

/// The application's visual identity, in the Material 3 Expressive idiom.
///
/// Expressive is not a switch Flutter exposes as one flag, so it is assembled
/// here from the parts that carry its character: a scheme built with
/// [DynamicSchemeVariant.expressive], a type scale with real weight contrast,
/// a generous and *varied* shape scale, and springy motion.
///
/// The seed stays the project's muted archival green — the colour of aged
/// ledger cloth — because the expressive variant derives a far wider spread of
/// hues from a seed than the tonal-spot default does. The calm base is still
/// what sits behind photographs and dense name lists; the energy goes into
/// containers, accents and shape.
abstract final class AppTheme {
  const AppTheme._();

  static const Color seed = Color(0xFF2F6B5E);

  /// The bundled family, which covers Arabic and Latin in one voice.
  static const String fontFamily = 'Cairo';

  static ThemeData light(Locale locale) => _build(Brightness.light, locale);
  static ThemeData dark(Locale locale) => _build(Brightness.dark, locale);

  /// Material 3 Expressive's shape scale.
  ///
  /// Expressive draws much of its character from corner radius, and from
  /// *contrast* between radii rather than one rounded value used everywhere.
  static const double shapeSmall = 12;
  static const double shapeMedium = 16;
  static const double shapeLarge = 20;
  static const double shapeExtraLarge = 28;
  static const double shapeExtraExtraLarge = 36;

  static ThemeData _build(Brightness brightness, Locale locale) {
    final colors = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.expressive,
    );
    final text = _textTheme(colors, locale);

    return ThemeData(
      colorScheme: colors,
      textTheme: text,
      fontFamily: fontFamily,
      extensions: [
        brightness == Brightness.light
            ? SemanticColors.light
            : SemanticColors.dark,
        brightness == Brightness.light
            ? PersonColors.light
            : PersonColors.dark,
      ],
      scaffoldBackgroundColor: colors.surface,
      splashFactory: InkSparkle.splashFactory,
      // Expressive's page motion: content slides a short distance and
      // cross-fades, rather than the older zoom. It is also the transition
      // that reads correctly when mirrored for Arabic.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 3,
        surfaceTintColor: colors.surfaceTint,
        titleTextStyle: text.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHighest,
        // A pill-shaped field is one of Expressive's most recognisable marks.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeLarge),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeLarge),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeLarge),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeLarge),
          borderSide: BorderSide(color: colors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeLarge),
          borderSide: BorderSide(color: colors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: text.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: text.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: text.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeExtraLarge),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: colors.secondaryContainer,
        labelStyle: text.labelMedium?.copyWith(
          color: colors.onSecondaryContainer,
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeMedium),
        ),
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeExtraExtraLarge),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(shapeExtraExtraLarge),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeMedium),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        // The 2024 indicator — a wavy track with a rounded stop — is the
        // Expressive one. The flag is deprecated because it will become the
        // default; until then, opting in requires naming it.
        // ignore: deprecated_member_use
        year2023: false,
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        space: 1,
        thickness: 1,
      ),
    );
  }

  /// An expressive type scale.
  ///
  /// Expressive leans on weight and size contrast rather than colour alone, so
  /// display and headline styles are heavy and set tight, while body text
  /// stays comfortable at a normal weight.
  ///
  /// **Tracking is applied to Latin only.** `letterSpacing` inserts space
  /// between glyphs, and Arabic is a cursive script whose letters join — the
  /// negative and positive tracking that sharpens a Latin headline visibly
  /// breaks Arabic words apart. Arabic also sits taller, so it is given a
  /// little more leading.
  static TextTheme _textTheme(ColorScheme colors, Locale locale) {
    final isArabic = locale.languageCode == 'ar';
    double tracking(double latin) => isArabic ? 0 : latin;
    double leading(double latin) => isArabic ? latin + 0.12 : latin;

    TextStyle style(
      double size,
      FontWeight weight,
      double track,
      double height,
    ) => TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: tracking(track),
      height: leading(height),
    );

    return TextTheme(
      displayLarge: style(52, FontWeight.w800, -1.0, 1.12),
      displayMedium: style(44, FontWeight.w800, -0.8, 1.14),
      displaySmall: style(36, FontWeight.w700, -0.5, 1.18),
      headlineLarge: style(32, FontWeight.w700, -0.4, 1.20),
      headlineMedium: style(28, FontWeight.w700, -0.3, 1.22),
      headlineSmall: style(24, FontWeight.w600, -0.2, 1.26),
      titleLarge: style(22, FontWeight.w700, 0, 1.28),
      titleMedium: style(17, FontWeight.w600, 0.1, 1.34),
      titleSmall: style(15, FontWeight.w600, 0.1, 1.36),
      bodyLarge: style(17, FontWeight.w400, 0.1, 1.50),
      bodyMedium: style(15, FontWeight.w400, 0.15, 1.50),
      bodySmall: style(13, FontWeight.w400, 0.2, 1.46),
      labelLarge: style(16, FontWeight.w600, 0.1, 1.30),
      labelMedium: style(13, FontWeight.w600, 0.4, 1.30),
      labelSmall: style(11, FontWeight.w600, 0.5, 1.30),
    ).apply(bodyColor: colors.onSurface, displayColor: colors.onSurface);
  }
}

/// Colours that carry meaning rather than brand.
///
/// A warning has to *look* like caution, and the generated scheme cannot
/// promise that: `DynamicSchemeVariant.expressive` rotates hues far from the
/// seed, and on this palette `tertiaryContainer` lands on cyan — a colour that
/// reads as information, not "be careful". Caution is amber in almost every
/// interface a person has used, so it is fixed here instead of borrowed from
/// a role that happens to be free.
///
/// Registered as a [ThemeExtension] so it still travels through `Theme.of`
/// and still animates between light and dark.
@immutable
class SemanticColors extends ThemeExtension<SemanticColors> {
  const SemanticColors({
    required this.warningContainer,
    required this.onWarningContainer,
  });

  /// Amber that clears 4.5:1 against its foreground in both themes.
  static const SemanticColors light = SemanticColors(
    warningContainer: Color(0xFFFFE0A3),
    onWarningContainer: Color(0xFF4A2E00),
  );

  static const SemanticColors dark = SemanticColors(
    warningContainer: Color(0xFF4A3410),
    onWarningContainer: Color(0xFFFFDFA6),
  );

  final Color warningContainer;
  final Color onWarningContainer;

  /// The set in force, falling back to light rather than throwing if the
  /// extension was somehow not registered.
  static SemanticColors of(BuildContext context) =>
      Theme.of(context).extension<SemanticColors>() ?? light;

  @override
  SemanticColors copyWith({
    Color? warningContainer,
    Color? onWarningContainer,
  }) => SemanticColors(
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
  );

  @override
  SemanticColors lerp(ThemeExtension<SemanticColors>? other, double t) {
    if (other is! SemanticColors) return this;
    return SemanticColors(
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
    );
  }
}

/// The colours a person is drawn in, by the sex their record states.
///
/// A family tree is read by scanning it, and the first thing anybody scans
/// for is which of two people is which. webtrees says so with a class on
/// every chart box; before this the app threw that away and picked an avatar
/// colour by hashing the name, which was variety without meaning.
///
/// Blue and pink, because that is what a reader of a family tree expects and
/// what webtrees' own themes use — but derived per brightness rather than
/// fixed, because a pastel that reads correctly on paper turns to mud on a
/// dark surface. Each pair clears 4.5:1 between its container and the text
/// drawn on it, in both themes.
///
/// Not taken from the generated scheme: `DynamicSchemeVariant.expressive`
/// rotates hues far from the seed and offers nothing dependably blue or
/// dependably pink, and a role that happens to land near one today would move
/// the next time the seed changed. Same reasoning as [SemanticColors].
@immutable
class PersonColors extends ThemeExtension<PersonColors> {
  const PersonColors({
    required this.male,
    required this.onMale,
    required this.female,
    required this.onFemale,
    required this.unknown,
    required this.onUnknown,
  });

  static const PersonColors light = PersonColors(
    male: Color(0xFFCFE4F7),
    onMale: Color(0xFF0E3350),
    female: Color(0xFFF8D3E2),
    onFemale: Color(0xFF4A1030),
    unknown: Color(0xFFE2E2E4),
    onUnknown: Color(0xFF3A3A3E),
  );

  static const PersonColors dark = PersonColors(
    male: Color(0xFF14384F),
    onMale: Color(0xFFBFDDF5),
    female: Color(0xFF4A2136),
    onFemale: Color(0xFFF6C9DC),
    unknown: Color(0xFF37373B),
    onUnknown: Color(0xFFDCDCE0),
  );

  final Color male;
  final Color onMale;
  final Color female;
  final Color onFemale;
  final Color unknown;
  final Color onUnknown;

  /// The container colour and the colour to draw on it, for [sex].
  (Color, Color) forSex(Sex sex) => switch (sex) {
    Sex.male => (male, onMale),
    Sex.female => (female, onFemale),
    Sex.unknown => (unknown, onUnknown),
  };

  /// The set in force, falling back to light rather than throwing if the
  /// extension was somehow not registered.
  static PersonColors of(BuildContext context) =>
      Theme.of(context).extension<PersonColors>() ?? light;

  @override
  PersonColors copyWith({
    Color? male,
    Color? onMale,
    Color? female,
    Color? onFemale,
    Color? unknown,
    Color? onUnknown,
  }) => PersonColors(
    male: male ?? this.male,
    onMale: onMale ?? this.onMale,
    female: female ?? this.female,
    onFemale: onFemale ?? this.onFemale,
    unknown: unknown ?? this.unknown,
    onUnknown: onUnknown ?? this.onUnknown,
  );

  @override
  PersonColors lerp(ThemeExtension<PersonColors>? other, double t) {
    if (other is! PersonColors) return this;
    return PersonColors(
      male: Color.lerp(male, other.male, t)!,
      onMale: Color.lerp(onMale, other.onMale, t)!,
      female: Color.lerp(female, other.female, t)!,
      onFemale: Color.lerp(onFemale, other.onFemale, t)!,
      unknown: Color.lerp(unknown, other.unknown, t)!,
      onUnknown: Color.lerp(onUnknown, other.onUnknown, t)!,
    );
  }
}
