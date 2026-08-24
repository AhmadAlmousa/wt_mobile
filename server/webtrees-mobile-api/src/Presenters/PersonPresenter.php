<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Presenters;

use Fisharebest\Webtrees\Date;
use Fisharebest\Webtrees\Gedcom;
use Fisharebest\Webtrees\Individual;
use Fisharebest\Webtrees\MediaFile;
use WebtreesMobileApi\Compat\Compat;
use WebtreesMobileApi\Compat\CompatInterface;

use function preg_match_all;
use function strip_tags;

/**
 * A person as they appear in a list: enough to draw a row and open them.
 *
 * The same shape everywhere a person is mentioned — a search result, a
 * relative, a chart box, the far end of a relationship — because every screen
 * that shows one shows the same five things.
 *
 * Two fields exist because a stock instance cannot state them. `sex` is
 * rendered as a translated *word* on an individual page, so the app currently
 * has to recover it from that person's own chart box on the relatives tab;
 * and the autocomplete endpoint never states it at all. `deceased` is read
 * from `Individual::isDead()`, which is what webtrees itself uses, rather than
 * inferred from a birth year.
 */
final class PersonPresenter
{
    private readonly CompatInterface $compat;

    /**
     * @param int $thumbnail The longest edge of the portrait to sign a URL for.
     */
    public function __construct(private readonly int $thumbnail = 160)
    {
        $this->compat = Compat::current();
    }

    /**
     * @return array<string,mixed>
     */
    public function present(Individual $individual): array
    {
        return [
            'xref'          => $individual->xref(),
            // fullName() answers the site's word for "Private" when this
            // reader may not see the name, so a hidden person is still a row
            // rather than a gap - exactly as the website draws them.
            'name'          => Text::of($individual->fullName()),
            'alternateName' => $this->alternateName($individual),
            'sex'           => self::sexName($this->compat->sexCode($individual)),
            'deceased'      => $this->isDeceased($individual),
            'lifespan'      => $this->lifespan($individual),
            'birthYear'     => $this->year($individual->getBirthDate()),
            'deathYear'     => $this->year($individual->getDeathDate()),
            'birthPlace'    => $this->birthPlace($individual),
            'thumbnail'     => $this->thumbnailUrl($individual),
            'private'       => !$individual->canShow(),
        ];
    }

    /**
     * The year of a date, **in the calendar the record keeps it in**.
     *
     * `Date::minimumDate()` is the calendar date object webtrees itself
     * sorts and converts with, and its `year` is that calendar's own year —
     * 1318 for a Hijri record, 1901 for a Gregorian one. Deliberately not
     * converted to a common era: the HTML transport can only read the year
     * the page *printed*, which is this one, and a module that answered a
     * converted year would disagree with the floor about every Hijri record
     * in the tree.
     *
     * Zero means the date states no year at all — `Date('')` for a record
     * with no birth, and an event dated to a month with no year — which is
     * absence rather than the year nought.
     */
    private function year(Date $date): int|null
    {
        if (!$date->isOK()) {
            return null;
        }

        $year = $date->minimumDate()->year();

        return $year === 0 ? null : $year;
    }

    /**
     * Where the tree records the birth, shortened as the site shortens it.
     *
     * `Place::shortName()` is what `Individual::lifespan()` puts in the title
     * of the year it prints, which is the only place a stock instance states
     * a birthplace on a search result — so this is the same string, and the
     * two transports can be diffed on it.
     */
    private function birthPlace(Individual $individual): string|null
    {
        if (!$individual->canShow()) {
            return null;
        }

        return Text::orNull(strip_tags($individual->getBirthPlace()->shortName()));
    }

    /**
     * Whether the tree **records** this person as no longer living.
     *
     * Not `Individual::isDead()`, which also *infers* death from age — a
     * person born in 1850 with no death recorded is dead to webtrees and
     * unknown to a chart box, so the two transports disagreed about exactly
     * that. The contract the app documents is "the tree said so", because the
     * HTML path reads a death fact out of a chart box and can never know
     * anything else. False therefore means "nothing said so", not "alive".
     *
     * **All three death events, not just `DEAT`.** `Gedcom::DEATH_EVENTS` is
     * `DEAT`, `BURI`, `CREM` in both versions, and it is what a chart box
     * prints a tag for — so a man whose tree records his burial and no death
     * was mourned on one transport and living on the other (`PROJECT.md` §7,
     * bug 49). A burial is not an inference.
     */
    private function isDeceased(Individual $individual): bool
    {
        return $individual->facts(Gedcom::DEATH_EVENTS)->isNotEmpty();
    }

    /**
     * A second name form the tree records — a romanized name beside an Arabic
     * one, a married name beside a maiden one.
     *
     * **Not `GedcomRecord::alternateName()`**, which is narrower than it
     * looks: it answers only when the primary and secondary names differ by
     * *character set*, so a person recorded twice in the same script has none.
     * A real tree disagreed — a woman with two Arabic `NAME` lines, the second
     * with an unknown given name — where the HTML path read the second line
     * from the names accordion and this read null.
     *
     * **Nor every row of `getAllNames()`**, which is wider than it looks, and
     * the same real tree said so a second time.
     * `GedcomRecord::extractNamesFromFacts()` adds a row for every `ROMN`,
     * `FONE` and `_XXX` *subtag* of a name as well as for each `NAME` line —
     * so a woman with one name and a `2 _MARNM` under it has two rows, and
     * this answered a "second name" the website never shows as one. webtrees
     * renders those subtags as **fields inside** the name block
     * (`الإسم ما بعد الزواج: …`) and gives a `span.NAME` only to a name line,
     * which is exactly what the HTML transport counts.
     *
     * So the guard is the number of `NAME` lines. Counted off the record's
     * own GEDCOM because that names no access level and is identical in both
     * webtrees versions; the rows themselves still come from `getAllNames()`,
     * which is what applies the placeholders and the privacy.
     */
    private function alternateName(Individual $individual): string|null
    {
        if (!$individual->canShowName()) {
            return null;
        }

        if (preg_match_all('/^1 NAME /m', $individual->gedcom()) < 2) {
            return null;
        }

        $all     = $individual->getAllNames();
        $primary = $all[$individual->getPrimaryName()]['full'] ?? '';

        foreach ($all as $index => $name) {
            if ($index === $individual->getPrimaryName()) {
                continue;
            }

            if (($name['full'] ?? '') !== $primary) {
                return Text::orNull($name['full']);
            }
        }

        return null;
    }

    /**
     * A signed thumbnail URL for this person's highlighted photograph.
     *
     * Signed server-side, at whatever size was asked for. On a stock instance
     * the app can only harvest the 100-pixel URL the media tab happens to
     * emit, because the signature covers the dimensions and the key is not
     * the client's — which is the whole of that limitation.
     *
     * It is still not an authorization token: `MediaFileThumbnail` checks
     * `canShow()` for the current user before it validates the signature, and
     * picks watermarking from the same answer. It must be fetched through the
     * session.
     */
    private function thumbnailUrl(Individual $individual): string|null
    {
        $file = $individual->findHighlightedMediaFile();

        if (!$file instanceof MediaFile) {
            return null;
        }

        return $file->imageUrl($this->thumbnail, $this->thumbnail, 'contain');
    }

    /**
     * Birth and death years as webtrees writes them, e.g. `1901–1974`.
     *
     * Null rather than the site's own `…–…` when the tree records neither: a
     * dash between two ellipses is not information, and every row would
     * carry one.
     */
    private function lifespan(Individual $individual): string|null
    {
        if (!$individual->getBirthDate()->isOK() && !$individual->getDeathDate()->isOK()) {
            return null;
        }

        return Text::orNull($individual->lifespan());
    }

    /**
     * The GEDCOM sex letter as a word a client can switch on.
     */
    public static function sexName(string $code): string
    {
        return match ($code) {
            'M'     => 'male',
            'F'     => 'female',
            'X'     => 'other',
            default => 'unknown',
        };
    }
}
