<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Fisharebest\Webtrees\Date\GregorianDate;
use Fisharebest\Webtrees\Fact;
use Fisharebest\Webtrees\Individual;
use Fisharebest\Webtrees\Registry;
use Fisharebest\Webtrees\Validator;
use Illuminate\Support\Collection;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Compat\Compat;
use WebtreesMobileApi\Http\Json;
use WebtreesMobileApi\Presenters\DatePresenter;
use WebtreesMobileApi\Presenters\FactPresenter;
use WebtreesMobileApi\Presenters\PersonPresenter;
use WebtreesMobileApi\Presenters\Text;
use WebtreesMobileApi\Support\Request;

use function array_filter;
use function array_map;
use function array_values;
use function explode;
use function implode;
use function in_array;
use function max;
use function min;
use function trim;

/**
 * A life against a scale of years.
 *
 * webtrees draws this by positioning every event box and every year label in
 * pixels, so a client reading HTML compares one position with another and is
 * careful never to read a year *out of* a position — the box sits a few
 * pixels above the line it points at, so the arithmetic comes out a year
 * short.
 *
 * Here every event states its own Julian day and the scale states its own
 * range, so a client places the events itself and the pixels belong to
 * whichever screen is drawing them.
 *
 * The events are the ones webtrees itself puts on a timeline: the person's
 * facts and their families' facts, minus the administrative tags in
 * `TimelineChartModule::NON_FACTS`, and only those with a usable date.
 */
final class Timeline implements RequestHandlerInterface
{
    /** Tags webtrees keeps off a timeline: edit logs, ordinances, to-dos. */
    private const array NON_FACTS = [
        'FAM:CHAN',
        'INDI:BAPL',
        'INDI:CHAN',
        'INDI:ENDL',
        'INDI:SLGC',
        'INDI:SLGS',
        'INDI:_TODO',
    ];

    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $tree    = Request::tree($request);
        $subject = Request::individual($request);
        $people  = new PersonPresenter(Request::thumbnail($request));
        $facts   = new FactPresenter($people, new DatePresenter($tree));

        $individuals = [$subject];

        // Several lives against one scale — what the lifespans chart is for.
        foreach (explode(',', Validator::queryParams($request)->string('with', '')) as $xref) {
            $other = Registry::individualFactory()->make(trim($xref), $tree);

            if ($other instanceof Individual && $other->canShow() && $other->xref() !== $subject->xref()) {
                $individuals[] = $other;
            }
        }

        $collected = new Collection();

        foreach ($individuals as $individual) {
            foreach ($this->factsOf($individual) as $fact) {
                $collected->push($fact);
            }
        }

        // A marriage belongs to both spouses, so asking for a couple would
        // otherwise put it on the scale twice.
        $collected = $collected->uniqueStrict(static fn (Fact $fact): string => $fact->record()->xref() . ':' . $fact->id());

        $events   = [];
        $earliest = null;
        $latest   = null;

        foreach (Compat::current()->sortFacts($collected) as $fact) {
            $date = $fact->date();
            $day  = $date->minimumJulianDay();

            $earliest = $earliest === null ? $day : min($earliest, $day);
            $latest   = $latest === null ? $date->maximumJulianDay() : max($latest, $date->maximumJulianDay());

            $events[] = $facts->present($fact, FactPresenter::SELF, null) + [
                // The site's own one-line summary of the event, composed the
                // way `timeline-chart/chart.phtml` composes it — label, date,
                // value, place, joined with webtrees' own separator. A client
                // draws one box per event and needs one string for it; the
                // structured fields above it are there for everything else.
                'summary'   => $this->summary($fact),
                'julianDay' => $day,
                // The Gregorian year, for a scale. Never the year to *show*:
                // the fact's own date carries that, written by the server in
                // whichever calendars this tree converts to.
                'year'      => (new GregorianDate($day))->year(),
            ];
        }

        return Json::ok([
            'subject' => $people->present($subject),
            'people'  => array_map($people->present(...), $individuals),
            'range'   => [
                'fromJulianDay' => $earliest,
                'toJulianDay'   => $latest,
                'fromYear'      => $earliest === null ? null : (new GregorianDate($earliest))->year(),
                'toYear'        => $latest === null ? null : (new GregorianDate($latest))->year(),
            ],
            'events'  => $events,
        ]);
    }

    /**
     * `Label — 12 March 1901 — Kuwait`, in the site's words and punctuation.
     */
    private function summary(Fact $fact): string
    {
        $parts = [Text::of($fact->label())];

        if ($fact->date()->isOK()) {
            $parts[] = Text::of($fact->date()->display());
        }

        $value = Text::orNull($fact->value());

        if ($value !== null && $value !== 'CLOSE_RELATIVE') {
            $parts[] = $value;
        }

        if ($fact->place()->gedcomName() !== '') {
            $parts[] = Text::of($fact->place()->shortName());
        }

        return implode(' — ', $parts);
    }

    /**
     * @return array<Fact>
     */
    private function factsOf(Individual $individual): array
    {
        $facts = [];

        foreach ($individual->facts() as $fact) {
            $facts[] = $fact;
        }

        foreach ($individual->spouseFamilies() as $family) {
            foreach ($family->facts() as $fact) {
                $facts[] = $fact;
            }
        }

        return array_values(array_filter($facts, static fn (Fact $fact): bool =>
            !in_array($fact->tag(), self::NON_FACTS, true) && $fact->date()->isOK()));
    }
}
