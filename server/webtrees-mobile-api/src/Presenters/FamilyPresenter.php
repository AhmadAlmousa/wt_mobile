<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Presenters;

use Fisharebest\Webtrees\Family;
use Fisharebest\Webtrees\Individual;

use function array_map;
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
 */
final class FamilyPresenter
{
    /** The person appears here as a child: its spouses are their parents. */
    public const string PARENTS = 'parents';

    /** The person appears here as a spouse: its children are theirs. */
    public const string OWN = 'own';

    /** The person does not appear in this family at all. */
    public const string STEP = 'step';

    public function __construct(
        private readonly PersonPresenter $people,
        private readonly FactPresenter $facts,
    ) {
    }

    /**
     * @param Individual|null $subject Whose page this family is being shown on.
     *
     * @return array<string,mixed>
     */
    public function present(Family $family, string $kind, Individual|null $subject = null): array
    {
        $facts = [];
        $ended = false;

        foreach ($family->facts([], true) as $fact) {
            $facts[] = $this->facts->present($fact, FactPresenter::FAMILY, $family);

            // DIV, ANUL and DIVF all end a marriage. The tag is the fact; the
            // site's word for it is in the label beside it.
            if (in_array($fact->tag(), ['FAM:DIV', 'FAM:ANUL', 'FAM:DIVF'], true)) {
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
            'facts'          => $facts,
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
