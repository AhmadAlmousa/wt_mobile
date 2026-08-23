import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/records.dart';
import 'package:webtrees_mobile/features/charts/relationship_modes.dart';

PersonRef person(String xref, [Sex sex = Sex.unknown]) =>
    PersonRef(xref: xref, name: xref, sex: sex);

/// The subject, with a father, a mother and a wife.
IndividualRecord subject() => IndividualRecord(
  xref: 'ME',
  name: 'ME',
  sex: Sex.male,
  facts: const [],
  families: [
    FamilyGroup(
      xref: 'F1',
      label: 'parents',
      kind: FamilyKind.parents,
      spouses: [person('DAD', Sex.male), person('MUM', Sex.female)],
      children: [person('ME', Sex.male)],
    ),
    FamilyGroup(
      xref: 'F2',
      label: 'own',
      kind: FamilyKind.own,
      spouses: [person('ME', Sex.male), person('WIFE', Sex.female)],
      children: const [],
    ),
  ],
);

/// A path leaving the subject through [first] and going on for [more] steps.
///
/// The relationship words are the site's own and are deliberately nonsense
/// here: nothing in the code under test may read them.
RelationshipPath through(String first, {int more = 0}) => RelationshipPath(
  description: 'somehow related',
  from: person('ME', Sex.male),
  steps: [
    RelationshipStep(relationship: '؟', person: person(first)),
    for (var at = 0; at < more; at++)
      RelationshipStep(relationship: '؟', person: person('X$at')),
  ],
);

void main() {
  group('the ways of asking', () {
    late RelationshipRoutes routes;

    setUp(() {
      routes = RelationshipRoutes(
        paths: [
          through('DAD', more: 3),
          through('MUM', more: 1),
          through('WIFE', more: 2),
        ],
        subject: subject(),
      );
    });

    test('sorts a side by which relative the path leaves through', () {
      // Structural: the first step's *person*, matched against the parents
      // and spouses the record names. Nothing reads the kinship word, which
      // is translated and would work in one language only.
      expect(
        routes
            .matching(RelationshipSide.fatherSide)
            .single
            .steps
            .first
            .person
            .xref,
        'DAD',
      );
      expect(
        routes
            .matching(RelationshipSide.motherSide)
            .single
            .steps
            .first
            .person
            .xref,
        'MUM',
      );
      expect(
        routes
            .matching(RelationshipSide.throughSpouse)
            .single
            .steps
            .first
            .person
            .xref,
        'WIFE',
      );
    });

    test('the closest is the shortest, and only the shortest', () {
      final closest = routes.matching(RelationshipSide.closest);
      expect(closest, hasLength(1));
      // Two steps through the mother beats four through the father.
      expect(closest.single.steps.first.person.xref, 'MUM');
    });

    test('offers every side it has a path for', () {
      for (final side in RelationshipSide.values) {
        expect(routes.offers(side), isTrue, reason: side.name);
      }
    });

    test('orders every path shortest first', () {
      expect(routes.all.map((path) => path.steps.length), [2, 3, 4]);
    });
  });

  test('a side with no path is not offered', () {
    // Shown disabled rather than hidden by the screen: "there is no link on
    // your mother's side" is an answer, and a missing button is not.
    final routes = RelationshipRoutes(
      paths: [through('DAD')],
      subject: subject(),
    );

    expect(routes.offers(RelationshipSide.fatherSide), isTrue);
    expect(routes.offers(RelationshipSide.motherSide), isFalse);
    expect(routes.offers(RelationshipSide.throughSpouse), isFalse);
    expect(routes.matching(RelationshipSide.motherSide), isEmpty);
  });

  test('a path leaving downwards belongs to no side', () {
    // Somebody's own child is neither a parent nor a spouse, so the path is
    // an answer to "how are we related" and to nothing more specific.
    final routes = RelationshipRoutes(
      paths: [through('SON')],
      subject: subject(),
    );

    expect(routes.offers(RelationshipSide.closest), isTrue);
    expect(routes.offers(RelationshipSide.fatherSide), isFalse);
    expect(routes.offers(RelationshipSide.motherSide), isFalse);
  });

  test('a subject whose parents are unrecorded still answers the closest', () {
    final orphan = IndividualRecord(
      xref: 'ME',
      name: 'ME',
      facts: const [],
      families: const [],
    );
    final routes = RelationshipRoutes(
      paths: [through('SOMEBODY')],
      subject: orphan,
    );

    expect(routes.offers(RelationshipSide.closest), isTrue);
    expect(routes.offers(RelationshipSide.fatherSide), isFalse);
  });

  test('no paths at all is empty rather than an error', () {
    final routes = RelationshipRoutes(paths: const [], subject: subject());

    expect(routes.isEmpty, isTrue);
    for (final side in RelationshipSide.values) {
      expect(routes.matching(side), isEmpty);
    }
  });
}
