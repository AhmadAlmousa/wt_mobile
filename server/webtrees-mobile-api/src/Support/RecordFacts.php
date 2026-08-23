<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Support;

use Fisharebest\Webtrees\Fact;
use Fisharebest\Webtrees\GedcomRecord;
use Fisharebest\Webtrees\Individual;

use function array_filter;
use function array_values;
use function preg_match;

/**
 * The facts a tab would gather for one record.
 *
 * The notes, sources and media tabs each build the same set: the record's own
 * facts, plus the facts of every family it is a spouse in — because a note may
 * hang off a marriage as easily as off a birth, and it belongs to both people.
 */
final class RecordFacts
{
    /**
     * @return array<Fact>
     */
    public static function matching(GedcomRecord $record, string $pattern): array
    {
        $facts = [];

        foreach ($record->facts() as $fact) {
            $facts[] = $fact;
        }

        if ($record instanceof Individual) {
            foreach ($record->spouseFamilies() as $family) {
                if ($family->canShow()) {
                    foreach ($family->facts() as $fact) {
                        $facts[] = $fact;
                    }
                }
            }
        }

        return array_values(array_filter(
            $facts,
            static fn (Fact $fact): bool => preg_match($pattern, $fact->gedcom()) === 1,
        ));
    }
}
