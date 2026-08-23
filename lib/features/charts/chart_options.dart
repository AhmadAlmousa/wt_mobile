import 'package:meta/meta.dart';

import '../../domain/charts.dart';
import '../../domain/records.dart';

/// Which people a chart draws.
///
/// Hiding half a family is not the same as deleting half the boxes: everyone
/// above a mother is reached *through* her, so dropping her and keeping her
/// parents would leave a branch attached to nothing. Hiding therefore cuts
/// the branch — which is not a compromise but the thing a reader means. On a
/// pedigree it gives the paternal or the maternal line; on a descendants
/// chart it gives descent through the sons or through the daughters, the view
/// an Arab family tree is usually drawn in.
enum ShowPeople {
  everyone,
  menOnly,
  womenOnly;

  /// Whether [sex] is one of the people this setting shows.
  ///
  /// Someone whose sex the tree never recorded is always shown: hiding them
  /// would answer a question the record did not ask.
  bool includes(Sex sex) => switch (this) {
    ShowPeople.everyone => true,
    ShowPeople.menOnly => sex != Sex.female,
    ShowPeople.womenOnly => sex != Sex.male,
  };
}

/// The shapes one chart can take.
///
/// Not different charts: webtrees offers an ancestors chart, a fan chart and
/// a compact chart, and all three describe the same people. Fetching the
/// shape once and drawing it three ways is both less work for the site and
/// less waiting for the reader.
enum ChartShape {
  /// Boxes and joining lines, generations marching sideways.
  tree,

  /// The same pedigree bent round a circle. There is no such thing as a fan
  /// of descendants, so this is offered only where it means something.
  circle,

  /// Smaller boxes, more of the family on one screen.
  compact,
}

/// How a reader has asked for their charts to be drawn.
///
/// One object rather than a handful of flags on the screen, because the same
/// answers apply to every chart and are worth keeping between them: somebody
/// who turned the photographs off did not mean "on this pedigree only".
@immutable
final class ChartOptions {
  const ChartOptions({
    this.generations,
    this.shape = ChartShape.tree,
    this.showPhotos = true,
    this.showDates = true,
    this.colourBySex = true,
    this.fitToName = false,
    this.show = ShowPeople.everyone,
  });

  /// How many generations to ask the site for, or null to take the number its
  /// administrator settled on.
  ///
  /// webtrees puts this in the chart's own address, so changing it is a new
  /// request rather than a redraw — which is why it is the one option that
  /// costs anything.
  final int? generations;

  /// Which of the three shapes an ancestors chart takes. Ignored by the
  /// charts that only have one.
  final ChartShape shape;

  /// Photographs on the boxes. Off draws more of the family in the same
  /// space, which on a phone is often the better trade.
  final bool showPhotos;

  /// The years under each name.
  final bool showDates;

  /// Fill each box by the sex the record states, as the rest of the app does.
  final bool colourBySex;

  /// Widen a box to hold its name rather than cutting the name to the box.
  ///
  /// Off by default: a chart of even columns is easier to read down, and this
  /// family's names vary enough in length that fitting every one of them
  /// makes a ragged chart.
  final bool fitToName;

  final ShowPeople show;

  /// What a site will accept. webtrees validates the generations segment with
  /// `isBetween(2, 63)`; ten is as many as a phone can show without the
  /// boxes becoming decoration.
  static const int fewestGenerations = 2;
  static const int mostGenerations = 10;

  ChartOptions copyWith({
    int? generations,
    ChartShape? shape,
    bool? showPhotos,
    bool? showDates,
    bool? colourBySex,
    bool? fitToName,
    ShowPeople? show,
  }) => ChartOptions(
    generations: generations ?? this.generations,
    shape: shape ?? this.shape,
    showPhotos: showPhotos ?? this.showPhotos,
    showDates: showDates ?? this.showDates,
    colourBySex: colourBySex ?? this.colourBySex,
    fitToName: fitToName ?? this.fitToName,
    show: show ?? this.show,
  );

  /// The same options with the depth set — the one field [copyWith] cannot
  /// change, because null there means "as the site sets it" rather than
  /// "leave it alone".
  ChartOptions withGenerations(int? many) => ChartOptions(
    generations: many,
    shape: shape,
    showPhotos: showPhotos,
    showDates: showDates,
    colourBySex: colourBySex,
    fitToName: fitToName,
    show: show,
  );

  @override
  bool operator ==(Object other) =>
      other is ChartOptions &&
      other.generations == generations &&
      other.shape == shape &&
      other.showPhotos == showPhotos &&
      other.showDates == showDates &&
      other.colourBySex == colourBySex &&
      other.fitToName == fitToName &&
      other.show == show;

  @override
  int get hashCode => Object.hash(
    generations,
    shape,
    showPhotos,
    showDates,
    colourBySex,
    fitToName,
    show,
  );
}

/// [root] with every branch that runs through a hidden person cut away.
///
/// The subject is kept whatever their sex: they are who the chart is about,
/// and a chart of nobody answers nothing.
AncestorNode ancestorsShowing(AncestorNode root, ShowPeople show) {
  if (show == ShowPeople.everyone) return root;

  AncestorNode keep(AncestorNode node) => AncestorNode(
    person: node.person,
    sosa: node.sosa,
    familyXref: node.familyXref,
    parentsLabel: node.parentsLabel,
    parents: [
      for (final parent in node.parents)
        if (show.includes(parent.person.sex)) keep(parent),
    ],
  );

  return keep(root);
}

/// [root] with descent through a hidden person cut away.
///
/// A spouse who is hidden loses their box but not their family: the children
/// are still the subject's, and a line has to come down from somewhere.
DescendantNode descendantsShowing(DescendantNode root, ShowPeople show) {
  if (show == ShowPeople.everyone) return root;

  DescendantNode keep(DescendantNode node) => DescendantNode(
    person: node.person,
    number: node.number,
    families: [
      for (final family in node.families)
        DescendantFamily(
          xref: family.xref,
          spouse: family.spouse != null && show.includes(family.spouse!.sex)
              ? family.spouse
              : null,
          label: family.label,
          endedInDivorce: family.endedInDivorce,
          children: [
            for (final child in family.children)
              if (show.includes(child.person.sex)) keep(child),
          ],
        ),
    ],
  );

  return keep(root);
}
