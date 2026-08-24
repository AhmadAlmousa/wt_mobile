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
use WebtreesMobileApi\Http\ApiException;
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
 * `SearchService::searchIndividualNames()` answers the first half in one call:
 * `whereSearch()` applies no filter for an empty term array, so the same
 * method that searches also **walks a whole tree in `n_sort` order**, which is
 * what makes browsing possible at all.
 *
 * **It does not answer the second half by itself, and reading the source
 * carelessly says it does.** `paginateQuery()` dedupes against the collection
 * it is *building*, and counts the offset down over rows it has not deduped —
 * so asking for `offset=5&limit=5` counts five *rows* and answers five
 * *people*, and a person with two name rows arrives again on the next page.
 * That is the same trap as the stock autocomplete, inherited rather than
 * fixed (`PROJECT.md` §7, bug 53).
 *
 * What does fix it is asking from the top every time: with `offset=0` every
 * accepted row is pushed, so the dedup set *is* everything walked so far, and
 * the page is taken here. Exact, duplicate-free paging over a method that
 * cannot offer it.
 *
 * Two costs to design around, both bounded by `MAX_OFFSET`. The walk is a PHP
 * cursor rather than a SQL `LIMIT`, so it is `O(offset)` in time; and taking
 * the page here means holding the whole prefix, so it is `O(offset)` in memory
 * too. Deep pages get progressively more expensive, which is why `surname`
 * exists — partitioned browsing beats scrolling to row 5,000, and past that
 * row this endpoint says so rather than exhausting `memory_limit`.
 */
final class Individuals implements RequestHandlerInterface
{
    /**
     * How deep a name search may be paged.
     *
     * The same number webtrees caps its own advanced search at, and for the
     * same reason: a page taken from the top holds every person before it, so
     * beyond a few thousand the honest answer is the surname index rather
     * than a request that walks the tree and then runs out of memory.
     */
    public const int MAX_OFFSET = 5000;

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

        if ($offset > self::MAX_OFFSET) {
            throw ApiException::invalidParameter(
                'That is too far into the results. Browse by surname instead.',
                'offset',
            );
        }

        // From the top, always, and one person beyond the page: that is what
        // makes `paginateQuery()`'s dedup cover everything walked rather than
        // only the page being built, and what makes "are there more" a fact
        // rather than an inference from a full page.
        $found = $this->search_service
            ->searchIndividualNames([$tree], $terms, 0, $offset + $limit + 1)
            ->all();

        $more = count($found) > $offset + $limit;
        $rows = array_slice($found, $offset, $limit);

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
