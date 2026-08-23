import 'package:flutter/material.dart';

import '../../data/transport.dart';
import '../../domain/records.dart';
import '../browse/authenticated_image.dart';
import 'bidi.dart';

/// The title of a screen that draws something *about* one person.
///
/// A chart fills the screen with other people's names, so the bar has to say
/// whose chart it is — otherwise a reader two taps deep into a pedigree has
/// nothing on screen telling them where they started. The portrait carries
/// that faster than the name does, and it is the same portrait, in the same
/// colours, with the same ribbon, as everywhere else in the app.
class ChartHeaderTitle extends StatelessWidget {
  const ChartHeaderTitle({
    required this.title,
    required this.person,
    required this.records,
    super.key,
  });

  /// What this screen is — the chart's name, in the reader's language.
  final String title;

  /// Whose it is. Null while the record is still being fetched, when the
  /// chart's own name is all there is to show.
  final PersonRef? person;

  final RecordsTransport records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subject = person;

    if (subject == null) return Text(title);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AuthenticatedImage(
          url: subject.thumbnailUrl,
          records: records,
          name: subject.name,
          sex: subject.sex,
          deceased: subject.isDeceased,
          size: 34,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              Text(
                subject.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // A name is written in the family's language, not the
                // reader's, so it takes its direction from itself.
                textDirection: directionOf(subject.name),
                style: theme.textTheme.labelSmall?.copyWith(
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
