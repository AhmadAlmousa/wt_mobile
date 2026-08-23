<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Presenters;

use Fisharebest\Webtrees\Date;
use Fisharebest\Webtrees\Tree;
use WebtreesMobileApi\Compat\Compat;
use WebtreesMobileApi\Compat\CompatInterface;

use function array_slice;
use function array_values;
use function explode;
use function html_entity_decode;
use function preg_replace;
use function strip_tags;
use function trim;

use const ENT_HTML5;
use const ENT_QUOTES;

/**
 * A date, kept structured enough for a client to show one calendar.
 *
 * Every payload carries both halves of what webtrees knows: the **rendered**
 * string in each calendar on offer — the site's own month names, numerals and
 * qualifier words — and the **machine-readable** GEDCOM value, calendar escape
 * and Julian-day bounds beside them. A client should never parse the first or
 * display the second.
 *
 * This is also where the module quietly outperforms the website. webtrees 2.3
 * puts its whole calendar-conversion block inside `if ($this->date2 !== null)`
 * (`app/Date.php`), so an ordinary single date loses its conversion on the
 * page. Converting from `convertToCalendar()` here is not affected, and the
 * same payload comes out of 2.2.x and 2.3.
 */
final class DatePresenter
{
    /** Escape → the name a client keys on. */
    private const array CALENDARS = [
        '@#DGREGORIAN@' => 'gregorian',
        '@#DJULIAN@'    => 'julian',
        '@#DHEBREW@'    => 'jewish',
        '@#DFRENCH R@'  => 'french',
        '@#DHIJRI@'     => 'hijri',
        '@#DJALALI@'    => 'jalali',
        '@#DROMAN@'     => 'roman',
    ];

    private readonly CompatInterface $compat;

    public function __construct(private readonly Tree $tree)
    {
        $this->compat = Compat::current();
    }

    /**
     * @return array<string,mixed>|null Null when the record holds no usable date.
     */
    public function present(Date $date): array|null
    {
        if (!$date->isOK()) {
            return null;
        }

        $native = $this->render($date);

        if ($native === '') {
            return null;
        }

        [$qualifier] = $this->compat->dateQualifiers($date);

        $escape   = $this->compat->calendarEscape($date->minimumDate());
        $rendered = [$this->entry($escape, $native)];
        $bare     = [$native];

        foreach ($this->conversions($date, $escape, $native) as $conversion) {
            $rendered[] = $conversion['entry'];
            $bare[]     = $conversion['bare'];
        }

        return [
            'gedcom'    => $this->gedcom($date),
            // What the site itself would print: the native rendering with its
            // conversions after it, in webtrees' own parentheses.
            'text'      => $this->compose($bare),
            'qualifier' => $qualifier === '' ? null : $qualifier,
            'julianDay' => [$date->minimumJulianDay(), $date->maximumJulianDay()],
            'rendered'  => $rendered,
        ];
    }

    /**
     * The date written back as GEDCOM, in the calendar the tree records it in.
     *
     * @param array<string>|null $escapes Override the calendar of each part.
     */
    public function gedcom(Date $date, array|null $escapes = null): string
    {
        [$qualifier1, $qualifier2] = $this->compat->dateQualifiers($date);

        $minimum = $date->minimumDate();
        $maximum = $date->maximumDate();

        $first  = $escapes === null ? $this->compat->gedcomOf($minimum) : $escapes[0];
        $second = $escapes === null ? $this->compat->gedcomOf($maximum) : $escapes[1];

        // A single date has no second half; `maximumDate()` answers the first
        // one again, and repeating it would invent a range.
        if ($qualifier2 === '') {
            return $this->squash($qualifier1 . ' ' . $first);
        }

        return $this->squash($qualifier1 . ' ' . $first . ' ' . $qualifier2 . ' ' . $second);
    }

    /**
     * The same date in every other calendar this tree converts to.
     *
     * The tree's `CALENDAR_FORMAT` is a manager-level preference, and honouring
     * it is the point: the module presents what webtrees decided, it does not
     * decide for itself which calendars a site publishes.
     *
     * @return array<array<string,mixed>>
     */
    private function conversions(Date $date, string $native_escape, string $native_text): array
    {
        $format = $this->tree->getPreference('CALENDAR_FORMAT');

        $conversions = [];

        foreach (explode('_and_', $format) as $calendar) {
            if ($calendar === 'none' || $calendar === '') {
                continue;
            }

            $converted = $this->convert($date, $calendar);

            if ($converted === null) {
                continue;
            }

            [$escape, $text, $bare] = $converted;

            // webtrees converts regardless of calendar and shows the result
            // only when it differs — which is what stops a year-only date
            // being printed twice between Julian and Gregorian.
            if ($escape === $native_escape || $text === '' || $text === $native_text) {
                continue;
            }

            $conversions[$escape] = [
                'entry' => $this->entry($escape, $text),
                // Without the qualifier. `Date::display()` renders a
                // conversion by formatting the converted *date* and leaving
                // the surrounding words to the original, so an `ABT 1875`
                // reads "about 1875 (1292)" and never "about 1875 (about
                // 1292)". The full form above is what a reader asking for
                // Hijri *alone* should see, so both are kept.
                'bare'  => $bare,
            ];
        }

        return array_values($conversions);
    }

    /**
     * @return array{0:string,1:string,2:string}|null Escape, rendering, and
     *                                                the rendering without
     *                                                the date's qualifier.
     */
    private function convert(Date $date, string $calendar): array|null
    {
        $minimum = $date->minimumDate()->convertToCalendar($calendar);
        $maximum = $date->maximumDate()->convertToCalendar($calendar);

        if (!$minimum->inValidRange() || !$maximum->inValidRange()) {
            return null;
        }

        // Recomposing GEDCOM and re-parsing it is what makes this work on both
        // versions: 2.2.x renders a converted date with
        // `AbstractCalendarDate::format()`, which 2.3 deleted, but both render
        // a whole `Date` in the reader's own language.
        $gedcom = $this->gedcom($date, [
            $this->compat->gedcomOf($minimum),
            $this->compat->gedcomOf($maximum),
        ]);

        return [
            $this->compat->calendarEscape($minimum),
            $this->render(new Date($gedcom)),
            $this->render(new Date($this->compat->gedcomOf($minimum))),
        ];
    }

    /**
     * @return array<string,string>
     */
    private function entry(string $escape, string $text): array
    {
        return [
            'calendar' => self::CALENDARS[$escape] ?? 'unknown',
            'escape'   => $escape,
            'text'     => $text,
        ];
    }

    /**
     * One string holding every calendar, the way webtrees prints them.
     *
     * @param array<string> $parts The native rendering, then each conversion
     *                             without its qualifier.
     */
    private function compose(array $parts): string
    {
        $text = $parts[0];

        foreach (array_slice($parts, 1) as $conversion) {
            $text .= ' (' . $conversion . ')';
        }

        return $text;
    }

    /**
     * webtrees' own rendering of a date, as text.
     *
     * `display()` is asked for no tree and no conversion, so it produces the
     * date and nothing else — no calendar links, no second calendar, and in
     * 2.2.x no `<span class="date">` once the tags come off.
     */
    private function render(Date $date): string
    {
        $html = $date->display(null, null, false);

        return trim(html_entity_decode(strip_tags($html), ENT_QUOTES | ENT_HTML5, 'UTF-8'));
    }

    private function squash(string $text): string
    {
        return trim((string) preg_replace('/\s+/', ' ', $text));
    }
}
