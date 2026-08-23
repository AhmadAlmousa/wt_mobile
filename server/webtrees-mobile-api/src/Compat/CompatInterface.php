<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Compat;

use Fisharebest\Webtrees\Date;
use Fisharebest\Webtrees\Date\AbstractCalendarDate;
use Fisharebest\Webtrees\Fact;
use Fisharebest\Webtrees\Individual;
use Fisharebest\Webtrees\Services\ModuleService;
use Fisharebest\Webtrees\StatisticsData;
use Illuminate\Support\Collection;

/**
 * The entire webtrees-version surface this module touches.
 *
 * Eleven methods. Everything else the module calls has an identical public
 * signature in 2.2.x and 2.3, which is why one implementation per minor
 * version is cheap and a third should be too.
 *
 * The rule this file exists to enforce: **no code outside `Compat/` may name
 * a webtrees version, or a class that exists in only one of them.**
 */
interface CompatInterface
{
    /**
     * Which webtrees generation this adapter is for, e.g. "2.2" or "2.3".
     *
     * Reported by /capabilities, so a client can tell which adapter answered.
     */
    public function generation(): string;

    /**
     * Register one route.
     *
     * 2.2.x has an Aura router keyed by name; 2.3 has webtrees' own
     * RouteCollection keyed by controller class. Both dispatch a PSR-15
     * handler and both accept middleware as class-name strings.
     *
     * @param array<string> $middleware
     */
    public function addRoute(string $url, string $handler, array $middleware = []): void;

    /**
     * Sort facts the way the individual page sorts them.
     *
     * 2.2.x: `Fact::sortFacts()`. 2.3: `FactSortService::sort()`.
     *
     * @param Collection<int,Fact> $facts
     *
     * @return Collection<int,Fact>
     */
    public function sortFacts(Collection $facts): Collection;

    /**
     * A person's families, earliest marriage first.
     *
     * 2.2.x: `Family::marriageDateComparator()`. 2.3: `FamilyComparator`.
     * The descendants chart sorts them this way, and its d'Aboville numbers
     * depend on the order.
     *
     * @param Collection<int,\Fisharebest\Webtrees\Family> $families
     *
     * @return Collection<int,\Fisharebest\Webtrees\Family>
     */
    public function sortFamiliesByMarriage(Collection $families): Collection;

    /**
     * A family's children, eldest first.
     *
     * 2.2.x: `Individual::birthDateComparator()`. 2.3: `IndividualComparator`.
     *
     * @param Collection<int,Individual> $children
     *
     * @return Collection<int,Individual>
     */
    public function sortChildrenByBirth(Collection $children): Collection;

    /**
     * The GEDCOM letter for a person's sex: `M`, `F`, `U` or `X`.
     *
     * 2.2.x returns the letter; 2.3 returns a `Sex` enum backed by it.
     */
    public function sexCode(Individual $individual): string;

    /**
     * A date's two GEDCOM qualifiers, e.g. `['BET', 'AND']` or `['ABT', '']`.
     *
     * 2.2.x exposes `$qual1`/`$qual2`; 2.3 replaced them with a `DateType`
     * enum whose cases fold both into one value.
     *
     * @return array{0:string,1:string}
     */
    public function dateQualifiers(Date $date): array;

    /**
     * The GEDCOM calendar escape for one calendar date, e.g. `@#DHIJRI@`.
     */
    public function calendarEscape(AbstractCalendarDate $date): string;

    /**
     * One calendar date written back as GEDCOM, e.g. `@#DHIJRI@ 21 DHUAQ 1318`.
     *
     * 2.2.x has `AbstractCalendarDate::format()` with the `%@ %A %O %E`
     * re-formatting extensions; 2.3 dropped `format()` and added
     * `calendarEscape()` and `gedcomMonth()` in its place.
     */
    public function gedcomOf(AbstractCalendarDate $date): string;

    /**
     * How many individuals of one sex the tree records.
     *
     * 2.2.x takes the GEDCOM letter; 2.3 takes a `Sex` enum.
     */
    public function countIndividualsBySex(StatisticsData $data, string $sex): int;

    /**
     * Every language tag this site can render in.
     *
     * 2.2.x asks each language module for its `locale()`; 2.3 asks for its
     * `language()`. Both answer a `languageTag()`.
     *
     * @return array<string>
     */
    public function languageTags(ModuleService $module_service): array;
}
