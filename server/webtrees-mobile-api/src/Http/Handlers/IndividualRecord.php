<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Fisharebest\Webtrees\Services\IndividualFactsService;
use Fisharebest\Webtrees\Services\ModuleService;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Http\Json;
use WebtreesMobileApi\Support\RecordComposer;
use WebtreesMobileApi\Support\Request;

/**
 * Everything one person's page says, in one request and with nothing inferred.
 *
 * This is the endpoint that retires the largest and most fragile parser in the
 * client — 727 lines that read facts, dates, places, relatives, families,
 * notes, sources and photographs out of a page written for a desktop browser.
 *
 * Four things it can state that the markup cannot:
 *
 * - **The GEDCOM tag of every fact.** A page translates every label, and the
 *   only structural clue it leaves is the `fact_DEAT` class inside a chart
 *   box — so a client has to build a label→tag dictionary from the boxes a
 *   page happened to render, and a relative's death under its own label never
 *   appears in one.
 * - **Where a fact came from.** `fact.phtml` marks relative, associate and
 *   historic facts `collapse` and says nothing more; the five methods of
 *   `IndividualFactsService` are the real answer.
 * - **What kind of family each block is.** Derived from block order and the
 *   position of a marriage row in HTML; asked directly here.
 * - **This person's own sex, lifespan and death.** The individual page states
 *   the sex only as a translated word, so a client has to find the person's
 *   own chart box on their relatives tab to recover it.
 *
 * The record itself is composed by `RecordComposer`, because `Records`
 * answers the identical payload two hundred at a time. What stays here is the
 * one difference between the two: `sections` and `charts` describe the tree
 * rather than the person, so a page of records states them once and a single
 * record carries its own.
 */
final class IndividualRecord implements RequestHandlerInterface
{
    public function __construct(
        private readonly IndividualFactsService $individual_facts_service,
        private readonly ModuleService $module_service,
    ) {
    }

    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $tree       = Request::tree($request);
        $individual = Request::individual($request);

        $composer = new RecordComposer(
            $tree,
            $this->individual_facts_service,
            $this->module_service,
            Request::thumbnail($request),
            Request::image($request, 'w', 800),
        );

        return Json::ok($composer->compose($individual) + [
            'sections' => $composer->sections(),
            'charts'   => $composer->charts(),
        ]);
    }
}
