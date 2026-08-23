import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../data/session_manager.dart';
import '../../data/settings_store.dart';
import '../../data/transport.dart';
import '../../domain/charts.dart';
import '../../domain/dates.dart';
import '../../domain/records.dart';
import '../../l10n/app_localizations.dart';
import '../charts/chart_screen.dart' show chartTitle;
import '../shared/bidi.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import '../shared/person_tile.dart';
import 'authenticated_image.dart';
import 'fact_icons.dart';

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
  final RecordsTransport records;
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

    return FutureBuilder<IndividualRecord>(
      future: _person,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _Waiting(title: text.person, onReload: _load);
        }

        final error = snapshot.error;
        if (error != null) {
          return _Waiting(
            title: text.person,
            onReload: _load,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: MessagePanel.error(
                error is WebtreesError
                    ? error.localized(text)
                    : text.personOpenFailed,
              ),
            ),
          );
        }

        // Rebuilt on a settings change so switching calendar takes effect
        // without reloading the record from the server.
        return ListenableBuilder(
          listenable: widget.settings,
          builder: (context, _) => _PersonBody(
            person: snapshot.data!,
            records: widget.records,
            calendar: widget.settings.calendarView,
            onReload: _load,
            onOpenPerson: widget.onOpenPerson,
            onOpenChart: widget.onOpenChart,
          ),
        );
      },
    );
  }
}

/// The page before it has anything to show, or after it failed to get it.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.title, required this.onReload, this.child});

  final String title;
  final VoidCallback onReload;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: text.reload,
            onPressed: onReload,
          ),
        ],
      ),
      body: SafeArea(
        child: child ?? const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _PersonBody extends StatelessWidget {
  const _PersonBody({
    required this.person,
    required this.records,
    required this.calendar,
    required this.onReload,
    required this.onOpenPerson,
    required this.onOpenChart,
  });

  final IndividualRecord person;
  final RecordsTransport records;
  final CalendarView calendar;
  final VoidCallback onReload;
  final void Function(String xref) onOpenPerson;
  final void Function(ChartKind kind) onOpenChart;

  @override
  Widget build(BuildContext context) {
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

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _CollapsingHeader(
            person: person,
            records: records,
            onReload: onReload,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            sliver: SliverList.list(
              children: [
                _Identity(person: person),

                // Only the charts this site actually runs, and only those the
                // app can draw for itself — offering one it cannot draw would
                // be a promise the next tap breaks.
                _Charts(
                  kinds: ChartKind.drawnFrom(person.charts),
                  onOpen: onOpenChart,
                ),

                // Each warning names a section that could not be loaded.
                // Saying so is the difference between a known gap and an app
                // that looks broken.
                for (final warning in person.warnings) ...[
                  const SizedBox(height: 12),
                  MessagePanel.warning(warning.localized(text)),
                ],
                const SizedBox(height: 20),

                if (person.primaryFacts.isNotEmpty)
                  _SectionCard(
                    icon: Icons.event_note_outlined,
                    title: text.factsAndEvents,
                    count: person.primaryFacts.length,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final fact in person.primaryFacts)
                          _FactTile(fact: fact, calendar: calendar),
                      ],
                    ),
                  ),

                _Relatives(
                  icon: Icons.escalator_warning_outlined,
                  label: text.parents,
                  people: person.parents.toList(),
                  // The parents' own marriage is recorded against their
                  // family, and this is the only place it is stated.
                  facts: birthFamilies
                      .expand((family) => family.facts)
                      .toList(),
                  calendar: calendar,
                  records: records,
                  onOpenPerson: onOpenPerson,
                ),
                _Relatives(
                  icon: Icons.groups_outlined,
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

                // Family comes before everything a tree adds around it: this
                // is the part of the record anyone opened the app for.
                if (person.media.isNotEmpty)
                  _Photos(media: person.media, records: records),
                if (person.notes.isNotEmpty) _Notes(notes: person.notes),
                if (person.sources.isNotEmpty)
                  _Sources(citations: person.sources),

                if (secondary.isNotEmpty)
                  _CloseRelativesEvents(
                    facts: secondary,
                    calendar: calendar,
                    onOpenPerson: onOpenPerson,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The photograph and name, shrinking into the bar as the page scrolls.
///
/// Built from the flexible space's own height rather than with
/// [FlexibleSpaceBar]'s title, which scales a finished layout: laying a name
/// out at `width / scale` and then magnifying it leaves an Arabic name
/// wrapping and a romanized one truncated at exactly the moment there is most
/// room for both. Interpolating the sizes instead means every state is laid
/// out at the width it is actually drawn at.
class _CollapsingHeader extends StatelessWidget {
  const _CollapsingHeader({
    required this.person,
    required this.records,
    required this.onReload,
  });

  final IndividualRecord person;
  final RecordsTransport records;
  final VoidCallback onReload;

  /// How tall the bar is with the page at the top.
  static const double _expanded = 156;

  static const double _portraitLarge = 84;
  static const double _portraitSmall = 34;

  /// Room kept clear at the start once the bar has collapsed, so a name never
  /// lands on the back button. Expanded, the portrait sits at the page's own
  /// margin instead.
  static const double _clearOfBack = 56;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final alternate = person.alternateName;

    return SliverAppBar(
      pinned: true,
      expandedHeight: _expanded,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: text.reload,
          onPressed: onReload,
        ),
      ],
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final tallest = _expanded + top;
          final shortest = kToolbarHeight + top;
          // 0 with the page at the top, 1 once the bar has fully collapsed.
          final gone =
              ((tallest - constraints.maxHeight) / (tallest - shortest)).clamp(
                0.0,
                1.0,
              );

          final portrait = lerpDouble(_portraitLarge, _portraitSmall, gone)!;
          final name = TextStyle.lerp(
            theme.textTheme.headlineSmall,
            theme.textTheme.titleMedium,
            gone,
          );

          return Padding(
            padding: EdgeInsetsDirectional.only(
              start: lerpDouble(16, _clearOfBack, gone)!,
              end: _clearOfBack,
              bottom: 12,
            ),
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AuthenticatedImage(
                    url: person.thumbnailUrl,
                    records: records,
                    name: person.name,
                    sex: person.sex,
                    deceased: person.isDeceased,
                    size: portrait,
                  ),
                  SizedBox(width: lerpDouble(14, 10, gone)!),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.name,
                          // Two lines while there is room for them; one once
                          // the bar is a toolbar, which is all it can hold.
                          maxLines: gone > 0.6 ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          textDirection: directionOf(person.name),
                          style: name?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (alternate != null)
                          // Folded away rather than faded in place: keeping
                          // its height would push the name out of a 56-pixel
                          // bar, and a second name is context, not identity.
                          ClipRect(
                            child: Align(
                              alignment: AlignmentDirectional.topStart,
                              heightFactor: 1 - gone,
                              child: Opacity(
                                opacity: 1 - gone,
                                child: Text(
                                  alternate,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textDirection: directionOf(alternate),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// What the record is, beneath what it is about: the years, and the id.
class _Identity extends StatelessWidget {
  const _Identity({required this.person});

  final IndividualRecord person;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final lifespan = person.lifespan;

    // Colours come from the theme rather than from the person's sex: this
    // strip describes the *record*, and the portrait above it has already
    // said who the record is about.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (lifespan != null)
          _Pill(
            icon: Icons.calendar_today_outlined,
            // All digits and a dash: without an isolate the Arabic layout
            // reverses it and the person dies before they are born.
            label: ltrRun(lifespan),
          ),
        if (person.isDeceased)
          _Pill(icon: Icons.hourglass_bottom_outlined, label: text.deceased),
        _Pill(
          icon: Icons.tag,
          // A record id is always Latin, whichever way the page reads.
          label: ltrRun(person.xref),
          tooltip: text.recordId,
        ),
      ],
    );
  }
}

/// A small rounded label, quieter than a chip and not tappable.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.tooltip});

  final IconData icon;
  final String label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    final hint = tooltip;
    return hint == null ? pill : Tooltip(message: hint, child: pill);
  }
}

/// One titled, bordered block of the page.
///
/// The page used to be a single run of rounded rectangles separated by
/// nothing but space, so a reader scrolling past a second marriage had no
/// edge to tell them one family had ended and another begun. A card with a
/// visible boundary does that work; the icon and the count let it be
/// recognised without being read.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.count,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final int? count;

  /// A line under the heading — what happened to this family, for instance.
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final total = count;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.shapeExtraLarge),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.primary,
                    ),
                  ),
                ),
                if (total != null && total > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      // A count is digits and nothing else, so it is isolated
                      // like every other number in the interface.
                      ltrRun('$total'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            if (subtitle != null) ...[const SizedBox(height: 6), subtitle!],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
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
    final colors = theme.colorScheme;
    final about = fact.about;
    // The date is shown exactly as webtrees wrote it, in whichever calendars
    // the reader asked to keep: it has already applied the tree's calendar and
    // language, and re-formatting would lose the approximations.
    final detail = [?fact.date?.display(calendar), ?fact.place].join(' · ');

    final tile = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.shapeMedium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chosen by GEDCOM tag, never by the label: the label is already
          // translated, and an icon table keyed on English words would go
          // blank in Arabic.
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(iconForFact(fact.tag), size: 17, color: colors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fact.type == null
                      ? fact.label
                      : '${fact.label} — ${fact.type}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.primary,
                  ),
                ),
                // Whose event this was. "Birth of a brother" names the event
                // but not the brother, and the name is the part a reader is
                // looking for.
                if (about != null)
                  Text(about.name, style: theme.textTheme.bodyLarge),
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
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (about != null && onOpenPerson != null)
            Icon(Icons.chevron_right, size: 18, color: colors.onSurfaceVariant),
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
    required this.icon,
    required this.label,
    required this.people,
    required this.records,
    required this.calendar,
    required this.onOpenPerson,
    this.facts = const [],
  });

  final IconData icon;
  final String label;
  final List<PersonRef> people;

  /// What happened to the family these people belong to — a marriage, a
  /// divorce — which is recorded against the family and nowhere else.
  final List<FactEntry> facts;

  final RecordsTransport records;
  final CalendarView calendar;
  final void Function(String xref) onOpenPerson;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty && facts.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;

    return _SectionCard(
      icon: icon,
      title: label,
      count: people.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final person in people)
            PersonTile(
              person: person,
              records: records,
              dense: true,
              color: colors.surfaceContainerHigh,
              onOpen: () => onOpenPerson(person.xref),
            ),
          for (final fact in facts) _FactTile(fact: fact, calendar: calendar),
        ],
      ),
    );
  }
}

/// One family a person made, or was placed in beside a step-parent.
///
/// Shown as a block rather than folded into one list of spouses and one of
/// children: somebody who married twice has two sets of children, and merging
/// them would put a child under the wrong marriage. The card's own border is
/// what says where one marriage ends and the next begins.
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

  final RecordsTransport records;
  final CalendarView calendar;
  final void Function(String xref) onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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

    return _SectionCard(
      icon: family.endedInDivorce
          ? Icons.heart_broken_outlined
          : Icons.family_restroom_outlined,
      title: heading,
      // What happened to the couple, said once at the top of their block —
      // each label is the server's own word for the event, so a divorce
      // announces itself in the reader's language without the app owning a
      // translation of it.
      subtitle: family.facts.isEmpty
          ? null
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final fact in family.facts)
                  _Pill(
                    icon: iconForFact(fact.tag),
                    label: [fact.label, ?fact.value].join(' · '),
                  ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final person in partners)
            PersonTile(
              person: person,
              records: records,
              dense: true,
              color: colors.surfaceContainerHigh,
              onOpen: () => onOpenPerson(person.xref),
            ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 6),
            _SubTitle(
              family.kind == FamilyKind.own
                  ? text.childCount(children.length)
                  : text.siblings,
            ),
            const SizedBox(height: 8),
            for (final child in children)
              PersonTile(
                person: child,
                records: records,
                dense: true,
                color: colors.surfaceContainerHigh,
                onOpen: () => onOpenPerson(child.xref),
              ),
          ],
        ],
      ),
    );
  }
}

/// The photographs a tree publishes for this person.
///
/// Thumbnails only: the media tab renders them at 100 pixels and signs each
/// URL for that size, so the app cannot ask for a bigger one — the full image
/// lives behind the media record, which v1 has no screen for.
class _Photos extends StatelessWidget {
  const _Photos({required this.media, required this.records});

  final List<MediaItem> media;
  final RecordsTransport records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return _SectionCard(
      icon: Icons.photo_library_outlined,
      title: text.photos,
      count: media.length,
      child: SizedBox(
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
                    // A document or a sound file has no face and no initial:
                    // the placeholder people get would say the wrong thing
                    // about a photograph of a certificate.
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
      padding: const EdgeInsets.only(top: 14),
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
  ChartKind.relationship => Icons.compare_arrows,
  ChartKind.timeline => Icons.timeline,
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

/// Somebody else's events, which webtrees folds into this person's list.
class _CloseRelativesEvents extends StatelessWidget {
  const _CloseRelativesEvents({
    required this.facts,
    required this.calendar,
    required this.onOpenPerson,
  });

  final List<FactEntry> facts;
  final CalendarView calendar;
  final void Function(String xref) onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = AppText.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.shapeExtraLarge),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: ExpansionTile(
        leading: Icon(
          Icons.people_alt_outlined,
          size: 18,
          color: colors.primary,
        ),
        title: Text(
          text.eventsOfCloseRelatives,
          style: theme.textTheme.titleSmall?.copyWith(color: colors.primary),
        ),
        shape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final fact in facts)
            _FactTile(
              fact: fact,
              calendar: calendar,
              // These are somebody else's events, so the person they happened
              // to is the point of the row — and somewhere the reader may
              // want to go.
              onOpenPerson: onOpenPerson,
            ),
        ],
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
    final colors = theme.colorScheme;
    final text = AppText.of(context);
    // A note about the person comes before a note about one of their facts,
    // which is the order webtrees itself shows them in.
    final ordered = [
      ...notes.where((note) => !note.isSecondary),
      ...notes.where((note) => note.isSecondary),
    ];

    return _SectionCard(
      icon: Icons.sticky_note_2_outlined,
      title: text.notes,
      count: notes.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final note in ordered)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppTheme.shapeMedium),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note.text,
                    // A tree writes its notes in the family's language, not
                    // the reader's, so the paragraph takes its direction from
                    // what it says — as webtrees does with `dir="auto"`.
                    textDirection: directionOf(note.text),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
        ],
      ),
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
    final colors = theme.colorScheme;
    final text = AppText.of(context);

    return _SectionCard(
      icon: Icons.menu_book_outlined,
      title: text.sources,
      count: citations.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final citation in citations)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppTheme.shapeMedium),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    citation.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.primary,
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
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
