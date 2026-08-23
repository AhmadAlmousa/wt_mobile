import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/settings_store.dart';
import '../../l10n/app_localizations.dart';
import '../shared/bidi.dart';
import 'chart_options.dart';

/// How a chart is drawn, put in the reader's hands.
///
/// A sheet rather than a screen, and a sheet that changes the chart behind it
/// as each switch is thrown: the whole question is what the chart looks like,
/// and answering it against a chart you cannot see is guesswork.
class ChartOptionsSheet extends StatelessWidget {
  const ChartOptionsSheet({
    required this.settings,
    this.offersGenerations = true,
    this.offersShape = false,
    super.key,
  });

  final SettingsStore settings;

  /// Whether asking for more generations means anything here.
  ///
  /// A chart the app stitches from two others — an hourglass — takes the same
  /// number for both halves, and a timeline has no depth at all.
  final bool offersGenerations;

  /// Whether this chart has more than one shape to take. Only an ancestors
  /// chart does: a fan is a pedigree bent round a circle, and there is no
  /// such thing as a fan of descendants.
  final bool offersShape;

  static Future<void> show(
    BuildContext context,
    SettingsStore settings, {
    bool offersGenerations = true,
    bool offersShape = false,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => ChartOptionsSheet(
      settings: settings,
      offersGenerations: offersGenerations,
      offersShape: offersShape,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final options = settings.chartOptions;
          void update(ChartOptions changed) =>
              settings.setChartOptions(changed);

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text.chartOptions, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 24),

                if (offersShape) ...[
                  _GroupLabel(text.chartView),
                  const SizedBox(height: 8),
                  _Choices<ChartShape>(
                    value: options.shape,
                    onSelected: (shape) =>
                        update(options.copyWith(shape: shape)),
                    options: [
                      (
                        ChartShape.tree,
                        text.chartViewTree,
                        Icons.account_tree_outlined,
                      ),
                      (
                        ChartShape.circle,
                        text.chartViewCircle,
                        Icons.donut_small_outlined,
                      ),
                      (
                        ChartShape.compact,
                        text.chartViewCompact,
                        Icons.density_small,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                ],

                if (offersGenerations) ...[
                  _GroupLabel(text.chartGenerations),
                  const SizedBox(height: 8),
                  _Generations(
                    value: options.generations,
                    onChanged: (many) => update(options.withGenerations(many)),
                  ),
                  const SizedBox(height: 28),
                ],

                _GroupLabel(text.chartWhoToShow),
                const SizedBox(height: 8),
                _Choices<ShowPeople>(
                  value: options.show,
                  onSelected: (show) => update(options.copyWith(show: show)),
                  options: [
                    (
                      ShowPeople.everyone,
                      text.chartShowEveryone,
                      Icons.groups_outlined,
                    ),
                    (ShowPeople.menOnly, text.chartShowMen, Icons.male),
                    (ShowPeople.womenOnly, text.chartShowWomen, Icons.female),
                  ],
                ),
                const SizedBox(height: 10),
                // Hiding one sex hides everyone reached through them, which
                // is what a reader asking for a paternal line means — and a
                // surprise to anyone who expected boxes simply to vanish.
                _Footnote(text.chartLineNote),
                const SizedBox(height: 28),

                _Switch(
                  label: text.chartShowPhotos,
                  icon: Icons.photo_outlined,
                  value: options.showPhotos,
                  onChanged: (on) => update(options.copyWith(showPhotos: on)),
                ),
                _Switch(
                  label: text.chartShowDates,
                  icon: Icons.calendar_today_outlined,
                  value: options.showDates,
                  onChanged: (on) => update(options.copyWith(showDates: on)),
                ),
                _Switch(
                  label: text.chartColourBySex,
                  icon: Icons.palette_outlined,
                  value: options.colourBySex,
                  onChanged: (on) => update(options.copyWith(colourBySex: on)),
                ),
                _Switch(
                  label: text.chartFitToName,
                  icon: Icons.fit_screen_outlined,
                  value: options.fitToName,
                  onChanged: (on) => update(options.copyWith(fitToName: on)),
                ),
                const SizedBox(height: 24),

                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(text.done),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// How many generations to ask the site for.
///
/// The site's own number comes first, because it is the one its administrator
/// chose and the only one the app can be sure the server will draw quickly.
class _Generations extends StatelessWidget {
  const _Generations({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final colors = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: Text(text.chartGenerationsSite),
          selected: value == null,
          onSelected: (_) => onChanged(null),
        ),
        for (
          var many = ChartOptions.fewestGenerations;
          many <= ChartOptions.mostGenerations;
          many++
        )
          ChoiceChip(
            // Digits and nothing else, which an Arabic layout would otherwise
            // reorder against the chips beside it.
            label: Text(ltrRun('$many')),
            selected: value == many,
            selectedColor: colors.primaryContainer,
            onSelected: (_) => onChanged(many),
          ),
      ],
    );
  }
}

/// One thing a chart either shows or does not.
class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.shapeLarge),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 12, 6),
            child: Row(
              children: [
                Icon(icon, size: 20, color: colors.onSurfaceVariant),
                const SizedBox(width: 14),
                Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
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
/// The same shape the settings sheet uses, kept private to each so neither
/// has to become a general widget before there is a third caller.
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
