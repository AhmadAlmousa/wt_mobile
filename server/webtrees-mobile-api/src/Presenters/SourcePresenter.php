<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Presenters;

use Fisharebest\Webtrees\Fact;
use Fisharebest\Webtrees\Gedcom;
use Fisharebest\Webtrees\Registry;
use Fisharebest\Webtrees\Source;
use Fisharebest\Webtrees\Tree;

use function array_slice;
use function explode;
use function implode;
use function preg_match;
use function preg_match_all;
use function preg_replace;
use function str_ends_with;
use function strtr;

use const PREG_SET_ORDER;

/**
 * Which source a fact came from, and where in it to look.
 *
 * A citation's own fields — page, quality, the date the record was made —
 * arrive as whole sentences the site has already worded and translated,
 * separator included (`%1$s: %2$s`). Splitting them into a pair for a client
 * to rejoin would mean guessing at punctuation webtrees has already chosen,
 * and it chooses differently per language.
 */
final class SourcePresenter
{
    /**
     * @param iterable<Fact> $facts
     *
     * @return array<array<string,mixed>>
     */
    public static function fromFacts(iterable $facts): array
    {
        $citations = [];

        foreach ($facts as $fact) {
            if (str_ends_with($fact->tag(), ':SOUR')) {
                $citations[] = self::entry($fact, $fact->gedcom(), false);
                continue;
            }

            // A citation hanging off a fact rather than off the record: the
            // level-2 block and everything under it.
            preg_match_all('/\n(2 SOUR\b.*(?:\n[^2].*)*)/', $fact->gedcom(), $matches, PREG_SET_ORDER);

            foreach ($matches as $match) {
                $citations[] = self::entry($fact, $match[1], true);
            }
        }

        return $citations;
    }

    /**
     * @return array<string,mixed>
     */
    private static function entry(Fact $fact, string $gedcom, bool $secondary): array
    {
        $tree = $fact->record()->tree();

        $xref  = null;
        $title = '';

        if (preg_match('/^\d SOUR @(' . Gedcom::REGEX_XREF . ')@/m', $gedcom, $match) === 1) {
            $source = Registry::sourceFactory()->make($match[1], $tree);

            if ($source instanceof Source && $source->canShow()) {
                $xref  = $match[1];
                $title = Text::of($source->fullName());
            }
        }

        return [
            'label'     => Text::of($fact->label()),
            'title'     => $title,
            'xref'      => $xref,
            'details'   => self::fields($gedcom, $fact->tag(), $tree),
            'secondary' => $secondary,
            'pending'   => FactPresenter::pending($fact),
        ];
    }

    /**
     * The citation's subordinate lines, each worded by the element that owns
     * its tag — `Page: 42`, with the site's own separator between the two.
     *
     * This is `fact-gedcom-fields.phtml` without the markup: walk the level
     * numbers to build each line's qualified tag, ask the element factory for
     * that tag, and let it say the line.
     *
     * @return array<string>
     */
    private static function fields(string $gedcom, string $parent, Tree $tree): array
    {
        $hierarchy = explode(':', $parent);

        // Merge CONT lines onto the line they continue, as webtrees does, and
        // put the newlines back before the element renders them.
        $gedcom = (string) preg_replace('/\n\d CONT ?/', "\r", $gedcom);

        preg_match_all('/^(\d+) (\w+) ?(.*)/m', $gedcom, $matches);
        [, $levels, $tags, $values] = $matches;

        $lines = [];

        foreach ($values as $key => $value) {
            $level = (int) $levels[$key];

            $hierarchy[$level] = $tags[$key];
            $full_tag          = implode(':', array_slice($hierarchy, 0, 1 + $level));

            // Line zero is the pointer to the source itself, already presented
            // as `title` and `xref` rather than repeated as a field.
            if ($key === 0 || $value === '') {
                continue;
            }

            $element = Registry::elementFactory()->make($full_tag);
            $line    = Text::of($element->labelValue(strtr($value, ["\r" => "\n"]), $tree));

            if ($line !== '') {
                $lines[] = $line;
            }
        }

        return $lines;
    }
}
