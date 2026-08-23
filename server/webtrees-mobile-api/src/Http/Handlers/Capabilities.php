<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Fisharebest\Webtrees\Services\ModuleService;
use Fisharebest\Webtrees\Webtrees;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Compat\Compat;
use WebtreesMobileApi\Http\Json;
use WebtreesMobileApi\Support\Request;
use WebtreesMobileApi\WebtreesMobileApi;

/**
 * What this installation can answer — asked before signing in.
 *
 * The one endpoint that must never require anything. A client probes it at
 * connect time and then selects **per capability**, not globally: a site
 * running an older module still gets the fast path for whatever it does
 * implement, and a newer client asking for something this module has never
 * heard of simply does not ask.
 */
final class Capabilities implements RequestHandlerInterface
{
    public function __construct(private readonly ModuleService $module_service)
    {
    }

    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $compat = Compat::current();

        return Json::ok([
            'api'        => WebtreesMobileApi::API_VERSION,
            'module'     => WebtreesMobileApi::MODULE_VERSION,
            'webtrees'   => Webtrees::VERSION,
            // Which compat adapter answered. Worth stating: the version string
            // above is a number a distribution can patch, and this is the
            // behaviour actually in force.
            'generation' => $compat->generation(),
            // v1 rides the webtrees session the client already holds. Adding
            // per-user device tokens later adds a word here rather than a
            // release.
            'auth'       => ['session'],
            'features'   => WebtreesMobileApi::FEATURES,
            'limits'     => [
                'maxPageSize'    => Request::MAX_PAGE_SIZE,
                'maxGenerations' => Request::MAX_GENERATIONS,
                'maxRecursion'   => Request::MAX_RECURSION,
                'maxImage'       => Request::MAX_IMAGE,
            ],
            // So a client can offer only the languages this site runs, and
            // send one of them in `?lang=` without writing the account's
            // stored preference the way `POST /language/{tag}` does.
            'languages'  => $compat->languageTags($this->module_service),
        ]);
    }
}
