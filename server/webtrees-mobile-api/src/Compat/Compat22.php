<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Compat;

use Fisharebest\Webtrees\Date;
use Fisharebest\Webtrees\Date\AbstractCalendarDate;
use Fisharebest\Webtrees\Fact;
use Fisharebest\Webtrees\Family;
use Fisharebest\Webtrees\Individual;
use Fisharebest\Webtrees\Module\ModuleLanguageInterface;
use Fisharebest\Webtrees\Registry;
use Fisharebest\Webtrees\Services\ModuleService;
use Fisharebest\Webtrees\StatisticsData;
use Illuminate\Support\Collection;

use function preg_replace;
use function trim;

/**
 * webtrees 2.2.x.
 *
 * Routing is Aura's; access levels are `int` constants; `Date` carries two
 * string qualifiers; and `AbstractCalendarDate::format()` still exists, which
 * is what makes writing a calendar date back as GEDCOM a one-liner here.
 */
final class Compat22 implements CompatInterface
{
    public function generation(): string
    {
        return '2.2';
    }

    public function addRoute(string $url, string $handler, array $middleware = []): void
    {
        // Aura names a route and dispatches its handler; webtrees names both
        // after the handler class, and RequestHandler resolves the string
        // through the container.
        Registry::routeFactory()
            ->routeMap()
            ->get($handler, $url)
            ->extras(['middleware' => $middleware]);
    }

    public function sortFacts(Collection $facts): Collection
    {
        return Fact::sortFacts($facts);
    }

    public function sortFamiliesByMarriage(Collection $families): Collection
    {
        return $families->sort(Family::marriageDateComparator());
    }

    public function sortChildrenByBirth(Collection $children): Collection
    {
        return $children->sort(Individual::birthDateComparator());
    }

    public function sexCode(Individual $individual): string
    {
        return $individual->sex();
    }

    public function dateQualifiers(Date $date): array
    {
        return [$date->qual1, $date->qual2];
    }

    public function calendarEscape(AbstractCalendarDate $date): string
    {
        return trim($date->format('%@'));
    }

    public function gedcomOf(AbstractCalendarDate $date): string
    {
        // %@ escape, %A GEDCOM day, %O GEDCOM month, %E GEDCOM year. Each is
        // empty when that part of the date is unknown, so the result needs
        // its runs of spaces collapsing.
        return $this->squash($date->format('%@ %A %O %E'));
    }

    public function countIndividualsBySex(StatisticsData $data, string $sex): int
    {
        return $data->countIndividualsBySex($sex);
    }

    public function languageTags(ModuleService $module_service): array
    {
        return $module_service
            ->findByInterface(ModuleLanguageInterface::class, true)
            ->map(static fn (ModuleLanguageInterface $module): string => $module->locale()->languageTag())
            ->all();
    }

    private function squash(string $text): string
    {
        return trim((string) preg_replace('/\s+/', ' ', $text));
    }
}
