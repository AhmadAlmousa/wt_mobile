import 'package:flutter/material.dart';

import '../../domain/records.dart';
import '../../l10n/app_localizations.dart';
import '../shared/bidi.dart';
import 'search_filter.dart';

/// Where a reader narrows the results they already have.
///
/// A sheet rather than a row of controls above the list. Three filters is
/// more than a phone has room for beside a search field, and the one thing a
/// person is doing on this screen is reading names — so the controls come up
/// when asked for and go away again, leaving the whole screen to the results.
///
/// Only what the rows can answer is offered ([SearchFacets]), and the button
/// at the bottom says how many people the current choice leaves. That last
/// part matters more than it looks: a filter that hides everything and a
/// search that found nothing look identical from outside, and this one says
/// which it is before it is applied.
class SearchFilterSheet extends StatefulWidget {
  const SearchFilterSheet({
    required this.filter,
    required this.facets,
    required this.people,
    super.key,
  });

  final SearchFilter filter;
  final SearchFacets facets;

  /// The results being narrowed, so the button can count what survives.
  final List<PersonRef> people;

  /// Asks for a filter, answering the chosen one — or null if nothing was
  /// chosen, which leaves the one in force alone.
  static Future<SearchFilter?> show(
    BuildContext context, {
    required SearchFilter filter,
    required SearchFacets facets,
    required List<PersonRef> people,
  }) => showModalBottomSheet<SearchFilter>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) =>
        SearchFilterSheet(filter: filter, facets: facets, people: people),
  );

  @override
  State<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<SearchFilterSheet> {
  late SearchFilter _filter = widget.filter;

  /// Each slider's own position, which is its whole span until it is moved.
  ///
  /// Held separately from the filter because "no filter" and "a filter that
  /// happens to cover everything" are the same set of people and different
  /// states: only the first leaves a person the tree says nothing about
  /// visible without a rule about it, and only the second counts towards the
  /// badge on the button.
  late RangeValues _years = RangeValues(
    (_filter.bornFrom ?? widget.facets.earliestBirth ?? 0).toDouble(),
    (_filter.bornTo ?? widget.facets.latestBirth ?? 0).toDouble(),
  );

  late RangeValues _ages = RangeValues(
    (_filter.agedFrom ?? widget.facets.youngest ?? 0).toDouble(),
    (_filter.agedTo ?? widget.facets.oldest ?? 0).toDouble(),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final facets = widget.facets;
    final surviving = _filter.applyTo(widget.people).length;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      text.filterTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: _filter.isEmpty ? null : _clear,
                    child: Text(text.filterClear),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (facets.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    text.filterNone,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

              // Offered only where a row states one. A stock instance never
              // does — its search rows carry a name, two years and a place,
              // and nothing about sex — so this simply is not there.
              if (facets.offersSex) ...[
                _Heading(text.filterSex),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final sex in _offeredSexes(facets))
                      FilterChip(
                        avatar: Icon(_iconFor(sex), size: 18),
                        label: Text(_labelFor(sex, text)),
                        selected: _filter.sexes.contains(sex),
                        onSelected: (on) => _toggleSex(sex, on),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              // How old somebody is, or was — one question a reader asks
              // and two the data answers. Offered wherever the rows can be
              // asked it, which today means a site running the module: an
              // age is arithmetic on days, and a search row from the page
              // carries two printed years that may not even be in the same
              // calendar.
              if (facets.offersAges) ...[
                _Heading(
                  text.filterAge,
                  trailing: ltrRun(
                    text.filterAgeRange(
                      '${_ages.start.round()}',
                      '${_ages.end.round()}',
                    ),
                  ),
                ),
                RangeSlider(
                  values: _ages,
                  min: facets.youngest!.toDouble(),
                  max: facets.oldest!.toDouble(),
                  divisions: facets.oldest! - facets.youngest!,
                  labels: RangeLabels(
                    '${_ages.start.round()}',
                    '${_ages.end.round()}',
                  ),
                  onChanged: (chosen) => setState(() {
                    _ages = chosen;
                    _filter = _filter.withAges(
                      chosen.start.round(),
                      chosen.end.round(),
                    );
                  }),
                ),
                Text(
                  text.filterAgeNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
              ],

              if (facets.offersYears) ...[
                _Heading(
                  text.filterBorn,
                  // Isolated as one run rather than a number at a time: two
                  // isolates with a dash between them are three neutrals, and
                  // an Arabic line lays those out right to left — which draws
                  // the range backwards even though each number is correct.
                  // The same rule every lifespan in the app follows.
                  trailing: ltrRun(
                    text.filterBornRange(
                      '${_years.start.round()}',
                      '${_years.end.round()}',
                    ),
                  ),
                ),
                RangeSlider(
                  values: _years,
                  min: facets.earliestBirth!.toDouble(),
                  max: facets.latestBirth!.toDouble(),
                  // One stop per year: a family tree is read in generations,
                  // and a slider that lands between two years is a slider
                  // whose label does not match what it filtered.
                  divisions: facets.latestBirth! - facets.earliestBirth!,
                  labels: RangeLabels(
                    '${_years.start.round()}',
                    '${_years.end.round()}',
                  ),
                  onChanged: (chosen) => setState(() {
                    _years = chosen;
                    _filter = _filter.withYears(
                      chosen.start.round(),
                      chosen.end.round(),
                    );
                  }),
                ),
                Text(
                  text.filterYearsNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
              ],

              if (facets.offersPlace) ...[
                _Heading(text.filterBirthPlace),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(text.filterAnyPlace),
                      selected: _filter.birthPlace == null,
                      onSelected: (_) => setState(
                        () => _filter = _filter.withBirthPlace(null),
                      ),
                    ),
                    // The places these results actually name, which is the
                    // only list the app can offer: a stock instance publishes
                    // no index of a tree's places, and typing one on a phone
                    // is a filter nobody uses.
                    for (final place in facets.places)
                      ChoiceChip(
                        label: Text(place, textDirection: directionOf(place)),
                        selected: _filter.birthPlace == place,
                        onSelected: (on) => setState(
                          () => _filter = _filter.withBirthPlace(
                            on ? place : null,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              FilledButton(
                onPressed: () => Navigator.of(context).pop(_filter),
                child: Text(text.filterApply(surviving)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The sexes to draw chips for, in a fixed order.
  ///
  /// [SearchFacets] answers a set, and a set of enum values does not iterate
  /// in the order anybody wrote it — so the order comes from here, where it
  /// is a decision rather than an accident.
  List<Sex> _offeredSexes(SearchFacets facets) => [
    for (final sex in [Sex.male, Sex.female, Sex.unknown])
      if (facets.sexes.contains(sex)) sex,
  ];

  void _toggleSex(Sex sex, bool on) => setState(() {
    final chosen = {..._filter.sexes};
    if (on) {
      chosen.add(sex);
    } else {
      chosen.remove(sex);
    }
    _filter = _filter.withSexes(chosen);
  });

  void _clear() => setState(() {
    _filter = const SearchFilter();
    _years = RangeValues(
      (widget.facets.earliestBirth ?? 0).toDouble(),
      (widget.facets.latestBirth ?? 0).toDouble(),
    );
    _ages = RangeValues(
      (widget.facets.youngest ?? 0).toDouble(),
      (widget.facets.oldest ?? 0).toDouble(),
    );
  });

  static IconData _iconFor(Sex sex) => switch (sex) {
    Sex.male => Icons.male,
    Sex.female => Icons.female,
    Sex.unknown => Icons.help_outline,
  };

  static String _labelFor(Sex sex, AppText text) => switch (sex) {
    Sex.male => text.filterSexMale,
    Sex.female => text.filterSexFemale,
    Sex.unknown => text.filterSexUnknown,
  };
}

/// One section's name, and what has been chosen in it.
class _Heading extends StatelessWidget {
  const _Heading(this.label, {this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing case final chosen?)
            Text(
              chosen,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }
}
