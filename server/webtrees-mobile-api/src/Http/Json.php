<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http;

use Fisharebest\Webtrees\Registry;
use Psr\Http\Message\ResponseFactoryInterface;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\StreamFactoryInterface;

use function json_encode;

use const JSON_INVALID_UTF8_SUBSTITUTE;
use const JSON_UNESCAPED_SLASHES;
use const JSON_UNESCAPED_UNICODE;

/**
 * Builds every response this module sends.
 *
 * Deliberately built from the **PSR-17** factories rather than from
 * `Registry::responseFactory()`: webtrees' own response factory takes an
 * `int` status in 2.2.x and an `HttpStatusCode` enum in 2.3, and going
 * straight to PSR-17 keeps one more type out of the compat surface.
 */
final class Json
{
    /**
     * webtrees renders Arabic, and escaping it to `\uXXXX` would triple the
     * size of every payload this app exists to carry. Slashes are left alone
     * so a signed media URL reads as one.
     */
    private const int FLAGS = JSON_UNESCAPED_UNICODE
        | JSON_UNESCAPED_SLASHES
        | JSON_INVALID_UTF8_SUBSTITUTE;

    /**
     * @param array<string,mixed> $payload
     */
    public static function ok(array $payload, int $status = 200): ResponseInterface
    {
        $responses = Registry::container()->get(ResponseFactoryInterface::class);
        $streams   = Registry::container()->get(StreamFactoryInterface::class);

        $body = json_encode($payload, self::FLAGS);

        if ($body === false) {
            $body   = '{"error":"server_error","message":"Could not encode the response.","detail":null}';
            $status = 500;
        }

        return $responses
            ->createResponse($status)
            ->withHeader('content-type', 'application/json; charset=UTF-8')
            // A record is privacy-filtered per user and per session; a shared
            // cache holding one reader's answer for another is a data leak.
            ->withHeader('cache-control', 'private, no-store')
            ->withBody($streams->createStream($body));
    }

    public static function error(
        int $status,
        string $error,
        string $message,
        string|null $detail = null,
    ): ResponseInterface {
        return self::ok(
            ['error' => $error, 'message' => $message, 'detail' => $detail],
            $status,
        );
    }
}
