<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Throwable;
use WebtreesMobileApi\Http\ApiException;
use WebtreesMobileApi\Http\Json;

use function error_log;

/**
 * Turns anything thrown below it into the one error shape.
 *
 * This is the outermost middleware on every route, and it matters more than
 * it looks. webtrees' own error handling renders an HTML page, and its
 * authentication middleware answers `302` to the sign-in form — so without
 * this a client cannot tell "your session expired" from "that person does not
 * exist" from "the server broke", which is precisely the ambiguity a client
 * of a stock instance has to resolve by guesswork.
 */
final class JsonErrors implements MiddlewareInterface
{
    public function process(ServerRequestInterface $request, RequestHandlerInterface $handler): ResponseInterface
    {
        try {
            return $handler->handle($request);
        } catch (ApiException $exception) {
            return Json::error(
                $exception->status,
                $exception->error,
                $exception->getMessage(),
                $exception->detail,
            );
        } catch (Throwable $exception) {
            // The message may name a table, a file path or a query. It goes
            // to the server's log, and the client is told only that it broke.
            error_log('webtrees-mobile-api: ' . $exception);

            return Json::error(500, 'server_error', 'The server could not answer that request.');
        }
    }
}
