import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/transport.dart';
import '../../domain/charts.dart';
import '../../l10n/app_localizations.dart';
import '../shared/bidi.dart';
import '../shared/person_tile.dart';

/// One way two people are related, drawn as a path rather than listed.
///
/// A relationship is a route through a family, and a list of names is the one
/// thing that does not look like one: the reader has to hold the order in
/// their head and work out which way it runs. A spine down the page with each
/// link named on it says the same thing without being read.
///
/// The words on the rungs are the site's own — `father`, `أخ أكبر` — and stay
/// that way. Composing them here would mean inventing kinship terms in two
/// languages, and Arabic distinguishes an older brother from a younger one
/// where English has no word at all.
class RelationshipPathView extends StatelessWidget {
  const RelationshipPathView({
    required this.path,
    required this.records,
    required this.onOpenPerson,
    super.key,
  });

  final RelationshipPath path;
  final RecordsTransport records;
  final void Function(String xref) onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final last = path.steps.isEmpty ? null : path.steps.last.person.xref;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PersonTile(
          person: path.from,
          records: records,
          dense: true,
          onOpen: () => onOpenPerson(path.from.xref),
        ),
        for (final step in path.steps) ...[
          _Rung(step.relationship),
          PersonTile(
            person: step.person,
            records: records,
            dense: true,
            // The far end is where the reader was going, and the one box on
            // the path worth arriving at.
            trailing: step.person.xref == last
                ? Icon(
                    Icons.flag_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
            onOpen: () => onOpenPerson(step.person.xref),
          ),
        ],
      ],
    );
  }
}

/// One rung of the ladder: a piece of spine, and what the link is called.
class _Rung extends StatelessWidget {
  const _Rung(this.relationship);

  final String relationship;

  /// Where the spine runs, measured from the start edge: down the middle of
  /// the avatars in the tiles above and below it.
  static const double _spine = 33;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: _spine),
      child: Row(
        children: [
          // Drawn flush against the cards either side, so the two segments
          // and the avatars between them read as one continuous line.
          SizedBox(
            width: 2,
            height: 38,
            child: ColoredBox(color: colors.outlineVariant),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                relationship,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // A kinship term is written in the site's language, not the
                // reader's, so it takes its direction from itself.
                textDirection: directionOf(relationship),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Both ends of the comparison, and the site's own phrase for what lies
/// between them.
class RelationshipSummary extends StatelessWidget {
  const RelationshipSummary({
    required this.description,
    required this.steps,
    super.key,
  });

  /// The whole relationship as one phrase, as the site put it.
  final String description;

  /// How many links the shortest path holds.
  final int steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = AppText.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.shapeExtraLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            textDirection: directionOf(description),
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text.relationshipSteps(steps),
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onPrimaryContainer.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
