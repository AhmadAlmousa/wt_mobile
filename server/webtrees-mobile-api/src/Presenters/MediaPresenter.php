<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Presenters;

use Fisharebest\Webtrees\Fact;
use Fisharebest\Webtrees\Gedcom;
use Fisharebest\Webtrees\Media;
use Fisharebest\Webtrees\MediaFile;
use Fisharebest\Webtrees\Registry;
use Fisharebest\Webtrees\Tree;

use function preg_match_all;
use function str_ends_with;

use const PREG_SET_ORDER;

/**
 * Photographs and other media objects.
 *
 * The module signs the URL and the client fetches the bytes, which is why
 * `AuthenticatedImage` and `MediaCache` stay exactly as they are. What changes
 * is the **size**: `MediaFile::imageUrl()` signs any dimensions asked for,
 * where a stock client can only harvest whatever the media tab happened to
 * emit — 100 pixels — because the signature covers the dimensions and the
 * signing key is the server's.
 *
 * A signed URL is still not an authorization token. `MediaFileThumbnail`
 * checks `canShow()` for the current user *before* it validates the signature
 * and picks watermarking from the same answer, so the URL must be fetched
 * through the session that asked for it.
 */
final class MediaPresenter
{
    public function __construct(
        private readonly int $width = 800,
        private readonly int $height = 800,
        private readonly string $fit = 'contain',
    ) {
    }

    /**
     * @return array<string,mixed>
     */
    public function present(Media $media): array
    {
        $files = [];

        foreach ($media->mediaFiles() as $file) {
            $files[] = $this->file($file);
        }

        return [
            'xref'    => $media->xref(),
            'title'   => Text::of($media->fullName()),
            'note'    => Text::orNull($media->getNote()),
            'files'   => $files,
            'pending' => FactPresenter::pending($media),
        ];
    }

    /**
     * @return array<string,mixed>
     */
    private function file(MediaFile $file): array
    {
        $image = $file->isImage() && !$file->isExternal();

        return [
            'title'    => Text::orNull($file->title()),
            'format'   => $file->format(),
            'mimeType' => $file->mimeType(),
            'isImage'  => $image,
            'width'    => $image ? $this->width : null,
            'height'   => $image ? $this->height : null,
            'fit'      => $image ? $this->fit : null,
            'url'      => $image ? $file->imageUrl($this->width, $this->height, $this->fit) : null,
            // The original bytes, at whatever size they were uploaded.
            'download' => $file->isExternal() ? null : $file->downloadUrl('inline'),
        ];
    }

    /**
     * The media objects a record's facts point at.
     *
     * Mirrors the media tab: an `OBJE` recorded against the record itself, and
     * one hanging off a fact. The second kind is what the tab collapses, and
     * the distinction is kept rather than flattened.
     *
     * @param iterable<Fact> $facts
     *
     * @return array<array<string,mixed>>
     */
    public function fromFacts(iterable $facts, Tree $tree): array
    {
        $items = [];
        $seen  = [];

        foreach ($facts as $fact) {
            $secondary = !str_ends_with($fact->tag(), ':OBJE');

            preg_match_all(
                '/\n\d OBJE @(' . Gedcom::REGEX_XREF . ')@/',
                "\n" . $fact->gedcom(),
                $matches,
                PREG_SET_ORDER,
            );

            foreach ($matches as $match) {
                $media = Registry::mediaFactory()->make($match[1], $tree);

                if (!$media instanceof Media || !$media->canShow()) {
                    continue;
                }

                // The same photograph is often cited against several facts.
                $key = $match[1] . ':' . ($secondary ? '2' : '1');

                if (isset($seen[$key])) {
                    continue;
                }

                $seen[$key] = true;

                $items[] = $this->present($media) + [
                    'label'     => Text::of($fact->label()),
                    'secondary' => $secondary,
                ];
            }
        }

        return $items;
    }
}
