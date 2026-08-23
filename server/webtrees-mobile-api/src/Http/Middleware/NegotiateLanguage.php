<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Middleware;

use Fisharebest\Webtrees\I18N;
use Fisharebest\Webtrees\Services\ModuleService;
use Fisharebest\Webtrees\Validator;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Compat\Compat;

use function explode;
use function str_contains;
use function strcasecmp;
use function strtok;
use function trim;

/**
 * Renders this one request in the language the client asked for.
 *
 * The whole point of doing it here. webtrees' global `UseLanguage` middleware
 * consults `Accept-Language` **only** when the session holds no language, and
 * `Login::doLogin()` seeds the session from the account's stored preference —
 * so after signing in there is no stock way to ask for a different language
 * except `POST /language/{tag}`, which `SelectLanguage` writes into *both* the
 * session and the account's own preference. Reading a tree in English on a
 * phone should not change the language the website greets that person with.
 *
 * Module route middleware runs inside `Router`, i.e. after `UseLanguage`, so
 * `I18N::init()` here rebinds the translations for this request and nothing
 * else. Nothing is written to the session or to the user.
 */
final class NegotiateLanguage implements MiddlewareInterface
{
    public function __construct(private readonly ModuleService $module_service)
    {
    }

    public function process(ServerRequestInterface $request, RequestHandlerInterface $handler): ResponseInterface
    {
        $available = Compat::current()->languageTags($this->module_service);

        $wanted = Validator::queryParams($request)->string('lang', '');

        if ($wanted === '') {
            $wanted = $request->getHeaderLine('accept-language');
        }

        $tag = $this->choose($wanted, $available);

        if ($tag !== null) {
            I18N::init($tag);
        }

        return $handler->handle($request);
    }

    /**
     * The first offered language this site can actually render.
     *
     * `en-GB` and `en` are different modules in webtrees, so an exact match is
     * tried for every candidate before any is widened to its primary subtag.
     * Quality values are parsed off but not ordered by: a client that cares
     * which language it gets should send `?lang=`, and one that does not is
     * better served by its first choice than by arithmetic.
     *
     * @param array<string> $available
     */
    private function choose(string $header, array $available): string|null
    {
        if ($header === '') {
            return null;
        }

        $candidates = [];

        foreach (explode(',', $header) as $part) {
            $tag = trim((string) strtok(trim($part), ';'));

            if ($tag !== '' && $tag !== '*') {
                $candidates[] = $tag;
            }
        }

        foreach ($candidates as $candidate) {
            foreach ($available as $tag) {
                if (strcasecmp($tag, $candidate) === 0) {
                    return $tag;
                }
            }
        }

        foreach ($candidates as $candidate) {
            $primary = str_contains($candidate, '-') ? explode('-', $candidate)[0] : $candidate;

            foreach ($available as $tag) {
                if (strcasecmp($tag, $primary) === 0) {
                    return $tag;
                }
            }

            // `ar` should still find `ar-EG` if that is all the site runs.
            foreach ($available as $tag) {
                if (strcasecmp(explode('-', $tag)[0], $primary) === 0) {
                    return $tag;
                }
            }
        }

        return null;
    }
}
