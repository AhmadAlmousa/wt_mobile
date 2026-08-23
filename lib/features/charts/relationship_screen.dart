import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../data/session_manager.dart';
import '../../data/stock/charts_repository.dart';
import '../../data/stock/records_repository.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import '../../l10n/app_localizations.dart';
import '../shared/bidi.dart';
import '../shared/chart_header_title.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import '../shared/person_tile.dart';

/// How two people in a tree are related.
///
/// The one question a family tree gets asked more than any other, and the one
/// the app cannot answer for itself: working it out means walking a graph the
/// app would have to fetch a record at a time. webtrees already knows, and
/// says so in the reader's language — including distinctions English does not
/// make, where Arabic separates an older brother from a younger one.
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
  final RecordsRepository records;
  final ChartsRepository charts;
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
    final url = person.charts[ChartKind.relationship];
    if (url == null) return;

    setState(() {
      _other = other;
      _paths = widget.session.withSession(
        () =>
            widget.charts.relationship(url, from: person.xref, to: other.xref),
      );
    });
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

            return _Path(
              paths: _paths!,
              from: person.asReference,
              to: other,
              records: widget.records,
              bloodLinesOnly: ChartsRepository.bloodLinesOnly(
                person.charts[ChartKind.relationship] ?? '',
              ),
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

/// The path itself: who, then how, then who.
class _Path extends StatelessWidget {
  const _Path({
    required this.paths,
    required this.from,
    required this.to,
    required this.records,
    required this.bloodLinesOnly,
    required this.onOpenPerson,
    required this.onChooseAgain,
  });

  final Future<List<RelationshipPath>> paths;
  final PersonRef from;
  final PersonRef to;
  final RecordsRepository records;

  /// Whether the site is set to search only through common ancestors.
  final bool bloodLinesOnly;

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

        final found = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (found.isEmpty) ...[
              MessagePanel.warning(text.relationshipNoLink),
              // Two people can be in one tree and not related at all — and on
              // a site set to search blood lines only, a marriage is not a
              // link either. Saying which is the difference between an answer
              // and an apparent failure.
              if (bloodLinesOnly) ...[
                const SizedBox(height: 12),
                Text(
                  text.relationshipBloodOnly,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ] else ...[
              // The site's own phrase for the whole relationship. Composing
              // one here would mean inventing kinship terms in two languages,
              // and Arabic makes distinctions English has no word for.
              Text(found.first.description, style: theme.textTheme.titleLarge),
              if (found.length > 1) ...[
                const SizedBox(height: 8),
                Text(
                  text.relationshipPaths,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              for (final path in found) ...[
                PersonTile(
                  person: path.from,
                  records: records,
                  onOpen: () => onOpenPerson(path.from.xref),
                ),
                for (final step in path.steps) ...[
                  _Link(step.relationship),
                  PersonTile(
                    person: step.person,
                    records: records,
                    onOpen: () => onOpenPerson(step.person.xref),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ],
            const SizedBox(height: 8),
            Center(
              child: OutlinedButton.icon(
                onPressed: onChooseAgain,
                icon: const Icon(Icons.search),
                label: Text(text.relationshipChoose),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One rung of the ladder: how the person below is related to the one above.
class _Link extends StatelessWidget {
  const _Link(this.relationship);

  final String relationship;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 28, top: 4, bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.subdirectory_arrow_right,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              relationship,
              textDirection: directionOf(relationship),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
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
  final RecordsRepository records;
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
