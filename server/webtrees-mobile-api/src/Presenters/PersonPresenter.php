<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Presenters;

use Fisharebest\Webtrees\Individual;
use Fisharebest\Webtrees\MediaFile;
use WebtreesMobileApi\Compat\Compat;
use WebtreesMobileApi\Compat\CompatInterface;

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
            'thumbnail'     => $this->thumbnailUrl($individual),
            'private'       => !$individual->canShow(),
        ];
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
     */
    private function isDeceased(Individual $individual): bool
    {
        return $individual->facts(['DEAT'])->isNotEmpty();
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
     * The accordion's reading is the right one: it is what the tree actually
     * records, and it is what the two transports have to agree on.
     */
    private function alternateName(Individual $individual): string|null
    {
        if (!$individual->canShowName()) {
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
