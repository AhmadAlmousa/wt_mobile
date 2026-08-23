<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Fisharebest\Webtrees\Media;
use Fisharebest\Webtrees\Registry;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Http\ApiException;
use WebtreesMobileApi\Http\Json;
use WebtreesMobileApi\Presenters\MediaPresenter;
use WebtreesMobileApi\Support\Request;

/**
 * One media object, signed at whatever size the screen wants.
 *
 * The 100-pixel ceiling a client reading HTML lives under is a property of the
 * media *tab*, not of webtrees: `MediaFile::imageUrl()` will sign any
 * dimensions, but the signature covers them and the key is the server's, so
 * only the server can mint a bigger one.
 *
 * The bytes still come back through the ordinary authenticated request — this
 * endpoint hands over a URL, not an image — so nothing about how a client
 * caches or displays photographs has to change.
 */
final class MediaRecord implements RequestHandlerInterface
{
    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $tree = Request::tree($request);
        $xref = Request::xref($request);

        $media = Registry::mediaFactory()->make($xref, $tree);

        if (!$media instanceof Media || !$media->canShow()) {
            throw ApiException::notFound('No such media object.');
        }

        $width  = Request::image($request, 'w', 800);
        $height = Request::image($request, 'h', $width);

        return Json::ok((new MediaPresenter($width, $height, Request::fit($request)))->present($media));
    }
}
