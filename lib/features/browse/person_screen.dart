import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../data/session_manager.dart';
import '../../data/settings_store.dart';
import '../../data/stock/records_repository.dart';
import '../../domain/charts.dart';
import '../../domain/dates.dart';
import '../../domain/records.dart';
import '../../l10n/app_localizations.dart';
import '../charts/chart_screen.dart' show chartTitle;
import '../shared/bidi.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import 'authenticated_image.dart';

/// One person: their names, photo, facts and family.
class PersonScreen extends StatefulWidget {
  const PersonScreen({
    required this.session,
    required this.records,
    required this.settings,
    required this.tree,
    required this.xref,
    required this.onOpenPerson,
    required this.onOpenChart,
    super.key,
  });

  final SessionManager session;
  final RecordsRepository records;
  final SettingsStore settings;
  final String tree;
  final String xref;
  final void Function(String xref) onOpenPerson;

  /// Opens one of the charts this site draws for this person.
  final void Function(ChartKind kind) onOpenChart;

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

            // Rebuilt on a settings change so switching calendar takes
            // effect without reloading the record from the server.
            return ListenableBuilder(
              listenable: widget.settings,
              builder: (context, _) => _PersonBody(
                person: snapshot.data!,
                records: widget.records,
                calendar: widget.settings.calendarView,
                onOpenPerson: widget.onOpenPerson,
                onOpenChart: widget.onOpenChart,
              ),
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
    required this.calendar,
    required this.onOpenPerson,
    required this.onOpenChart,
  });

  final IndividualRecord person;
  final RecordsRepository records;
  final CalendarView calendar;
  final void Function(String xref) onOpenPerson;
  final void Function(ChartKind kind) onOpenChart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final secondary = person.facts.where((fact) => fact.isSecondary).toList();

    // Birth families are shown as parents and brothers and sisters, the way
    // anyone would name them. The families a person made are shown one block
    // at a time: with two marriages, a single merged list of children says
    // nothing about which of them belongs to whom.
    final birthFamilies = person.families
        .where((family) => family.kind == FamilyKind.parents)
        .toList();
    final otherFamilies = person.families
        .where((family) => family.kind != FamilyKind.parents)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Header(person: person, records: records),

        // Only the charts this site actually runs, and only those the app can
        // draw for itself — offering one it cannot draw would be a promise
        // the next tap breaks.
        _Charts(
          kinds: person.charts.keys.where(ChartKind.drawable.contains).toList(),
          onOpen: onOpenChart,
        ),

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
          for (final fact in person.primaryFacts)
            _FactTile(fact: fact, calendar: calendar),
        ],

        _Relatives(
          label: text.parents,
          people: person.parents.toList(),
          // The parents' own marriage is recorded against their family, and
          // this is the only place it is stated.
          facts: birthFamilies.expand((family) => family.facts).toList(),
          calendar: calendar,
          records: records,
          onOpenPerson: onOpenPerson,
        ),
        _Relatives(
          label: text.siblings,
          people: person.siblings.toList(),
          calendar: calendar,
          records: records,
          onOpenPerson: onOpenPerson,
        ),

        for (final family in otherFamilies)
          _FamilyBlock(
            family: family,
            self: person.xref,
            calendar: calendar,
            records: records,
            onOpenPerson: onOpenPerson,
          ),

        // Family comes before everything a tree adds around it: this is the
        // part of the record anyone opened the app for.
        if (person.media.isNotEmpty)
          _Photos(media: person.media, records: records),
        if (person.notes.isNotEmpty) _Notes(notes: person.notes),
        if (person.sources.isNotEmpty) _Sources(citations: person.sources),

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
              children: [
                for (final fact in secondary)
                  _FactTile(
                    fact: fact,
                    calendar: calendar,
                    // These are somebody else's events, so the person they
                    // happened to is the point of the row — and somewhere the
                    // reader may want to go.
                    onOpenPerson: onOpenPerson,
                  ),
              ],
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
          name: person.name,
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

/// A heading for a list inside a section, quieter than the section's own.
class _SubTitle extends StatelessWidget {
  const _SubTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
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
  const _FactTile({
    required this.fact,
    required this.calendar,
    this.onOpenPerson,
  });

  final FactEntry fact;
  final CalendarView calendar;

  /// Offered for a fact that happened to somebody else, so the reader can go
  /// to them. Null where the fact is the person's own and there is nobody
  /// else to open.
  final void Function(String xref)? onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final about = fact.about;
    // The date is shown exactly as webtrees wrote it, in whichever calendars
    // the reader asked to keep: it has already applied the tree's calendar and
    // language, and re-formatting would lose the approximations.
    final detail = [?fact.date?.display(calendar), ?fact.place].join(' · ');

    final tile = Container(
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
          // Whose event this was. "Birth of a brother" names the event but
          // not the brother, and the name is the part a reader is looking for.
          if (about != null) Text(about.name, style: theme.textTheme.bodyLarge),
          if (fact.value != null)
            Text(
              fact.value!,
              textDirection: directionOf(fact.value),
              style: theme.textTheme.bodyLarge,
            ),
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

    final open = onOpenPerson;
    if (about == null || open == null) return tile;

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.shapeMedium),
      onTap: () => open(about.xref),
      child: tile,
    );
  }
}

class _Relatives extends StatelessWidget {
  const _Relatives({
    required this.label,
    required this.people,
    required this.records,
    required this.calendar,
    required this.onOpenPerson,
    this.facts = const [],
  });

  final String label;
  final List<PersonRef> people;

  /// What happened to the family these people belong to — a marriage, a
  /// divorce — which is recorded against the family and nowhere else.
  final List<FactEntry> facts;

  final RecordsRepository records;
  final CalendarView calendar;
  final void Function(String xref) onOpenPerson;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty && facts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        _SectionTitle(label),
        const SizedBox(height: 8),
        for (final person in people)
          _PersonTile(
            person: person,
            records: records,
            onOpen: () => onOpenPerson(person.xref),
          ),
        for (final fact in facts) _FactTile(fact: fact, calendar: calendar),
      ],
    );
  }
}

/// One family a person made, or was placed in beside a step-parent.
///
/// Shown as a block rather than folded into one list of spouses and one of
/// children: somebody who married twice has two sets of children, and merging
/// them would put a child under the wrong marriage.
class _FamilyBlock extends StatelessWidget {
  const _FamilyBlock({
    required this.family,
    required this.self,
    required this.records,
    required this.calendar,
    required this.onOpenPerson,
  });

  final FamilyGroup family;

  /// The person whose page this is, who is a member of this family and is not
  /// listed again inside it.
  final String self;

  final RecordsRepository records;
  final CalendarView calendar;
  final void Function(String xref) onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final partners = family.spouses
        .where((person) => person.xref != self)
        .toList();
    final children = family.children
        .where((person) => person.xref != self)
        .toList();
    if (partners.isEmpty && children.isEmpty && family.facts.isEmpty) {
      return const SizedBox.shrink();
    }

    // The site's own heading — "Family with Sarah" — already translated and
    // already naming the person it is a family with. A theme that renders the
    // caption without text leaves the parser holding the family's identifier,
    // which is no heading at all.
    final heading = family.label == family.xref
        ? (family.kind == FamilyKind.own ? text.spouses : text.parents)
        : family.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        _SectionTitle(heading),
        const SizedBox(height: 8),
        for (final person in partners)
          _PersonTile(
            person: person,
            records: records,
            onOpen: () => onOpenPerson(person.xref),
          ),
        for (final fact in family.facts)
          _FactTile(fact: fact, calendar: calendar),
        if (children.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SubTitle(
            family.kind == FamilyKind.own ? text.children : text.siblings,
          ),
          const SizedBox(height: 6),
          for (final child in children)
            _PersonTile(
              person: child,
              records: records,
              onOpen: () => onOpenPerson(child.xref),
            ),
        ],
      ],
    );
  }
}

/// One person in a list of relatives.
class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.person,
    required this.records,
    required this.onOpen,
  });

  final PersonRef person;
  final RecordsRepository records;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      leading: AuthenticatedImage(
        url: person.thumbnailUrl,
        records: records,
        name: person.name,
        size: 48,
      ),
      title: Text(person.name),
      subtitle: Text(
        [
          if (person.alternateName != null) isolatedRun(person.alternateName),
          if (person.lifespan != null) ltrRun(person.lifespan),
        ].join(' · '),
      ),
      onTap: onOpen,
    ),
  );
}

/// The photographs a tree publishes for this person.
///
/// Thumbnails only: the media tab renders them at 100 pixels and signs each
/// URL for that size, so the app cannot ask for a bigger one — the full image
/// lives behind the media record, which v1 has no screen for.
class _Photos extends StatelessWidget {
  const _Photos({required this.media, required this.records});

  final List<MediaItem> media;
  final RecordsRepository records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        _SectionTitle(text.photos),
        const SizedBox(height: 8),
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: media.length,
            separatorBuilder: (context, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = media[index];
              return SizedBox(
                width: 104,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AuthenticatedImage(
                      url: item.thumbnailUrl,
                      records: records,
                      size: 104,
                      // A document or a sound file has no face and no
                      // initial: the placeholder people get would say the
                      // wrong thing about a photograph of a certificate.
                      fallback: const _PhotoPlaceholder(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The charts a reader can open from here.
class _Charts extends StatelessWidget {
  const _Charts({required this.kinds, required this.onOpen});

  final List<ChartKind> kinds;
  final void Function(ChartKind kind) onOpen;

  @override
  Widget build(BuildContext context) {
    if (kinds.isEmpty) return const SizedBox.shrink();
    final text = AppText.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final kind in kinds)
            ActionChip(
              avatar: Icon(_iconFor(kind), size: 18),
              label: Text(chartTitle(kind, text)),
              onPressed: () => onOpen(kind),
            ),
        ],
      ),
    );
  }
}

/// The icon that stands for a chart.
IconData _iconFor(ChartKind kind) => switch (kind) {
  ChartKind.ancestors => Icons.account_tree_outlined,
  ChartKind.hourglass => Icons.hourglass_empty,
  _ => Icons.family_restroom_outlined,
};

/// Stands in for a photograph that is loading, missing or unreadable.
class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.photo_outlined,
        color: colors.onSurfaceVariant,
        size: 32,
      ),
    );
  }
}

/// What the family wrote down about this person, in their own words.
class _Notes extends StatelessWidget {
  const _Notes({required this.notes});

  final List<NoteEntry> notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    // A note about the person comes before a note about one of their facts,
    // which is the order webtrees itself shows them in.
    final ordered = [
      ...notes.where((note) => !note.isSecondary),
      ...notes.where((note) => note.isSecondary),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        _SectionTitle(text.notes),
        const SizedBox(height: 8),
        for (final note in ordered)
          Container(
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
                  note.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  note.text,
                  // A tree writes its notes in the family's language, not the
                  // reader's, so the paragraph takes its direction from what
                  // it says — as webtrees does with `dir="auto"`.
                  textDirection: directionOf(note.text),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Where the facts came from.
class _Sources extends StatelessWidget {
  const _Sources({required this.citations});

  final List<SourceCitation> citations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        _SectionTitle(text.sources),
        const SizedBox(height: 8),
        for (final citation in citations)
          Container(
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
                  citation.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  citation.title,
                  textDirection: directionOf(citation.title),
                  style: theme.textTheme.bodyLarge,
                ),
                // Page, quality, date — each already worded by the site, so
                // the app prints them rather than composing a sentence.
                for (final detail in citation.details)
                  Text(
                    detail,
                    textDirection: directionOf(detail),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
