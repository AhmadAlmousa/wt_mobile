<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Support;

use Fisharebest\Webtrees\Auth;
use Fisharebest\Webtrees\Individual;
use Fisharebest\Webtrees\Module\ModuleChartInterface;
use Fisharebest\Webtrees\Module\ModuleSidebarInterface;
use Fisharebest\Webtrees\Module\ModuleTabInterface;
use Fisharebest\Webtrees\Services\IndividualFactsService;
use Fisharebest\Webtrees\Services\ModuleService;
use Fisharebest\Webtrees\Tree;
use Illuminate\Support\Collection;
use WebtreesMobileApi\Compat\Compat;
use WebtreesMobileApi\Presenters\DatePresenter;
use WebtreesMobileApi\Presenters\FactPresenter;
use WebtreesMobileApi\Presenters\FamilyPresenter;
use WebtreesMobileApi\Presenters\MediaPresenter;
use WebtreesMobileApi\Presenters\NotePresenter;
use WebtreesMobileApi\Presenters\PersonPresenter;
use WebtreesMobileApi\Presenters\SourcePresenter;

use function in_array;
use function spl_object_id;

/**
 * One person's whole record, composed once and reusable many times.
 *
 * Extracted from `IndividualRecord` when `Records` began answering the same
 * payload in pages of two hundred, and the split is where the cost is: three
 * of the things that record needs — which tabs this site runs, which charts it
 * offers, and which facts its sidebars and tabs already claim — are properties
 * of the **tree and the reader**, not of the person. Asked once per request
 * here rather than once per record, they stop being two hundred module lookups
 * and two hundred repetitions of the same array on the wire.
 *
 * Nothing else changed in the move: the fact collections are the five
 * `IndividualFactsService` answers the individual page merges, in that order,
 * sorted with the same comparator, and provenance is still kept by object
 * identity because merging five collections is exactly what throws it away.
 */
final class RecordComposer
{
    /** Family meta-data webtrees never shows on a person's page. */
    private const array EXCLUDE = ['FAM:CHAN', 'FAM:_UID', 'FAM:UID', 'FAM:SUBM'];

    private readonly PersonPresenter $people;

    private readonly FactPresenter $fact_presenter;

    private readonly FamilyPresenter $family_presenter;

    private readonly MediaPresenter $media_presenter;

    /** @var Collection<int,string> */
    private readonly Collection $exclude;

    /** @var array<string> */
    private readonly array $sections;

    /** @var array<string> */
    private readonly array $charts;

    /**
     * @param int $thumbnail The longest edge of the portrait to sign a URL for.
     * @param int $image     The box to sign a media item's URL for.
     */
    public function __construct(
        private readonly Tree $tree,
        private readonly IndividualFactsService $individual_facts_service,
        ModuleService $module_service,
        int $thumbnail = 160,
        int $image = 800,
    ) {
        $this->people           = new PersonPresenter($thumbnail);
        $dates                  = new DatePresenter($tree);
        $this->fact_presenter   = new FactPresenter($this->people, $dates);
        $this->family_presenter = new FamilyPresenter($this->people, $this->fact_presenter);
        $this->media_presenter  = new MediaPresenter($image, $image);

        $this->sections = $module_service
            ->findByComponent(ModuleTabInterface::class, $tree, Auth::user())
            ->map(static fn (ModuleTabInterface $tab): string => $tab->name())
            ->values()
            ->all();

        $this->charts = $module_service
            ->findByComponent(ModuleChartInterface::class, $tree, Auth::user())
            ->map(static fn (ModuleChartInterface $chart): string => $chart->chartMenuClass())
            ->values()
            ->all();

        $this->exclude = (new Collection(self::EXCLUDE))
            ->merge($this->supportedFacts($module_service, ModuleSidebarInterface::class))
            ->merge($this->supportedFacts($module_service, ModuleTabInterface::class));
    }

    /**
     * Which tabs this site runs for this tree and this reader.
     *
     * @return array<string>
     */
    public function sections(): array
    {
        return $this->sections;
    }

    /**
     * @return array<string>
     */
    public function charts(): array
    {
        return $this->charts;
    }

    /**
     * Everything one person's page says.
     *
     * `sections` and `charts` are deliberately **not** here: they belong to
     * the tree, and the caller states them once beside however many records
     * it is sending.
     *
     * @return array<string,mixed>
     */
    public function compose(Individual $individual): array
    {
        return $this->people->present($individual) + [
            'pending'  => FactPresenter::pending($individual),
            'facts'    => $this->facts($individual),
            'families' => $this->families($individual),
            // A tab a site does not run is `null`, not `[]`. The difference
            // matters: an empty list would say "this person has none", and
            // warning about a section the site never offered would put a
            // caution on every record it ever shows.
            'notes'    => $this->notes($individual),
            'sources'  => $this->sources($individual),
            'media'    => $this->media($individual),
            // Nothing here is best-effort, so nothing is ever partly read.
            'warnings' => [],
        ];
    }

    /**
     * Every fact on this person's page, in the site's own order, each knowing
     * where it came from.
     *
     * @return array<array<string,mixed>>
     */
    private function facts(Individual $individual): array
    {
        $service = $this->individual_facts_service;

        $sources = [
            FactPresenter::SELF      => $service->individualFacts($individual, $this->exclude),
            FactPresenter::FAMILY    => $service->familyFacts($individual, $this->exclude),
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
            $rows[] = $this->fact_presenter->present($fact, $origin, $individual);
        }

        return $rows;
    }

    /**
     * Every family this person belongs to, and how they belong to it.
     *
     * @return array<array<string,mixed>>
     */
    private function families(Individual $individual): array
    {
        $groups = [];

        foreach ($individual->childFamilies() as $family) {
            $groups[] = $this->family_presenter->summary($family, FamilyPresenter::PARENTS, $individual);
        }

        foreach ($individual->spouseFamilies() as $family) {
            $groups[] = $this->family_presenter->summary($family, FamilyPresenter::OWN, $individual);
        }

        foreach ($individual->childStepFamilies() as $family) {
            $groups[] = $this->family_presenter->summary($family, FamilyPresenter::STEP, $individual);
        }

        foreach ($individual->spouseStepFamilies() as $family) {
            $groups[] = $this->family_presenter->summary($family, FamilyPresenter::STEP, $individual);
        }

        return $groups;
    }

    /**
     * @return array<array<string,mixed>>|null
     */
    private function notes(Individual $individual): array|null
    {
        if (!in_array('notes', $this->sections, true)) {
            return null;
        }

        return NotePresenter::fromFacts(RecordFacts::matching($individual, '/(?:^1|\n\d) NOTE/'));
    }

    /**
     * @return array<array<string,mixed>>|null
     */
    private function sources(Individual $individual): array|null
    {
        if (!in_array('sources_tab', $this->sections, true)) {
            return null;
        }

        return SourcePresenter::fromFacts(RecordFacts::matching($individual, '/(?:^1|\n\d) SOUR/'));
    }

    /**
     * @return array<array<string,mixed>>|null
     */
    private function media(Individual $individual): array|null
    {
        if (!in_array('media', $this->sections, true)) {
            return null;
        }

        return $this->media_presenter
            ->fromFacts(RecordFacts::matching($individual, '/(?:^1|\n\d) OBJE @/'), $this->tree);
    }

    /**
     * @return Collection<int,string>
     */
    private function supportedFacts(ModuleService $module_service, string $interface): Collection
    {
        return $module_service
            ->findByComponent($interface, $this->tree, Auth::user())
            ->map(static fn ($module): Collection => $module->supportedFacts())
            ->flatten();
    }
}
