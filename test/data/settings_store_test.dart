import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:webtrees_mobile/data/settings_store.dart';
import 'package:webtrees_mobile/domain/dates.dart';
import 'package:webtrees_mobile/features/charts/chart_options.dart';

void main() {
  late SharedPreferencesAsync store;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    store = SharedPreferencesAsync();
  });

  /// A fresh store reading whatever the last one wrote — a restarted app.
  Future<SettingsStore> reopened() async {
    final settings = SettingsStore(preferences: store);
    await settings.load();
    return settings;
  }

  test('chart options survive a restart', () async {
    final settings = await reopened();
    await settings.setChartOptions(
      const ChartOptions(
        generations: 7,
        shape: ChartShape.compact,
        showPhotos: false,
        showDates: false,
        colourBySex: false,
        fitToName: true,
        show: ShowPeople.menOnly,
      ),
    );

    // Somebody who turned the photographs off did not mean "on this pedigree
    // only", and did not mean "until the app is closed" either.
    final again = await reopened();
    expect(again.chartOptions.generations, 7);
    expect(again.chartOptions.shape, ChartShape.compact);
    expect(again.chartOptions.showPhotos, isFalse);
    expect(again.chartOptions.showDates, isFalse);
    expect(again.chartOptions.colourBySex, isFalse);
    expect(again.chartOptions.fitToName, isTrue);
    expect(again.chartOptions.show, ShowPeople.menOnly);
  });

  test('“as the site sets it” is remembered as an answer, not as nothing',
      () async {
    final settings = await reopened();
    await settings.setChartOptions(const ChartOptions(generations: 5));
    await settings.setChartOptions(
      settings.chartOptions.withGenerations(null),
    );

    expect((await reopened()).chartOptions.generations, isNull);
  });

  test('a stored line it cannot read falls back to the defaults', () async {
    // An option renamed, or a value written by an older build. A settings
    // screen that threw here would be a screen nobody could reach.
    await store.setString('settings.chart', 'nonsense');

    final settings = await reopened();
    expect(settings.chartOptions, const ChartOptions());
  });

  test('theme, language and calendar survive a restart too', () async {
    final settings = await reopened();
    await settings.setThemeMode(ThemeMode.dark);
    await settings.setLocale(const Locale('ar'));
    await settings.setCalendarView(CalendarView.hijri);

    final again = await reopened();
    expect(again.themeMode, ThemeMode.dark);
    expect(again.locale, const Locale('ar'));
    expect(again.calendarView, CalendarView.hijri);
  });
}
