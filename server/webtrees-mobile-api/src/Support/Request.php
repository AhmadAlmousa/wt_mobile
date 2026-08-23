<?php

declare(strict_types=1);

namespace WebtreesMobileApi\Support;

use Fisharebest\Webtrees\GedcomRecord;
use Fisharebest\Webtrees\Individual;
use Fisharebest\Webtrees\Registry;
use Fisharebest\Webtrees\Tree;
use Fisharebest\Webtrees\Validator;
use Psr\Http\Message\ServerRequestInterface;
use WebtreesMobileApi\Http\ApiException;

use function max;
use function min;

/**
 * Reads and validates everything that arrives in a URL.
 *
 * Every parameter is bounded before it is used, and an unusable one is a
 * `400` naming itself rather than a stack trace or a silently-clamped value
 * the caller never learns about.
 */
final class Request
{
    /** A page of results this large is already more than a phone can show. */
    public const int MAX_PAGE_SIZE = 200;

    /** webtrees' own charts stop here; asking for more is a denial of service. */
    public const int MAX_GENERATIONS = 10;

    /** How many alternative relationship paths to look for. */
    public const int MAX_RECURSION = 10;

    /** Signed image dimensions a client may ask for. */
    public const int MIN_IMAGE = 16;
    public const int MAX_IMAGE = 2000;

    /**
     * The tree this route names.
     *
     * `{tree}` binds through `TreeService::all()`, which already hides trees
     * this user may not see — so a private tree simply fails to bind, and the
     * answer is the same `404` the website gives. That is what keeps the app's
     * existing "an anonymous 404 proves a private tree" reasoning true.
     */
    public static function tree(ServerRequestInterface $request): Tree
    {
        $tree = Validator::attributes($request)->treeOptional();

        if (!$tree instanceof Tree) {
            throw ApiException::notFound('No such family tree.');
        }

        return $tree;
    }

    public static function individual(ServerRequestInterface $request, string $parameter = 'xref'): Individual
    {
        $tree = self::tree($request);
        $xref = self::xref($request, $parameter);

        $individual = Registry::individualFactory()->make($xref, $tree);

        // `canShow()` is webtrees' own answer for this reader. A record they
        // may not see is absent rather than empty: inventing a placeholder
        // would tell them something the privacy rules just refused to.
        if (!$individual instanceof Individual || !$individual->canShow()) {
            throw ApiException::notFound('No such individual.');
        }

        return $individual;
    }

    public static function record(ServerRequestInterface $request, string $parameter = 'xref'): GedcomRecord
    {
        $tree = self::tree($request);
        $xref = self::xref($request, $parameter);

        $record = Registry::gedcomRecordFactory()->make($xref, $tree);

        if (!$record instanceof GedcomRecord || !$record->canShow()) {
            throw ApiException::notFound('No such record.');
        }

        return $record;
    }

    public static function xref(ServerRequestInterface $request, string $parameter = 'xref'): string
    {
        $xref = Validator::attributes($request)->string($parameter, '');

        if ($xref === '') {
            throw ApiException::invalidParameter('A record identifier is required.', $parameter);
        }

        return $xref;
    }

    public static function offset(ServerRequestInterface $request): int
    {
        $offset = Validator::queryParams($request)->integer('offset', 0);

        if ($offset < 0) {
            throw ApiException::invalidParameter('The offset cannot be negative.', 'offset');
        }

        return $offset;
    }

    public static function limit(ServerRequestInterface $request, int $default = 50): int
    {
        $limit = Validator::queryParams($request)->integer('limit', $default);

        if ($limit < 1) {
            throw ApiException::invalidParameter('The limit must be at least one.', 'limit');
        }

        return min($limit, self::MAX_PAGE_SIZE);
    }

    public static function generations(ServerRequestInterface $request, int $default = 4): int
    {
        $generations = Validator::queryParams($request)->integer('generations', $default);

        return min(max($generations, 1), self::MAX_GENERATIONS);
    }

    public static function thumbnail(ServerRequestInterface $request, int $default = 160): int
    {
        $size = Validator::queryParams($request)->integer('thumb', $default);

        return min(max($size, self::MIN_IMAGE), self::MAX_IMAGE);
    }

    public static function image(ServerRequestInterface $request, string $parameter, int $default): int
    {
        $size = Validator::queryParams($request)->integer($parameter, $default);

        return min(max($size, self::MIN_IMAGE), self::MAX_IMAGE);
    }

    /**
     * How an image should be fitted into the box asked for.
     *
     * The same two words Glide and `MediaFile::imageUrl()` use.
     */
    public static function fit(ServerRequestInterface $request): string
    {
        $fit = Validator::queryParams($request)->string('fit', 'contain');

        if ($fit !== 'contain' && $fit !== 'crop') {
            throw ApiException::invalidParameter('Fit must be "contain" or "crop".', 'fit');
        }

        return $fit;
    }
}
