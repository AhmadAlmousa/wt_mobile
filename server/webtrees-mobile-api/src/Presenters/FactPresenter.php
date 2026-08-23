<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Presenters;

use Fisharebest\Webtrees\Fact;
use Fisharebest\Webtrees\Family;
use Fisharebest\Webtrees\GedcomRecord;
use Fisharebest\Webtrees\Individual;
use Fisharebest\Webtrees\Registry;

use function explode;
use function in_array;
use function str_contains;

/**
 * One row of a record's facts table — a birth, a marriage, an occupation.
 *
 * Every fact carries **both halves**: what webtrees rendered (the translated
 * label, the formatted date and place, the enumerated value in words) and what
 * it means (the bare GEDCOM tag, the qualified tag, the calendar escape, the
 * xref of whoever it is really about). That duality is the whole contract. A
 * client that had only the words could not tell a death from an occupation in
 * Arabic; a client that had only the tags would have to invent the words.
 *
 * On a stock instance the tag is the hard half. Every label on a record page
 * is already translated, and the *only* structural statement a page makes
 * about what kind of event a row is comes from the `fact_DEAT` classes inside
 * chart boxes — so the app has to build a label→tag dictionary out of the
 * boxes a page happened to render, and a fact whose tag no box printed stays
 * untyped. Here nothing is untyped.
 */
final class FactPresenter
{
    /**
     * A fact folded into a person's list from somewhere else.
     *
     * The five values are the five methods of `IndividualFactsService`, and
     * they are strictly more than the boolean the markup offers: webtrees
     * marks the last three `collapse` in `fact.phtml` and says nothing more.
     */
    public const string SELF      = 'self';
    public const string FAMILY    = 'family';
    public const string RELATIVE  = 'relative';
    public const string ASSOCIATE = 'associate';
    public const string HISTORIC  = 'historic';

    /** The origins webtrees itself renders collapsed. */
    private const array SECONDARY = [self::RELATIVE, self::ASSOCIATE, self::HISTORIC];

    public function __construct(
        private readonly PersonPresenter $people,
        private readonly DatePresenter $dates,
    ) {
    }

    /**
     * @param GedcomRecord|null $subject Whose list this is, when it has one.
     *
     * @return array<string,mixed>
     */
    public function present(Fact $fact, string $origin, GedcomRecord|null $subject = null): array
    {
        $qualified = $fact->tag();
        $tag       = $this->bareTag($fact);
        $date      = $this->dates->present($fact->date());

        return [
            'tag'           => $tag,
            'qualifiedTag'  => $qualified,
            'label'         => Text::of($fact->label()),
            'origin'        => $origin,
            'secondary'     => in_array($origin, self::SECONDARY, true),
            'value'         => $this->value($fact),
            'type'          => Text::orNull($fact->attribute('TYPE')),
            'date'          => $date,
            'place'         => PlacePresenter::present($fact),
            'about'         => $this->about($fact, $subject),
            'pending'       => self::pending($fact),
        ];
    }

    /**
     * The bare GEDCOM word for this fact — `DEAT`, `DIV`, `OCCU`.
     *
     * `Fact::tag()` qualifies it with the record type, so a divorce is
     * `FAM:DIV`; the second segment is what a chart box would have printed
     * and what the app's own tag dictionary holds.
     *
     * A relative's event is the interesting case. `IndividualFactsService`
     * rewrites it to `1 EVEN CLOSE_RELATIVE / 2 TYPE Birth of a son` so the
     * page can label it in the reader's language — which throws the original
     * tag away. The fact still knows which record it came from and which fact
     * of that record it is, so the tag is looked back up rather than lost.
     */
    private function bareTag(Fact $fact): string
    {
        $parts = explode(':', $fact->tag());
        $tag   = $parts[1] ?? $parts[0];

        if ($tag !== 'EVEN' || $fact->value() !== 'CLOSE_RELATIVE') {
            return $tag;
        }

        foreach ($fact->record()->facts() as $original) {
            if ($original->id() === $fact->id() && $original->value() !== 'CLOSE_RELATIVE') {
                $parts = explode(':', $original->tag());

                return $parts[1] ?? $tag;
            }
        }

        return $tag;
    }

    /**
     * The fact's own value, in words, where it has one beyond a date and place.
     *
     * Enumerated values go through the element that owns the tag, so
     * `INDI:SEX` of `M` arrives as the site's word for male and `FAM:MARR:TYPE`
     * of `RELIGIOUS` as its word for a religious marriage. `CLOSE_RELATIVE` is
     * webtrees' own marker for a folded-in event and is not a value at all —
     * `fact.phtml` blanks it too.
     */
    private function value(Fact $fact): string|null
    {
        $value = $fact->value();

        if ($value === '' || $value === 'CLOSE_RELATIVE') {
            return null;
        }

        // A pointer is presented as `about`, not as a value.
        if (str_contains($value, '@') && $fact->target() !== null) {
            return null;
        }

        $element = Registry::elementFactory()->make($fact->tag());

        return Text::orNull($element->value($value, $fact->record()->tree()));
    }

    /**
     * Whose event this really is, when it is not the subject's own.
     *
     * `fact.phtml` renders exactly this as `.wt-fact-record` — the sibling
     * whose birth it was, the spouse a marriage was to. Without it, "Birth of
     * a brother" names an event and no brother, and the reader has no way to
     * walk to them.
     *
     * @return array<string,mixed>|null
     */
    private function about(Fact $fact, GedcomRecord|null $subject): array|null
    {
        $record = $fact->record();

        if ($subject !== null && $record->xref() === $subject->xref()) {
            return null;
        }

        if ($record instanceof Individual) {
            return $this->people->present($record);
        }

        // A family fact — a marriage, a divorce — is about the *other* spouse,
        // which is what the page names beside it. A family with one recorded
        // spouse names nobody, and neither does this.
        if ($record instanceof Family && $subject instanceof Individual) {
            $spouse = $record->spouse($subject);

            return $spouse instanceof Individual ? $this->people->present($spouse) : null;
        }

        return null;
    }

    private function aboutFamily(Fact $fact, GedcomRecord|null $subject): string|null
    {
        $record = $fact->record();

        if ($subject !== null && $record->xref() === $subject->xref()) {
            return null;
        }

        return $record instanceof Family ? $record->xref() : null;
    }

    /**
     * Whether this row is queued for approval, and which way.
     *
     * Worth a flag of its own: `fact.phtml` marks a pending deletion on the
     * table *row*, while the notes, sources and media tabs mark it on the
     * *cells* — an asymmetry that has already cost one reader a record shown
     * as current when it was queued for removal.
     */
    public static function pending(Fact|GedcomRecord $subject): string|null
    {
        if ($subject->isPendingAddition()) {
            return 'addition';
        }

        if ($subject->isPendingDeletion()) {
            return 'deletion';
        }

        return null;
    }
}
