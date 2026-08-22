import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Reads the stored choices. Safe to call before `runApp`.
  ///
  /// A device with no working preference store is not a failure worth
  /// blocking startup for — the app simply follows the system.
  Future<void> load() async {
    try {
      final theme = await _preferences.getString(_themeKey);
      final language = await _preferences.getString(_localeKey);

      _themeMode = switch (theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      _locale = _localeFrom(language);
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
