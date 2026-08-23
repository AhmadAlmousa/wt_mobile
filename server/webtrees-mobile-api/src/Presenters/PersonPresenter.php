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
            'alternateName' => Text::orNull($individual->alternateName()),
            'sex'           => self::sexName($this->compat->sexCode($individual)),
            'deceased'      => $individual->isDead(),
            'lifespan'      => $this->lifespan($individual),
            'thumbnail'     => $this->thumbnailUrl($individual),
            'private'       => !$individual->canShow(),
        ];
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
