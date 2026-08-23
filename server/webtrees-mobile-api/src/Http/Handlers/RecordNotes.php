<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Http\Handlers;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;
use WebtreesMobileApi\Http\Json;
use WebtreesMobileApi\Presenters\NotePresenter;
use WebtreesMobileApi\Support\RecordFacts;
use WebtreesMobileApi\Support\Request;

/**
 * The notes recorded against any record, and against its facts.
 *
 * Separate from `/individual/{xref}` so a client can fetch them for a record
 * that is not a person — a source, a media object — and so a person's page
 * stays one request when the site does not run the notes tab.
 */
final class RecordNotes implements RequestHandlerInterface
{
    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $record = Request::record($request);

        return Json::ok([
            'xref'  => $record->xref(),
            'notes' => NotePresenter::fromFacts(RecordFacts::matching($record, '/(?:^1|\n\d) NOTE/')),
        ]);
    }
}
