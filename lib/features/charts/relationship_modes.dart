/// The ways of asking how two people are related.
///
/// webtrees itself offers exactly one choice — "find any relationship" or
/// "find relationships via ancestors" — and it is a tree preference rather
/// than a question the reader is asked. It has no idea what "on my mother's
/// side" means.
///
/// But it answers with *every* path it found, and a path says which of the
/// subject's own relatives it leaves through: its first step. That, matched
/// against the parents and spouses the subject's record already names, is
/// enough to sort the answers into the ways a person would actually ask the
/// question — and it is structural, so it works the same in both languages.
library;

import 'package:meta/meta.dart';

import '../../domain/charts.dart';
import '../../domain/records.dart';

/// How a relationship is put on screen.
///
/// Two modes rather than one, because the question has two halves and no
/// single drawing answers both. The path down the page says *what the link
/// is*: a spine of names with the site's own word on every rung, read top to
/// bottom like a sentence. The tree says *where these people sit in the
/// family*: two branches leaving one grandfather and meeting again three
/// generations later, which a list has no up or down to show.
///
/// Each gets the whole body when it is chosen. A chart squeezed under a
/// column of controls is a picture of a family rather than one anybody can
/// read, and a path is easier to follow at full width too.
enum RelationshipView {
  /// The steps, one under the next.
  path,

  /// The same steps, placed by generation and joined.
  tree,
}

/// A way through the family, as a reader would name it.
enum RelationshipSide {
  /// The shortest link there is, whichever way it runs.
  closest,

  /// Leaving through the subject's father.
  fatherSide,

  /// Leaving through the subject's mother.
  motherSide,

  /// Leaving through somebody the subject married.
  throughSpouse,
}

/// The paths webtrees found, sorted into the ways of asking for them.
@immutable
final class RelationshipRoutes {
  RelationshipRoutes({
    required List<RelationshipPath> paths,
    required IndividualRecord subject,
  }) : _paths = List.unmodifiable(paths),
       _father = _parentOf(subject, Sex.male),
       _mother = _parentOf(subject, Sex.female),
       _spouses = {for (final spouse in subject.spouses) spouse.xref};

  final List<RelationshipPath> _paths;
  final String? _father;
  final String? _mother;
  final Set<String> _spouses;

  bool get isEmpty => _paths.isEmpty;

  /// Every path, shortest first — the order a reader would want them in.
  List<RelationshipPath> get all =>
      [..._paths]..sort((a, b) => a.steps.length.compareTo(b.steps.length));

  /// The paths that answer [side], shortest first.
  ///
  /// [RelationshipSide.closest] answers with the single shortest path: it is
  /// a question about *the* relationship, not about all of them.
  List<RelationshipPath> matching(RelationshipSide side) {
    final ordered = all;
    if (side == RelationshipSide.closest) {
      return ordered.isEmpty ? const [] : [ordered.first];
    }
    return [
      for (final path in ordered)
        if (_leaves(path, side)) path,
    ];
  }

  /// Whether this comparison has anything to say about [side].
  ///
  /// A side with no path is shown as unavailable rather than hidden: "there
  /// is no link on your mother's side" is an answer, and a missing button is
  /// not.
  bool offers(RelationshipSide side) => matching(side).isNotEmpty;

  /// Whether [path] leaves the subject through the relative [side] names.
  ///
  /// Only the first step is read. Once a path has gone up through the father
  /// it is on the father's side however far it travels afterwards, and a path
  /// that leaves downwards — to a child — is on nobody's side, which is why
  /// it appears under [RelationshipSide.closest] alone.
  bool _leaves(RelationshipPath path, RelationshipSide side) {
    if (path.steps.isEmpty) return false;
    final first = path.steps.first.person.xref;

    return switch (side) {
      RelationshipSide.closest => true,
      RelationshipSide.fatherSide => first == _father,
      RelationshipSide.motherSide => first == _mother,
      RelationshipSide.throughSpouse => _spouses.contains(first),
    };
  }

  /// The subject's parent of [sex], if the record names one.
  ///
  /// Taken from the record rather than from a path, because a path only ever
  /// says who it went to next — not whether that person is a father.
  static String? _parentOf(IndividualRecord subject, Sex sex) {
    for (final parent in subject.parents) {
      if (parent.sex == sex) return parent.xref;
    }
    return null;
  }
}
