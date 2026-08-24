<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Fisharebest\Webtrees\DB;
use Fisharebest\Webtrees\GedcomRecord;
use Fisharebest\Webtrees\Individual;
use Fisharebest\Webtrees\Registry;
use Fisharebest\Webtrees\Services\IndividualFactsService;
use Fisharebest\Webtrees\Services\LinkedRecordService;
use Fisharebest\Webtrees\Services\ModuleService;
use Fisharebest\Webtrees\Tree;
use Fisharebest\Webtrees\Validator;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Http\Json;
use WebtreesMobileApi\Support\RecordComposer;
use WebtreesMobileApi\Support\Request;
use WebtreesMobileApi\Support\SyncToken;

use function array_diff_key;
use function array_keys;
use function array_map;
use function array_slice;
use function array_values;
use function count;
use function ksort;
use function trim;

/**
 * The whole tree, a page at a time — and afterwards, only what changed.
 *
 * The endpoint a local copy of a tree is filled from. `sync_eval.md` argues
 * the shape at length and the conclusion is worth restating here, because it
 * is the reason this is a list of records rather than a file to download: a
 * server-built `.sqlite` puts a multi-megabyte build inside one PHP request
 * on somebody else's shared host, and it fails at install time, which is the
 * worst moment. A paged walk is bounded per request, resumable by
 * construction, needs no server-side state, and makes the first sync and the
 * daily delta the same code path with one parameter changed.
 *
 * **A page here is the same record `/individual/{xref}` answers**, minus the
 * two fields that describe the tree rather than the person: `sections` and
 * `charts` are stated once per page instead of two hundred times.
 *
 * Two modes, one route:
 *
 * - **No `since`** — every individual this reader may see, in xref order, one
 *   indexed `LIMIT` per page. Deliberately not the name-ordered walk the
 *   search endpoint uses; `everybody()` says why at length, and the short
 *   version is that paging that walk hands the same person over twice.
 * - **`since=<token>`** — only the records a change has touched. A changed
 *   family, note, source or photograph is answered as the *individuals* it
 *   affects, because those are the records a client stores; anything that no
 *   longer resolves, or that this reader may no longer see, is a tombstone in
 *   `deleted`.
 *
 * Three rules a client has to hold to, none of which the wire can enforce:
 *
 * 1. **Advance the token only when `hasMore` is false.** Each page states the
 *    fingerprint as it is *now*, so a tree edited mid-walk answers a
 *    different token on a later page than on the first. Keep the first, and
 *    if the last page disagrees with it, run a delta from the first — the
 *    walk is then complete rather than one record short.
 * 2. **`resync: true` means discard and start again.** It is not an error and
 *    carries no records: the client's token names a state this tree can no
 *    longer describe a path from — almost always a re-import.
 * 3. **`deleted` is whole, not paged.** Tombstones are xrefs and cost
 *    nothing, so every page of a delta carries all of them, and applying
 *    them twice is the same as applying them once.
 */
final class Records implements RequestHandlerInterface
{
    /**
     * A conservative page for somebody who did not say.
     *
     * A full record is a few kilobytes, so `limit=200` — the ceiling — is
     * around a megabyte, which is the right ask from a sync loop and the
     * wrong one from a first look with `curl`.
     */
    private const int DEFAULT_LIMIT = 50;

    public function __construct(
        private readonly IndividualFactsService $individual_facts_service,
        private readonly ModuleService $module_service,
        private readonly LinkedRecordService $linked_record_service,
    ) {
    }

    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $tree   = Request::tree($request);
        $offset = Request::offset($request);
        $limit  = Request::limit($request, self::DEFAULT_LIMIT);
        $since  = trim(Validator::queryParams($request)->string('since', ''));

        $composer = new RecordComposer(
            $tree,
            $this->individual_facts_service,
            $this->module_service,
            Request::thumbnail($request),
            Request::image($request, 'w', 800),
        );

        $token = SyncToken::of($tree);

        if ($since === '') {
            return $this->everybody($tree, $offset, $limit, $token, $composer);
        }

        return $this->changed($tree, $since, $offset, $limit, $token, $composer);
    }

    /**
     * Every visible individual, in pages, in xref order.
     *
     * **Not `SearchService`.** Its walk is the right tool for browsing and the
     * wrong one for a sync: it orders by `n_sort`, which needs a join to the
     * name table and returns a row per name *form*, and its offset counts
     * those rows while its page counts people — so paging it hands the same
     * person over twice (`PROJECT.md` §7, bug 53). Ordering by xref instead
     * makes the offset a real SQL `LIMIT` over the primary key: no join, no
     * duplicates, and `O(1)` rather than `O(offset)`, which is what turns a
     * thousand-page tree into a walk a phone can finish.
     *
     * Order is arbitrary and that is deliberate. A client sorting a local copy
     * of a tree sorts it locally; what a sync needs from an order is only that
     * it is total and stable, which xref order is and name order is not.
     *
     * Two consequences a client has to know. A page can be **shorter than the
     * limit** — privacy is applied after the rows are taken, so `hasMore` is
     * counted from the rows and never from the records handed over; advance
     * the offset by the limit you asked for and never by what you received.
     * And a record created between two pages shifts the ones after it, which
     * is what the token comparison in rule 1 exists to catch.
     */
    private function everybody(
        Tree $tree,
        int $offset,
        int $limit,
        SyncToken $token,
        RecordComposer $composer,
    ): ResponseInterface {
        // One row beyond the page, so "are there more" is a fact rather than
        // an inference from a full page.
        $rows = DB::table('individuals')
            ->where('i_file', '=', $tree->id())
            ->orderBy('i_id')
            ->offset($offset)
            ->limit($limit + 1)
            ->select(['individuals.*'])
            ->get();

        $more = $rows->count() > $limit;

        $people = $rows
            ->take($limit)
            ->map(Registry::individualFactory()->mapper($tree))
            ->filter(static fn (Individual|null $individual): bool => $individual instanceof Individual)
            // webtrees' own answer for this reader, as everywhere else here: a
            // record they may not see is absent rather than empty.
            ->filter(static fn (Individual $individual): bool => $individual->canShow())
            ->values()
            ->all();

        return $this->page($token, $offset, $limit, $token->individuals(), $more, $composer, $people);
    }

    /**
     * Only what a change has touched since the client's token.
     */
    private function changed(
        Tree $tree,
        string $since,
        int $offset,
        int $limit,
        SyncToken $token,
        RecordComposer $composer,
    ): ResponseInterface {
        $earlier = SyncToken::parse($since);

        if (!$earlier instanceof SyncToken || !$token->follows($earlier)) {
            return $this->resync($token, $offset, $limit);
        }

        $changed = SyncToken::changedSince($tree, $earlier);

        if (count($changed) > SyncToken::MAX_DELTA) {
            return $this->resync($token, $offset, $limit);
        }

        [$people, $deleted] = $this->expand($tree, $changed);

        $rows = array_slice($people, $offset, $limit);
        $more = $offset + count($rows) < count($people);

        return $this->page(
            $token,
            $offset,
            $limit,
            count($people),
            $more,
            $composer,
            $rows,
            $deleted,
            $since,
        );
    }

    /**
     * Which individuals a list of changed xrefs is really about.
     *
     * A client stores individuals, so every change has to be translated into
     * the people whose *record* it alters — which is more of them than it
     * looks, and the reason this method is not a lookup:
     *
     * - A changed **family, note, source or photograph** is not a record the
     *   client holds at all. It shows up on the people it is attached to.
     * - A changed **individual** alters their own record *and* everybody
     *   whose record draws them. A person's payload names their parents,
     *   spouses, siblings and children, so renaming one man restates a dozen
     *   other records. A store that missed that would show his old name
     *   beside his children for as long as nothing else touched them.
     *
     * Both are the same walk, which is why there is no branch on record type:
     * everything a changed record links to, and everybody in every family it
     * belongs to. `LinkedRecordService` is the public way to ask, it
     * privacy-filters what it answers, and it is identical in 2.2.6 and 2.3.
     *
     * Two hops rather than three is a deliberate floor, not a claim about
     * GEDCOM: a source citation on a note on a family is not followed, and a
     * client that syncs regularly picks the record up the next time the
     * person themselves is touched. What is *never* missed is a change to the
     * individual, to a family they are in, or to anything attached directly
     * to either. The cost is that one edit re-sends a household — which is
     * what a denormalized payload buys its speed with, and is bounded by
     * `MAX_DELTA` giving up in favour of a full walk.
     *
     * @param array<string> $changed
     *
     * @return array{0:array<Individual>,1:array<string>}
     */
    private function expand(Tree $tree, array $changed): array
    {
        /** @var array<string,Individual> $people */
        $people = [];
        /** @var array<string,true> $deleted */
        $deleted = [];

        foreach ($changed as $xref) {
            $record = Registry::gedcomRecordFactory()->make($xref, $tree);

            if (!$record instanceof GedcomRecord) {
                // Gone from the tree altogether. A client that never held it
                // — a note, a submitter — loses nothing by being told.
                $deleted[$xref] = true;
                continue;
            }

            if ($record instanceof Individual) {
                if ($record->canShow()) {
                    $people[$record->xref()] = $record;
                } else {
                    // Not "deleted" but, for one reader's copy of a tree,
                    // the same instruction: this record must not stay.
                    $deleted[$xref] = true;
                }
            }

            foreach ($this->linked_record_service->linkedIndividuals($record) as $individual) {
                $people[$individual->xref()] = $individual;
            }

            foreach ($this->linked_record_service->linkedFamilies($record) as $family) {
                foreach ($this->linked_record_service->linkedIndividuals($family) as $individual) {
                    $people[$individual->xref()] = $individual;
                }
            }
        }

        // A tombstone and a record for the same xref would be a contradiction
        // a client would have to break a tie on. Privacy filtering already
        // makes it impossible; this makes it impossible to introduce.
        $deleted = array_diff_key($deleted, $people);

        // Paging a delta means paging a set, so the order has to be the same
        // on every request. xref order is arbitrary and stable, which is all
        // a page boundary needs.
        ksort($people);
        ksort($deleted);

        return [array_values($people), array_keys($deleted)];
    }

    /**
     * @param array<Individual> $rows
     * @param array<string>     $deleted
     */
    private function page(
        SyncToken $token,
        int $offset,
        int $limit,
        int $total,
        bool $more,
        RecordComposer $composer,
        array $rows,
        array $deleted = [],
        string|null $since = null,
    ): ResponseInterface {
        return Json::ok([
            'token'    => $token->value(),
            'since'    => $since,
            'offset'   => $offset,
            'limit'    => $limit,
            'total'    => $total,
            'hasMore'  => $more,
            'resync'   => false,
            // Properties of the tree and the reader rather than of a person,
            // so they are stated once for the whole page.
            'sections' => $composer->sections(),
            'charts'   => $composer->charts(),
            'people'   => array_map($composer->compose(...), $rows),
            'deleted'  => $deleted,
        ]);
    }

    /**
     * Start again: this tree cannot describe a path from where the client is.
     *
     * Deliberately not an error status. Nothing is wrong — a tree was
     * re-imported, or the client has been away for thousands of edits — and a
     * `4xx` would send an app looking for a fault instead of running the walk
     * it already knows how to run.
     */
    private function resync(SyncToken $token, int $offset, int $limit): ResponseInterface
    {
        return Json::ok([
            'token'    => $token->value(),
            'offset'   => $offset,
            'limit'    => $limit,
            'total'    => $token->individuals(),
            'hasMore'  => false,
            'resync'   => true,
            'people'   => [],
            'deleted'  => [],
        ]);
    }
}
