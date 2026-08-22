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
    this.fallback,
    super.key,
  });

  final String? url;
  final RecordsRepository records;
  final double size;

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
    final placeholder = SizedBox.square(
      dimension: widget.size,
      child: widget.fallback ?? _SilhouettePlaceholder(size: widget.size),
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
