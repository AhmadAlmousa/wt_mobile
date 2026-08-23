<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Compat;

use Fisharebest\Webtrees\Comparators\FamilyComparator;
use Fisharebest\Webtrees\Comparators\IndividualComparator;
use Fisharebest\Webtrees\Date;
use Fisharebest\Webtrees\Date\AbstractCalendarDate;
use Fisharebest\Webtrees\Enums\DateType;
use Fisharebest\Webtrees\Enums\Sex;
use Fisharebest\Webtrees\Individual;
use Fisharebest\Webtrees\Module\ModuleLanguageInterface;
use Fisharebest\Webtrees\Registry;
use Fisharebest\Webtrees\Services\FactSortService;
use Fisharebest\Webtrees\Services\ModuleService;
use Fisharebest\Webtrees\StatisticsData;
use Illuminate\Support\Collection;

use function preg_replace;
use function sprintf;
use function trim;

/**
 * webtrees 2.3.
 *
 * Routing moved to webtrees' own RouteCollection, several `int`/`string`
 * parameters became enums, and `AbstractCalendarDate::format()` was dropped —
 * so a GEDCOM date has to be assembled from its parts here.
 */
final class Compat23 implements CompatInterface
{
    public function generation(): string
    {
        return '2.3';
    }

    public function addRoute(string $url, string $handler, array $middleware = []): void
    {
        Registry::routeFactory()->routeMap()->add($url, $handler, $middleware);
    }

    public function sortFacts(Collection $facts): Collection
    {
        return Registry::container()->get(FactSortService::class)->sort($facts);
    }

    public function sortFamiliesByMarriage(Collection $families): Collection
    {
        return $families->sort(FamilyComparator::byMarriageDate(...));
    }

    public function sortChildrenByBirth(Collection $children): Collection
    {
        return $children->sort(IndividualComparator::byBirthDate(...));
    }

    public function sexCode(Individual $individual): string
    {
        return $individual->sex()->value;
    }

    public function dateQualifiers(Date $date): array
    {
        // One enum case now covers what used to be two words.
        return match ($date->type) {
            DateType::Between => ['BET', 'AND'],
            DateType::FromTo  => ['FROM', 'TO'],
            DateType::Exact   => ['', ''],
            default           => [$date->type->value, ''],
        };
    }

    public function calendarEscape(AbstractCalendarDate $date): string
    {
        return $date->calendarEscape()->value;
    }

    public function gedcomOf(AbstractCalendarDate $date): string
    {
        // The same four parts 2.2's `%@ %A %O %E` produced, in the same order
        // and with the same zero-suppression.
        $day  = $date->day() === 0 ? '' : sprintf('%02d', $date->day());
        $year = $date->year() === 0 ? '' : sprintf('%04d', $date->year());

        return $this->squash(
            $date->calendarEscape()->value . ' ' . $day . ' ' . $date->gedcomMonth() . ' ' . $year
        );
    }

    public function countIndividualsBySex(StatisticsData $data, string $sex): int
    {
        return $data->countIndividualsBySex(Sex::from($sex));
    }

    public function languageTags(ModuleService $module_service): array
    {
        return $module_service
            ->findByInterface(ModuleLanguageInterface::class, true)
            ->map(static fn (ModuleLanguageInterface $module): string => $module->language()->languageTag())
            ->all();
    }

    private function squash(string $text): string
    {
        return trim((string) preg_replace('/\s+/', ' ', $text));
    }
}
