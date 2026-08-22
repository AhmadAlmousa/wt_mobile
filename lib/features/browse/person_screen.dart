import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../data/session_manager.dart';
import '../../data/stock/records_repository.dart';
import '../../domain/records.dart';
import '../../l10n/app_localizations.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import 'authenticated_image.dart';

/// One person: their names, photo, facts and family.
class PersonScreen extends StatefulWidget {
  const PersonScreen({
    required this.session,
    required this.records,
    required this.tree,
    required this.xref,
    required this.onOpenPerson,
    super.key,
  });

  final SessionManager session;
  final RecordsRepository records;
  final String tree;
  final String xref;
  final void Function(String xref) onOpenPerson;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  late Future<IndividualRecord> _person;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PersonScreen old) {
    super.didUpdateWidget(old);
    if (old.xref != widget.xref) _load();
  }

  void _load() {
    setState(() {
      _person = widget.session.withSession(
        () => widget.records.individual(widget.tree, widget.xref),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(text.person),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: text.reload,
            onPressed: _load,
          ),
        ],
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

            return _PersonBody(
              person: snapshot.data!,
              records: widget.records,
              onOpenPerson: widget.onOpenPerson,
            );
          },
        ),
      ),
    );
  }
}

class _PersonBody extends StatelessWidget {
  const _PersonBody({
    required this.person,
    required this.records,
    required this.onOpenPerson,
  });

  final IndividualRecord person;
  final RecordsRepository records;
  final void Function(String xref) onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final secondary = person.facts.where((fact) => fact.isSecondary).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Header(person: person, records: records),

        // Each warning names a section that could not be loaded. Saying so is
        // the difference between a known gap and an app that looks broken.
        for (final warning in person.warnings) ...[
          const SizedBox(height: 16),
          MessagePanel.warning(warning.localized(text)),
        ],

        if (person.primaryFacts.isNotEmpty) ...[
          const SizedBox(height: 28),
          _SectionTitle(text.factsAndEvents),
          const SizedBox(height: 8),
          for (final fact in person.primaryFacts) _FactTile(fact: fact),
        ],

        _Relatives(
          label: text.parents,
          people: person.parents.toList(),
          records: records,
          onOpenPerson: onOpenPerson,
        ),
        _Relatives(
          label: text.siblings,
          people: person.siblings.toList(),
          records: records,
          onOpenPerson: onOpenPerson,
        ),
        _Relatives(
          label: text.spouses,
          people: person.spouses.toList(),
          records: records,
          onOpenPerson: onOpenPerson,
        ),
        _Relatives(
          label: text.children,
          people: person.children.toList(),
          records: records,
          onOpenPerson: onOpenPerson,
        ),

        if (secondary.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              title: Text(
                text.eventsOfCloseRelatives,
                style: theme.textTheme.titleSmall,
              ),
              shape: const Border(),
              childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final fact in secondary) _FactTile(fact: fact)],
            ),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.person, required this.records});

  final IndividualRecord person;
  final RecordsRepository records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthenticatedImage(
          url: person.thumbnailUrl,
          records: records,
          size: 104,
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(person.name, style: theme.textTheme.headlineMedium),
              if (person.alternateName != null) ...[
                const SizedBox(height: 4),
                Text(
                  person.alternateName!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  person.xref,
                  // A record id is always Latin, whichever way the page reads.
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.fact});

  final FactEntry fact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Date and place are shown exactly as webtrees rendered them: it has
    // already applied the tree's calendar and language, and re-formatting
    // would lose the calendar and the approximations.
    final detail = [?fact.date, ?fact.place].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.shapeMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fact.type == null ? fact.label : '${fact.label} — ${fact.type}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          if (fact.value != null)
            Text(fact.value!, style: theme.textTheme.bodyLarge),
          if (detail.isNotEmpty)
            Text(
              detail,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _Relatives extends StatelessWidget {
  const _Relatives({
    required this.label,
    required this.people,
    required this.records,
    required this.onOpenPerson,
  });

  final String label;
  final List<PersonRef> people;
  final RecordsRepository records;
  final void Function(String xref) onOpenPerson;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        _SectionTitle(label),
        const SizedBox(height: 8),
        for (final person in people)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: AuthenticatedImage(
                url: person.thumbnailUrl,
                records: records,
                size: 48,
              ),
              title: Text(person.name),
              subtitle: Text(
                [?person.alternateName, ?person.lifespan].join(' · '),
              ),
              onTap: () => onOpenPerson(person.xref),
            ),
          ),
      ],
    );
  }
}
