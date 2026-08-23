<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Fisharebest\Webtrees\I18N;
use Fisharebest\Webtrees\Place;
use Fisharebest\Webtrees\Services\UserService;
use Fisharebest\Webtrees\StatisticsData;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Compat\Compat;
use WebtreesMobileApi\Compat\CompatInterface;
use WebtreesMobileApi\Http\Json;
use WebtreesMobileApi\Presenters\Text;
use WebtreesMobileApi\Support\Request;

use function array_map;
use function array_slice;
use function array_values;
use function round;
use function strip_tags;

/**
 * What a site says about a whole family tree — as numbers.
 *
 * A statistics page says everything twice and neither half is easy to read.
 * Its counts are in the markup, rendered in the reader's own numerals
 * (`١٬٤٦٣`), and the data behind each chart is in a `<script>` beside it,
 * handed to a charting library. Worse, webtrees writes some of those option
 * objects **by hand**, with comments and unquoted keys — so a client that
 * decoded both arguments as JSON dropped most of the pie charts on the page.
 *
 * `StatisticsData` is the layer under all of that, it is typed, and it is
 * identical in 2.2.x and 2.3. (`Statistics` above it returns rendered HTML and
 * is the wrong layer to call.)
 *
 * Counts arrive twice on purpose: `value` is the site's own rendering, in its
 * own numerals and separators, and `count` is the plain integer. Dataset rows
 * carry plain numbers only, because a client that draws a chart has to write
 * the numerals itself — `NumberFormat` for Arabic produces Latin digits, and a
 * screen that changed numerals halfway down would look broken.
 */
final class Statistics implements RequestHandlerInterface
{
    private const int TOP_SURNAMES = 10;
    private const int TOP_COUNTRIES = 10;

    public function __construct(private readonly UserService $user_service)
    {
    }

    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $tree   = Request::tree($request);
        $data   = new StatisticsData($tree, $this->user_service);
        $compat = Compat::current();

        return Json::ok([
            'tree'  => $tree->name(),
            'parts' => [
                $this->individuals($data, $compat),
                $this->families($data),
                $this->records($data),
            ],
        ]);
    }

    /**
     * @return array<string,mixed>
     */
    private function individuals(StatisticsData $data, CompatInterface $compat): array
    {
        $males   = $compat->countIndividualsBySex($data, 'M');
        $females = $compat->countIndividualsBySex($data, 'F');
        $unknown = $compat->countIndividualsBySex($data, 'U');

        return [
            'title'    => I18N::translate('Individuals'),
            'sections' => [
                [
                    'title'    => I18N::translate('Total individuals'),
                    'total'    => $this->number($data->countIndividuals()),
                    'items'    => [
                        $this->item(I18N::translate('Total males'), $males),
                        $this->item(I18N::translate('Total females'), $females),
                        $this->item(I18N::translate('Total living'), $data->countIndividualsLiving()),
                        $this->item(I18N::translate('Total dead'), $data->countIndividualsDeceased()),
                    ],
                    'datasets' => [
                        $this->dataset(
                            I18N::translate('Sex'),
                            'pie',
                            [I18N::translate('Sex'), I18N::translate('Total individuals')],
                            [
                                [I18N::translate('Males'), $males],
                                [I18N::translate('Females'), $females],
                                [I18N::translate('Unknown'), $unknown],
                            ],
                        ),
                        $this->centuries(I18N::translate('Births by century'), $data->countEventsByCentury('BIRT')),
                        $this->centuries(I18N::translate('Deaths by century'), $data->countEventsByCentury('DEAT')),
                        $this->ages($data),
                    ],
                ],
                [
                    'title'    => I18N::translate('Total surnames'),
                    'total'    => null,
                    'items'    => $this->surnames($data),
                    'datasets' => [],
                ],
            ],
        ];
    }

    /**
     * @return array<string,mixed>
     */
    private function families(StatisticsData $data): array
    {
        return [
            'title'    => I18N::translate('Families'),
            'sections' => [
                [
                    'title'    => I18N::translate('Total families'),
                    'total'    => $this->number($data->countFamilies()),
                    'items'    => [
                        $this->item(
                            I18N::translate('Number of families without children'),
                            $data->countFamiliesWithNoChildren(),
                        ),
                        $this->item(I18N::translate('Total males'), $data->countMarriedMales()),
                        $this->item(I18N::translate('Total females'), $data->countMarriedFemales()),
                        [
                            'label' => I18N::translate('Average number of children per family'),
                            'value' => I18N::number(round($data->averageChildrenPerFamily(), 2)),
                            'count' => round($data->averageChildrenPerFamily(), 2),
                        ],
                    ],
                    'datasets' => [
                        $this->centuries(
                            I18N::translate('Marriages by century'),
                            $data->countEventsByCentury('MARR'),
                        ),
                        $this->centuries(
                            I18N::translate('Divorces by century'),
                            $data->countEventsByCentury('DIV'),
                        ),
                    ],
                ],
            ],
        ];
    }

    /**
     * @return array<string,mixed>
     */
    private function records(StatisticsData $data): array
    {
        return [
            'title'    => I18N::translate('Other'),
            'sections' => [
                [
                    'title'    => I18N::translate('Records'),
                    'total'    => $this->number($data->countAllRecords()),
                    'items'    => [
                        $this->item(I18N::translate('Media objects'), $data->countMedia('all')),
                        $this->item(I18N::translate('Sources'), $data->countSources()),
                        $this->item(I18N::translate('Notes'), $data->countNotes()),
                        $this->item(I18N::translate('Repositories'), $data->countRepositories()),
                        $this->item(I18N::translate('Places'), $data->countAllPlaces()),
                    ],
                    'datasets' => [
                        $this->dataset(
                            I18N::translate('Media by type'),
                            'pie',
                            [I18N::translate('Type'), I18N::translate('Media objects')],
                            $data->countMediaByType(),
                        ),
                        $this->dataset(
                            I18N::translate('Events in countries'),
                            'column',
                            [I18N::translate('Country'), I18N::translate('Events')],
                            $this->countries($data),
                        ),
                    ],
                ],
            ],
        ];
    }

    /**
     * Where events happened, by country.
     *
     * `countCountries()` hands back `Place` objects rather than names, because
     * the site renders a place through its own hierarchy settings.
     *
     * @return array<array<int,mixed>>
     */
    private function countries(StatisticsData $data): array
    {
        $rows = [];

        foreach ($data->countCountries(self::TOP_COUNTRIES) as $row) {
            $place = $row['place'];

            if ($place instanceof Place) {
                $rows[] = [Text::of($place->placeName()), $row['count']];
            }
        }

        return $rows;
    }

    /**
     * Average age at death, by century and sex.
     *
     * @return array<string,mixed>
     */
    private function ages(StatisticsData $data): array
    {
        $by_century = [];

        foreach ($data->statsAge() as $row) {
            $century = $this->centuryName((int) $row->century);

            $by_century[$century] ??= [$century, 0.0, 0.0];

            if ($row->sex === 'M') {
                $by_century[$century][1] = round((float) $row->age, 1);
            } elseif ($row->sex === 'F') {
                $by_century[$century][2] = round((float) $row->age, 1);
            }
        }

        return $this->dataset(
            I18N::translate('Average age related to death century'),
            'column',
            [I18N::translate('Century'), I18N::translate('Males'), I18N::translate('Females')],
            array_values($by_century),
        );
    }

    /**
     * @return array<array<string,mixed>>
     */
    private function surnames(StatisticsData $data): array
    {
        $items = [];

        foreach ($data->commonSurnames(self::TOP_SURNAMES, 1, 'count') as $surname => $variants) {
            $total = 0;

            foreach ($variants as $count) {
                $total += $count;
            }

            $items[] = $this->item((string) $surname, $total);
        }

        return $items;
    }

    /**
     * @param array<array{0:string,1:int}> $rows
     *
     * @return array<string,mixed>
     */
    private function centuries(string $title, array $rows): array
    {
        return $this->dataset(
            $title,
            'column',
            [I18N::translate('Century'), I18N::translate('Total events')],
            $rows,
        );
    }

    /**
     * @param array<string>            $columns
     * @param array<array<int,mixed>>  $rows
     *
     * @return array<string,mixed>
     */
    private function dataset(string $title, string $shape, array $columns, array $rows): array
    {
        return [
            'title'   => $title,
            'shape'   => $shape,
            'columns' => $columns,
            'rows'    => array_map(
                static fn (array $row): array => [
                    'label'  => (string) $row[0],
                    'values' => array_map(static fn ($value): float => (float) $value, array_slice($row, 1)),
                ],
                $rows,
            ),
        ];
    }

    /**
     * @return array<string,mixed>
     */
    private function item(string $label, int|float $count): array
    {
        return ['label' => $label, 'value' => $this->number($count), 'count' => $count];
    }

    private function number(int|float $count): string
    {
        return I18N::number($count);
    }

    /**
     * The site's own name for a century.
     *
     * `StatisticsData::centuryName()` is `private`, and `countEventsByCentury()`
     * has already applied it to the rows it returns — but `statsAge()` hands
     * back raw century numbers, so this one case has to say it again. The
     * strings are webtrees' own, from its own catalogue and its own `CENTURY`
     * context, so a site that translates "20th" translates this too.
     */
    private function centuryName(int $century): string
    {
        if ($century < 0) {
            return I18N::translate('%s BCE', $this->centuryName(-$century));
        }

        $ordinals = [
            1 => '1st', 2 => '2nd', 3 => '3rd', 4 => '4th', 5 => '5th', 6 => '6th',
            7 => '7th', 8 => '8th', 9 => '9th', 10 => '10th', 11 => '11th',
            12 => '12th', 13 => '13th', 14 => '14th', 15 => '15th', 16 => '16th',
            17 => '17th', 18 => '18th', 19 => '19th', 20 => '20th', 21 => '21st',
        ];

        if (isset($ordinals[$century])) {
            return strip_tags(I18N::translateContext('CENTURY', $ordinals[$century]));
        }

        return ($century - 1) . '01-' . $century . '00';
    }
}
