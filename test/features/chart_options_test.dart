import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/records.dart';
import 'package:webtrees_mobile/features/charts/chart_options.dart';

PersonRef person(String xref, Sex sex) =>
    PersonRef(xref: xref, name: xref, sex: sex);

void main() {
  group('who a chart shows', () {
    test('everyone is the answer for a sex the tree never recorded', () {
      // Hiding somebody because their record is silent would answer a
      // question nobody asked of it.
      for (final show in ShowPeople.values) {
        expect(show.includes(Sex.unknown), isTrue);
      }
    });

    test('names the two lines correctly', () {
      expect(ShowPeople.menOnly.includes(Sex.male), isTrue);
      expect(ShowPeople.menOnly.includes(Sex.female), isFalse);
      expect(ShowPeople.womenOnly.includes(Sex.female), isTrue);
      expect(ShowPeople.womenOnly.includes(Sex.male), isFalse);
    });
  });

  group('a pedigree of one line', () {
    /// Subject, both parents, and both of the father's parents.
    AncestorNode tree() => AncestorNode(
      person: person('X1', Sex.male),
      sosa: 1,
      parents: [
        AncestorNode(
          person: person('FATHER', Sex.male),
          sosa: 2,
          parents: [
            AncestorNode(person: person('GRANDPA', Sex.male), sosa: 4),
            AncestorNode(person: person('GRANDMA', Sex.female), sosa: 5),
          ],
        ),
        AncestorNode(person: person('MOTHER', Sex.female), sosa: 3),
      ],
    );

    Iterable<String> namesIn(AncestorNode node) =>
        node.everyone.map((one) => one.person.xref);

    test('leaves the chart alone when everyone is shown', () {
      expect(
        namesIn(ancestorsShowing(tree(), ShowPeople.everyone)),
        namesIn(tree()),
      );
    });

    test('cuts the branch, not just the box', () {
      // Everyone above a mother is reached *through* her, so keeping her
      // parents and dropping her would leave a branch attached to nothing.
      final male = ancestorsShowing(tree(), ShowPeople.menOnly);
      expect(namesIn(male), ['X1', 'FATHER', 'GRANDPA']);

      final female = ancestorsShowing(tree(), ShowPeople.womenOnly);
      expect(namesIn(female), ['X1', 'MOTHER']);
    });

    test('keeps the subject whatever their sex', () {
      // A chart of nobody answers nothing.
      final chart = AncestorNode(
        person: person('HER', Sex.female),
        sosa: 1,
        parents: [AncestorNode(person: person('DAD', Sex.male), sosa: 2)],
      );
      expect(namesIn(ancestorsShowing(chart, ShowPeople.menOnly)), [
        'HER',
        'DAD',
      ]);
    });
  });

  group('descent through one line', () {
    DescendantNode tree() => DescendantNode(
      person: person('X1', Sex.male),
      number: '1',
      families: [
        DescendantFamily(
          xref: 'F1',
          spouse: person('WIFE', Sex.female),
          children: [
            DescendantNode(
              person: person('SON', Sex.male),
              number: '1.1',
              families: [
                DescendantFamily(
                  xref: 'F2',
                  children: [
                    DescendantNode(
                      person: person('GRANDSON', Sex.male),
                      number: '1.1.1',
                    ),
                  ],
                ),
              ],
            ),
            DescendantNode(
              person: person('DAUGHTER', Sex.female),
              number: '1.2',
            ),
          ],
        ),
      ],
    );

    test('follows the sons and drops what hangs off a daughter', () {
      final male = descendantsShowing(tree(), ShowPeople.menOnly);
      expect(male.everyone.map((one) => one.person.xref), [
        'X1',
        'SON',
        'GRANDSON',
      ]);
      // The wife loses her box but the family keeps its children: a line
      // still has to come down from somewhere.
      expect(male.families.single.spouse, isNull);
      expect(male.families.single.children, hasLength(1));
    });

    test('keeps a divorce it was told about', () {
      final divorced = DescendantNode(
        person: person('X1', Sex.male),
        number: '1',
        families: [
          DescendantFamily(
            xref: 'F1',
            spouse: person('WIFE', Sex.female),
            endedInDivorce: true,
          ),
        ],
      );
      final male = descendantsShowing(divorced, ShowPeople.menOnly);
      expect(male.families.single.endedInDivorce, isTrue);
    });
  });
}
