<?php

declare(strict_types=1);

namespace WebtreesMobileApi;

use Fisharebest\Webtrees\I18N;
use Fisharebest\Webtrees\Module\AbstractModule;
use Fisharebest\Webtrees\Module\ModuleCustomInterface;
use Fisharebest\Webtrees\Module\ModuleCustomTrait;
use WebtreesMobileApi\Compat\Compat;
use WebtreesMobileApi\Http\Handlers\Access;
use WebtreesMobileApi\Http\Handlers\Ancestors;
use WebtreesMobileApi\Http\Handlers\Capabilities;
use WebtreesMobileApi\Http\Handlers\Descendants;
use WebtreesMobileApi\Http\Handlers\FamilyRecord;
use WebtreesMobileApi\Http\Handlers\IndividualRecord;
use WebtreesMobileApi\Http\Handlers\Individuals;
use WebtreesMobileApi\Http\Handlers\MediaRecord;
use WebtreesMobileApi\Http\Handlers\RecordNotes;
use WebtreesMobileApi\Http\Handlers\RecordSources;
use WebtreesMobileApi\Http\Handlers\Relationship;
use WebtreesMobileApi\Http\Handlers\Statistics;
use WebtreesMobileApi\Http\Handlers\Timeline;
use WebtreesMobileApi\Http\Middleware\JsonErrors;
use WebtreesMobileApi\Http\Middleware\NegotiateLanguage;
use WebtreesMobileApi\Http\Middleware\RequireSignIn;

/**
 * A read-only JSON API for the webtrees_mobile client.
 *
 * **Optional, and permanently so.** The app it serves works against an
 * untouched webtrees instance by reading HTML, and every capability this
 * module adds keeps that path. What the module changes is the cost and the
 * honesty of the answer: privacy, translated labels, structured names, real
 * pagination, signed media at any size, per-request language and typed
 * statistics are all public API *inside* webtrees, and none of them survive
 * being rendered to a page and read back.
 *
 * Three rules the code holds to:
 *
 * 1. **The module presents; webtrees decides.** No privacy, no access level
 *    and no genealogy is reimplemented here. `canShow()`, `canShowName()`,
 *    `facts()` and `TreeService::all()` are called as the real signed-in
 *    reader, and whatever survives is what is sent.
 * 2. **Every payload carries both halves.** What webtrees *rendered* — the
 *    translated label, the formatted date, the place name — and what it
 *    *means* — the bare GEDCOM tag, the calendar escape, the Julian day, the
 *    xref. A client draws the first and reasons about the second.
 * 3. **No version outside `Compat/`.** PSR-15 handlers are version-neutral in
 *    2.2.x and 2.3; nine differences are not, and they all live in one folder.
 */
class WebtreesMobileApi extends AbstractModule implements ModuleCustomInterface
{
    use ModuleCustomTrait;

    /**
     * The wire contract. Bumped only for a breaking change; anything additive
     * is announced through `capabilities.features` instead, so an old client
     * and a new module degrade per capability rather than per release.
     */
    public const int API_VERSION = 1;

    public const string MODULE_VERSION = '1.0.0';

    public const string AUTHOR = 'webtrees_mobile';

    public const string SUPPORT_URL = 'https://github.com/webtrees-mobile/webtrees-mobile-api';

    /** Site-wide endpoints. */
    private const string BASE = '/mobile-api/v1';

    /** Tree-scoped endpoints. */
    private const string TREE_BASE = '/tree/{tree}/mobile-api/v1';

    /**
     * What this module answers. A client reads it from `/capabilities` and
     * uses only what it finds, so an older module and a newer app still
     * agree about everything they both implement.
     */
    public const array FEATURES = [
        'access',
        'individuals',
        'individual',
        'family',
        'ancestors',
        'descendants',
        'relationship',
        'timeline',
        'statistics',
        'media',
        'notes',
        'sources',
    ];

    public function title(): string
    {
        return I18N::translate('Mobile API');
    }

    public function description(): string
    {
        return I18N::translate('A read-only JSON interface for the webtrees mobile app.');
    }

    public function customModuleAuthorName(): string
    {
        return self::AUTHOR;
    }

    public function customModuleVersion(): string
    {
        return self::MODULE_VERSION;
    }

    public function customModuleSupportUrl(): string
    {
        return self::SUPPORT_URL;
    }

    public function resourcesFolder(): string
    {
        return __DIR__ . '/../resources/';
    }

    /**
     * Register every route.
     *
     * **GET only.** `Router` injects `CheckCsrf` unconditionally and its
     * `EXCLUDE_ROUTES` is a `private const` a module cannot extend, so a
     * write endpoint would have to carry a session token the app has no
     * reason to hold. Read-only endpoints sidestep the question entirely,
     * and v1 is read-only anyway.
     *
     * `JsonErrors` is outermost on every route: without it an expired session
     * is a `302` to the sign-in *page* and a missing record is an HTML error,
     * which is exactly the ambiguity this interface exists to remove.
     */
    public function boot(): void
    {
        $compat = Compat::current();

        $public = [JsonErrors::class, NegotiateLanguage::class];
        $secure = [JsonErrors::class, NegotiateLanguage::class, RequireSignIn::class];

        // Anonymous and cheap, so a client can ask what it is talking to
        // before it signs in.
        $compat->addRoute(self::BASE . '/capabilities', Capabilities::class, $public);
        $compat->addRoute(self::BASE . '/access', Access::class, $secure);

        // Tree-scoped. `{tree}` binds through `TreeService::all()`, so a tree
        // this reader may not see never reaches the handler at all.
        $compat->addRoute(self::TREE_BASE . '/individuals', Individuals::class, $public);
        $compat->addRoute(self::TREE_BASE . '/individual/{xref}', IndividualRecord::class, $public);
        $compat->addRoute(self::TREE_BASE . '/family/{xref}', FamilyRecord::class, $public);
        $compat->addRoute(self::TREE_BASE . '/ancestors/{xref}', Ancestors::class, $public);
        $compat->addRoute(self::TREE_BASE . '/descendants/{xref}', Descendants::class, $public);
        $compat->addRoute(self::TREE_BASE . '/relationship/{xref}/{xref2}', Relationship::class, $public);
        $compat->addRoute(self::TREE_BASE . '/timeline/{xref}', Timeline::class, $public);
        $compat->addRoute(self::TREE_BASE . '/statistics', Statistics::class, $public);
        $compat->addRoute(self::TREE_BASE . '/media/{xref}', MediaRecord::class, $public);
        $compat->addRoute(self::TREE_BASE . '/record/{xref}/notes', RecordNotes::class, $public);
        $compat->addRoute(self::TREE_BASE . '/record/{xref}/sources', RecordSources::class, $public);
    }
}
