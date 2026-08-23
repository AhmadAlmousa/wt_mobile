<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Fisharebest\Webtrees\Individual;
use Fisharebest\Webtrees\Registry;
use Fisharebest\Webtrees\Services\SearchService;
use Fisharebest\Webtrees\Tree;
use Fisharebest\Webtrees\Validator;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Http\Json;
use WebtreesMobileApi\Presenters\PersonPresenter;
use WebtreesMobileApi\Support\Request;

use function array_map;
use function array_slice;
use function array_unshift;
use function array_values;
use function count;
use function trim;
use function usort;

/**
 * Finding people: search, and — for the first time — browsing.
 *
 * A stock instance has exactly one route that answers JSON, and it is an
 * autocomplete: `AbstractTomSelectHandler` returns an empty collection unless
 * `query` is non-empty, so it can search a tree and cannot list one. Its
 * paging is worse than it looks — the `nextUrl` it offers is built from the
 * tree, `at` and the page number only, dropping the query, so a client that
 * followed it would page through an empty search; and because the search
 * joins the name table, somebody recorded under two names is two rows, deduped
 * only within the page being built, so the same person arrives again on the
 * next one.
 *
 * `SearchService::searchIndividualNames()` fixes all of that in one call.
 * `whereSearch()` applies no filter for an empty term array, so the same
 * method that searches also **walks a whole tree in `n_sort` order**; and
 * `paginateQuery()` dedupes across the entire cursor and applies `canShow()`
 * *before* counting down the offset, so a page is a page.
 *
 * The one cost to design around: that walk is a PHP cursor rather than a SQL
 * `LIMIT`, so it is `O(offset)`. Deep pages get progressively more expensive,
 * which is why `surname` exists — partitioned browsing beats scrolling to row
 * 5,000.
 */
final class Individuals implements RequestHandlerInterface
{
    public function __construct(private readonly SearchService $search_service)
    {
    }

    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $tree    = Request::tree($request);
        $offset  = Request::offset($request);
        $limit   = Request::limit($request);
        $people  = new PersonPresenter(Request::thumbnail($request));
        $query   = trim(Validator::queryParams($request)->string('q', ''));
        $surname = trim(Validator::queryParams($request)->string('surname', ''));

        if ($surname !== '') {
            return $this->bySurname($tree, $surname, $offset, $limit, $people);
        }

        return $this->byName($tree, $query, $offset, $limit, $people);
    }

    /**
     * Search by name, or list the whole tree when the query is empty.
     */
    private function byName(
        Tree $tree,
        string $query,
        int $offset,
        int $limit,
        PersonPresenter $people,
    ): ResponseInterface {
        $terms = $query === '' ? [] : [$query];

        // One row beyond the page, so "are there more" is a fact rather than
        // an inference from a full page.
        $found = $this->search_service
            ->searchIndividualNames([$tree], $terms, $offset, $limit + 1)
            ->all();

        $more = count($found) > $limit;
        $rows = array_slice($found, 0, $limit);

        // webtrees' own autocomplete resolves an xref before searching, and
        // an app that has just followed a link has an xref rather than a name.
        if ($offset === 0 && $query !== '') {
            $this->promoteXref($rows, $tree, $query, $limit);
        }

        return Json::ok([
            'offset'  => $offset,
            'limit'   => $limit,
            // Not stated. A cheap `COUNT` would count the multi-name rows
            // `paginateQuery` removes and the records privacy hides, so it
            // would be a wrong number rather than an expensive one.
            'total'   => null,
            'hasMore' => $more,
            'people'  => array_map($people->present(...), $rows),
        ]);
    }

    /**
     * Everybody whose surname begins with these letters — a browsable index.
     *
     * `searchIndividualsAdvanced()` is the public way to ask that question:
     * `BEGINS` matches on the indexed `n_surn`/`n_surname` columns rather than
     * with the `%term%` a general search uses, so "Al" is an initial and not a
     * substring. It answers everything at once (webtrees caps it at 5,000), so
     * the page is taken here — which is fine, because the point of browsing by
     * surname is that no partition is ever large enough to need a deep offset.
     */
    private function bySurname(
        Tree $tree,
        string $surname,
        int $offset,
        int $limit,
        PersonPresenter $people,
    ): ResponseInterface {
        $found = $this->search_service
            ->searchIndividualsAdvanced(
                $tree,
                ['INDI:NAME:SURN' => $surname],
                ['INDI:NAME:SURN' => 'BEGINS'],
            )
            ->all();

        // `n_sort` is what `sortName()` holds, so this is the order the name
        // search would have produced, applied to a set that arrived unordered.
        usort($found, static fn (Individual $a, Individual $b): int => $a->sortName() <=> $b->sortName());

        $rows = array_slice($found, $offset, $limit);

        return Json::ok([
            'offset'  => $offset,
            'limit'   => $limit,
            // Here the total is honest: the whole partition was fetched and
            // privacy-filtered before the page was taken.
            'total'   => count($found),
            'hasMore' => $offset + count($rows) < count($found),
            'people'  => array_map($people->present(...), $rows),
        ]);
    }

    /**
     * Put the record this query names at the top of its own results.
     *
     * @param array<Individual> $rows
     */
    private function promoteXref(array &$rows, Tree $tree, string $query, int $limit): void
    {
        $individual = Registry::individualFactory()->make($query, $tree);

        if (!$individual instanceof Individual || !$individual->canShow()) {
            return;
        }

        foreach ($rows as $index => $row) {
            if ($row->xref() === $individual->xref()) {
                unset($rows[$index]);
                $rows = array_values($rows);
                break;
            }
        }

        array_unshift($rows, $individual);
        $rows = array_slice($rows, 0, $limit);
    }
}
