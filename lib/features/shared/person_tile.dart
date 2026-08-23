import 'package:flutter/material.dart';

import '../../data/stock/records_repository.dart';
import '../../domain/records.dart';
import '../browse/authenticated_image.dart';
import 'bidi.dart';

/// One person in a list, wherever the app shows a list of people.
///
/// Search results, a page of relatives, a step on a relationship path and the
/// picker that starts one all used to write this row out for themselves —
/// four copies of the same card, avatar, name and years, which is four places
/// to remember when a person gains something worth showing. One widget now,
/// so a gender colour or a mourning ribbon arrives everywhere at once.
class PersonTile extends StatelessWidget {
  const PersonTile({
    required this.person,
    required this.records,
    required this.onOpen,
    this.dense = false,
    this.relationship,
    this.trailing,
    this.color,
    super.key,
  });

  final PersonRef person;
  final RecordsRepository records;
  final VoidCallback onOpen;

  /// A tighter row, for a list inside a card rather than one filling a page.
  final bool dense;

  /// The row's own surface. A tile inside a card has to sit *on* it rather
  /// than repeat it, or the nesting disappears and a family block stops
  /// looking like a block.
  final Color? color;

  /// What this person is to whoever is being read — "father", "أخ أكبر" —
  /// where the site has already said it. Shown above the name, because it is
  /// what the reader is scanning the list for.
  final String? relationship;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = relationship;

    // A line each, rather than one line joined by a separator. Joined, a
    // narrow tile wraps wherever it likes — and the place it picks is the
    // dash inside `1869–1930`, which leaves a person born in 1869 and, on
    // the next line, the year 1930 belonging to nothing.
    final alternate = person.alternateName;
    final lifespan = person.lifespan;

    return Card(
      margin: EdgeInsets.only(bottom: dense ? 6 : 8),
      color: color,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: dense
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 2)
            : null,
        leading: AuthenticatedImage(
          url: person.thumbnailUrl,
          records: records,
          name: person.name,
          sex: person.sex,
          deceased: person.isDeceased,
          size: dense ? 42 : 48,
        ),
        title: label == null
            ? Text(person.name, maxLines: 2, overflow: TextOverflow.ellipsis)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    textDirection: directionOf(label),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Text(
                    person.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
        subtitle: alternate == null && lifespan == null
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (alternate != null)
                    Text(
                      alternate,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // A second name may be Arabic beside an Arabic one or
                      // romanized beside it; only the text can say.
                      textDirection: directionOf(alternate),
                    ),
                  if (lifespan != null)
                    Text(
                      // All digits and a dash: without an isolate the Arabic
                      // layout reverses it and the person dies before they
                      // are born.
                      ltrRun(lifespan),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
        trailing: trailing,
        onTap: onOpen,
      ),
    );
  }
}
