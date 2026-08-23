<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Fisharebest\Webtrees\Family;
use Fisharebest\Webtrees\I18N;
use Fisharebest\Webtrees\Individual;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Compat\Compat;
use WebtreesMobileApi\Compat\CompatInterface;
use WebtreesMobileApi\Http\Json;
use WebtreesMobileApi\Presenters\PersonPresenter;
use WebtreesMobileApi\Presenters\Text;
use WebtreesMobileApi\Support\Request;

use function in_array;
use function implode;

/**
 * Who descends from a person, family by family.
 *
 * The numbering is the subtle part and it has already caught a client out
 * once. A d'Aboville number runs across **all** of a person's families:
 * `descendancy-chart/tree.phtml` declares `$child_number` before its family
 * loop and never resets it, so a second marriage continues the count rather
 * than starting again. Numbering per family gives two different children the
 * same `1.1`.
 *
 * The order matters for the same reason — families earliest marriage first,
 * children eldest first — so both use webtrees' own comparators through the
 * compat layer rather than a sort invented here.
 */
final class Descendants implements RequestHandlerInterface
{
    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $individual  = Request::individual($request);
        $generations = Request::generations($request, 3);
        $people      = new PersonPresenter(Request::thumbnail($request));

        return Json::ok([
            'subject'     => $people->present($individual),
            'generations' => $generations,
            'tree'        => $this->node($individual, '1', $generations, $people, Compat::current(), []),
        ]);
    }

    /**
     * @param array<string> $seen Xrefs already on this branch.
     *
     * @return array<string,mixed>
     */
    private function node(
        Individual $individual,
        string $number,
        int $generations,
        PersonPresenter $people,
        CompatInterface $compat,
        array $seen,
    ): array {
        $families = [];

        // Cousins marry, and in the family this was built for that is
        // ordinary - so a descendant chart can reach the same person twice.
        // Stopping only on the current branch keeps both placements while
        // making an endless loop impossible.
        $seen[] = $individual->xref();

        if ($generations > 1) {
            // One counter for every family, never reset. This is the bug that
            // gave two children the same number when it was per family.
            $child_number = 0;

            foreach ($compat->sortFamiliesByMarriage($individual->spouseFamilies()) as $family) {
                $children = [];

                foreach ($compat->sortChildrenByBirth($family->children()) as $child) {
                    $child_number++;

                    if (in_array($child->xref(), $seen, true)) {
                        continue;
                    }

                    $children[] = $this->node(
                        $child,
                        $number . '.' . $child_number,
                        $generations - 1,
                        $people,
                        $compat,
                        $seen,
                    );
                }

                $families[] = $this->family($family, $individual, $children, $people);
            }
        }

        return [
            'person'   => $people->present($individual),
            // Built by joining integers rather than by formatting a number, so
            // it arrives in plain digits whatever language the site renders
            // in - unlike a Sosa number, which webtrees localizes.
            'number'   => $number,
            'families' => $families,
        ];
    }

    /**
     * @param array<array<string,mixed>> $children
     *
     * @return array<string,mixed>
     */
    private function family(
        Family $family,
        Individual $individual,
        array $children,
        PersonPresenter $people,
    ): array {
        $spouse = $family->spouse($individual);
        $ended  = false;
        $parts  = [];

        // webtrees' own caption for the family: "Marriage 1925 — 2 children".
        // Composed from the same three facts it uses, so the words and the
        // numerals stay the site's.
        foreach ($family->facts(['MARR', 'DIV', '_NMR'], true) as $fact) {
            $part = Text::of($fact->label());

            if ($fact->date()->isOK()) {
                $part .= ' ' . Text::of($fact->date()->display());
            }

            $parts[] = $part;

            if ($fact->tag() === 'FAM:DIV') {
                $ended = true;
            }
        }

        $count   = $family->children()->count();
        $parts[] = I18N::plural('%s child', '%s children', $count, I18N::number($count));

        return [
            'xref'           => $family->xref(),
            'spouse'         => $spouse instanceof Individual ? $people->present($spouse) : null,
            'label'          => implode(' — ', $parts),
            'endedInDivorce' => $ended,
            'children'       => $children,
        ];
    }
}
