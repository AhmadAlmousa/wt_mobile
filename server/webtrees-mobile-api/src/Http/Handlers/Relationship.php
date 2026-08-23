<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Fisharebest\Webtrees\Family;
use Fisharebest\Webtrees\GedcomRecord;
use Fisharebest\Webtrees\I18N;
use Fisharebest\Webtrees\Individual;
use Fisharebest\Webtrees\Registry;
use Fisharebest\Webtrees\Services\RelationshipService;
use Fisharebest\Webtrees\Tree;
use Fisharebest\Webtrees\Validator;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Http\Json;
use WebtreesMobileApi\Presenters\PersonPresenter;
use WebtreesMobileApi\Presenters\Text;
use WebtreesMobileApi\Support\RelationshipFinder;
use WebtreesMobileApi\Support\Request;

use function count;
use function max;
use function min;

/**
 * How two people are related, along every path the site can find.
 *
 * webtrees answers this as a grid of absolutely-positioned table cells with
 * the lines drawn in background images — a shape that says nothing on a
 * phone, and which a client can only read by walking cell coordinates. Here
 * the path is a path.
 *
 * **The wording is still the site's.** `RelationshipService::nameFromPath()`
 * is public, so `أخ أكبر` stays webtrees' word and not the module's
 * invention — which matters because Arabic separates an older brother from a
 * younger one and English has no word for the difference.
 *
 * `settings` is echoed back deliberately. A site configured for blood lines
 * only — as `RELATIONSHIP_ANCESTORS` makes it — answers "no relationship" for
 * two people linked by a marriage, and that is a *correct* answer that looks
 * exactly like a failure unless the client can say why.
 */
final class Relationship implements RequestHandlerInterface
{
    /** webtrees' own default: effectively unlimited, clamped below. */
    private const string DEFAULT_RECURSION = '99';

    public function __construct(
        private readonly RelationshipService $relationship_service,
        private readonly RelationshipFinder $finder,
    ) {
    }

    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $tree = Request::tree($request);
        $from = Request::individual($request);
        $to   = Request::individual($request, 'xref2');

        // The tree's own default, which the website's form is filled in with.
        $ancestors = Validator::queryParams($request)
            ->integer('ancestors', (int) $tree->getPreference('RELATIONSHIP_ANCESTORS', '0'));

        // Zero is what the website's own form offers first — "find the
        // closest relationships" — and it is the cheap answer. A client that
        // wants the others asks for them.
        $asked = Validator::queryParams($request)->integer('recursion', 0);

        // Recursion is what stops a deep search costing the server a minute,
        // so the tree's ceiling is honoured exactly as the website honours it.
        $ceiling = (int) $tree->getPreference('RELATIONSHIP_RECURSION', self::DEFAULT_RECURSION);
        $recursion = min(max($asked, 0), max($ceiling, 0), Request::MAX_RECURSION);

        $people = new PersonPresenter(Request::thumbnail($request));
        $paths  = [];

        foreach ($this->finder->paths($from, $to, $recursion, $ancestors !== 0) as $path) {
            $nodes = $this->nodes($path, $tree);

            if ($nodes === []) {
                continue;
            }

            $paths[] = $this->path($nodes, $people);
        }

        return Json::ok([
            'from'     => $people->present($from),
            'to'       => $people->present($to),
            'settings' => [
                'ancestors'         => $ancestors,
                'recursion'         => $asked,
                'clampedRecursion'  => $recursion,
                // Says, in the site's own words, that this instance searches
                // blood lines only - the difference between "no link" and
                // "no link this site will look for".
                'bloodLinesOnly'    => $ancestors !== 0,
            ],
            'paths'    => $paths,
        ]);
    }

    /**
     * A path of xrefs turned into the records it names.
     *
     * Alternating individual, family, individual — the shape
     * `nameFromPath()` expects. A path with a record this reader may not see
     * is dropped rather than shown with a hole in it.
     *
     * @param array<string> $path
     *
     * @return array<GedcomRecord>
     */
    private function nodes(array $path, Tree $tree): array
    {
        $nodes = [];

        foreach ($path as $index => $xref) {
            $record = $index % 2 === 0
                ? Registry::individualFactory()->make($xref, $tree)
                : Registry::familyFactory()->make($xref, $tree);

            if (!$record instanceof GedcomRecord || !$record->canShow()) {
                return [];
            }

            $nodes[] = $record;
        }

        return $nodes;
    }

    /**
     * @param array<GedcomRecord> $nodes
     *
     * @return array<string,mixed>
     */
    private function path(array $nodes, PersonPresenter $people): array
    {
        $language = I18N::language();
        $steps    = [];

        // Each step is named by the three nodes around it, exactly as the
        // chart labels the cell between two boxes.
        for ($n = 1; $n + 1 < count($nodes); $n += 2) {
            $person = $nodes[$n + 1];
            $family = $nodes[$n];

            $steps[] = [
                'relationship' => Text::of($this->relationship_service->nameFromPath(
                    [$nodes[$n - 1], $family, $person],
                    $language,
                )),
                'person'       => $person instanceof Individual ? $people->present($person) : null,
                'via'          => ['family' => $family instanceof Family ? $family->xref() : null],
            ];
        }

        return [
            // The whole relationship as one phrase, which no client should
            // try to compose from the steps.
            'description' => Text::of($this->relationship_service->nameFromPath($nodes, $language)),
            'steps'       => $steps,
        ];
    }
}
