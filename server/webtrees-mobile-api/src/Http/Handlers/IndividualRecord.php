<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Fisharebest\Webtrees\Auth;
use Fisharebest\Webtrees\Individual;
use Fisharebest\Webtrees\Module\ModuleChartInterface;
use Fisharebest\Webtrees\Module\ModuleSidebarInterface;
use Fisharebest\Webtrees\Module\ModuleTabInterface;
use Fisharebest\Webtrees\Services\IndividualFactsService;
use Fisharebest\Webtrees\Services\ModuleService;
use Fisharebest\Webtrees\Tree;
use Illuminate\Support\Collection;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Compat\Compat;
use WebtreesMobileApi\Http\Json;
use WebtreesMobileApi\Presenters\DatePresenter;
use WebtreesMobileApi\Presenters\FactPresenter;
use WebtreesMobileApi\Presenters\FamilyPresenter;
use WebtreesMobileApi\Presenters\MediaPresenter;
use WebtreesMobileApi\Presenters\NotePresenter;
use WebtreesMobileApi\Presenters\PersonPresenter;
use WebtreesMobileApi\Presenters\SourcePresenter;
use WebtreesMobileApi\Support\RecordFacts;
use WebtreesMobileApi\Support\Request;

use function in_array;
use function spl_object_id;

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
 */
final class IndividualRecord implements RequestHandlerInterface
{
    /** Family meta-data webtrees never shows on a person's page. */
    private const array EXCLUDE = ['FAM:CHAN', 'FAM:_UID', 'FAM:UID', 'FAM:SUBM'];

    public function __construct(
        private readonly IndividualFactsService $individual_facts_service,
        private readonly ModuleService $module_service,
    ) {
    }

    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $tree       = Request::tree($request);
        $individual = Request::individual($request);
        $user       = Auth::user();

        $people   = new PersonPresenter(Request::thumbnail($request));
        $dates    = new DatePresenter($tree);
        $facts    = new FactPresenter($people, $dates);
        $families = new FamilyPresenter($people, $facts);

        $sections = $this->tabNames($tree);

        return Json::ok($people->present($individual) + [
            'pending'  => FactPresenter::pending($individual),
            'facts'    => $this->facts($individual, $tree, $facts),
            'families' => $this->families($individual, $families),
            // A tab a site does not run is `null`, not `[]`. The difference
            // matters: an empty list would say "this person has none", and
            // warning about a section the site never offered would put a
            // caution on every record it ever shows.
            'notes'    => $this->notes($individual, $sections),
            'sources'  => $this->sources($individual, $sections),
            'media'    => $this->media($individual, $tree, $sections, $request),
            'sections' => $sections,
            'charts'   => $this->charts($tree),
            // Nothing here is best-effort, so nothing is ever partly read.
            'warnings' => [],
        ]);
    }

    /**
     * Every fact on this person's page, in the site's own order, each knowing
     * where it came from.
     *
     * The five collections are exactly what `IndividualFactsTabModule` merges,
     * and they are merged here in the same order and sorted with the same
     * comparator — so the list is the page's list. Provenance is kept in a map
     * keyed by object identity, because merging five collections into one is
     * precisely what throws it away.
     *
     * @return array<array<string,mixed>>
     */
    private function facts(Individual $individual, Tree $tree, FactPresenter $presenter): array
    {
        $exclude = new Collection(self::EXCLUDE);
        $exclude = $exclude
            ->merge($this->supportedFacts(ModuleSidebarInterface::class, $tree))
            ->merge($this->supportedFacts(ModuleTabInterface::class, $tree));

        $service = $this->individual_facts_service;

        $sources = [
            FactPresenter::SELF      => $service->individualFacts($individual, $exclude),
            FactPresenter::FAMILY    => $service->familyFacts($individual, $exclude),
            FactPresenter::RELATIVE  => $service->relativeFacts($individual),
            FactPresenter::ASSOCIATE => $service->associateFacts($individual),
            FactPresenter::HISTORIC  => $service->historicFacts($individual),
        ];

        $origins = [];
        $merged  = new Collection();

        foreach ($sources as $origin => $collection) {
            foreach ($collection as $fact) {
                $origins[spl_object_id($fact)] = $origin;
            }

            $merged = $merged->merge($collection);
        }

        $rows = [];

        foreach (Compat::current()->sortFacts($merged) as $fact) {
            $origin = $origins[spl_object_id($fact)] ?? FactPresenter::SELF;
            $rows[] = $presenter->present($fact, $origin, $individual);
        }

        return $rows;
    }

    /**
     * Every family this person belongs to, and how they belong to it.
     *
     * @return array<array<string,mixed>>
     */
    private function families(Individual $individual, FamilyPresenter $presenter): array
    {
        $groups = [];

        foreach ($individual->childFamilies() as $family) {
            $groups[] = $presenter->present($family, FamilyPresenter::PARENTS, $individual);
        }

        foreach ($individual->spouseFamilies() as $family) {
            $groups[] = $presenter->present($family, FamilyPresenter::OWN, $individual);
        }

        foreach ($individual->childStepFamilies() as $family) {
            $groups[] = $presenter->present($family, FamilyPresenter::STEP, $individual);
        }

        foreach ($individual->spouseStepFamilies() as $family) {
            $groups[] = $presenter->present($family, FamilyPresenter::STEP, $individual);
        }

        return $groups;
    }

    /**
     * @param array<string> $sections
     *
     * @return array<array<string,mixed>>|null
     */
    private function notes(Individual $individual, array $sections): array|null
    {
        if (!in_array('notes', $sections, true)) {
            return null;
        }

        return NotePresenter::fromFacts(RecordFacts::matching($individual, '/(?:^1|\n\d) NOTE/'));
    }

    /**
     * @param array<string> $sections
     *
     * @return array<array<string,mixed>>|null
     */
    private function sources(Individual $individual, array $sections): array|null
    {
        if (!in_array('sources_tab', $sections, true)) {
            return null;
        }

        return SourcePresenter::fromFacts(RecordFacts::matching($individual, '/(?:^1|\n\d) SOUR/'));
    }

    /**
     * @param array<string> $sections
     *
     * @return array<array<string,mixed>>|null
     */
    private function media(
        Individual $individual,
        Tree $tree,
        array $sections,
        ServerRequestInterface $request,
    ): array|null {
        if (!in_array('media', $sections, true)) {
            return null;
        }

        $size = Request::image($request, 'w', 800);

        return (new MediaPresenter($size, $size))
            ->fromFacts(RecordFacts::matching($individual, '/(?:^1|\n\d) OBJE @/'), $tree);
    }

    /**
     * Which tabs this site runs for this tree and this reader.
     *
     * @return array<string>
     */
    private function tabNames(Tree $tree): array
    {
        return $this->module_service
            ->findByComponent(ModuleTabInterface::class, $tree, Auth::user())
            ->map(static fn (ModuleTabInterface $tab): string => $tab->name())
            ->values()
            ->all();
    }

    /**
     * @return Collection<int,string>
     */
    private function supportedFacts(string $interface, Tree $tree): Collection
    {
        return $this->module_service
            ->findByComponent($interface, $tree, Auth::user())
            ->map(static fn ($module): Collection => $module->supportedFacts())
            ->flatten();
    }

    /**
     * @return array<string>
     */
    private function charts(Tree $tree): array
    {
        return $this->module_service
            ->findByComponent(ModuleChartInterface::class, $tree, Auth::user())
            ->map(static fn (ModuleChartInterface $chart): string => $chart->chartMenuClass())
            ->values()
            ->all();
    }
}
