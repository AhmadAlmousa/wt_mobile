<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Middleware;

use Fisharebest\Webtrees\Auth;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Http\ApiException;

/**
 * Refuses an anonymous request, as JSON and never as a redirect.
 *
 * Applied only where the answer is *about the account* — `/access`. Tree data
 * is left to webtrees' own privacy rules, so a public tree stays as readable
 * through the API as it is through the website, and a private one is invisible
 * because `TreeService::all()` never binds it.
 */
final class RequireSignIn implements MiddlewareInterface
{
    public function process(ServerRequestInterface $request, RequestHandlerInterface $handler): ResponseInterface
    {
        if (!Auth::check()) {
            throw ApiException::notSignedIn();
        }

        return $handler->handle($request);
    }
}
