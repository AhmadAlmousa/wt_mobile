import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// How prominent a message is.
enum MessageTone { error, warning, info }

/// A short block of feedback: a failure, a caveat, or a note.
///
/// Colour alone never carries the meaning — each tone also has its own icon,
/// so the message reads the same to someone who cannot distinguish them.
class MessagePanel extends StatelessWidget {
  const MessagePanel({
    required this.message,
    required this.tone,
    this.details = const [],
    super.key,
  });

  const MessagePanel.error(String message, {Key? key})
    : this(message: message, tone: MessageTone.error, key: key);

  const MessagePanel.warning(String message, {Key? key})
    : this(message: message, tone: MessageTone.warning, key: key);

  final String message;
  final MessageTone tone;

  /// Supporting lines, shown smaller beneath the message.
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final semantic = SemanticColors.of(context);

    final (Color background, Color foreground, IconData icon) = switch (tone) {
      MessageTone.error => (
        colors.errorContainer,
        colors.onErrorContainer,
        Icons.error_outline,
      ),
      MessageTone.warning => (
        semantic.warningContainer,
        semantic.onWarningContainer,
        Icons.warning_amber_outlined,
      ),
      MessageTone.info => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
        Icons.info_outline,
      ),
    };

    return Semantics(
      liveRegion: tone == MessageTone.error,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppTheme.shapeLarge),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                  for (final detail in details) ...[
                    const SizedBox(height: 6),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: foreground.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
