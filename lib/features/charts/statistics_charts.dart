/// The chart marks a statistics screen is built from.
///
/// Drawn from plain widgets rather than a charting package: the figures are
/// simple — a share of a whole, a count per category — and a widget tree
/// mirrors itself for Arabic, scales with the reader's text size and picks up
/// the app's own theme without any of that being asked for twice.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/statistics.dart';

/// Colours that carry identity in a chart.
///
/// Not the app's own scheme: its secondary and tertiary are a slate blue and a
/// teal that sit 1.2 ΔE apart under deuteranopia — indistinguishable — and
/// below the chroma floor where a hue stops doing any identity work at all.
/// These four are the first slots of a palette checked against both of this
/// app's surfaces: lightness band, chroma floor, colour-vision separation and
/// contrast all pass, in light and in dark.
///
/// A count per category needs none of this — the bar's length says the number
/// and one hue is enough — so only shares of a whole are coloured from here.
abstract final class ChartPalette {
  static const List<Color> _light = [
    Color(0xFF2A78D6),
    Color(0xFFEB6834),
    Color(0xFF1BAF7A),
    Color(0xFFEDA100),
  ];

  static const List<Color> _dark = [
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
  ];

  /// The identity colours in the order they are handed out, which never
  /// changes: the order is what makes the palette safe under colour blindness.
  static List<Color> of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  /// Beyond the fourth category the palette is not extended — a fifth hue
  /// would be indistinguishable from one already in use. Anything past it is
  /// drawn in the muted ink the axes use, and named by its label.
  static Color spare(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;
}

/// A number in the reader's own numerals.
///
/// The counts webtrees renders arrive as text and are shown as they came; the
/// numbers behind its charts arrive as numbers, and have to be written out
/// here — in Arabic-Indic digits when that is what the rest of the screen is
/// using.
String formatCount(BuildContext context, double value) {
  final locale = Localizations.localeOf(context);
  final format = NumberFormat.decimalPattern(locale.toString());
  final text = value == value.roundToDouble()
      ? format.format(value.round())
      : format.format(value);

  // The site writes its own counts in Arabic-Indic digits, and a chart drawn
  // beside them must not change numerals halfway down the screen. Plain `ar`
  // formats with Latin digits — the numbering system that goes with the
  // language here is the eastern one, so the digits are mapped rather than the
  // locale being fudged into `ar_EG`.
  return locale.languageCode == 'ar' ? easternDigits(text) : text;
}

/// Latin digits and separators rewritten as Arabic-Indic ones.
String easternDigits(String text) {
  const zero = 0x0660;
  return text.runes.map((rune) {
    if (rune >= 0x30 && rune <= 0x39) {
      return String.fromCharCode(zero + rune - 0x30);
    }
    return switch (rune) {
      0x2C => '\u066C', // thousands separator
      0x2E => '\u066B', // decimal separator
      _ => String.fromCharCode(rune),
    };
  }).join();
}

/// One share of a whole, drawn as a single bar cut into its parts.
///
/// A pie is what webtrees draws; a bar is easier to read and far easier to
/// label, which matters more here than matching the site's own picture.
class ShareBar extends StatelessWidget {
  const ShareBar({required this.dataset, super.key});

  final StatisticDataset dataset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = ChartPalette.of(context);
    final rows = dataset.rows.where((row) => row.value > 0).toList();
    final total = rows.fold<double>(0, (sum, row) => sum + row.value);
    if (rows.isEmpty || total == 0) return const SizedBox.shrink();

    Color colourOf(int index) =>
        index < palette.length ? palette[index] : ChartPalette.spare(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            // The width has to be asked for: every segment is a flex child,
            // so the row has no width of its own to be laid out at, and a
            // column aligned to the start would give it none.
            width: double.infinity,
            height: 18,
            child: Row(
              // A coloured box has no height of its own; without this the
              // segments centre themselves into nothing and the bar is 18
              // pixels of empty surface.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  // A gap of the surface itself between segments, so two
                  // colours never touch and the edge stays legible for
                  // somebody who cannot tell them apart.
                  if (index > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: (rows[index].value * 1000 / total).round(),
                    child: ColoredBox(color: colourOf(index)),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Identity is never colour alone: every part is named and counted
        // beside its own swatch.
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            for (var index = 0; index < rows.length; index++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colourOf(index),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(rows[index].label, style: theme.textTheme.bodySmall),
                  const SizedBox(width: 6),
                  Text(
                    formatCount(context, rows[index].value),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// A count per category, drawn as bars along the reading direction.
///
/// One hue for every bar: length already says how many, and colouring by value
/// would spend the identity channel saying it twice.
class MagnitudeBars extends StatelessWidget {
  const MagnitudeBars({required this.dataset, this.limit = 12, super.key});

  final StatisticDataset dataset;

  /// How many bars are worth drawing. Past a dozen the chart is a table with
  /// extra steps, and the tail says less than the space it takes.
  final int limit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [...dataset.rows.where((row) => row.value > 0)]
      ..sort((a, b) => b.value.compareTo(a.value));
    if (rows.isEmpty) return const SizedBox.shrink();

    final shown = rows.take(limit).toList();
    final largest = shown.first.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 108,
                  child: Text(
                    row.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    // Bars grow from the edge the reader starts at, which is
                    // the right-hand one in Arabic.
                    alignment: AlignmentDirectional.centerStart,
                    child: FractionallySizedBox(
                      widthFactor: (row.value / largest).clamp(0.02, 1),
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius:
                              const BorderRadiusDirectional.horizontal(
                                end: Radius.circular(4),
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatCount(context, row.value),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        if (rows.length > shown.length)
          Text(
            '+${formatCount(context, (rows.length - shown.length).toDouble())}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
