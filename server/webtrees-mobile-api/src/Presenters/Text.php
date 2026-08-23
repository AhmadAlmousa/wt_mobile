<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Presenters;

use function html_entity_decode;
use function preg_replace;
use function strip_tags;
use function trim;

use const ENT_HTML5;
use const ENT_QUOTES;

/**
 * webtrees renders for a browser; this module answers a client that draws its
 * own interface.
 *
 * Everything human-readable in a payload has been through here. The *words*
 * stay exactly as the site wrote them — translated, in its own numerals, with
 * its own punctuation — and only the markup around them is dropped. Nothing
 * here rewrites, re-formats or re-orders anything.
 */
final class Text
{
    /**
     * Markup out, words and entities intact.
     */
    public static function of(string $html): string
    {
        $text = html_entity_decode(strip_tags($html), ENT_QUOTES | ENT_HTML5, 'UTF-8');

        // Removing an element can leave the whitespace that surrounded it.
        return trim((string) preg_replace('/[ \t]+/', ' ', $text));
    }

    /**
     * As [of], but an empty result is an absent one.
     */
    public static function orNull(string|null $html): string|null
    {
        if ($html === null) {
            return null;
        }

        $text = self::of($html);

        return $text === '' ? null : $text;
    }
}
