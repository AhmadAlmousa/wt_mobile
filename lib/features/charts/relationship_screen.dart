import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../data/session_manager.dart';
import '../../data/transport.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import '../../l10n/app_localizations.dart';
import '../shared/chart_header_title.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import '../shared/person_tile.dart';
import 'relationship_modes.dart';
import 'relationship_path_view.dart';

/// How two people in a tree are related.
///
/// The one question a family tree gets asked more than any other, and the one
/// the app cannot answer for itself: working it out means walking a graph the
/// app would have to fetch a record at a time. webtrees already knows, and
/// says so in the reader's language — including distinctions English does not
/// make, where Arabic separates an older brother from a younger one.
///
/// What the app *can* do is ask the question the way a person would. webtrees
/// answers with every path it found; sorting those by which of the subject's
/// own relatives each one leaves through turns a list into "on my mother's
/// side" — see [RelationshipRoutes].
class RelationshipScreen extends StatefulWidget {
  const RelationshipScreen({
    required this.session,
    required this.records,
    required this.charts,
    required this.tree,
    required this.xref,
    required this.onOpenPerson,
    super.key,
  });

  final SessionManager session;
  final RecordsTransport records;
  final ChartsTransport charts;
  final String tree;
  final String xref;
  final void Function(String xref) onOpenPerson;

  @override
  State<RelationshipScreen> createState() => _RelationshipScreenState();
}

class _RelationshipScreenState extends State<RelationshipScreen> {
  late Future<IndividualRecord> _person;

  /// The person the comparison starts from, once their record has arrived.
  PersonRef? _subject;

  /// The person to compare with, once the reader has chosen one.
  PersonRef? _other;
  Future<List<RelationshipPath>>? _paths;

  /// Whether to search blood lines only, or `null` to leave the site's own
  /// setting alone. Asking either way is a request webtrees means to answer —
  /// see [ChartsRepository.relationship].
  bool? _bloodOnly;

  RelationshipSide _side = RelationshipSide.closest;

  @override
  void initState() {
    super.initState();
    _person = widget.session.withSession(
      () => widget.records.individual(widget.tree, widget.xref),
    );
    // Remembered so the bar can name them while a path is being fetched.
    _person.then((person) {
      if (mounted) setState(() => _subject = person.asReference);
    }).ignore();
  }

  void _compareWith(PersonRef other, IndividualRecord person) {
    setState(() {
      _other = other;
      _side = RelationshipSide.closest;
      _bloodOnly = null;
      _search(person);
    });
  }

  /// Asks the site again, with whatever the reader has chosen.
  void _search(IndividualRecord person) {
    final url = person.charts[ChartKind.relationship];
    final other = _other;
    if (url == null || other == null) return;

    _paths = widget.session.withSession(
      () => widget.charts.relationship(
        url,
        from: person.xref,
        to: other.xref,
        bloodLinesOnly: _bloodOnly,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        title: ChartHeaderTitle(
          title: text.chartRelationship,
          person: _subject,
          records: widget.records,
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<IndividualRecord>(
          future: _person,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final error = snapshot.error;
            if (error != null) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: MessagePanel.error(
                  error is WebtreesError
                      ? error.localized(text)
                      : text.personOpenFailed,
                ),
              );
            }

            final person = snapshot.data!;
            final other = _other;
            if (other == null) {
              return _PersonPicker(
                session: widget.session,
                records: widget.records,
                tree: widget.tree,
                prompt: text.relationshipPick(person.name),
                onPicked: (picked) => _compareWith(picked, person),
              );
            }

            return _Answer(
              paths: _paths!,
              subject: person,
              to: other,
              records: widget.records,
              side: _side,
              onSide: (side) => setState(() => _side = side),
              // The site's own setting is what the app was offered, and what
              // it falls back to; the switch says which of the two is in
              // force, not which one the administrator chose.
              bloodOnly:
                  _bloodOnly ??
                  widget.charts.bloodLinesOnly(
                    person.charts[ChartKind.relationship] ?? '',
                  ),
              onBloodOnly: (only) => setState(() {
                _bloodOnly = only;
                _side = RelationshipSide.closest;
                _search(person);
              }),
              onOpenPerson: widget.onOpenPerson,
              onChooseAgain: () => setState(() {
                _other = null;
                _paths = null;
              }),
            );
          },
        ),
      ),
    );
  }
}

/// The answer, and the ways of asking for a different one.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.paths,
    required this.subject,
    required this.to,
    required this.records,
    required this.side,
    required this.onSide,
    required this.bloodOnly,
    required this.onBloodOnly,
    required this.onOpenPerson,
    required this.onChooseAgain,
  });

  final Future<List<RelationshipPath>> paths;
  final IndividualRecord subject;
  final PersonRef to;
  final RecordsTransport records;

  final RelationshipSide side;
  final ValueChanged<RelationshipSide> onSide;

  /// Whether the search in force is limited to blood relations.
  final bool bloodOnly;
  final ValueChanged<bool> onBloodOnly;

  final void Function(String xref) onOpenPerson;
  final VoidCallback onChooseAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return FutureBuilder<List<RelationshipPath>>(
      future: paths,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final error = snapshot.error;
        if (error != null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: MessagePanel.error(
              error is WebtreesError ? error.localized(text) : text.chartFailed,
            ),
          );
        }

        final routes = RelationshipRoutes(
          paths: snapshot.data!,
          subject: subject,
        );
        final chosen = routes.matching(side);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // Who is being compared with. The subject is already named in
            // the bar, so repeating them here would cost a third of the
            // screen to say what it already says.
            _Comparing(
              // Preferred over the search result the reader picked, which
              // carries no sex: webtrees' autocomplete sends a name, a
              // lifespan and sometimes a photograph, and nothing else.
              person: _asKnown(routes, to),
              records: records,
              onChooseAgain: onChooseAgain,
            ),
            const SizedBox(height: 16),

            _Ways(
              routes: routes,
              side: side,
              onSide: onSide,
              bloodOnly: bloodOnly,
              onBloodOnly: onBloodOnly,
            ),
            const SizedBox(height: 16),

            if (routes.isEmpty) ...[
              MessagePanel.warning(text.relationshipNoLink),
              // Two people can be in one tree and not related at all — and on
              // a search limited to blood lines, a marriage is not a link
              // either. Saying which is the difference between an answer and
              // an apparent failure — and here the reader can lift the limit
              // in the row above rather than being told about it.
              if (bloodOnly) ...[
                const SizedBox(height: 12),
                Text(
                  text.relationshipBloodOnly,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ] else if (chosen.isEmpty)
              MessagePanel.warning(text.relationshipNoneThisWay)
            else ...[
              // The site's own phrase for the whole relationship. Composing
              // one here would mean inventing kinship terms in two languages,
              // and Arabic makes distinctions English has no word for.
              RelationshipSummary(
                description: chosen.first.description,
                steps: chosen.first.steps.length,
              ),
              const SizedBox(height: 16),
              RelationshipPathView(
                path: chosen.first,
                records: records,
                onOpenPerson: onOpenPerson,
              ),

              // A family where cousins marry links two people by more than
              // one line, and each is true.
              if (chosen.length > 1) ...[
                const SizedBox(height: 28),
                Text(
                  text.relationshipOtherWays,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                for (final path in chosen.skip(1)) ...[
                  const SizedBox(height: 12),
                  RelationshipPathView(
                    path: path,
                    records: records,
                    onOpenPerson: onOpenPerson,
                  ),
                ],
              ],
            ],

          ],
        );
      },
    );
  }

  /// [person] as a chart box described them, where any path reached them.
  ///
  /// A path's boxes carry the sex and the death that a search result cannot,
  /// which is what keeps one screen from drawing the same person two ways.
  static PersonRef _asKnown(RelationshipRoutes routes, PersonRef person) {
    for (final path in routes.all) {
      for (final step in path.steps) {
        if (step.person.xref == person.xref) return step.person;
      }
      if (path.from.xref == person.xref) return path.from;
    }
    return person;
  }
}

/// The person the subject is being compared with, and a way to change them.
class _Comparing extends StatelessWidget {
  const _Comparing({
    required this.person,
    required this.records,
    required this.onChooseAgain,
  });

  final PersonRef person;
  final RecordsTransport records;
  final VoidCallback onChooseAgain;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return PersonTile(
      person: person,
      records: records,
      relationship: text.relationshipWith,
      trailing: IconButton(
        icon: const Icon(Icons.search),
        tooltip: text.relationshipChoose,
        onPressed: onChooseAgain,
      ),
      onOpen: onChooseAgain,
    );
  }
}

/// The ways of asking the question.
///
/// A side with no path is shown disabled rather than hidden: "there is no
/// link on your mother's side" is an answer, and a missing button is not.
class _Ways extends StatelessWidget {
  const _Ways({
    required this.routes,
    required this.side,
    required this.onSide,
    required this.bloodOnly,
    required this.onBloodOnly,
  });

  final RelationshipRoutes routes;
  final RelationshipSide side;
  final ValueChanged<RelationshipSide> onSide;
  final bool bloodOnly;
  final ValueChanged<bool> onBloodOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    String label(RelationshipSide which) => switch (which) {
      RelationshipSide.closest => text.relationshipClosest,
      RelationshipSide.fatherSide => text.relationshipFatherSide,
      RelationshipSide.motherSide => text.relationshipMotherSide,
      RelationshipSide.throughSpouse => text.relationshipThroughSpouse,
    };

    IconData icon(RelationshipSide which) => switch (which) {
      RelationshipSide.closest => Icons.timeline,
      RelationshipSide.fatherSide => Icons.male,
      RelationshipSide.motherSide => Icons.female,
      RelationshipSide.throughSpouse => Icons.favorite_outline,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.relationshipHow,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final which in RelationshipSide.values)
              ChoiceChip(
                avatar: Icon(icon(which), size: 17),
                label: Text(label(which)),
                selected: which == side,
                onSelected: routes.offers(which)
                    ? (_) => onSide(which)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 4),
        // The one thing the server itself can be asked differently, and the
        // only way a link through a marriage is ever found.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: bloodOnly,
          onChanged: onBloodOnly,
          title: Text(
            bloodOnly
                ? text.relationshipBloodOnlyToggle
                : text.relationshipAnyLink,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

/// Finds the other person.
///
/// The same search the tree screen uses, without its paging: somebody looking
/// for one person to compare against is naming them, not browsing.
class _PersonPicker extends StatefulWidget {
  const _PersonPicker({
    required this.session,
    required this.records,
    required this.tree,
    required this.prompt,
    required this.onPicked,
  });

  final SessionManager session;
  final RecordsTransport records;
  final String tree;
  final String prompt;
  final void Function(PersonRef person) onPicked;

  @override
  State<_PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<_PersonPicker> {
  Timer? _debounce;
  List<PersonRef> _results = const [];
  bool _searching = false;
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }

    final generation = ++_generation;
    setState(() => _searching = true);
    try {
      final page = await widget.session.withSession(
        () => widget.records.search(widget.tree, query),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = page.people;
        _searching = false;
      });
    } on WebtreesError {
      if (!mounted || generation != _generation) return;
      setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.prompt,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: text.searchForAPerson,
                  hintText: text.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                onChanged: _onChanged,
                onSubmitted: _search,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final person = _results[index];
              return PersonTile(
                person: person,
                records: widget.records,
                onOpen: () => widget.onPicked(person),
              );
            },
          ),
        ),
      ],
    );
  }
}
