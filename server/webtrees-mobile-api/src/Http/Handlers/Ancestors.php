<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Fisharebest\Webtrees\Family;
use Fisharebest\Webtrees\Individual;
use Fisharebest\Webtrees\Services\ChartService;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Http\Json;
use WebtreesMobileApi\Presenters\PersonPresenter;
use WebtreesMobileApi\Presenters\Text;
use WebtreesMobileApi\Support\Request;

use function array_filter;
use function array_values;

/**
 * Who a person descends from, as a tree of people rather than a page of boxes.
 *
 * webtrees draws this in HTML for a wide, mouse-driven screen — floats,
 * background images and a reading direction baked into a stylesheet — so a
 * client redraws the *shape* for a phone. The shape is what this returns.
 *
 * Two things a rendered chart gets wrong as a data source. Its
 * Sosa-Stradonitz numbers are printed with `I18N::number`, so in Arabic they
 * arrive as `٤` and a client has to derive them from the nesting instead; and
 * the caption above each set of parents is prose. Here the number is a number
 * and the caption is still the site's own words.
 *
 * The set of ancestors comes from `ChartService::sosaStradonitzAncestors()`,
 * so the module walks the same first-child-family rule the website walks and
 * cannot quietly disagree with it.
 */
final class Ancestors implements RequestHandlerInterface
{
    public function __construct(private readonly ChartService $chart_service)
    {
    }

    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $individual  = Request::individual($request);
        $generations = Request::generations($request);
        $people      = new PersonPresenter(Request::thumbnail($request));

        $ancestors = $this->chart_service
            ->sosaStradonitzAncestors($individual, $generations)
            ->all();

        return Json::ok([
            'subject'     => $people->present($individual),
            'generations' => $generations,
            'tree'        => $this->node($ancestors, 1, $people),
        ]);
    }

    /**
     * One person and the parents above them.
     *
     * The Sosa-Stradonitz rule is the whole structure: the subject is 1, and
     * the parents of *n* are 2n (the father) and 2n+1 (the mother). A person
     * who appears twice — cousins marry, and in the family this was built for
     * that is ordinary — holds two numbers, which is exactly what a pedigree
     * should say.
     *
     * @param array<int,Individual> $ancestors
     *
     * @return array<string,mixed>|null
     */
    private function node(array $ancestors, int $sosa, PersonPresenter $people): array|null
    {
        $individual = $ancestors[$sosa] ?? null;

        if (!$individual instanceof Individual) {
            return null;
        }

        $family = $individual->childFamilies()->first();
        $father = $this->node($ancestors, $sosa * 2, $people);
        $mother = $this->node($ancestors, $sosa * 2 + 1, $people);

        return [
            'person'       => $people->present($individual),
            'sosa'         => $sosa,
            'familyXref'   => $family instanceof Family ? $family->xref() : null,
            // "Parents — Marriage 1898 — 3 children", already translated. A
            // client shows it as it arrived rather than rebuilding it from
            // parts it would have to punctuate itself.
            'parentsLabel' => $family instanceof Family
                ? Text::orNull($individual->getChildFamilyLabel($family))
                : null,
            'parents'      => array_values(array_filter([$father, $mother])),
        ];
    }
}
