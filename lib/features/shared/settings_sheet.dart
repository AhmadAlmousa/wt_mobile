import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/diagnostics.dart';
import '../../data/settings_store.dart';
import '../../domain/dates.dart';
import '../../l10n/app_localizations.dart';
import 'diagnostics_screen.dart';

/// Lets the reader choose the theme and the language.
///
/// Reachable from the first screen onward, because someone who reads Arabic
/// should not have to sign in through an English form to find the switch.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({required this.settings, this.diagnostics, super.key});

  final SettingsStore settings;

  /// What the app knows about the site, when there is a site to know about.
  ///
  /// A snapshot rather than a live reading: the sheet is built when it opens,
  /// and a diagnostics screen that changed under the reader while they copied
  /// it would be worse than one that is a moment stale.
  final Diagnostics? diagnostics;

  static Future<void> show(
    BuildContext context,
    SettingsStore settings, {
    Diagnostics? diagnostics,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) =>
        SettingsSheet(settings: settings, diagnostics: diagnostics),
  );

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text.settings, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 24),

              _GroupLabel(text.appearance),
              const SizedBox(height: 8),
              _Choices<ThemeMode>(
                value: settings.themeMode,
                onSelected: settings.setThemeMode,
                options: [
                  (ThemeMode.system, text.themeSystem, Icons.brightness_auto),
                  (ThemeMode.light, text.themeLight, Icons.light_mode_outlined),
                  (ThemeMode.dark, text.themeDark, Icons.dark_mode_outlined),
                ],
              ),
              const SizedBox(height: 28),

              _GroupLabel(text.language),
              const SizedBox(height: 8),
              _Choices<Locale?>(
                value: settings.locale,
                onSelected: settings.setLocale,
                options: [
                  (null, text.languageSystem, Icons.translate),
                  (const Locale('en'), text.languageEnglish, Icons.abc),
                  (
                    const Locale('ar'),
                    text.languageArabic,
                    Icons.text_fields_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // The site, not the app, writes the dates — so choosing a
              // language here reaches further than the interface, and saying
              // so is better than surprising someone on the website later.
              _Footnote(text.languageAffectsSite),
              const SizedBox(height: 28),

              _GroupLabel(text.calendar),
              const SizedBox(height: 8),
              _Choices<CalendarView>(
                value: settings.calendarView,
                onSelected: settings.setCalendarView,
                options: [
                  (CalendarView.both, text.calendarBoth, Icons.calendar_month),
                  (
                    CalendarView.gregorian,
                    text.calendarGregorian,
                    Icons.calendar_today_outlined,
                  ),
                  (
                    CalendarView.hijri,
                    text.calendarHijri,
                    Icons.nightlight_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _Footnote(text.calendarOnlyWhenOffered),
              const SizedBox(height: 28),

              // Last, and quiet: nobody opens the settings looking for it,
              // and everybody who needs it needs it badly.
              if (diagnostics case final report?) ...[
                _GroupLabel(text.diagnostics),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.troubleshoot_outlined),
                  label: Text(text.diagnostics),
                  onPressed: () => DiagnosticsScreen.show(context, report),
                ),
                const SizedBox(height: 28),
              ],

              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(text.done),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet line under a choice group, for a consequence worth stating but not
/// worth interrupting anyone over.
class _Footnote extends StatelessWidget {
  const _Footnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

/// A single-choice group, drawn as Expressive's connected button group.
///
/// Selection is announced by shape as well as colour — the chosen option grows
/// a heavier fill and a check — so the choice survives a reader who cannot
/// separate the two colours.
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final T value;
  final List<(T, String, IconData)> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        for (final (option, label, icon) in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: option == value
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.shapeLarge),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onSelected(option),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: option == value
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: option == value
                                    ? colors.onPrimaryContainer
                                    : colors.onSurface,
                              ),
                        ),
                      ),
                      if (option == value)
                        Icon(
                          Icons.check_circle,
                          size: 20,
                          color: colors.onPrimaryContainer,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
