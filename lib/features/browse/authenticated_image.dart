import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/stock/records_repository.dart';

/// A photo fetched through the signed-in session.
///
/// Not `Image.network`: that would use its own HTTP client with no cookies,
/// and webtrees checks the viewer's permission on every media request. An
/// unauthenticated fetch gets a refusal, or somebody else's view of the file.
class AuthenticatedImage extends StatefulWidget {
  const AuthenticatedImage({
    required this.url,
    required this.records,
    required this.size,
    this.name,
    this.fallback,
    super.key,
  });

  final String? url;
  final RecordsRepository records;
  final double size;

  /// The person's name, used to draw an initial when they have no photo.
  ///
  /// Most people in a real tree have no photograph, so the placeholder is what
  /// the reader sees most: a wall of identical silhouettes tells them nothing,
  /// while a first letter makes a list of relatives scannable.
  final String? name;

  /// Shown while loading, when there is no photo, and when one cannot be
  /// fetched. A missing photo is ordinary, not an error worth a message.
  final Widget? fallback;

  @override
  State<AuthenticatedImage> createState() => _AuthenticatedImageState();
}

class _AuthenticatedImageState extends State<AuthenticatedImage> {
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AuthenticatedImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  void _load() {
    final url = widget.url;
    _bytes = url == null ? null : widget.records.image(url);
  }

  @override
  Widget build(BuildContext context) {
    final initial = _initialOf(widget.name);
    final placeholder = SizedBox.square(
      dimension: widget.size,
      child:
          widget.fallback ??
          (initial == null
              ? _SilhouettePlaceholder(size: widget.size)
              : _InitialPlaceholder(
                  initial: initial,
                  seed: widget.name!,
                  size: widget.size,
                )),
    );

    final bytes = _bytes;
    if (bytes == null) return placeholder;

    return FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return placeholder;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            snapshot.data!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => placeholder,
          ),
        );
      },
    );
  }
}

/// The first letter of a name, or null when there is nothing to show.
///
/// Works on characters rather than code units: an Arabic name's first letter
/// is a single grapheme, and so is an emoji or a combining sequence, which
/// `name[0]` would cut in half.
String? _initialOf(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;

  // Skip anything that would draw as nothing — a stray bracket or a directional
  // mark ahead of the name itself.
  for (final character in trimmed.characters) {
    if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(character)) {
      return character.toUpperCase();
    }
  }
  return null;
}

/// A person with no photograph, drawn as their initial.
///
/// The colour is derived from the name, so the same person keeps the same
/// avatar everywhere in the app — and a list of relatives gains a little
/// variety to scan by. Every option comes from the theme's own container
/// pairs, so contrast holds in both light and dark.
class _InitialPlaceholder extends StatelessWidget {
  const _InitialPlaceholder({
    required this.initial,
    required this.seed,
    required this.size,
  });

  final String initial;
  final String seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = [
      (colors.primaryContainer, colors.onPrimaryContainer),
      (colors.secondaryContainer, colors.onSecondaryContainer),
      (colors.tertiaryContainer, colors.onTertiaryContainer),
    ];
    final (background, foreground) =
        palette[seed.hashCode.abs() % palette.length];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          initial,
          // A single letter has no reading direction of its own, and an
          // Arabic initial beside a Latin one must not reorder the row.
          textDirection: TextDirection.ltr,
          style: theme.textTheme.titleLarge?.copyWith(
            color: foreground,
            fontSize: size * 0.42,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _SilhouettePlaceholder extends StatelessWidget {
  const _SilhouettePlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.person_outline,
        size: size * 0.55,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
