<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Presenters;

use Fisharebest\Webtrees\Fact;

/**
 * Where something happened.
 *
 * `full` and `short` are both the site's own renderings: `short` honours the
 * tree's `SHOW_PEDIGREE_PLACES` setting for how many parts of a hierarchy to
 * print and from which end, which is a manager's choice a client should not
 * be second-guessing. `gedcom` is the raw hierarchy for anything that needs to
 * compare two places rather than show one.
 */
final class PlacePresenter
{
    /**
     * @return array<string,mixed>|null
     */
    public static function present(Fact $fact): array|null
    {
        $place = $fact->place();

        if ($place->gedcomName() === '') {
            return null;
        }

        return [
            'full'      => Text::of($place->fullName()),
            'short'     => Text::of($place->shortName()),
            'gedcom'    => $place->gedcomName(),
            // PLAC:MAP:LATI / LONG, where the tree records them. Enough for a
            // place screen, and eventually for the map chart v1 declined.
            'latitude'  => $fact->latitude(),
            'longitude' => $fact->longitude(),
        ];
    }
}
