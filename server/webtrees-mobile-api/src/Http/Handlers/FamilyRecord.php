<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Fisharebest\Webtrees\Family;
use Fisharebest\Webtrees\Registry;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Http\ApiException;
use WebtreesMobileApi\Http\Json;
use WebtreesMobileApi\Presenters\DatePresenter;
use WebtreesMobileApi\Presenters\FactPresenter;
use WebtreesMobileApi\Presenters\FamilyPresenter;
use WebtreesMobileApi\Presenters\PersonPresenter;
use WebtreesMobileApi\Support\Request;

/**
 * A family in its own right — the couple, their children, and what happened.
 *
 * New. A client reading HTML only ever sees a family folded into one of its
 * members' pages, so a marriage is shown against whichever spouse was opened
 * and a family with no living member on screen has nowhere to appear at all.
 */
final class FamilyRecord implements RequestHandlerInterface
{
    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $tree = Request::tree($request);
        $xref = Request::xref($request);

        $family = Registry::familyFactory()->make($xref, $tree);

        if (!$family instanceof Family || !$family->canShow()) {
            throw ApiException::notFound('No such family.');
        }

        $people = new PersonPresenter(Request::thumbnail($request));
        $facts  = new FactPresenter($people, new DatePresenter($tree));

        return Json::ok((new FamilyPresenter($people, $facts))
            ->present($family, FamilyPresenter::OWN));
    }
}
