import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/dates.dart';
import '../features/charts/chart_options.dart';

/// The reader's choice of theme and language.
///
/// Both default to *following the device*, which is the only honest default:
/// the app cannot know whether someone prefers Arabic until they say so, and
/// the platform already holds that answer.
///
/// Deliberately not in the keystore. These are preferences, not secrets, and
/// they must be readable before anyone signs in — the sign-in screen itself
/// has to be drawn in the right language and direction.
class SettingsStore extends ChangeNotifier {
  SettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _themeKey = 'settings.themeMode';
  static const String _localeKey = 'settings.locale';
  static const String _calendarKey = 'settings.calendarView';
  static const String _chartKey = 'settings.chart';

  /// The languages the app is translated into.
  ///
  /// Arabic is not an afterthought here: the tree this was built against is
  /// Arabic, so the layout, typography and fixtures were designed for it.
  static const List<Locale> supportedLocales = [Locale('en'), Locale('ar')];

  final SharedPreferencesAsync _preferences;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  /// The chosen language, or `null` to follow the device.
  Locale? _locale;
  Locale? get locale => _locale;

  /// Which calendar dates are shown in.
  ///
  /// Trees that record Gregorian dates and convert to Hijri — this project's
  /// own among them — render every date twice, which doubles the length of
  /// every fact row. Showing both is the default because it is what the site
  /// itself does.
  CalendarView _calendarView = CalendarView.both;
  CalendarView get calendarView => _calendarView;

  /// How the reader has asked for their charts to be drawn.
  ///
  /// Kept here rather than on a chart screen because the same answers apply
  /// to every chart and are worth keeping between them: somebody who turned
  /// the photographs off did not mean "on this pedigree only".
  ChartOptions _chartOptions = const ChartOptions();
  ChartOptions get chartOptions => _chartOptions;

  /// Reads the stored choices. Safe to call before `runApp`.
  ///
  /// A device with no working preference store is not a failure worth
  /// blocking startup for — the app simply follows the system.
  Future<void> load() async {
    try {
      final theme = await _preferences.getString(_themeKey);
      final language = await _preferences.getString(_localeKey);
      final calendar = await _preferences.getString(_calendarKey);

      _themeMode = switch (theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      _locale = _localeFrom(language);
      _calendarView = CalendarView.values.firstWhere(
        (view) => view.name == calendar,
        orElse: () => CalendarView.both,
      );
      _chartOptions = _chartOptionsFrom(
        await _preferences.getString(_chartKey),
      );
    } on Exception catch (problem) {
      developer.log(
        'Could not read settings: $problem',
        name: 'webtrees.settings',
      );
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _write(_themeKey, mode.name);
  }

  /// Chooses a language, or passes `null` to follow the device again.
  Future<void> setLocale(Locale? locale) async {
    if (locale == _locale) return;
    _locale = locale;
    notifyListeners();
    await _write(_localeKey, locale?.languageCode ?? '');
  }

  Future<void> setCalendarView(CalendarView view) async {
    if (view == _calendarView) return;
    _calendarView = view;
    notifyListeners();
    await _write(_calendarKey, view.name);
  }

  Future<void> setChartOptions(ChartOptions options) async {
    if (options == _chartOptions) return;
    _chartOptions = options;
    notifyListeners();
    await _write(_chartKey, _chartOptionsTo(options));
  }

  /// Chart options as one stored line.
  ///
  /// Written by hand rather than as JSON because it is six answers, and a
  /// stored value that cannot be read back — an option renamed, a file from
  /// an older build — has to fall back to the defaults rather than throw on
  /// a screen that has not been drawn yet.
  static String _chartOptionsTo(ChartOptions options) => [
    options.generations ?? '',
    options.shape.name,
    options.showPhotos,
    options.showDates,
    options.colourBySex,
    options.fitToName,
    options.show.name,
  ].join('|');

  static ChartOptions _chartOptionsFrom(String? stored) {
    final parts = stored?.split('|') ?? const [];
    if (parts.length != 7) return const ChartOptions();

    bool flag(int at, {required bool fallback}) => switch (parts[at]) {
      'true' => true,
      'false' => false,
      _ => fallback,
    };

    return ChartOptions(
      generations: int.tryParse(parts[0]),
      shape: ChartShape.values.firstWhere(
        (option) => option.name == parts[1],
        orElse: () => ChartShape.tree,
      ),
      showPhotos: flag(2, fallback: true),
      showDates: flag(3, fallback: true),
      colourBySex: flag(4, fallback: true),
      fitToName: flag(5, fallback: false),
      show: ShowPeople.values.firstWhere(
        (option) => option.name == parts[6],
        orElse: () => ShowPeople.everyone,
      ),
    );
  }

  /// The locale the interface will actually use, given the device's own.
  ///
  /// Needed because the theme is built per-locale — Arabic gets different
  /// tracking and leading — so the theme has to know the resolved answer, not
  /// the stored preference.
  Locale resolve(Locale? platformLocale) {
    final chosen = _locale;
    if (chosen != null) return chosen;

    final device = platformLocale?.languageCode;
    return supportedLocales.firstWhere(
      (candidate) => candidate.languageCode == device,
      orElse: () => const Locale('en'),
    );
  }

  /// The webtrees language tag matching [locale].
  ///
  /// webtrees renders every fact label, month name and numeral in the language
  /// held in *its own* session, which it seeds from the account's preference
  /// at sign-in — so an app in Arabic still receives English dates until it
  /// says otherwise. British English is used for `en` because it orders a date
  /// day-first, as Arabic does, rather than the American month-first form.
  static String webtreesLanguageTag(Locale locale) =>
      switch (locale.languageCode) {
        'ar' => 'ar',
        _ => 'en-GB',
      };

  static Locale? _localeFrom(String? code) => switch (code) {
    'en' => const Locale('en'),
    'ar' => const Locale('ar'),
    _ => null,
  };

  Future<void> _write(String key, String value) async {
    try {
      await _preferences.setString(key, value);
    } on Exception catch (problem) {
      developer.log(
        'Could not save settings: $problem',
        name: 'webtrees.settings',
      );
    }
  }
}
