<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Presenters;

use Fisharebest\Webtrees\Fact;
use Fisharebest\Webtrees\Gedcom;
use Fisharebest\Webtrees\GedcomRecord;
use Fisharebest\Webtrees\Note;
use Fisharebest\Webtrees\Registry;

use function preg_match;
use function preg_match_all;
use function preg_replace;
use function str_ends_with;
use function trim;

use const PREG_SET_ORDER;

/**
 * Notes recorded against a record, and against its facts.
 *
 * webtrees keeps both in one tab and collapses the second kind, so the
 * distinction is kept rather than flattened: a note about the person and a
 * note about their birth are different things to a reader.
 *
 * A *shared* note is a record several people may cite and has an xref; a plain
 * one is text inside this record and has none. Both arrive here as text, with
 * `CONT` lines rejoined, because that is what the tab shows.
 */
final class NotePresenter
{
    /**
     * @param iterable<Fact> $facts
     *
     * @return array<array<string,mixed>>
     */
    public static function fromFacts(iterable $facts): array
    {
        $notes = [];

        foreach ($facts as $fact) {
            if (str_ends_with($fact->tag(), ':NOTE')) {
                $notes[] = self::entry($fact, $fact->label(), $fact->value(), false);
                continue;
            }

            // Level-two notes: a note hanging off a fact rather than off the
            // record. Their heading is *that fact's* label.
            preg_match_all("/\n[1-9] NOTE ?(.*(?:\n\d CONT.*)*)/", $fact->gedcom(), $matches, PREG_SET_ORDER);

            foreach ($matches as $match) {
                $notes[] = self::entry($fact, $fact->label(), $match[1], true);
            }
        }

        return $notes;
    }

    /**
     * @return array<string,mixed>
     */
    private static function entry(Fact $fact, string $label, string $value, bool $secondary): array
    {
        $text = trim((string) preg_replace('/\n\d CONT ?/', "\n", $value));
        $xref = null;

        if (preg_match('/^@(' . Gedcom::REGEX_XREF . ')@$/', $text, $match) === 1) {
            $note = Registry::noteFactory()->make($match[1], $fact->record()->tree());
            $xref = $match[1];
            $text = $note instanceof Note && $note->canShow() ? $note->getNote() : '';
        }

        return [
            'label'     => Text::of($label),
            'text'      => $text,
            'xref'      => $xref,
            'secondary' => $secondary,
            'about'     => self::about($fact->record()),
            'pending'   => FactPresenter::pending($fact),
        ];
    }

    /**
     * @return array<string,string>
     */
    private static function about(GedcomRecord $record): array
    {
        return ['xref' => $record->xref(), 'tag' => $record->tag()];
    }
}
