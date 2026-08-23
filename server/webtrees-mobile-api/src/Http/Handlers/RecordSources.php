<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Http\Json;
use WebtreesMobileApi\Presenters\SourcePresenter;
use WebtreesMobileApi\Support\RecordFacts;
use WebtreesMobileApi\Support\Request;

/**
 * The source citations behind any record's facts.
 */
final class RecordSources implements RequestHandlerInterface
{
    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $record = Request::record($request);

        return Json::ok([
            'xref'    => $record->xref(),
            'sources' => SourcePresenter::fromFacts(RecordFacts::matching($record, '/(?:^1|\n\d) SOUR/')),
        ]);
    }
}
