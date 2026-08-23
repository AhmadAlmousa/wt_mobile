<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Presenters;

use Fisharebest\Webtrees\Fact;
use Fisharebest\Webtrees\Family;
use Fisharebest\Webtrees\Gedcom;
use Fisharebest\Webtrees\Individual;

use function array_map;
use function array_merge;
use function in_array;

/**
 * A couple and their children.
 *
 * Two things here are guesswork on a stock instance and stated facts through
 * the module. **Which kind of family this is** — the one a person was born
 * into, the one they made, or a step-family — is derived by the HTML parser
 * from where the block sits on the relatives tab and whether a marriage row
 * came before or after; here it is answered by asking webtrees which
 * collection the family came from. And **whether the couple separated** is
 * read from a `DIV` fact rather than matched against the site's word for a
 * divorce, which is what a chart needs in order to draw the line differently.
 *
 * **A family is presented two ways, because webtrees shows it two ways.** On
 * a member's page it is a couple, their children and what happened to the
 * marriage; in its own right it is a record with a history. The difference is
 * which facts come back, and getting it wrong is not cosmetic: `HUSB`, `WIFE`
 * and `CHIL` are facts like any other, so a family of four answers a marriage
 * *and* four pointers that a client has no way to tell apart from events.
 */
final class FamilyPresenter
{
    /** The person appears here as a child: its spouses are their parents. */
    public const string PARENTS = 'parents';

    /** The person appears here as a spouse: its children are theirs. */
    public const string OWN = 'own';

    /** The person does not appear in this family at all. */
    public const string STEP = 'step';

    /**
     * The pointers that make a family a family.
     *
     * They are already answered as `spouses` and `children`, and webtrees'
     * own family page filters exactly these three out for the same reason
     * (`FamilyPage`, identical in 2.2.6 and 2.3).
     */
    private const array POINTERS = ['FAM:HUSB', 'FAM:WIFE', 'FAM:CHIL'];

    /** DIV, ANUL and DIVF all end a marriage. */
    private const array ENDINGS = ['FAM:DIV', 'FAM:ANUL', 'FAM:DIVF'];

    public function __construct(
        private readonly PersonPresenter $people,
        private readonly FactPresenter $facts,
    ) {
    }

    /**
     * A family as it appears on the page of one of its members.
     *
     * Only what happened to the couple, which is what `family.phtml` prints
     * between the spouses and the children — a marriage, a divorce, and
     * nothing else. The rest of the family's record belongs to the family's
     * own screen, and repeating a pointer to each child as a fact would put
     * the word "son" on a person's page once per son.
     *
     * @param Individual $subject Whose page this family is being shown on.
     *
     * @return array<string,mixed>
     */
    public function summary(Family $family, string $kind, Individual $subject): array
    {
        $events = array_merge(Gedcom::MARRIAGE_EVENTS, Gedcom::DIVORCE_EVENTS);

        return $this->present($family, $kind, $subject, $family->facts($events, true)->all());
    }

    /**
     * A family in its own right, with everything its record says.
     *
     * @return array<string,mixed>
     */
    public function record(Family $family): array
    {
        $facts = $family->facts([], true)
            ->reject(static fn (Fact $fact): bool => in_array($fact->tag(), self::POINTERS, true))
            ->all();

        return $this->present($family, self::OWN, null, $facts);
    }

    /**
     * @param array<Fact> $facts
     *
     * @return array<string,mixed>
     */
    private function present(
        Family $family,
        string $kind,
        Individual|null $subject,
        array $facts,
    ): array {
        $rows  = [];
        $ended = false;

        foreach ($facts as $fact) {
            $rows[] = $this->facts->present($fact, FactPresenter::FAMILY, $family);

            // The tag is the fact; the site's word for it is in the label
            // beside it.
            if (in_array($fact->tag(), self::ENDINGS, true)) {
                $ended = true;
            }
        }

        return [
            'xref'           => $family->xref(),
            // The site's own heading for this family, already translated and
            // already knowing whether these are the parents, the step-parents
            // or a spouse - which is not something a client should compose.
            'label'          => $this->label($family, $kind, $subject),
            'kind'           => $kind,
            'spouses'        => $this->people($family->spouses()->all()),
            'children'       => $this->people($family->children()->all()),
            'facts'          => $rows,
            'endedInDivorce' => $ended,
            'pending'        => FactPresenter::pending($family),
        ];
    }

    /**
     * @param array<Individual> $individuals
     *
     * @return array<array<string,mixed>>
     */
    private function people(array $individuals): array
    {
        return array_map($this->people->present(...), $individuals);
    }

    private function label(Family $family, string $kind, Individual|null $subject): string|null
    {
        if (!$subject instanceof Individual) {
            return Text::orNull($family->fullName());
        }

        $label = match ($kind) {
            self::PARENTS => $subject->getChildFamilyLabel($family),
            self::STEP    => $subject->getStepFamilyLabel($family),
            default       => $subject->getSpouseFamilyLabel($family),
        };

        return Text::orNull($label);
    }
}
