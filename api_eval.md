# A purpose-built API for `webtrees_mobile`

**An architectural evaluation. No code was changed to produce it.**

The app is functionally complete through Phase 7c and reads *everything* by
parsing HTML. This document asks whether a server-side module should replace
or supplement that, whether the existing `webtrees-API` module can be the
foundation, and — if not — exactly what to build instead.

It is written to be the technical design basis for that implementation, so
every claim below names the file that proves it. Paths beginning `app/` or
`resources/` are in `../webtrees` (working tree = **2.3.0-dev**, tag **2.2.6**
available); paths beginning `src/` are in `../webtrees-API`; the rest are in
this repository.

**Decisions taken with the user before this was written**

| Question | Answer |
|---|---|
| Distribution | **Private now, public later** — design for public release, ship privately |
| webtrees versions | **2.2.x and 2.3**, matching the app's existing fixture matrix |

---

## 1. Summary and recommendation

**Build a new, separate module. Do not extend `webtrees-API`. Adopt it as a
capability-negotiated fast path beside the stock HTML transport, never as a
replacement for it.**

Three findings drive that, and each is developed below.

1. **`webtrees-API` cannot be extended into this.** The mismatch is
   structural, not a matter of missing endpoints: one OAuth2 grant (client
   credentials), one technical user for every request, GEDCOM payloads, no
   pagination, and it does not boot on 2.3 for two independent reasons (§5).
   Extending it means rewriting auth, transport and payload — everything
   except the module skeleton.
2. **A new module's version-compatibility surface is genuinely small.** 2.3's
   `InvokeController` short-circuits to `RequestHandlerInterface::handle()`,
   which is *all* 2.2.6's `RequestHandler` ever did — so every handler written
   as PSR-15 is version-neutral. Only route registration and five type changes
   need an adapter (§6).
3. **The hard parts are already solved inside webtrees, and calling them is
   free.** Privacy, translated labels, structured names, real pagination,
   signed media URLs at any size, per-request language and typed statistics all
   exist as public APIs (§4). The module's job is presentation, not genealogy.

Adopting the module closes eight of the seventeen open risks in `PROJECT.md`
§9 — 1, 3, 5, 6, 7, 14, 15, 16 — and removes the cause of nine of the
twenty-seven bugs in §7.

It must remain optional. `PROJECT.md`'s first constraint is that the app works
against an untouched instance; the stock transport is the floor and stays.

---

## 2. How the app obtains and parses data today

| Concern | Route(s) | Read by |
|---|---|---|
| URL style, health, version | `/ping`, `/` | `data/instance_probe.dart` |
| Sign-in, keep-alive, sign-out | `GET`/`POST /login`, `/my-account`, `POST /logout` | `data/session.dart` |
| Trees, roles, account, own xref | `/my-account`, `/admin`, `/tree/{t}/changes-log`, `/pending`, `/autocomplete/place`, anonymous `/tree/{t}` | `data/access_probe.dart` |
| Search | `/tree/{t}/tom-select-individual?at=&query=&page=` | `records_repository.search` |
| A person | `/tree/{t}/individual/{xref}` (+ tab fragments) | `data/stock/record_parser.dart` |
| Fact meanings | the same page's `chart-box` markup | `data/stock/fact_tags.dart` |
| Charts | `…/ancestors-…`, `…/descendants-…`, `…/relationships-…`, `…/timeline`, all `?ajax=1` | `data/stock/chart_parser.dart` |
| Statistics | statistics tabs + `<script>` `statistics.draw*Chart(…)` | `data/stock/statistics_parser.dart` |
| Photographs | HMAC-signed thumbnail URLs harvested from markup | `authenticated_image.dart`, `media_cache.dart` |

Exactly **one** stock route answers JSON, and it is an autocomplete endpoint:
`AbstractTomSelectHandler` (`app/Http/Controllers/AbstractTomSelectHandler.php`)
returns an empty collection unless `query` is non-empty, so it searches and
cannot enumerate. `app/Http/Routes/ApiRoutes.php` is an empty placeholder in
both versions.

### What that costs

**In code.** 2,168 lines of parsing in `lib/data/stock/`:

| File | Lines |
|---|---|
| `record_parser.dart` | 727 |
| `chart_parser.dart` | 431 |
| `statistics_parser.dart` | 212 |
| `fact_tags.dart` | 177 |
| `chart_box.dart` | 99 |
| `dom.dart` | 79 |
| the HTML-specific halves of `records_repository.dart` (409) and `charts_repository.dart` (263) | ~440 |

Behind it, ~1,700 lines of parser tests (`record_parser_test` 502,
`charts_repository_test` 509, `records_repository_test` 461, `chart_parser_test`
331, `statistics_parser_test` 130, `fact_tags_test` 114) and a 212 KB
two-version fixture matrix that has to be maintained for *every* markup detail
the app depends on.

**In requests.** The access screen alone is `4 + 3·N` for `N` trees
(`/my-account`, `/admin`, tree discovery, then per tree: the tree page, up to
three ladder probes, one anonymous probe). A statistics page is one request per
tab. A chart is one request that returns a full desktop layout.

**In correctness.** Nine of the twenty-seven bugs in §7 are markup-coupling
bugs — 13, 16, 17, 19, 20, 23, 24, 26, 27 — and the §9 risks that remain open
are dominated by "we have never seen this markup from a real server".

---

## 3. What an API can retire, and what it cannot

**Retired outright:** facts and their labels; the primary/secondary split;
relatives and family blocks; marriage and divorce; notes; source citations;
media lists; names and alternate names; sex, lifespan and death; the
`FactTagIndex` chart-box dictionary; calendar-link reading; the access-probe
ladder; search paging and its duplicate-name dedupe; ancestor, descendant and
timeline structure; relationship paths; statistics counts and datasets; and the
slug `301` dance (`records_repository._fetchRecord`).

**Kept regardless of any module:**

- **URL-style detection and sign-in.** Both must happen before the module can
  be asked anything, and the module cannot change either.
- **The bad-bot User-Agent rule.** `BadBotBlocker` sits in the global stack
  (`app/Webtrees.php:154`) *before* `Router`, so it applies to module routes
  exactly as it does to pages. `kUserAgent` and `BotListCheck` stay.
- **Image bytes.** The module can mint a signed URL, but fetching it still runs
  `MediaFileThumbnail`, which checks `$media->canShow()` for the current user
  and picks watermarking from it. `AuthenticatedImage` and `MediaCache` stay.
- **Bidi, calendar choice, typography, layout.** These are the app's, not the
  server's, and the module makes them easier rather than unnecessary.

---

## 4. webtrees internals worth reusing

The recurring theme: the module presents; webtrees decides.

### Privacy is free — if the module runs as the real user

Everything routes through four public methods, each taking an access level that
defaults to the current user's:

- `GedcomRecord::canShow()` — `app/GedcomRecord.php:186`
- `GedcomRecord::canShowName()` — `:204`
- `GedcomRecord::facts($filter, $sort, $access_level)` — `:514`, which filters
  by `Fact::canShow()` per row
- `GedcomRecord::canShowByType()` — `:791`, reading `Tree::getFactPrivacy()`

`Auth::accessLevel(Tree)` (`app/Auth.php:104`) resolves Manager / Member /
Public from the user's stored `PREF_TREE_ROLE`. Above that, a `{tree}` route
parameter is resolved through `TreeService::all()`
(`app/Services/TreeService.php:73`), which already excludes trees the user may
not see — in **both** versions, in the `Router` middleware.

So a module that authenticates as the real person inherits webtrees' privacy
model exactly, including relationship-based privacy and per-fact restrictions.
**No privacy logic is reimplemented, and none should be.**

### Search with real pagination — and enumeration

`SearchService::searchIndividualNames(array $trees, array $search, int $offset,
int $limit)` (`app/Services/SearchService.php:190`).

Two properties matter enormously:

1. `whereSearch()` (`:1034`) applies **no** filter for an empty term array. So
   the same method enumerates a whole tree ordered by `n_sort` — the thing
   `PROJECT.md` §2 records as impossible on a stock instance, and the reason
   v1 is search-driven rather than browsable.
2. `paginateQuery()` (`:996`) dedupes multi-name rows across the *whole* cursor
   (`containsStrict`) and applies `canShow()` **before** counting down the
   offset. That fixes both halves of the app's paging trap in one move: the
   `nextUrl` that drops its query, and the person recorded under two names
   appearing on two pages.

Caveat to design around: the walk is `O(offset)` — it is a PHP cursor, not a
SQL `LIMIT`. Deep pages get progressively more expensive, which argues for
surname-partitioned browsing rather than an infinite scroll to row 5,000.

### Fact classification, already exactly the app's model

`IndividualFactsService` (`app/Services/IndividualFactsService.php`):

| Method | Line | App meaning |
|---|---|---|
| `individualFacts()` | 54 | primary |
| `familyFacts()` | 67 | primary |
| `relativeFacts()` | 124 | secondary |
| `associateFacts()` | 81 | secondary |
| `historicFacts()` | 153 | secondary |

`resources/views/fact.phtml:50,55,64` marks precisely the last three
`collapse` — which is the markup `record_parser` reads to set
`FactEntry.isSecondary`. The module can emit `origin` as a five-valued enum:
strictly more information than the boolean, for free.

### Labels without guessing at translations

`Registry::elementFactory()->make($tag)->label()` and `->value($value, $tree)`
(`app/Fact.php:302`, `app/Contracts/ElementInterface.php`) give the translated
label for any GEDCOM tag and the translated form of any enumerated value —
`INDI:SEX`, `FAM:MARR:TYPE`. `Fact::tag()` gives the qualified tag,
`Fact::target()` (`:104`) resolves a pointer to its record, `Fact::attribute()`
(`:153`) reads a level-2 value, `Fact::place()` and `Fact::date()` the rest.

This is what makes `fact_tags.dart` unnecessary. The app currently learns what
this site calls a death by reading `class="fact_DEAT"` out of a chart box and
building a label→tag dictionary — an ingenious workaround for a page that
translates every label before sending it. The module simply sends both.

Its honest limit disappears too: the dictionary only ever learns tags a page's
chart boxes actually rendered, so a relative's death under its own label
(`وفاة الأب`) stays untyped. An API types every fact.

### Structured names

`GedcomRecord::getAllNames()` returns, per name,
`type` / `sort` / `full` / `fullNN` / `surname` / `givn` / `surn`
(`app/Individual.php:859` builds them), with `getPrimaryName()` and
`getSecondaryName()` giving the indices. `Individual::sex()` returns a `Sex`
enum; `lifespan()`, `getBirthDate()`, `getDeathDate()`, `isDead()` are all
public (`:600, :384, :329, :355, :191`).

This replaces `span.NAME` scraping and — importantly — the current workaround
where a person's own sex, lifespan and death are recovered from *their own
chart box on the relatives tab*, because the individual page states the sex
only as a translated word.

### Media at any size

`MediaFile::imageUrl(int $w, int $h, string $fit)` (`app/MediaFile.php:211`)
mints the HMAC-signed URL server-side, and `downloadUrl($disposition)` (`:261`)
addresses the original. The signature covers the dimensions
(`MediaFile::signature()`, `:355`), which is exactly why the app is stuck at
the 100 px thumbnails the media tab happens to emit.

**This closes §9 risk 3.** The module can offer any size the screen wants, and
a media-record screen becomes possible without a new scraper.

`Individual::findHighlightedMediaFile()` (`:286`) gives the portrait directly,
so a search result can carry a photograph — which the autocomplete endpoint
only manages when the person has a highlighted file.

### Dates, structured

Public in both versions: `Date::minimumDate()`, `maximumDate()`,
`minimumJulianDay()`, `maximumJulianDay()`, `julianDay()`, `isOK()`;
`AbstractCalendarDate::calendarEscape()`, `convertToCalendar()`, `year()`,
`month()`, `gedcomMonth()`, `day()`. The qualifier is `Date::$type` (a
`DateType` enum) in 2.3 and `Date::$qual1`/`$qual2` (strings) in 2.2.6 — public
in both.

**Recommended payload:** the raw GEDCOM value, julian-day bounds, the
qualifier, and one *rendered* string per calendar on offer. Build each rendered
string by recomposing a GEDCOM date from the converted parts
(`'BET @#DHIJRI@ 1394 AND @#DHIJRI@ 1395'`) and passing it through
`I18N::language()->formatDate(new Date($gedcom))` — because
`AbstractCalendarDate::format()` exists only in 2.2.6, while `formatDate()`
exists in both.

**An upstream bug worth reporting.** 2.3's `Date::display()`
(`app/Date.php:119`) places the calendar conversion *inside*
`if ($this->date2 !== null)` — `app/Date.php:160-176` — so an ordinary single
date loses its conversion entirely. That confirms `PROJECT.md` §9 #15 from
source rather than from observation, and it is the standing argument for
structured dates: the module reads `convertToCalendar()` directly and is not
affected.

### Statistics as numbers

`StatisticsData` exists in **both** versions with typed returns —
`countIndividuals(): int`, `countIndividualsBySex(Sex): int`,
`countEventsByCentury(string): array`, `commonSurnames(...): array`,
`statsAge(): array`, `countMediaByType(): array`, `countCountries(int): array`.
`Statistics` above it returns rendered HTML and is the wrong layer.

This retires the `<script>` scraping *and* §7 bug 23 — the one where the *data*
argument of `statistics.drawPieChart(…)` is strict JSON and the *options*
argument beside it is hand-written JavaScript, so a parser that decoded both
dropped most of the page.

### Charts

`ChartService` (`app/Services/ChartService.php`) is public and complete:
`sosaStradonitzAncestors(Individual, int $generations)`,
`sosaStradonitzAncestorPaths()`, `descendants()`, `descendantFamilies()`.
Family structure comes from `Individual::spouseFamilies()` / `childFamilies()`
(`:615`, `:676`) and `Family::spouses()` / `children()` / `getMarriage()`.
The captions the app currently reads as translated prose —
`Individual::getChildFamilyLabel()` (`:746`), `getSpouseFamilyLabel()` (`:815`)
— are public too, so the site's own wording survives.

### Relationships — the one real gap

`RelationshipService::nameFromPath(array $nodes, LanguageInterface)`
(`app/Services/RelationshipService.php:160`) is **public**, so the localized
wording stays the site's — including the distinction between an older and a
younger brother that Arabic makes and English cannot.

But the path-finding is not.
`RelationshipsChartModule::calculateRelationships()`
(`app/Module/RelationshipsChartModule.php:433`) is `private`, along with its
helpers `allAncestors()` and `excludeFamilies()`. Roughly 150 lines — a
Dijkstra over the `link` table with an exclusion-list expansion for alternative
paths — must be reimplemented in the module. `fisharebest/algorithm` is already
a core composer dependency, so the algorithm itself is available; only the
graph construction and the exclusion loop are ours.

Treat this as a discrete implementation task **and** a standing maintenance
risk: it is the one place the module duplicates core logic rather than calling
it, so it can silently drift from what the website answers.

The payoff is large: it retires §9 risk 5 — a relationship read out of a grid
of positioned table cells, which "answers an empty path rather than a wrong one
when the walk finds nothing", indistinguishable from a theme it could not read.

### Language per request, with no side effects

The global stack is
`… UseSession → UseLanguage → … → BootModules → Router`
(`app/Webtrees.php:154`), and `UseLanguage`
(`app/Http/Middleware/UseLanguage.php`) consults the request only when the
session holds no language:

```php
$language_tag = Session::get('language');
if (is_string($language_tag)) { … } else { $language = $this->language_factory->fromRequest($request); … }
I18N::init($language->languageTag());
```

Module route middleware runs inside `Router`, i.e. **after** that. So a
`NegotiateLanguage` middleware can honour `Accept-Language` or a `?lang=` value
by calling `I18N::init($tag)` for that request alone.

**This closes §9 risk 16.** Today the app must `POST /language/{tag}` to get
Arabic dates, and `SelectLanguage` writes the session *and the account's stored
preference* — so using the app in English changes what the website greets that
account with. There is no stock route that sets only the session. A module
needs no route at all.

### Pending edits

`GedcomRecord::isPendingAddition()` / `isPendingDeletion()` and the same pair on
`Fact` are public. Worth emitting as flags: the app currently has to notice that
`fact.phtml` marks a pending deletion on the *row* while the notes, sources and
media tabs mark it on the *cells*, "so a parser reading only the row shows a
record queued for removal".

---

## 5. What `webtrees-API` is, and why it is not the foundation

It is competent work for what it was built for: server-side automation, GEDCOM
import/export, and MCP access for AI agents. Twenty-two endpoints, an OpenAPI
3.1 description generated from PHP attributes, a Swagger UI, typed response
classes, a control-panel settings page, n8n workflow examples. None of that is
in question.

It is the wrong foundation for a mobile client for seven reasons, five of them
structural.

**1. Client credentials is the only grant.**
`src/WebtreesApi.php:764` enables exactly one:

```php
$authorization_server->enableGrantType(new ClientCredentialsGrant(), new DateInterval('PT1H'));
```

A shipped mobile binary cannot hold a client secret. `PROJECT.md`'s fourth
constraint — "Untrusted client: the app cannot hold any shared secret" — rules
this out on its own.

**2. Every request runs as one technical user.**
`src/Http/Middleware/Login.php` resolves the OAuth client to a single webtrees
user and logs in as them:

```php
$api_user = $user_service->find((int) $oauth_user_id);
Auth::login($api_user);
```

Per-user privacy, per-user tree visibility, relationship-based privacy and edit
attribution all collapse into that one identity. For a family tree where each
member sees a different amount of the same record, this is not a limitation to
work around — it is the opposite of the product.

`src/Http/Middleware/ApiPermission.php` compounds it: the `api_read_privacy`
scope calls `Auth::logout()` and serves everyone as a visitor, while
`api_read_member` serves everyone at the technical user's level. Two levels,
neither of them the reader's.

**3. Payloads are GEDCOM or GEDCOM-X.**
`src/Http/RequestHandlers/GetRecord.php` returns
`Functions::getPrivatizedGedcom($record, $access_level)`, optionally converted
to GEDCOM-X JSON by `liberu-genealogy/php-gedcom`. That pushes calendar
arithmetic, name assembly and label translation back into Dart — which is
precisely what this app spent three phases *removing*, and what makes an
Arabic tree readable at all.

**4. No pagination anywhere.** None of the twenty-two endpoints takes an
`offset` or a `limit`. `search-general` requires a non-empty query and returns
everything it finds.

**5. It does not boot on webtrees 2.3.** Two independent reasons:

- `boot()` calls `$router->get(Class, $url)->allows(…)->extras(['middleware' =>
  …])`. `RouteFactoryInterface::routeMap()` returns `Aura\Router\Map` in 2.2.6
  and `Fisharebest\Webtrees\Http\Routing\RouteCollection` in 2.3, whose only
  registration methods are `add()` and `group()`
  (`app/Http/Routing/RouteCollection.php`).
- Handlers read `Auth::PRIV_PRIVATE` (e.g. `src/Http/RequestHandlers/GetRecord.php`,
  `SearchGeneral.php`). The `PRIV_*` constants were replaced by the
  `AccessLevel` enum (`app/Enums/AccessLevel.php`); `Auth::accessLevel()` now
  returns `AccessLevel`.

**6. Dependency weight.** 8.6 MB vendored: its own `league/oauth2-server`,
`zircote/swagger-php`, `liberu-genealogy/php-gedcom` and
`jefferson49/webtrees-common`, plus a `"replace"` block covering eight PSR
packages to avoid colliding with core's own vendor tree. That is a fragile
arrangement to inherit and a large surface to keep secure.

**7. `TestApi`.** Registered at `src/WebtreesApi.php:251` as
`$router->post(TestApi::class, …)` with **no** `extras(['middleware' => …])`,
so none of the OAuth2 middleware applies. The handler mints an access token
carrying every API scope with
`AccessTokenRepository::UNLIMITED_EXPIRATION_INTERVAL`, which is `'P1000Y'`
(`src/OAuth2/Repositories/AccessTokenRepository.php:66`) and is not revocable.
Not exposed on `tree.almou.sa` — the module is not installed there. The
standing action from `PROJECT.md` §2 remains: **reproduce in a lab install,
then report upstream.**

### What to take from it anyway

Patterns, not code: the `module.php` + `autoload.php` shape; OpenAPI attributes
on handlers so the description is generated rather than maintained; typed
`Response4xx` classes; a control-panel settings page; and the discipline of
validating every query parameter before use.

---

## 6. Proposed architecture

```
modules_v4/webtrees-mobile-api/
  module.php                  return new WebtreesMobileApi();
  autoload.php                PSR-4 for this module's namespace only
  src/
    WebtreesMobileApi.php     boot(): register routes through Compat
    Compat/
      CompatInterface.php     the entire version surface, in one file
      Compat22.php
      Compat23.php
    Http/Middleware/
      NegotiateLanguage.php   I18N::init() per request; never writes a preference
      RequireMember.php       403 as JSON, never a redirect
      JsonErrors.php          every throwable becomes a problem document
      DeviceToken.php         v2 only — bearer token → Auth::login() for one request
    Http/Handlers/            PSR-15 RequestHandlerInterface, one per endpoint
    Presenters/               Individual|Family|Fact|Date|Place|Media|Person → array
  resources/
    views/settings.phtml      v2 — device tokens, per-tree enable
```

Deliberately **no** vendored dependencies. Everything needed is in core's
vendor tree already, including `fisharebest/algorithm` for the relationship
graph.

### Handlers are version-portable

2.3's `InvokeController` (`app/Http/Middleware/InvokeController.php`) begins:

```php
if ($controller instanceof RequestHandlerInterface) {
    return $controller->handle($request);
}
```

and 2.2.6's `RequestHandler` (`app/Http/Middleware/RequestHandler.php`) does
only that. So **writing every handler as a PSR-15 `RequestHandlerInterface`
makes the entire handler layer version-neutral.** Read the tree from
`Validator::attributes($request)`, not from a typed method parameter, and 2.3's
reflection-based parameter resolution never comes into play.

### The compat surface, exhaustively

| Concern | 2.2.6 | 2.3 |
|---|---|---|
| `Registry::routeFactory()->routeMap()` | `Aura\Router\Map`; `->get($class,$url)->allows(…)->extras(['middleware'=>…])` | `RouteCollection`; `->add($url,$class,$mw)` / `->group($prefix,$mw,$cb)` |
| Access level | `Auth::PRIV_*` int constants | `AccessLevel` enum (`app/Enums/AccessLevel.php`) |
| `UserService::__construct` | no arguments | requires `ClockInterface` |
| `AbstractCalendarDate::calendarEscape()` | `string` (class `ESCAPE` const) | `CalendarEscape` enum |
| Date qualifier | `Date::$qual1`, `$qual2` (strings) | `Date::$type` (`DateType` enum) |
| Per-calendar formatting | `AbstractCalendarDate::format()` | gone — recompose GEDCOM, then `I18N::language()->formatDate()` |
| Matched route object | `$route->handler` | `$route->controller` |
| Statistics | `StatisticsData` | `StatisticsData` — **same** |
| Privacy, search, charts, media, facts, names | — | **identical public APIs in both** |

That is the whole list. Everything else the module touches has the same
signature in both versions, which is why a second adapter class is cheap and a
third (for 2.4) should be too.

### Presenters are the contract

One presenter per concept, each mirroring an existing class in `lib/domain/`
so the JSON *is* the app's model: `PersonRef`, `FactEntry`, `FamilyGroup`,
`NoteEntry`, `SourceCitation`, `MediaItem`, `IndividualRecord`, `AncestorNode`,
`DescendantNode`, `RelationshipPath`, `TimelineChart`, `TreeStatistics`,
`AccessSummary`. Deserialization on the Dart side is then a constructor call,
and the existing widget tree does not move.

**Every payload carries both halves** — what webtrees *rendered* (translated
label, formatted date, place name, full name) and what it *means* (bare GEDCOM
tag, calendar escape, julian day, sex enum, xref). That duality is not
belt-and-braces; it is the app's central rule, that the server writes the words
and the app does the layout. It must survive the migration intact, or Arabic
regresses.

---

## 7. Endpoints and representative responses

Base: `/mobile-api/v1/…` for site-wide, `/tree/{tree}/mobile-api/v1/…` for
tree-scoped. **GET only in v1** — `Router` injects `CheckCsrf` unconditionally
and its `EXCLUDE_ROUTES` is a `private const` a module cannot extend, so
read-only endpoints simply avoid the question.

| Endpoint | Replaces |
|---|---|
| `GET /mobile-api/v1/capabilities` | the deferred Phase 2b probe (§5 of `PROJECT.md`) |
| `GET /mobile-api/v1/access` | all of `access_probe.dart`, in one request |
| `GET …/individuals?q=&surname=&offset=&limit=` | `tom-select-individual`; adds enumeration |
| `GET …/individual/{xref}` | `record_parser` entire; no slug `301` |
| `GET …/family/{xref}` | new |
| `GET …/ancestors/{xref}?generations=` | `chart_parser.parseAncestors` |
| `GET …/descendants/{xref}?generations=` | `chart_parser.parseDescendants` |
| `GET …/relationship/{a}/{b}?ancestors=&recursion=` | the grid walk (§9 risk 5) |
| `GET …/timeline/{xref}` | pixel-position reading |
| `GET …/statistics` | `<script>` scraping (§7 bug 23) |
| `GET …/media/{xref}?w=&h=&fit=` | signed-URL harvesting; unlocks full size (§9 risk 3) |
| `GET …/record/{xref}/notes`, `…/sources` | `parseNotes`, `parseSources` |

### `GET /mobile-api/v1/capabilities` — unauthenticated

```json
{
  "api": 1,
  "module": "1.0.0",
  "webtrees": "2.2.6",
  "auth": ["session"],
  "features": ["access", "individuals", "individual", "family",
               "ancestors", "descendants", "relationship",
               "timeline", "statistics", "media", "notes", "sources"],
  "limits": { "maxPageSize": 200, "maxGenerations": 10 }
}
```

Anonymous and cheap, so the app can probe before signing in. `features` is what
makes an old app and a new module — or the reverse — degrade **per capability**
rather than per release.

### `GET /mobile-api/v1/access`

```json
{
  "account": { "username": "mobile", "realName": "Mobile", "email": "…" },
  "isAdministrator": false,
  "trees": [
    { "name": "main", "title": "الموسى الصائغ", "role": "member",
      "private": true, "myXref": "X42",
      "modules": { "tabs": ["personal_facts","relatives","_vytux_cousins_"],
                   "charts": ["ancestry","descendants","relationship","timeline"] } }
  ]
}
```

`role` is stated, not inferred — so the Member/Visitor ambiguity on a public
tree disappears, along with the anonymous probe that currently decides it.
`modules` lets the app keep offering only what the site actually runs, which is
the design that already handles `_vytux_cousins_` without changes.

### `GET /tree/main/mobile-api/v1/individuals?q=محمد&offset=0&limit=50`

```json
{
  "total": 118,
  "offset": 0,
  "limit": 50,
  "people": [
    { "xref": "X42", "name": "محمد الموسى", "alternateName": "Mohammed Almousa",
      "sex": "male", "deceased": true, "lifespan": "١٩٠١–١٩٧٤",
      "thumbnail": "/tree/main/media-thumbnail?xref=M11&…&s=…" }
  ]
}
```

Deduplicated and privacy-filtered by `paginateQuery`; `sex` present, which the
autocomplete endpoint never states. Omitting `q` enumerates; `surname=` filters
by initial for a browsable index.

### `GET /tree/main/mobile-api/v1/individual/X42`

```json
{
  "xref": "X42",
  "name": "محمد الموسى",
  "alternateName": "Mohammed Almousa",
  "sex": "male",
  "deceased": true,
  "lifespan": "١٩٠١–١٩٧٤",
  "thumbnail": "…",
  "pending": null,
  "facts": [
    { "tag": "BIRT", "label": "الميلاد", "origin": "self",
      "value": null, "type": null,
      "date": {
        "gedcom": "12 MAR 1901",
        "julianDay": [2415466, 2415466],
        "qualifier": null,
        "rendered": [
          { "calendar": "gregorian", "escape": "@#DGREGORIAN@", "text": "١٢ مارس ١٩٠١" },
          { "calendar": "hijri",     "escape": "@#DHIJRI@",     "text": "٢١ ذو القعدة ١٣١٨" }
        ]
      },
      "place": { "full": "الكويت, الكويت", "short": "الكويت", "lat": 29.37, "lng": 47.98 },
      "about": null },
    { "tag": "BIRT", "label": "ولادة إبن", "origin": "relative",
      "about": { "xref": "X77", "name": "عبدالله", "sex": "male", "deceased": false } }
  ],
  "families": [
    { "xref": "F7", "kind": "own", "label": "العائلة مع فاطمة",
      "spouses": [ { "xref": "X42", … }, { "xref": "X55", … } ],
      "children": [ { "xref": "X77", … } ],
      "facts": [ { "tag": "MARR", "label": "الزواج", "date": { … } } ],
      "endedInDivorce": false }
  ],
  "notes": [], "sources": [], "media": [],
  "warnings": []
}
```

Every `label` is the site's own translation; every `tag` is the bare GEDCOM
word. `origin` replaces the scraped `collapse` class with the five real
categories. `about` names the relative whose event it is — the thing
`.wt-fact-record` carries and `record_parser` had to be taught to keep.

### `GET …/relationship/X42/X99?ancestors=0&recursion=3`

```json
{
  "settings": { "ancestors": 0, "recursion": 3, "clampedRecursion": 3 },
  "paths": [
    { "description": "القرابة: إبن",
      "steps": [ { "relationship": "إبن", "person": { "xref": "X99", … },
                   "via": { "family": "F7" } } ] }
  ]
}
```

`settings` is echoed so the app can still say *"this site searches blood lines
only"* rather than showing an unexplained empty screen — the behaviour Phase 6c
had to reverse-engineer from the URL.

### Errors

One shape everywhere, and **never a redirect**:

```json
{ "error": "forbidden", "message": "You are not a member of this tree.", "detail": null }
```

with `400 invalid_parameter`, `401 not_signed_in`, `403 forbidden`,
`404 not_found`, `429 rate_limited`, `500 server_error`. This matters more than
it looks: webtrees' own middleware answers `302` to the sign-in page for an
unauthenticated request, which is the ambiguity `core/response_status.dart`
exists to resolve. An API that states its own status removes the guesswork —
though `response_status.dart` stays for the stock transport.

---

## 8. Authentication and authorization

**Recommendation: reuse the webtrees session in v1; add per-user device tokens
in v2; never client credentials.**

### v1 — the webtrees session

The app already signs in through `/login` and holds `__Secure-WT-ID`
(`data/session.dart`, and `SessionManager` keeps it alive and re-establishes it
silently). The module's routes run under the ordinary pipeline, so `Auth::user()`
*is* the reader.

- No new authentication surface, and nothing new to get wrong.
- Per-user privacy, tree visibility and relationship privacy for free (§4).
- No secret in the binary — the fourth constraint is satisfied by construction.
- Ships with zero configuration: install the module, and it works.

Costs: the 24-minute idle expiry and 24-hour cap still apply (already handled),
and read endpoints must be GET (already the design).

### v2 — per-user device tokens

A signed-in user creates a labelled, revocable, **read-only** token from a
module settings page; the app sends `Authorization: Bearer …`; a `DeviceToken`
middleware resolves it to a `User` and calls `Auth::login($user)` for that
request only, logging out afterwards.

Design rules, all of them lessons from §5: store only a hash; scope to read;
bind to one user, never to a "technical user"; record a device label and a
last-used timestamp; make revocation per device; and give tokens a finite,
configurable lifetime with no unlimited option.

The prize is that the app no longer needs the account password in the keystore
— which is a real reduction in what a stolen device gives up.

### Never client credentials

If OAuth2 is ever wanted, it must be **authorization code with PKCE** and a
public client. `PROJECT.md` §2 already committed to this, and §5 above is what
happens otherwise.

### Two consequences worth stating

- **`BadBotBlocker` applies to API routes.** It sits before `Router` in the
  global stack, so `kUserAgent` and the `/robots.txt` self-check remain load-
  bearing even after every parser is gone.
- **CORS becomes possible.** `SecurityHeaders`
  (`app/Http/Middleware/SecurityHeaders.php`) sets five headers and *no* CORS
  header at all, and only fills in headers a response has not already set. A
  module may therefore add `Access-Control-Allow-Origin` on its own routes —
  which would make Flutter Web viable, currently ruled out in `PROJECT.md` §3.
  Opt-in per site, off by default.

---

## 9. Privacy and access — what is *not* reimplemented

The module never computes privacy. It calls the same `canShow()`,
`canShowName()` and `facts($filter, $sort, $access_level)` the web interface
calls, as the same user, and presents whatever survives. Three consequences the
app must be built to expect:

1. **A hidden record is absent, not empty.** A family may list two children
   where the tree records four. The API should never invent a placeholder, and
   the app should never read a short list as a complete one.
2. **A name may be visible where details are not.** `canShowName()` is
   separately overridden on `Individual` and `Family`. A person can legitimately
   appear as a name with no facts, and that is not a parse failure.
3. **Pending edits are real.** Emit `pending: "addition" | "deletion" | null` on
   records and facts. The app currently has to notice that `fact.phtml` marks a
   pending deletion on the row while three other tabs mark it on the cells —
   an asymmetry that a flag makes irrelevant.

A fourth, for the endpoint design: **tree-level privacy is enforced by route
parameter resolution.** `{tree}` binds through `TreeService::all()`, so a
private tree the user cannot see fails to bind and the handler receives null.
Answer `404`, matching what webtrees does, and the app's existing
"anonymous 404 proves a private tree" logic keeps working.

---

## 10. Cross-cutting concerns

**Pagination.** `offset` + `limit` on every collection, `limit` capped at the
value `capabilities.limits.maxPageSize` advertises. Return `total` where it is
one cheap `COUNT`, and omit it rather than lie when it is not. Document the
`O(offset)` cost of `paginateQuery` and prefer surname-partitioned browsing to
deep offsets.

**Searching and filtering.** `q` (name or xref, matching
`TomSelectIndividual`'s behaviour of resolving an xref first), `surname` for an
index, and — later — `SearchService::searchIndividualsAdvanced()` for a real
advanced search, which the app has no access to at all today.

**Localization.** `Accept-Language` per request via `NegotiateLanguage`; never
a session or preference write (§4). Fall back to the account's stored language,
then the site default. Every human-readable string in a payload is already
translated by the server; the app translates nothing it displays from the tree.

**Dates.** As §4: raw GEDCOM, julian-day bounds, qualifier, and one rendered
form per calendar. The app's `RenderedDate` / `DatePiece` model maps directly
onto that, and `CalendarView` finally works on 2.3 as well as 2.2.6 — because
the calendar is stated rather than inferred from a link.

**GEDCOM specifics.** Xrefs are opaque and tree-scoped; multi-surname names
produce several `getAllNames()` rows for one `NAME` line; `@N.N.` and `@P.N.`
placeholders must be resolved through `I18N::translateContext` (webtrees does
this in `addName()`); custom tags are registered by `RegisterGedcomTags` before
routing, so `elementFactory()` already knows them; and record types beyond
INDI/FAM (NOTE, SOUR, REPO, OBJE, SUBM, `_LOC`) need at least a generic
presenter so a citation can be followed.

**Places.** `Place::fullName()`, `shortName()`, `gedcomName()`, plus
`Fact::latitude()` / `longitude()` — enough for a place screen and, eventually,
for the pedigree map that v1 declined.

**Media.** Sizes are requested, not harvested. Return the signed URL rather than
the bytes, so the existing `AuthenticatedImage`/`MediaCache` path is unchanged
and the module stays cheap.

---

## 11. Backward compatibility and maintainability

- **The compat table in §6 is the contract with upstream.** One interface, one
  class per webtrees minor version, and a rule that no code outside `Compat/`
  may name a version.
- **CI against both.** A matrix job installing 2.2.x and 2.3 and running the
  module's own request tests. `PROJECT.md` §9 #11 already names upstream module
  churn as a risk; this is the mitigation it asks for.
- **Version the URL and the features.** `/v1` for breaking changes;
  `capabilities.features` for additive ones. An app must never assume that a
  module answering `/v1` implements all of it.
- **Never require the module.** Every capability the app gains through the API
  must still have a stock path, or the first constraint is broken. That is not
  a transitional rule — it is permanent.
- **Additive-only within a version.** New fields yes; renamed or removed fields
  only behind a new `v`.

---

## 12. Effort and risks

Sized in units of a focused working session, assuming the research in this
document is not repeated.

| Work | Size | Notes |
|---|---|---|
| Module skeleton, `Compat22`/`Compat23`, routing, error envelope, `capabilities` | S | Mostly mechanical once §6 is settled |
| `NegotiateLanguage`, `RequireMember`, `JsonErrors` | S | |
| Presenters for person, fact, date, place, media | M | The core of the contract; get this right first |
| `access`, `individuals`, `individual`, `family` | M | Retires `record_parser` and `access_probe` |
| `ancestors`, `descendants`, `timeline` | S | `ChartService` does the work |
| `relationship` | **L** | The reimplemented Dijkstra; the only real algorithm |
| `statistics` | M | Many small `StatisticsData` calls, little logic |
| `media`, `notes`, `sources` | S | |
| Flutter: extract transport interfaces, add `data/module/` | M | The one Flutter refactor; mechanical |
| Flutter: contract tests run against both transports | M | The check that keeps the two honest |
| Device tokens + settings page (v2) | M | Defer until v1 is proven |

**Risks, ranked.**

1. **Upstream module-API churn.** 2.3 rewrote routing; 2.4 may rewrite
   something else. Mitigated by `Compat/` and CI, not eliminated.
2. **The private `calculateRelationships`.** The module's only duplicated
   algorithm, and therefore the only place it can silently disagree with the
   website. Mitigate by testing module output against the rendered chart for a
   set of known pairs.
3. **Deep-offset cost.** `paginateQuery` walks a cursor in PHP. A large tree at
   offset 5,000 is a slow request. Mitigate with a page-size cap and
   surname-partitioned browsing.
4. **Two transports, one behaviour.** Every screen must behave identically on
   both, which doubles the meaningful test surface until the stock path is
   retired — and it never fully is.
5. **New security surface.** v2 tokens are a credential store the app did not
   have. §5's `TestApi` is the cautionary tale; the rules in §8 are the answer.
6. **The module could be wrong where the scraper was right.** The scrapers have
   been exercised against 40 real records; the module will not have been.
   Migration order (§13) exists to manage exactly this.

---

## 13. Migration strategy

Capability-first, per capability — which is what `PROJECT.md` §4 already
prescribes: *"Compose at the level of capabilities rather than swapping one
global transport: a module might serve structured person detail while stock
routes still handle search and media."*

1. **Extract transport interfaces first, with no module in sight.** Screens
   currently depend on `RecordsRepository` and `ChartsRepository` by type
   (`lib/app/app.dart:51,59` builds them per navigation, deliberately, because
   the client is replaced on reconnect). Introduce `RecordsTransport`,
   `ChartsTransport` and `AccessTransport`; make the stock classes implement
   them; change the field types. Mechanical, testable, and valuable even if the
   module is never built.
2. **Build `data/module/`** against those interfaces — the directory §4 of
   `PROJECT.md` already reserves.
3. **Probe `capabilities` at connect time** and select per capability, not
   globally. A site running an older module still gets the fast path for what
   it does implement.
4. **Migrate in order of scraping cost**: `individual` → `individuals`
   (search) → `access` → charts → statistics → media. `individual` first
   because it is 727 lines of the most fragile parser and the most-used screen.
5. **Keep both live and compare them.** Run one repository contract-test suite
   against both transports, and extend `tool/live_check.dart` to exercise each
   capability through both and diff the results against a real instance. This
   is the only check that would have caught bugs 5, 14–16 and 22 — every one of
   which was invisible to a green unit suite.
6. **Retire a parser only after its endpoint has passed live against real
   data**, and keep the fixtures either way: the stock path is permanent.

### What the app keeps regardless

Instance and URL-style detection; sign-in and session management; the
User-Agent rules; `AuthenticatedImage` and `MediaCache`; every parser, as the
stock floor; `domain/`, which the API is shaped to fill rather than replace;
and the whole interface — bidi, calendars, typography, chart layout — which was
never the server's business and still is not.

---

## Appendix — claims verified against source

| Claim | Evidence |
|---|---|
| No API on a stock instance | `app/Http/Routes/ApiRoutes.php` — empty `load()` in both versions |
| Autocomplete cannot enumerate | `app/Http/Controllers/AbstractTomSelectHandler.php` — empty collection unless `query !== ''` |
| Search can enumerate, with paging | `SearchService::searchIndividualNames` `:190`; `whereSearch` `:1034` no-ops on `[]`; `paginateQuery` `:996` |
| Privacy needs no reimplementation | `GedcomRecord::canShow` `:186`, `canShowName` `:204`, `facts` `:514`, `canShowByType` `:791`; `Auth::accessLevel` `:104` |
| Tree visibility is enforced by route binding | `TreeService::all` `:73`; `Router` in both versions |
| Fact origin is already five-valued | `IndividualFactsService` `:54,67,81,124,153`; `resources/views/fact.phtml:50,55,64` |
| Labels are available per tag | `Fact::label` `:302`; `Contracts/ElementInterface.php` |
| Names are structured | `Individual::addName` `:859`; `GedcomRecord::getAllNames` `:283` |
| Media at any size | `MediaFile::imageUrl` `:211`, `downloadUrl` `:261`, `signature` `:355` |
| Signed URL is not an authorization token | `app/Http/Controllers/MediaFileThumbnail.php` — `canShow()` before signature; watermark per user |
| 2.3 drops single-date calendar conversion | `app/Date.php:160-176` — conversion inside `if ($this->date2 !== null)` |
| 2.2.6 states the calendar in a link | `git show 2.2.6:app/Date.php` — `calendarUrl()` per date |
| Statistics are typed in both versions | `app/StatisticsData.php`; present at tag 2.2.6 |
| Relationship naming is public, path-finding is not | `RelationshipService::nameFromPath` `:160`; `RelationshipsChartModule::calculateRelationships` `:433` (`private`) |
| Language can be set per request | `app/Webtrees.php:154`; `app/Http/Middleware/UseLanguage.php` |
| Handlers are version-portable | `app/Http/Middleware/InvokeController.php`; `git show 2.2.6:app/Http/Middleware/RequestHandler.php` |
| Route registration is not | `app/Contracts/RouteFactoryInterface.php` in both; `app/Http/Routing/RouteCollection.php` |
| `Auth::PRIV_*` removed in 2.3 | `app/Enums/AccessLevel.php`; `Auth::accessLevel` returns the enum |
| CSRF cannot be opted out of | `app/Http/Middleware/CheckCsrf.php` — `private const EXCLUDE_ROUTES`; `Router` always injects it |
| No CORS headers are set | `app/Http/Middleware/SecurityHeaders.php` |
| webtrees-API: one grant | `src/WebtreesApi.php:764` |
| webtrees-API: one technical user | `src/Http/Middleware/Login.php` |
| webtrees-API: GEDCOM payloads | `src/Http/RequestHandlers/GetRecord.php` |
| webtrees-API: 2.2-only routing and access levels | `src/WebtreesApi.php` `boot()`; `Auth::PRIV_PRIVATE` in `GetRecord.php`, `SearchGeneral.php` |
| webtrees-API: `TestApi` unauthenticated, 1000-year token | `src/WebtreesApi.php:251`; `src/OAuth2/Repositories/AccessTokenRepository.php:66` |

---

## 14. What building it changed about this document

**Added 2026-08-23, after the module was written.** Everything above was
verified by reading source; the sections below are what only writing the code
found. The recommendation held — a separate module, PSR-15 handlers, per
capability adoption — but five specific claims did not, and the compat surface
turned out to be a *different* eleven differences rather than the seven
tabulated in §6.

### Five claims that were wrong

1. **`ChartService::sosaStradonitzAncestorPaths()` is 2.3-only.** §4 lists it
   beside `sosaStradonitzAncestors()` as though both were available; it does
   not exist at tag 2.2.6. Not needed in the end — the ancestors endpoint
   builds its tree from the sosa map and `childFamilies()->first()`, which is
   the same walk core makes — but a design that had leaned on it would have
   failed on the target instance.
2. **`I18N::language()->formatDate()` does not exist in 2.2.6.** §4 recommends
   it as the version-neutral way to render a recomposed date, on the grounds
   that `AbstractCalendarDate::format()` is 2.2-only. Both halves are true and
   the conclusion is not: 2.2.6's `ModuleLanguageInterface` has no
   `formatDate()` at all — it arrived with `Contracts\LanguageInterface` in
   2.3. What *is* version-neutral is `Date::display(null, null, false)`, which
   renders the whole date, in the reader's language, with no calendar links
   and no conversions. Strip the tags and it is the same string in both.
3. **`ResponseFactoryInterface::response()` is a compat difference, and §6
   missed it.** It takes an `int` status in 2.2.6 and an `HttpStatusCode` enum
   in 2.3. Avoided rather than adapted: both versions bind the **PSR-17**
   `ResponseFactoryInterface` and `StreamFactoryInterface` in the container, so
   the module builds every response from those and never names a status type.
4. **Fact sorting is a compat difference too.** 2.2.6 has the static
   `Fact::sortFacts()`; 2.3 deleted it and added `FactSortService::sort()`.
   The individual endpoint has to sort exactly as the page does, so this could
   not be sidestepped.
5. **So are three more:** `Individual::sex()` returns a string in 2.2.6 and a
   `Sex` enum in 2.3; `Family::marriageDateComparator()` and
   `Individual::birthDateComparator()` became `Comparators\FamilyComparator`
   and `Comparators\IndividualComparator`; and `Factories\LanguageFactory` is
   2.3-only, so enumerating a site's languages goes through
   `ModuleLanguageInterface::locale()` on 2.2 and `->language()` on 2.3.

### Three rows in §6 that turned out not to be needed

- **Access level.** `Auth::PRIV_*` versus the `AccessLevel` enum never comes
  up, because every privacy method — `canShow()`, `canShowName()`,
  `facts($filter, $sort, $access_level)`, `Fact::canShow()` — defaults its
  access level to the current user's. A module that never names one inherits
  the model exactly and stays version-neutral for free. This is the single
  most useful thing the implementation learned.
- **`UserService::__construct`.** Never constructed directly; both containers
  autowire it from the constructor's type hints, `ClockInterface` included.
- **The matched route object.** `$route->handler` versus `$route->controller`
  only matters to code that inspects the route, and nothing here does.

### One behavioural difference no adapter can hide

On **2.2.6**, when `{tree}` names a tree that does not exist or that the reader
may not see, `Router` hands the request to webtrees' own not-found handler
*before* module middleware runs — so the `404` arrives as an HTML page rather
than as the error envelope. 2.3 binds the attribute to null and lets the
handler answer. Stated in the module's README; a client must read any `404` as
not-found regardless of the body.

### What was built beyond §7

- **`GET …/individuals?surname=`** is a real initial index rather than a
  substring filter, through
  `searchIndividualsAdvanced($tree, ['INDI:NAME:SURN' => …], [… => 'BEGINS'])`
  — public in both versions, and matching on the indexed `n_surn` columns. It
  also answers an honest `total`, which the paginated name search cannot.
- **`capabilities.languages`**, so a client can offer only the languages the
  site runs and send one in `?lang=` without writing the account's preference.
- **A per-calendar `text`** composed by the module rather than by
  `Date::display()`, which is what makes 2.2.6 and 2.3 answer identically
  despite the 2.3 conversion bug in §4.

### Verification, and its limit

`tool/check_module.py` in the client repository checks every file's structure
and every `Fisharebest\Webtrees\…` import against **both** versions of the
webtrees source, and fails if anything outside `src/Compat/` names a class that
exists in only one. `.github/workflows/module.yml` runs that plus `php -l` on
8.3 and 8.4.

Neither runs an endpoint. That gap is closed below.

---

## 15. Running it

**Added 2026-08-23, after the module was executed.** `tool/lab/` in the client
repository stands up throwaway webtrees installs on SQLite — 2.2.6 and 2.3 side
by side — with the module symlinked in and a synthetic Arabic tree of fourteen
invented people. `tool/live_check.dart` reads the same person through both
transports and diffs them field by field.

**It works, on both versions, and the payloads are identical between them.**
All thirteen endpoints answer. Module and stock agree on name, alternate name,
sex, deceased, lifespan, every relative count, primary facts, tags named, and
the same date in both calendars. d'Aboville numbers continue across a second
marriage; cousins yield two distinct paths; the relationship wording stays the
site's own.

### Six more things reading did not find

Reading this document's own sources produced five errors (§14). Running the
code produced six more, in one afternoon:

1. `capabilities.languages` was a JSON **object** — `findByInterface()` keys
   its collection by module name, and `->map()->all()` keeps the keys.
2. **`I18N::init()` is not sufficient to change the language.** This is the one
   §4 got most wrong. Module middleware does run after `UseLanguage`, exactly
   as claimed — but the global stack also registers every GEDCOM tag's *label*
   between `UseLanguage` and `Router`, and `Gedcom::registerTags()` evaluates
   each label eagerly. So the element factory is already holding the session's
   language by the time a module can act, and the first attempt answered
   English dates beside Arabic labels. `registerTags()` has to be called again.
3. Tree privacy is a **column**, not a preference: schema 45 moved
   `REQUIRE_AUTHENTICATION` into `gedcom.private`, 2.2.6 kept a deprecated shim
   and 2.3 removed it. §9's "a private tree fails to bind" is still true — but
   anything *setting* privacy must write the column, and a lab that used the
   preference produced a tree that was never private and a symptom that looked
   exactly like the module leaking one.
4. An unbindable `{tree}` answers **`400` on 2.3**, not `404` — `Validator`
   throws `HttpBadRequestException`. §9's advice to "answer 404" is what the
   module does, and it is now the *more* consistent of the two.
5. `GET /login` answers **`400` on 2.3** while rendering the whole page.
6. 2.3 replaced Google Charts with **Chart.js**, moving statistics data out of
   the `<script>` and onto the canvas as `data-wt-chart-*` attributes. §7's
   claim that this endpoint retires `<script>` scraping holds; what it missed
   is that the scraping was *already* broken on 2.3, and that the new markup is
   strict JSON, which retires bug 23 on the stock path too.

### What §13 rule 6 actually means

"Retire a parser only after its endpoint has passed live" cannot mean *delete*,
because §11 makes the stock path permanent. It means: a capability becomes one
the composer may **prefer** the module for. The parser behind it stays, stays
fixtured and stays tested — otherwise the first constraint in `PROJECT.md` §1
is broken the moment a site declines to install the module.

Three capabilities are cleared on that reading — `access`, `individual`,
`individuals` — and the ledger lives in `PROJECT.md` §5.

### What is still untested

**The data.** Fourteen invented people is not 1,463 real ones. The scrapers
have been exercised against 40 real records and the module against none, so the
remaining steps are a lab loaded from a copy of the real tree, and then the
module installed on the instance itself.

---

## 16. What the real tree changed, and what a reader changed after that

**Added 2026-08-23, after the module was installed on `tree.almou.sa`.** §15
ended by naming the two steps left: a lab loaded from real data, and the module
running on the instance itself. Both have happened, and then a third thing
happened that this document had not anticipated at all — somebody used the app.

### The real tree: two disagreements in 1,463 people

The module answered against 1,463 real people rather than fourteen invented
ones, and `tool/live_check.dart` read the same records through both transports.
**Two differences, both on one woman's record, and nothing else across the
tree.**

- Her lifespan read `…–`. `Individual::lifespan()` always writes something,
  because a chart box wants the same height for everybody — so the HTML path
  showed an ellipsis and a dash for a person the tree records no dates for.
  The module answered null, and null is right.
- The module read no second name for her. §4 lists `getAllNames()` as the
  structured answer and it is, but the module had used
  `GedcomRecord::alternateName()`, which is narrower than it looks: it answers
  only when the primary and secondary names differ by **character set**. She
  has two Arabic `NAME` lines. The accordion's reading was right.

One fix on each side, which is the honest split. Walking the tree with
`--sample` then found two more classes that a single record could not:
`Individual::isDead()` *infers* death from age, so a person born in 1850 with
no death recorded was dead to the module and unknown to a chart box; and a
converted date repeated its qualifier — `about 1875 (about 1292)` where
webtrees writes `about 1875 (1292)`.

That is four in total from real data, after five errors from reading source
(§14) and six from first execution (§15). The trend is the finding.

### Then a reader looked at the screen

Four more faults, none of which any check in this project could see. Two were
in the module and are the reason this section exists.

**A family's members were being sent as facts.** `FamilyPresenter` asked
`Family::facts([], true)` and presented everything it got. `HUSB`, `WIFE` and
`CHIL` are facts like any other to webtrees, so a family of four answered a
marriage *and* four pointers, indistinguishable from events to any client. The
app already had those people as `spouses` and `children`, so it drew both: the
parents card listed the marriage and then "husband · wife · son · son", and
every family card wore a pill per member.

**webtrees answers this itself, twice and differently, and §4 missed both.**

| Where a family is shown | What webtrees prints | Evidence |
|---|---|---|
| In its own right | every fact **except** `FAM:HUSB`, `FAM:WIFE`, `FAM:CHIL` | `app/Http/Controllers/FamilyPage.php` — the same filter at 2.2.6 and 2.3 |
| Inside a member's page | only `Gedcom::MARRIAGE_EVENTS + DIVORCE_EVENTS` | `resources/views/modules/relatives/family.phtml` |

So a presenter needs both: `record()` for the first, `summary()` for the
second. This is the general lesson of §4 restated — *the module presents;
webtrees decides* — applied to a question §4 did not think to ask, which is
not "what does a family record contain" but "what does webtrees **show** of
it, and where".

The fixture is why it survived everything. `test/fixtures/module/` was written
from the design in §7 of this document rather than captured from a running
server, so it held exactly the facts the design said it would and never the
pointers a server actually sends. That is §14's lesson (a claim checked
against source is not a claim checked against behaviour) one level further
out: a fixture checked against a design is not a fixture checked against a
server. The standing check is now on the wire — `live_check` diffs the family
events both transports report, and fails on the old module.

The other module-side consequence is small and worth stating: **a client must
not assume the module it is talking to is the module it was written against.**
`capabilities` versions the feature *set*, not the shape of any payload within
it, and a site upgrades its module when it chooses to. The app therefore drops
the three pointer tags again on the way in. §11's "additive-only within a
version" is a promise about fields, and this was a bug about *values* — which
no version scheme catches.

### Two things §7's payloads should have said

- **`facts` on a family means events.** Stated here because "the facts of a
  family" is ambiguous in exactly the way that caused this, and a reader of
  §7's example payload would not have known which was meant.
- **`spouses` and `children` are the membership, and the only statement of
  it.** A client that also reads membership out of `facts` will double it.

### What is still untested

Unchanged from §15 in kind, narrowed in degree: a manager's or an editor's
view, a tree with pending edits, and the notes, sources and media capabilities
— `tree.almou.sa` runs none of those three tab modules, and this account can
see none of its 86 media objects. And now one more, which is not about the
module at all: **nothing in this project looks at the result.** Every check it
owns answers "is this value right", and the four faults above were all "is
this what a person would want to see". A device, and the habit of opening the
app after changing it, is the only thing that closes that.

---

## 17. What a lab with a photograph in it found

**Added 2026-08-23, after every remaining capability was diffed.** §16 ended
with a list of what had never been exercised: notes, sources and media, and a
manager's view. Two of those are now closed, and closing them found four more
faults — three in the module, one in webtrees.

### The media capability had never run, and the reason was one missing file

The lab's GEDCOM had declared `@M1@ OBJE` since it was written, the `media`
row existed, and the media tab rendered it. **No image was ever written to
disk.** So `MediaFileThumbnail` — the handler §4 cites for `canShow()` before
signature, and §10 for "sizes are requested, not harvested" — had never
executed in this project at all, on either transport.

A media *record* is not a photograph. §7's `GET …/media/{xref}?w=&h=&fit=` and
§9's privacy reasoning are both about bytes, and neither is tested by a record
that points at nothing. The lab now draws two files at install time.

### webtrees 2.3 cannot thumbnail anything but a JPEG

The second file is a PNG, and it answers `500` on 2.3.
`ImageFactory::autoRotateImage()` — new in 2.3 — calls `exif_read_data()` on
every image it resizes; PHP raises `E_WARNING: File not supported` for a PNG,
a GIF or a WebP; and `Http\Middleware\ErrorHandler` throws on any un-silenced
warning. Proved by storing one picture twice at one URL: PNG `500`, JPEG
`200`. 2.2.6 has no such call.

This is the third upstream defect this project has found by reading or running
2.3, after the single-date conversion loss in §4 and the `400` from
`GET /login` in §15 — and the first that breaks the *website* for ordinary
data. It belongs in the same upstream report.

### Three module faults, all of them about what a reader sees

None was a wrong value; each was a payload that said less than the page.

| Where | The page | The module | Fix |
|---|---|---|---|
| Relationship | `Relationship: أب`, from `RelationshipsChartModule`'s own `<h3>` | `أب` | Send what webtrees writes |
| Timeline | `١٩٧٤ (١٣٩٤)`, and the couple after a marriage | `١٩٧٤`, no couple | Compose from `DatePresenter`, append `Family::fullName()` |
| Statistics | 17 sections, 15 charts | 4 sections, 8 charts | Read from the page |

The first two restate §16's lesson exactly — *what does webtrees **show** of
this, and where* — for two payloads §7 designed without asking. The third does
not, and is the more interesting one.

### A transport can be right and still say less

Every figure the statistics endpoint states matches the page. It simply sends
a chosen quarter of what the page publishes, and the client had been
preferring it — so installing the module *cost* a reader thirteen sections of
their own tree.

Nothing in this document catches that. §11's rules are about compatibility
(additive-only, version the URL) and §13's migration order is about
correctness (retire nothing until its endpoint passes live). Both are
satisfied by a payload that is accurate and narrower. The missing rule:

> **Prefer the module only where it knows *more*.** Faster and more structured
> is not sufficient; a capability the module answers with less than the page
> stays on the page until the endpoint covers it.

Which is §13's "compose at the level of capabilities" carried one step
further: the composer's condition is not *does the module offer this* but
*does the module offer this better*. The client keeps that rule in one place,
and its diagnostics screen reads the same rule — because "the module is
installed" and "this screen used the module" were already different questions,
and this makes them differ for a third reason.

### The ledger

Nine capabilities move to cleared: `notes`, `sources`, `media`, `family`,
`ancestors`, `descendants`, `relationship`, `timeline` — on both labs, both
versions, fourteen records each, no differences — beside the three the real
tree cleared. `statistics` moves to a deliberate *not cleared*.

### What is still untested

A manager's or an editor's view, and a tree with pending edits: unchanged from
§15 and §16. And now, sharpened: the diffs written for this section have run
against fourteen invented people and never against 1,463 real ones, which is
exactly the gap that produced §16's two disagreements. The real tree is where
they go next.


---

## 18. What forty real records said that fourteen invented ones could not

**Added 2026-08-23, after every capability was diffed against `tree.almou.sa`.**
§17 cleared nine capabilities on two labs and ended by naming the gap: the
diffs had met fourteen invented people and never 1,463 real ones. They have
now, and the walk found four more things — one in the module, one in the
client, one in webtrees' data model, and one in the lab itself.

### A burial is a death

`deceased` asked webtrees for a `DEAT` fact. `Gedcom::DEATH_EVENTS` is
`DEAT`, `BURI`, `CREM`, and a chart box prints a tag for whichever it finds —
so a man whose tree records his burial and no death was mourned on the website
and living in the module. §4's advice to avoid `Individual::isDead()` (it
*infers* death from age) was right and incomplete: the alternative is not one
tag, it is the set webtrees itself calls a death.

### A name is not one thing, and this is the third time

§4 recommends `getAllNames()` for structured names, and it is right about
what it holds — but it holds a row per name **form**, not per name:
`extractNamesFromFacts()` adds one for every `ROMN`, `FONE` and `_XXX` subtag
as well as for each `NAME` line. A woman with one name and a `2 _MARNM` under
it therefore has two rows, and the module answered the second as an alternate
name for somebody the website shows one name for. The count of `1 NAME` lines
is the guard.

The sequence is worth keeping: `alternateName()` was too narrow (same-script
names invisible), `getAllNames()` too wide (subtags counted as names), and the
answer is the one webtrees renders — a `span.NAME` per name *line*.

### The markup does not always say who the couple is

This is the client's half, and it is the sharpest limit found in the stock
transport so far. webtrees separates a family's couple from its children with
the **marriage row**, and a family that records no marriage has none. A father
and a son both render `<tr class="wt-sex-m">` around a chart box; the `<th>`
between them is a translated relationship name. So a family with children, no
marriage and no second spouse recorded is genuinely ambiguous in HTML — and a
real record is exactly that, and had its eldest son read as a spouse.

What resolves it is the **caption**, in two shapes that mean different things:

| Caption | Means | Read as |
|---|---|---|
| `X + Y` (`Family::fullName()`) | lists both spouses, `… …` where one is not recorded | a named row is a spouse; the rest are children |
| *Family with X*, *Father's family with X* | names the **other** spouse only | the couple is the leading pair |
| *Parents and siblings* | names nobody | fall back to the leading pair |

with one structural fact underneath all three: **children never precede the
couple**, so a row known to be a spouse makes every row above it a spouse too.
And a page settles its own ambiguities — a step-family hangs off a parent or a
spouse whose marriage is stated in another table — provided only *stated*
couples are learnt from, and never the subject, who is a spouse in one family
and a child in another.

The rung that needs no caption is the best of them, and it comes from reading
`family.phtml` rather than from theorising: a child row prints the gap since
the previous child's birth, and `$prev` is empty until a marriage fills it —
so the first child of an unmarried couple can never carry one, and a row that
does **proves** the row above it is a child. Same code in 2.2.6 and 2.3.

One shape is still genuinely unreadable: a lone parent, no marriage, and
children the tree records no birth dates for. The module answers it correctly,
which is a fair summary of what this whole document argues. Every rung above
was added because a record broke the one before it — a real step-family, a lab
birth family, a real birth family with two parents, a real one with a lone
father. Four records, four rules, and the honest reading is that a fifth shape
exists and has not been met yet.

### The lab had privacy switched off

Building a record for the case above meant hiding a spouse, and hiding one did
nothing. `canShowRecord()` returns true for everybody before it reads a
restriction unless `HIDE_LIVE_PEOPLE` is `'1'`, and no lab had ever set it. So
§9's privacy reasoning — *a hidden record is absent, not empty*, *a name may
be visible where details are not* — had never once been executed. It is on
now, with a single `RESN confidential` person, and both halves hold:
`canShow()` false, `canShowName()` true, and the two transports agree.

That is bug 35's lesson for the third time, and the generalisation is worth
stating plainly: **a lab proves nothing about a feature it has switched off**,
and the switch is easy to leave alone precisely because nothing fails when it
is wrong.
