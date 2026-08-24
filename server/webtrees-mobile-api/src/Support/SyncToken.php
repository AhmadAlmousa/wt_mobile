<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Support;

use Fisharebest\Webtrees\DB;
use Fisharebest\Webtrees\Tree;

use function count;
use function ctype_digit;
use function explode;
use function implode;

/**
 * A fingerprint of a tree, small enough to hand to a client and hand back.
 *
 * A client keeping a local copy of a tree needs one question answered: *what
 * has changed since the last time I asked?* webtrees answers it almost for
 * free — every edit writes a row into `change`, so the largest `change_id`
 * this tree has ever seen is an incrementing watermark, and a delta is
 * everything above it.
 *
 * Two things stop that being the whole story, and both were confirmed against
 * 2.2.6 and 2.3 rather than assumed:
 *
 * - **An import writes no change rows and deletes the ones there were.** The
 *   loader truncates `change` for the tree before it reads the first record
 *   (`GedcomLoad`, both versions, and `TreeImport` on the command line), so a
 *   re-imported tree has a *lower* watermark than the client's. A watermark
 *   that moves backwards is therefore the exact signal for "throw your copy
 *   away", which is why the fingerprint keeps the number rather than hiding
 *   it behind a hash.
 * - **So the watermark alone cannot see an import at all.** A tree imported
 *   twice sits at nought both times. The record counts are what notice: if
 *   the watermark has not moved and the counts have, something changed
 *   without writing a row, and the only honest answer is a full walk.
 *
 * What it still cannot see, stated because a client cannot work it out: a
 * re-import of a *modified* file with the **same** number of individuals and
 * families and no edits since. There the fingerprint is unchanged and the
 * delta is empty. The counts are what `sync_eval.md` §12 asks for and they
 * are cheap — both tables are indexed by tree — where a content digest is a
 * full scan of every record on every sync. A client that offers "sync again
 * from scratch" covers the case; nothing the server can cheaply say does.
 *
 * The value is **opaque to a client**: store it, send it back, compare it for
 * equality, and read nothing out of it. The shape is readable so that a
 * person debugging a sync can see what it says.
 */
final class SyncToken
{
    /**
     * How many changed records a delta will describe before it gives up.
     *
     * Expansion — which individuals a changed note or family touches — is
     * recomputed for every page of a delta, so a client that has been away
     * long enough for thousands of edits is cheaper to answer with a full
     * walk than with a delta it pages through. Where that is the case the
     * answer is `resync`, which is honest rather than slow.
     */
    public const int MAX_DELTA = 2000;

    private const string PREFIX = 'v1';

    private function __construct(
        private readonly int $change,
        private readonly int $individuals,
        private readonly int $families,
    ) {
    }

    /**
     * The tree as it stands now.
     */
    public static function of(Tree $tree): self
    {
        return new self(
            (int) DB::table('change')
                ->where('gedcom_id', '=', $tree->id())
                ->max('change_id'),
            DB::table('individuals')->where('i_file', '=', $tree->id())->count(),
            DB::table('families')->where('f_file', '=', $tree->id())->count(),
        );
    }

    /**
     * A token a client sent back, or null for anything unreadable.
     *
     * Unreadable includes a token this module never minted — a client
     * upgraded across a change of shape, a truncated string, a value someone
     * typed. All of them mean the same thing to the caller: the client's copy
     * cannot be trusted, so it should be replaced.
     */
    public static function parse(string $value): self|null
    {
        $parts = explode('.', $value);

        if (count($parts) !== 4 || $parts[0] !== self::PREFIX) {
            return null;
        }

        foreach ([$parts[1], $parts[2], $parts[3]] as $number) {
            if ($number === '' || !ctype_digit($number)) {
                return null;
            }
        }

        return new self((int) $parts[1], (int) $parts[2], (int) $parts[3]);
    }

    public function value(): string
    {
        return implode('.', [self::PREFIX, $this->change, $this->individuals, $this->families]);
    }

    /**
     * The largest `change_id` this tree had when the token was minted.
     */
    public function changeId(): int
    {
        return $this->change;
    }

    /**
     * How many individuals the tree holds — **before** privacy.
     *
     * `individuals` is a count of records, and a reader may not see all of
     * them, so this is an upper bound on what a walk will hand over rather
     * than a promise. It is the same number the site's own statistics page
     * publishes, and it is stated because a progress bar needs a denominator
     * before the last page arrives; `hasMore` is the exact statement.
     */
    public function individuals(): int
    {
        return $this->individuals;
    }

    /**
     * Whether a delta from `$earlier` to here can be honestly computed.
     *
     * False in the two cases this class exists to notice: the watermark went
     * backwards, and the counts moved while the watermark stood still.
     */
    public function follows(self $earlier): bool
    {
        if ($earlier->change > $this->change) {
            return false;
        }

        if ($earlier->change === $this->change) {
            return $earlier->individuals === $this->individuals
                && $earlier->families === $this->families;
        }

        return true;
    }

    /**
     * Every xref this tree has recorded a change against since `$earlier`.
     *
     * Any status. A `pending` row belongs to an edit this reader may not be
     * shown, and a `rejected` one to a record that reverted — in both cases
     * re-sending the record as it now stands is either necessary or
     * harmlessly identical, and a status filter would only make the rule
     * longer.
     *
     * @return array<string>
     */
    public static function changedSince(Tree $tree, self $earlier): array
    {
        return DB::table('change')
            ->where('gedcom_id', '=', $tree->id())
            ->where('change_id', '>', $earlier->change)
            ->distinct()
            ->orderBy('xref')
            ->limit(self::MAX_DELTA + 1)
            ->pluck('xref')
            ->all();
    }
}
