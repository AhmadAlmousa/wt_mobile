import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/transport.dart';
import '../../domain/records.dart';

/// A photo fetched through the signed-in session.
///
/// Not `Image.network`: that would use its own HTTP client with no cookies,
/// and webtrees checks the viewer's permission on every media request. An
/// unauthenticated fetch gets a refusal, or somebody else's view of the file.
///
/// Also the one place in the app a person's face — or the placeholder that
/// stands in for it — is drawn, which is why the two things a reader wants to
/// know at a glance live here: whether this is a man or a woman, and whether
/// they are still living.
class AuthenticatedImage extends StatefulWidget {
  const AuthenticatedImage({
    required this.url,
    required this.records,
    required this.size,
    this.name,
    this.sex = Sex.unknown,
    this.deceased = false,
    this.fallback,
    super.key,
  });

  final String? url;
  final RecordsTransport records;
  final double size;

  /// The person's name, used to draw an initial when they have no photo.
  ///
  /// Most people in a real tree have no photograph, so the placeholder is what
  /// the reader sees most: a wall of identical silhouettes tells them nothing,
  /// while a first letter makes a list of relatives scannable.
  final String? name;

  /// Colours the placeholder, so a list of relatives can be read by shape as
  /// well as by name. Has no effect where a photograph is shown: a face says
  /// it better than a colour does.
  final Sex sex;

  /// Draws the mourning ribbon across the corner.
  final bool deceased;

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
              ? _SilhouettePlaceholder(size: widget.size, sex: widget.sex)
              : _InitialPlaceholder(
                  initial: initial,
                  sex: widget.sex,
                  size: widget.size,
                )),
    );

    final bytes = _bytes;
    final portrait = bytes == null
        ? placeholder
        : FutureBuilder<Uint8List>(
            future: bytes,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return placeholder;
              return ClipRRect(
                borderRadius: BorderRadius.circular(_radius),
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

    if (!widget.deceased) return portrait;

    return _Mourned(size: widget.size, child: portrait);
  }
}

/// The corner radius every avatar in the app is cut to.
const double _radius = 8;

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
/// The colour is the one their record earns: blue for a man, pink for a
/// woman, grey where the tree does not say. It used to be picked by hashing
/// the name, which gave a list of relatives variety to scan by but told the
/// reader nothing — and the tree had been stating the answer all along, in a
/// class on every chart box.
class _InitialPlaceholder extends StatelessWidget {
  const _InitialPlaceholder({
    required this.initial,
    required this.sex,
    required this.size,
  });

  final String initial;
  final Sex sex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = PersonColors.of(context).forSex(sex);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(_radius),
        // A pale container against a pale page has almost no edge of its own,
        // so the shape is given one — otherwise a row of avatars dissolves.
        border: Border.all(color: foreground.withValues(alpha: 0.14)),
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
  const _SilhouettePlaceholder({required this.size, this.sex = Sex.unknown});

  final double size;
  final Sex sex;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = PersonColors.of(context).forSex(sex);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: foreground.withValues(alpha: 0.14)),
      ),
      child: Icon(
        Icons.person_outline,
        size: size * 0.55,
        color: foreground.withValues(alpha: 0.7),
      ),
    );
  }
}

/// A portrait with a mourning ribbon across its leading top corner.
///
/// The convention a family album uses, and one that survives being small:
/// colour alone would be lost at the 40 pixels a chart box gives a face, and
/// a badge would cover it. The ribbon crosses a corner instead — and crosses
/// the *other* corner in Arabic, where the eye starts on the right.
class _Mourned extends StatelessWidget {
  const _Mourned({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: CustomPaint(
              painter: _RibbonPainter(
                fromTheStart: Directionality.of(context) == TextDirection.ltr,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _RibbonPainter extends CustomPainter {
  const _RibbonPainter({required this.fromTheStart});

  /// Whether the ribbon crosses the top-left corner, as it does in a
  /// left-to-right layout.
  final bool fromTheStart;

  /// How far along each edge the band reaches, as a share of the avatar.
  static const double _reach = 0.40;

  /// How wide the band itself is, as a share of the avatar.
  static const double _width = 0.115;

  @override
  void paint(Canvas canvas, Size size) {
    final reach = size.shortestSide * _reach;
    final width = size.shortestSide * _width;

    // Two points on the edges either side of the corner, and the band drawn
    // between them: the corner it cuts off is the corner the eye lands on.
    final along = fromTheStart
        ? [Offset(0, reach), Offset(reach, 0)]
        : [Offset(size.width - reach, 0), Offset(size.width, reach)];

    final direction = fromTheStart ? 1.0 : -1.0;
    final band = Path()
      ..moveTo(along.first.dx, along.first.dy)
      ..lineTo(along.last.dx, along.last.dy)
      ..lineTo(along.last.dx + direction * width, along.last.dy + width)
      ..lineTo(along.first.dx + direction * width, along.first.dy + width)
      ..close();

    canvas.drawPath(band, Paint()..color = const Color(0xFF16161A));
    // A hairline of light along the outer edge, so the band still reads as a
    // ribbon against a dark photograph rather than as a missing corner.
    canvas.drawPath(
      band,
      Paint()
        ..color = const Color(0x33FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75,
    );
  }

  @override
  bool shouldRepaint(_RibbonPainter old) =>
      old.fromTheStart != fromTheStart;
}
