<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Support;

use Fisharebest\Algorithm\Dijkstra;
use Fisharebest\Webtrees\DB;
use Fisharebest\Webtrees\Individual;
use Illuminate\Database\Query\JoinClause;

use function array_map;
use function count;
use function current;
use function implode;
use function in_array;
use function next;
use function sort;

/**
 * Every way two people in a tree are connected.
 *
 * **This is the module's only duplicated core logic, and therefore its only
 * silent-drift risk.** `RelationshipsChartModule::calculateRelationships()` is
 * `private`, along with its two helpers, so there is no way to call it — but
 * the *naming* of a path is public (`RelationshipService::nameFromPath()`), so
 * the site's own wording survives, including the distinction between an older
 * and a younger brother that Arabic makes and English cannot.
 *
 * The code below is a deliberate line-for-line port of that private method as
 * it stands in **both** 2.2.6 and 2.3, where the three methods are identical
 * but for a trailing comma. Keep it that way: if it is ever "improved", the
 * module will start answering something the website does not, and no test on
 * either side will notice.
 */
final class RelationshipFinder
{
    /**
     * The shortest paths between two people, then progressively more of them.
     *
     * A path alternates individual and family xrefs, starting and ending with
     * an individual.
     *
     * @param int  $recursion How many alternative routes to look for.
     * @param bool $ancestors Restrict the graph to relationships through a
     *                        common ancestor — a site's `RELATIONSHIP_ANCESTORS`
     *                        setting, which is what makes a link through a
     *                        marriage answer "no relationship found".
     *
     * @return array<array<string>>
     */
    public function paths(
        Individual $individual1,
        Individual $individual2,
        int $recursion,
        bool $ancestors = false,
    ): array {
        $tree = $individual1->tree();

        $rows = DB::table('link')
            ->where('l_file', '=', $tree->id())
            ->whereIn('l_type', ['FAMS', 'FAMC'])
            ->select(['l_from', 'l_to'])
            ->get();

        if ($ancestors) {
            $keep    = $this->allAncestors($individual1->xref(), $individual2->xref(), $tree->id());
            $exclude = $this->excludeFamilies($individual1->xref(), $individual2->xref(), $tree->id());
        } else {
            $keep    = [];
            $exclude = [];
        }

        $graph = [];

        foreach ($rows as $row) {
            if ($keep === [] || in_array($row->l_from, $keep, true) && !in_array($row->l_to, $exclude, true)) {
                $graph[$row->l_from][$row->l_to] = 1;
                $graph[$row->l_to][$row->l_from] = 1;
            }
        }

        $xref1    = $individual1->xref();
        $xref2    = $individual2->xref();
        $dijkstra = new Dijkstra($graph);
        $paths    = $dijkstra->shortestPaths($xref1, $xref2);

        // Only process each exclusion list once.
        $excluded = [];

        $queue = [];

        foreach ($paths as $path) {
            $queue[] = ['path' => $path, 'exclude' => []];

            for ($next = current($queue); $next !== false; $next = next($queue)) {
                // For each family on the path, try again without it.
                for ($n = count($next['path']) - 2; $n >= 1; $n -= 2) {
                    $exclude = $next['exclude'];

                    if (count($exclude) >= $recursion) {
                        continue;
                    }

                    $exclude[] = $next['path'][$n];
                    sort($exclude);
                    $key = implode('-', $exclude);

                    if (in_array($key, $excluded, true)) {
                        continue;
                    }

                    $excluded[] = $key;

                    foreach ($dijkstra->shortestPaths($xref1, $xref2, $exclude) as $new_path) {
                        $queue[] = ['path' => $new_path, 'exclude' => $exclude];
                    }
                }
            }
        }

        $paths = [];

        foreach ($queue as $next) {
            // The Dijkstra library does not use strict types, and converts
            // numeric array keys (XREFs) from strings to integers.
            $paths[implode('-', $next['path'])] = array_map(
                static fn ($xref): string => (string) $xref,
                $next['path'],
            );
        }

        return $paths;
    }

    /**
     * Every ancestor of either person, plus the two of them.
     *
     * @return array<string>
     */
    private function allAncestors(string $xref1, string $xref2, int $tree_id): array
    {
        $ancestors = [$xref1, $xref2];
        $queue     = [$xref1, $xref2];

        while ($queue !== []) {
            $parents = DB::table('link AS l1')
                ->join('link AS l2', static function (JoinClause $join): void {
                    $join
                        ->on('l1.l_to', '=', 'l2.l_to')
                        ->on('l1.l_file', '=', 'l2.l_file');
                })
                ->where('l1.l_file', '=', $tree_id)
                ->where('l1.l_type', '=', 'FAMC')
                ->where('l2.l_type', '=', 'FAMS')
                ->whereIn('l1.l_from', $queue)
                ->pluck('l2.l_from');

            $queue = [];

            foreach ($parents as $parent) {
                if (!in_array($parent, $ancestors, true)) {
                    $ancestors[] = $parent;
                    $queue[]     = $parent;
                }
            }
        }

        return $ancestors;
    }

    /**
     * The families both people are a spouse in — the ones a blood-line search
     * must not walk through.
     *
     * @return array<string>
     */
    private function excludeFamilies(string $xref1, string $xref2, int $tree_id): array
    {
        return DB::table('link AS l1')
            ->join('link AS l2', static function (JoinClause $join): void {
                $join
                    ->on('l1.l_to', '=', 'l2.l_to')
                    ->on('l1.l_type', '=', 'l2.l_type')
                    ->on('l1.l_file', '=', 'l2.l_file');
            })
            ->where('l1.l_file', '=', $tree_id)
            ->where('l1.l_type', '=', 'FAMS')
            ->where('l1.l_from', '=', $xref1)
            ->where('l2.l_from', '=', $xref2)
            ->pluck('l1.l_to')
            ->all();
    }
}
