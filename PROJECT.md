# webtrees Mobile Client

A cross-platform Flutter client for [webtrees](https://webtrees.net) genealogy
sites. A real mobile application, not a wrapper around the web interface.

**Living document.** Update the status table and the progress log as work
happens, and add to *Verified constraints* whenever something new is confirmed
against a real server. Every milestone ends with the ritual in §10.

---

## 1. Goal and constraints

Build a mobile app that works against **any** webtrees instance. The user enters
a site address, username and password — nothing is assumed to be installed on
the server.

| Constraint | Consequence |
|---|---|
| Must work on an untouched instance | No server-side module may be *required* |
| Each user is a real webtrees account | Per-user privacy and tree access must be preserved |
| Not a WebView wrapper | The app owns its own UI and navigation |
| Untrusted client | The app cannot hold any shared secret |

### Repository layout

This document lives inside `webtrees_mobile/`, which is the git repository —
so the project's history and its record of *why* stay together. The paths below
are relative to the parent workspace, which is **not** version-controlled.

| Path | What it is |
|---|---|
| `webtrees_mobile/` | The Flutter app — **the repository**, and where this file lives |
| `webtrees_mobile/server/webtrees-mobile-api/` | The optional webtrees module, written to `api_eval.md`. Copy it into an instance's `modules_v4/` |
| `../webtrees/` | Upstream webtrees source, read-only reference (2.3.0-dev, `2.2.6` tag available); its own clone |
| `../webtrees-API/` | Third-party API module, **evaluated and rejected** — see §2; its own clone |
| `api_eval.md` | Design basis for an optional **purpose-built API module** — see §2 |
| `sync_eval.md` | Whether to keep a local copy of the tree on the device, and in what shape — see §5 phase 10 |
| `../CLAUDE.md` | Flutter/Dart coding standards for this workspace |

Real genealogy data must stay out of the repository: `.gitignore` excludes
GEDCOM and SQL dumps, built artifacts and signing material. Phase 3 parser
fixtures go in **sanitized**, under `test/fixtures/`.

### Target instance

`https://tree.almou.sa` — webtrees **2.2.6**, pretty URLs, one **private** tree
`main`. A development account `mobile` exists with read-only Member access.

> Its password is passed via the `WEBTREES_PASSWORD` environment variable and is
> deliberately **not** recorded in this repository. The account has read access
> to real family data — disable it when development ends.

---

## 2. Key decisions

### `webtrees-API` is not the foundation

Full assessment: <https://claude.ai/code/artifact/43243a7c-4600-45f7-aa15-fdcd202984ed>

A fuller architectural evaluation — what an API module built *for this app*
would look like, which webtrees internals it would reuse, and how the app
would migrate to it one capability at a time — is in **`api_eval.md`**.

Classified **Category 4 — not suitable as the main mobile API**. It is competent
work for what it was built for (server-side automation and AI/MCP access), but
the mismatch is structural, not a matter of missing endpoints:

- Its only OAuth2 grant is **client credentials with confidential clients**
  (`src/WebtreesApi.php:764` enables exactly `ClientCredentialsGrant`). A
  shipped mobile binary cannot keep a secret.
- Every request runs as one shared **technical user** —
  `src/Http/Middleware/Login.php` does
  `Auth::login($user_service->find((int) $oauth_user_id))` — collapsing
  per-user privacy, tree access and edit attribution into a single identity.
- Data arrives as raw GEDCOM or GEDCOM-X (`GetRecord.php`), pushing calendar,
  name and label logic into Dart.
- No pagination anywhere — not one of its 22 endpoints takes an `offset` or a
  `limit`; writes pass whole records through the query string.
- **It does not boot on webtrees 2.3, for two independent reasons.** `boot()`
  calls `$router->get(…)->allows(…)->extras(…)` on what is now a
  `RouteCollection` whose only registration methods are `add()` and `group()`;
  and its handlers read `Auth::PRIV_PRIVATE`, replaced by the `AccessLevel`
  enum. Either alone is fatal.
- It vendors 8.6 MB of its own dependencies — `league/oauth2-server`,
  `swagger-php`, `php-gedcom` — and `"replace"`s eight PSR packages to avoid
  colliding with core's vendor tree.
- `TestApi` mints an all-scope, non-revocable token from a route with no auth
  middleware: registered at `src/WebtreesApi.php:251` with no `extras()`, and
  `UNLIMITED_EXPIRATION_INTERVAL` is literally `'P1000Y'`
  (`AccessTokenRepository.php:66`). **Report upstream after reproducing in a
  lab install.** Not currently exposed on `tree.almou.sa` — the module is not
  installed there.

### The module is a new one, and it is written

`api_eval.md` (2026-08-23) worked the question through and recommended a
**separate, purpose-built module**, adopted as a capability-negotiated fast
path beside the stock transport rather than as a replacement for it. Extending
`webtrees-API` would have meant rewriting auth, transport and payload —
everything except the module skeleton.

It now exists, at `server/webtrees-mobile-api/`: fourteen read-only `GET`
endpoints, no vendored dependencies, and one adapter class per webtrees minor
version. It runs: two lab installs, both webtrees versions, and the real tree
(§9 #18 governs what may be claimed for it, and no parser has been retired —
`api_eval.md` §11's rule is that none ever is). *This paragraph read "it has never been
executed — there is no PHP on this machine" until 2026-08-24; PHP 8.4 and the
labs arrived in §8 and this sentence did not notice.*

Three findings carry that, and each is a fact about upstream rather than a
preference:

- **The version-compatibility surface is small.** 2.3's `InvokeController`
  short-circuits with `if ($controller instanceof RequestHandlerInterface)
  return $controller->handle($request);`, which is all 2.2.6's `RequestHandler`
  ever did — so PSR-15 handlers are version-neutral. Everything that does need
  an adapter fits in eleven methods, now measured rather than estimated (§3).
- **Privacy needs no reimplementation at all.** A module running as the *real*
  user inherits `canShow()`, `canShowName()`, `Fact::canShow()` and
  `TreeService::all()` exactly as the website uses them.
- **The hard parts are already public API**: translated labels per GEDCOM tag,
  structured names, signed media URLs at any size, typed statistics, and search
  with real pagination.

Auth would be the **webtrees session the app already holds** in v1 — no new
surface, no secret in the binary — with revocable per-user *device tokens* as a
v2 refinement. Never client credentials; if OAuth2 is ever wanted, it is
authorization code with PKCE.

The module must stay optional. The first constraint in §1 is that the app works
against an untouched instance, so the stock transport is the floor and every
capability keeps its HTML path. That is permanent, not transitional.

### Decisions taken with the user

| Question | Decision |
|---|---|
| Data strategy | **Hybrid.** Stock HTTP/HTML transport always works; probe for an optional module and switch to a JSON fast path when present |
| Staying signed in | Password in the OS keystore, biometric-gated, silent re-login on expiry |
| v1 scope | **Read-only browsing.** Editing, moderation and offline sync deferred to v2 |
| Finding people (v1) | **Search, not enumeration** — *on a stock instance*. Its only JSON endpoint requires a non-empty query (§3), and no stock route paginates a whole tree cheaply. With the module, an empty query enumerates and `surname=` gives a real initial index |
| Where the app opens | **The last site, signed in.** An address typed once should not be typed again, and a list of one saved site is not a choice. The launch screen resumes it and steps aside; the connect screen is what you see when there is nothing to resume |
| Where the tree list goes | **Skipped when there is one tree.** The account screen keeps its diagnostic job and stays one tap away, but it is not a destination when it holds a single card |
| Which calendar to show | **The reader's, per the markup.** A tree's `CALENDAR_FORMAT` is a manager-level preference no member can change, so the choice is made in the app, over dates the server has already rendered — never by converting anything |
| Module capability probe | **Built.** `GET /mobile-api/v1/capabilities` is anonymous and cheap, and answers a `features` array so an old app and a new module degrade *per capability* rather than per release. Probed once per sign-in; a site that answers `404` — which is every real site today — takes the stock path for everything and reports nothing wrong |
| Module authentication | **The webtrees session the app already holds.** No new surface, no secret in the binary, and per-user privacy for free because `Auth::user()` *is* the reader. Revocable per-user device tokens are the v2 refinement; never client credentials |

---

## 3. Verified constraints

Confirmed by reading `webtrees/` (2.3.0-dev and the `2.2.6` tag) **and** by
running against the live instance. The wire protocol is **identical** across
2.2.6 and 2.3.0-dev — only PHP class names moved.

### Addressing

- **Two URL styles.** `rewrite_urls` defaults to `"0"`, so
  `index.php?route=/x` is the default for a fresh install. Detect with one
  request: `GET {base}/index.php?route=/ping`, redirects off — `200` means ugly,
  `308` means pretty and the `Location` reveals the server's canonical
  `base_url`.
- Detection **must run first**; every later request depends on it.
- Sites may live in a subdirectory, so the base can carry a path prefix.

### Authentication

- **A cookie must exist before signing in.** `Login::doLogin()` refuses any
  attempt arriving with no cookie, so `GET /login` first.
- `POST /login` with `username`, `password`, `_csrf`. Token comes from
  `<meta name="csrf">`; an `X-CSRF-TOKEN` header also works. Never send an
  empty `_csrf`.
- **Success and failure both answer `302`.** Omit `url` so it defaults to the
  home page, then read `Location`: a route ending in `/login` **with**
  `username=` means the credentials were rejected; **without** it, the CSRF
  gate failed. Confirm with `GET /my-account` (200 in, 302 out).
- **The session id rotates inside the sign-in redirect** — capture `Set-Cookie`
  before following. The CSRF token survives sign-in but not sign-out.
- Cookie name is scheme-dependent: `__Secure-WT-ID` (https) / `WT2_SESSION`
  (http), with an explicit `Domain` and a path-prefixed `Path`.
- Sessions expire on PHP's `gc_maxlifetime` (24 min idle by default) plus a 24 h
  cap. Activity stamps at most once a minute, so a 10-minute keep-alive is ample.
- **There is no login rate limiting.** Implement client-side backoff so a stale
  stored password does not flood the administrator's authentication log.
- Sign-out is `POST /logout`, CSRF-exempt; sending
  `X-Requested-With: XMLHttpRequest` yields `204` instead of a redirect.

### Bot filtering

- Empty User-Agent → `406`. ~1400 substrings are blocked **case-sensitively**,
  including `aa`. The enforced list is public at `/robots.txt`, so the app
  validates its own agent at connect time.
- A UA containing `Chrome/`, `Firefox/`, `Safari/` or `Opera/` with no cookie is
  served a cookie-challenge stub instead of the page. **Never spoof a browser.**
- Current agent: `WebtreesMobile/0.1.0 (Flutter)`, built from `kAppVersion`
  so it cannot drift from `pubspec.yaml`.

### Access detection

Middleware runs *before* controllers, so a denial is cheap — only success
renders a page. Probe URLs are identical in 2.2.6 and 2.3.0-dev.

| Role | Probe | `200` | `403` | `302` |
|---|---|---|---|---|
| Site administrator | `/admin` | has it | signed in, lacks it | not signed in |
| Manager | `/tree/{t}/changes-log` | ″ | ″ | ″ |
| Moderator | `/tree/{t}/pending` | ″ | ″ | ″ |
| Editor | `/tree/{t}/autocomplete/place?query=zz` | ″ | ″ | ″ |

Probe **bottom-up, stopping at the first refusal** — most users are read-only
members and cost one small request. An administrator is a manager everywhere, so
the per-tree ladder is skipped entirely.

**Member vs Visitor:** distinguishable only for *private* trees. `TreeService::all()`
lists a private tree only for users whose role is not Visitor, so an anonymous
refusal on `/tree/{t}` while signed-in access works **proves membership**.
Public trees stay ambiguous, and the UI must say so rather than guess.

> **The status differs by version, and reading only `404` broke this on 2.3.**
> 2.2.x hands the unmatched route to the not-found handler (`404`); 2.3 lets it
> match with a null tree and `Validator::tree()` throws
> `HttpBadRequestException` (`400`). Both mean "this tree did not bind", and
> the app composed the URL so a `400` cannot be its own malformed request —
> `TreeVisibility.of` accepts both. Confirmed against a private tree on each.
> A `403` still proves nothing.

**`GET /login` answers `400` on 2.3** — and renders the whole page anyway, meta
tags included. So anything reading that page must key on *what the body
contains*, not on the status: the version probe required `200` and lost the
version on every 2.3 site, while sign-in kept working only because it read the
CSRF token out of the body without checking. Both now read the body.

**Only these statuses carry meaning.** A probe answers a question about the
*account*; a `302` or a `5xx` answers a question about the *session* or the
*server*. Folding those into "the role is not held" states something false
about the user, so `core/response_status.dart` enumerates what each operation
accepts and turns anything else into a typed error. Only an anonymous `404`
proves a tree private — re-confirmed live 2026-08-22, along with `302` from an
anonymous `/my-account`.

### What a stock search row actually says

*Confirmed live on 2.2.6 and 2.3, 2026-08-24.* The autocomplete endpoint
renders `views/selects/individual.phtml`, which is a thumbnail, the full name
and `Individual::lifespan()`. That last one is not the string it looks like:

```html
<span title="الكويت، الكويت ⁨حوالي ١٨٧٥⁩">١٨٧٥</span>–<span title=" ⁨١٩٤٥⁩">١٩٤٥</span>
```

Each year is a span whose `title` holds the **place** and the full date of
that event, and the date is wrapped in `U+2068 … U+2069` — which is the only
thing that makes the two halves separable, because the space between them is
the site's own and the place may contain spaces too. So a birth year, a death
year and a birthplace arrive with every search result on an untouched
instance, at no extra request. **Sex does not**, and cannot: `fullName()`
emits a `span.NAME` and nothing else.

The lifespan text is rendered in the site's numerals (`١٨٧٥`), and in the
calendar the record is kept in — see `domain/numerals.dart` and §9 #24.

### Data availability on a stock instance

- **No API exists.** `app/Http/Routes/ApiRoutes.php` is an empty placeholder.
- The only useful JSON is
  `GET /tree/{t}/tom-select-individual?at=&query=X&page=N`. **`at` is
  required** — the handler validates it as `isInArray(['', '@'])->string('at')`
  with no default, so omitting it is a `400`, not an empty result. Empty asks
  for bare xrefs, `@` wraps them in GEDCOM pointer form
  — **search-as-you-type, not a list**. `AbstractTomSelectHandler` returns an
  empty collection unless `query` is non-empty, in both 2.2.6 and 2.3.0-dev, so
  it cannot enumerate a tree. It answers 50 per page plus a `nextUrl`.
  Its `text` is **rendered HTML** from `resources/views/selects/individual.phtml`
  — name and lifespan — carrying a thumbnail **only** when the individual has
  a highlighted media file.
- **Paging is by number, and `nextUrl` cannot be followed.** 50 per page,
  `page` counting from 1, and webtrees fetches one row beyond the page so
  `nextUrl` is an exact statement that more exist — but it builds that URL
  from the tree, `at` and the page **only**, dropping the query. A client that
  followed it would page through an empty search. Verified live: `محمد` gives
  50, then 50 more, with no overlap.
- The search joins the name table, so **someone recorded under two names is
  two rows**; webtrees removes those duplicates only within the page it is
  building, so the same person can arrive again on the next one.
- Enumeration, if ever needed, means `/tree/{t}/individual-list` partitioned by
  surname or initial. Its "show all" mode renders the entire tree server-side,
  so it is not a pagination API. *In-process* it is a different story — see
  "What changes with a server-side module" below.
- Thumbnails are HMAC-signed with a server-side `glide-key` and are
  **unforgeable**; signed URLs must be harvested from HTML or that endpoint.
- **A signed thumbnail URL is not an authorization token.**
  `MediaFileThumbnail` checks `$media->canShow()` for the current user *before*
  validating the signature, and picks watermarking per user. Images must
  therefore be fetched through the authenticated session, and any cache
  partitioned by site and account and cleared on sign-out.
- **webtrees 2.3 cannot make a thumbnail of anything that is not a JPEG.**
  2.3 added `ImageFactory::autoRotateImage()`, which calls `exif_read_data()`
  on every image it resizes (`app/Factories/ImageFactory.php:388`). PHP raises
  `E_WARNING: File not supported` for a PNG, a GIF or a WebP, and
  `Http\Middleware\ErrorHandler` turns any un-silenced warning into an
  exception — so the request answers **`500`**, on the website as much as in
  this app. 2.2.6 has no such call and serves the same file. Confirmed by
  requesting one URL twice with the same bytes stored first as a PNG and then
  as a JPEG: `500`, then `200`. **Worth reporting upstream**, and the reason
  the lab now holds one of each (§7, bug 44). The app already degrades
  correctly — `AuthenticatedImage` draws the placeholder for a photo it cannot
  fetch — which is why nothing had ever noticed.
- **A record URL redirects when the slug is absent.** The route is
  `/individual/{xref}{/slug}`, and the handler compares the given slug against
  one derived from the record's current name, answering `301` to the canonical
  URL otherwise. A search result carries only the xref, so this is the normal
  path, not an edge case. Follow `301`/`308` once; a `302` is still the
  middleware bouncing an expired session to the sign-in page. A bad xref is a
  clean `404`.
- **Every core tab is rendered into the page.** `canLoadAjax()` returns false
  for personal facts, relatives, notes, sources and media, so a stock record
  costs **one** request however many sections it has — confirmed live, where
  `tree.almou.sa` delivers personal facts, relatives and a custom tab inline
  and the app fetches nothing further.
- Record detail otherwise comes from AJAX tab fragments (~10× less markup than
  a full page). **Do not build these URLs.** The individual page renders every
  tab it offers as `<a data-wt-href="…" href="#{module}">`, so the server states
  the exact URL, and which tabs this tree actually has. That matters twice over:
  core tabs can be disabled or access-restricted per tree, and a site can carry
  custom tab modules (`tree.almou.sa` serves `_vytux_cousins_`). Both versions
  route a tab as `/module/{m}/Tab/{tree}?xref={x}`; 2.2.6 additionally declares
  `module-no-tree` (`/module/{m}/{action}`), so the tree may appear in the
  query instead. **The `xref` query parameter is part of the URL** — dropping
  it yields a 200 carrying `The parameter “xref” is missing.`
- **Tab module names are not view directory names.** The app only ever sees
  the module name — `personal_facts`, `relatives`, `notes`, `sources_tab`,
  `media` — which is what the anchor and the fragment URL carry. 2.3 renamed
  the sources tab's *view directory* to `sources-tab`; the module kept the
  underscore, so a client keyed on the directory would ask for a tab that does
  not exist.
- **Notes, sources and media are optional modules**, and their absence is a
  configuration rather than a fault: `tree.almou.sa` runs none of the three
  (sections offered there are `personal_facts`, `relatives`, `tree`, `places`
  and `_vytux_cousins_`). Warning about a section a site never offered would
  put a caution on every record it ever shows.
- Those three tabs share one shape: an ordinary fact row for something
  recorded against the person, and `tr.wt-level-two-{note,source,media}` for
  something hanging off a fact — whose `th.rela` carries **that fact's** label
  and no `.wt-fact-label` at all. They also mark a pending deletion with
  `wt-old` on the **cells**, where `fact.phtml` marks it on the row; a parser
  reading only the row shows a record queued for removal.
- A citation's fields are `label: value` lines webtrees has already worded and
  translated (`%1$s: %2$s`), including the separator — so they are shown whole
  rather than split into a pair the app would have to rejoin.
- **`.wt-fact-record` names the record a fact really belongs to** — the
  sibling whose birth it was, the spouse a marriage was to (with a link to the
  family beside them). Without it "Birth of a brother" names an event and no
  brother.
- **The tab anchor has no `id` in 2.2.6**; 2.3 added `id="{module}-tab"`. Key
  on the `href="#{module}"` fragment, which both emit. A parser keyed on the id
  finds *no tabs at all* on 2.2.6 — the version the target server runs.
- A tab whose module returns `canLoadAjax() === false` is already rendered into
  the page; re-requesting it fetches the same bytes twice.
- Only send `X-Requested-With` on fragment routes — elsewhere it downgrades 4xx
  to 200.
- Record markup is class-based and stable across both versions:
  `span.NAME` (every rendered name), `.wt-fact-label`, `.wt-fact-value`,
  `.wt-fact-date-age`, `.wt-fact-place`, `.wt-fact-type`, and `chart-box` with
  `data-wt-chart-xref`, `.wt-chart-box-name`, `-name-alt`, `-lifespan`,
  `-thumbnail`.
- **Dates are never re-formatted.** webtrees has already applied the tree's
  calendar, the reader's language and its own numerals, and a `DateTime` would
  drop the second calendar and the `about`/`between` qualifiers. But the
  *markup* around a date is readable, and the two versions differ completely:

  | | 2.2.6 (live) | 2.3.0-dev |
  |---|---|---|
  | Primary date | `<a href="…/calendar/day?cal=@#DGREGORIAN@…">١٢ مارس ١٩٠١</a>` | plain text |
  | Conversion | `<span dir="rtl">(<a href="…cal=@#DHIJRI@…">٢١ ذو القعدة ١٣١٨</a>)</span>` | ` [٢١ ذو القعدة ١٣١٨]` |

  The `cal` parameter is **the only place a stock site states which calendar a
  rendered date is in**, which is what makes an honest "show me Hijri only"
  possible. It must be read from the *undecoded* URL: the escape contains `#`,
  so decoding first turns the rest of the query into a fragment.
  A qualified date interleaves the two — `بين ١٩٧٤ (١٣٩٤) و ١٩٧٥ (١٣٩٥)` — so
  the conversion is dropped per date, in place, never by a regex over the
  whole string (`interpreted %s (%s)` puts real parentheses in the text).
  2.3 names no calendar, so the app shows both there rather than guessing.
- **A family's marriage is stated in the relatives tab and nowhere else** on
  a person's page: a row of `span.label` beside `span.field`, rendered by
  `Date::display()` *without* calendar links, so unlike a fact date it carries
  no calendar. A marriage with neither date nor place still prints its
  separators, arriving as a lone dash; and a family with no marriage recorded
  prints **no row at all** for a member — only an editor is offered "Add
  marriage details".
- Relatives carry **no machine-readable role**. The family view emits its
  `FAMC`/`FAMS` type only inside editor-only link text, and the `<th>`
  relationship names are translated. Role is therefore derived structurally:
  spouses render before any marriage-fact row, children after, and the family
  is a birth family or the person's own according to which block holds them.
- **The divider is a marriage, so a family that records none has no divider.**
  A father and a son both render `<tr class="wt-sex-m">` around a chart box,
  and the `<th>` between them is translated — so a family with children, no
  marriage recorded and no second spouse recorded looks exactly like a couple
  followed by children. A real record is that shape (§7, bug 50).
  **The caption is what says otherwise.** webtrees titles each family table
  with the *other* spouse: `الأسرة مع X` (*Family with X*) for one of the
  subject's own, `أسرة الأب مع X` (*Father's family with X*) for a parent's
  other family, and `X + Y` — `Family::fullName()`, with `… …` for a spouse
  the tree does not record — where the subject is a spouse of one of them.
  Only a **birth** family names nobody (*Parents and siblings*), and that is
  also the only table whose first two rows are reliably the couple. Both
  wordings are translated, so nothing reads them: a row is a spouse when its
  own rendered name appears in the caption, which is language-neutral.
  A page also settles its own ambiguities: a step-family hangs off a parent or
  a spouse, and that person's marriage is stated in another table on the same
  page, so who is half of a couple is known before the undivided tables are
  read.
- **A child row prints the gap since the previous child's birth, and that is
  an exact end-of-couple marker.** `family.phtml` starts `$prev` empty and
  fills it from the *marriage*, so in a family that records none the first
  child can never carry `div.wt-date-difference` — and a row that does carry
  one proves the row above it is a child. Same code in both versions. It is
  the one rung of the ladder that needs no caption and no other table, and it
  is what separates a lone father from a father and a mother when nothing else
  can. It needs two children with birth dates; where the tree has none, the
  leading pair is a guess, and §9 #7 says so.
- **The tree's title is only on its own page.** `<h1 class="wt-site-title">`
  in the default layout. The menu that carries titles is rendered only when a
  site allows switching trees, and a site with one tree does not — so for the
  common case this heading is the only thing standing between the reader and a
  home screen called `main`. Theme-dependent, so best-effort.
- **No machine-readable tree list.** Sources, in order: the post-sign-in
  redirect (default tree), the header menu `a[class*=menu-tree-]`, the search
  page `input[name="search_trees[]"]`. The latter two need
  `ALLOW_CHANGE_GEDCOM=1` and more than one tree.
- The user's own XREF is **not** on the account page (disabled control, empty
  value). Read `a.menu-myrecord[href]` from any page of that tree.
- **Every fact webtrees renders inside a chart box names its own GEDCOM tag.**
  `Fact::summary()` emits
  `<div class="fact_DEAT"><span class="label">…</span>: …</div>`, and
  `chart-box.phtml` prints a run of those into `.wt-chart-box-facts` (the
  person's birth and death) and into the hidden `.wt-chart-box-zoom-dropdown`
  beside it (*everything*, their spouse families' facts included).

  The tag in that class is **bare**. `summary()` builds it from the fact's own
  `$tag` property — the word off the GEDCOM line — not from `Fact::tag()`,
  which qualifies it with the record type. So a divorce is `fact_DIV`, never
  `fact_FAM:DIV`. The captured 2.2.6 chart fixtures had this right and a first
  reading of the 2.3 template got it wrong; nothing is lost by the bare form,
  since a death is only ever an individual's and a divorce only ever a
  family's. `FactTagIndex` accepts a qualified class too, for a theme that
  writes one.

  This is the only structural statement a stock site makes about what kind of
  event a row is. Every label on a record page — the facts table, the family
  blocks, a chart's captions — is already translated, and `INDI:SEX` is
  rendered as the *word* for the sex rather than as a class. So the app reads
  a page's chart boxes into a label → tag dictionary
  (`data/stock/fact_tags.dart`) and uses it to name every other fact on that
  same page. That is what makes "is this person dead", "did this marriage end
  in divorce" and "which icon does this row get" answerable in Arabic.

  **Confirmed against `tree.almou.sa` (2.2.6) on 2026-08-23.** The live check
  reads the subject's own sex and lifespan out of their chart box, types all
  13 of their relatives, finds the 2 the tree records as dead, and recovers
  `BIRT` from the fact block — which is also what settled the class form.

  It also showed the honest limit: **the dictionary only learns the tags a
  page's chart boxes actually rendered.** A living person's box has no `DEAT`,
  and a *relative's* death appears in the facts table under its own label
  (`وفاة الأب` — "death of the father"), which no box ever printed. Those rows
  keep the neutral icon, which is the right answer rather than a wrong one.
- **A person's own sex, lifespan and death come from the relatives tab, not
  from their page.** They appear in their own family tables as a chart box
  like anybody else, and that box carries `wt-chart-box-{m,f,u}`, the
  lifespan, and the death fact. The individual page states the sex only as
  the translated word for it, and the silhouette class
  (`wt-individual-silhouette-m`) exists only for someone with no media on a
  tree with silhouettes on — kept as a fallback, relied on for nothing.

### What changes with a server-side module

Everything above describes what a *stock* instance publishes over HTTP. A
custom module runs **inside** webtrees, so it is bound by different rules —
confirmed by reading both versions while writing `api_eval.md`.

- **Module routes are still bound by the global middleware.**
  `app/Webtrees.php:154` orders it
  `… BadBotBlocker … UseSession → UseLanguage → … → BootModules → Router`,
  and a module's own route middleware runs *inside* `Router`. Three
  consequences:
  - The **bad-bot User-Agent rule applies to API routes too**, so `kUserAgent`
    and `BotListCheck` stay load-bearing even if every parser is retired.
  - `CheckCsrf` is injected unconditionally by `Router`, and its
    `EXCLUDE_ROUTES` is a `private const` a module cannot extend — so read
    endpoints must be **GET**, which sidesteps the question entirely.
  - A module **can** set the request language per request. `UseLanguage`
    consults `Accept-Language` only when the session holds none, but a module
    middleware runs after it and may call `I18N::init($tag)` for that request
    alone — **without** writing the account's stored preference, which no stock
    route can avoid (§9 #16).
- **Handlers are version-portable; route registration is not.** 2.3's
  `InvokeController` begins `if ($controller instanceof
  RequestHandlerInterface) return $controller->handle($request);` — which is
  all 2.2.6's `RequestHandler` ever did. So a PSR-15 handler is version-neutral.

  **The compat surface is eleven methods.** This table replaces the seven-row
  one written before the module existed: building it found five differences
  that reading had missed and three rows that were never needed. Confirmed by
  `tool/check_module.py`, which resolves every import against both versions.

  | Concern | 2.2.6 | 2.3 |
  |---|---|---|
  | `Registry::routeFactory()->routeMap()` | `Aura\Router\Map`, `->get($name,$path)->extras(…)` | `RouteCollection`, `->add($url,$class,$mw)` |
  | Fact sorting | `Fact::sortFacts()` (static) | `Services\FactSortService::sort()` |
  | Families by marriage date | `Family::marriageDateComparator()` | `Comparators\FamilyComparator::byMarriageDate` |
  | Children by birth date | `Individual::birthDateComparator()` | `Comparators\IndividualComparator::byBirthDate` |
  | `Individual::sex()` | `string` — `M`/`F`/`U`/`X` | `Enums\Sex`, backed by the same letters |
  | Date qualifier | `Date::$qual1` / `$qual2` | `Date::$type` (`DateType`) |
  | Calendar escape | `AbstractCalendarDate::ESCAPE` const | `calendarEscape()`, a `CalendarEscape` enum |
  | A calendar date as GEDCOM | `format('%@ %A %O %E')` | `format()` gone — assemble from `calendarEscape()`, `day()`, `gedcomMonth()`, `year()` |
  | `StatisticsData::countIndividualsBySex()` | takes the letter | takes `Enums\Sex` |
  | A site's language tags | `ModuleLanguageInterface::locale()` | `->language()`; `Factories\LanguageFactory` is 2.3-only |
  | Adapter identity | — | reported by `/capabilities` as `generation` |

  **Three differences turn out not to be differences at all**, and the first is
  the useful one. *Access level never comes up*: `canShow()`, `canShowName()`,
  `facts($filter, $sort, $access_level)` and `Fact::canShow()` all default to
  the current user's, so code that lets webtrees decide never names
  `Auth::PRIV_*` or `AccessLevel`. *`UserService`* is never constructed —
  both containers autowire it from its type hints, `ClockInterface` included.
  *The matched route object* only matters to code that inspects a route.

  Two more were avoided rather than adapted. `ResponseFactoryInterface::response()`
  takes an `int` in 2.2.6 and an `HttpStatusCode` in 2.3 — so the module builds
  every response from the **PSR-17** factories both versions bind in the
  container, and names no status type. And `I18N::language()->formatDate()`,
  which `api_eval.md` recommended for rendering a converted date, **does not
  exist in 2.2.6** — `Date::display(null, null, false)` does, in both, and with
  its tags stripped it is the same string.

  Privacy, search, charts, media, facts, names and `StatisticsData` have
  **identical** public APIs in both — which is why `webtrees-API` failing on
  2.3 twice over (the Aura router *and* `Auth::PRIV_*`) is a property of its
  design rather than of webtrees.
- **A module route is not always reached.** On 2.2.6, when `{tree}` names a
  tree that does not exist or that the reader may not see, `Router` hands the
  request to webtrees' own not-found handler **before** module middleware runs
  — so the `404` arrives as an HTML page rather than as the module's error
  envelope. 2.3 binds the attribute to null and lets the handler answer. A
  client must read any `404` as not-found regardless of the body.
- **Privacy needs no reimplementation.** `GedcomRecord::canShow()`,
  `canShowName()`, `facts($filter, $sort, $access_level)` and
  `Fact::canShow()` all default to the current user's `Auth::accessLevel()`,
  and a `{tree}` route parameter binds through `TreeService::all()`, which
  already hides trees the user may not see. A module authenticating as the real
  person inherits the model exactly — relationship privacy included.
- **A tree *can* be enumerated in-process, though not over a stock route.**
  `SearchService::searchIndividualNames($trees, $search, $offset, $limit)`
  applies no filter for an empty term array, so the same method that searches
  also walks a whole tree ordered by `n_sort`.
  **Its paging does not fix the multi-name trap, and reading it carelessly says
  it does.** `paginateQuery()` dedupes against the collection it is *building*
  and counts the offset down over rows it has not deduped, so `offset=5` counts
  five *rows* where `limit=5` answered five *people* — and a person recorded
  under two names arrives again on the next page. Same code in 2.2.6 and 2.3,
  and it is the trap the stock autocomplete has, inherited rather than avoided
  (§7, bug 53). What removes it is asking from the top every time — at
  `offset=0` every accepted row is pushed, so the dedup set is everything
  walked — and taking the page in the module.
  It is a PHP cursor rather than a SQL `LIMIT`, so the cost is `O(offset)` in
  time, and `O(offset)` in memory once the page is taken this way: measured on
  a 1,469-person tree, a page at offset 1,400 costs 0.13 s against 0.05 s at
  the top and runs inside a 16 MB `memory_limit`.
- **Ordering by xref needs none of that.** `individuals` is keyed
  `(i_file, i_id)`, so a walk that does not care about name order is a real
  SQL `LIMIT` over an index: no join to `name`, no duplicates, and `O(1)` in
  the offset — 0.26 s per page of fifty full records whether the offset is 0 or
  1,400. Which is why the sync endpoint orders by xref and the search endpoint
  cannot.
- **An import writes no change rows, and deletes the ones there were.**
  `GedcomLoad` truncates `change` for the tree before reading the first record
  — `Http/RequestHandlers/GedcomLoad.php:106` on 2.2.6,
  `Http/Controllers/GedcomLoad.php` on 2.3, and `Cli/Commands/TreeImport.php`
  on both. Confirmed on the labs, where a freshly imported 19-person tree has
  `MAX(change_id)` of nothing at all. So a watermark taken from that column
  moves *backwards* after a re-import, which is what makes it a resync trigger;
  and it cannot see the import itself, which is why the tree's record counts
  are part of the fingerprint. What neither can see is in §9 #27.
- **`LinkedRecordService` answers "who does this record show up on".**
  `linkedIndividuals()` and `linkedFamilies()` are public, identical in both
  versions, and already privacy-filtered — and the `link` table holds **both
  directions** (`F1 CHIL X42` *and* `X42 FAMC F1`), so one hop finds the people
  a note or a photograph hangs on and two hops find everyone in a changed
  person's families.
- **Media can be requested at any size.** `MediaFile::imageUrl($w, $h, $fit)`
  mints the signed URL server-side and `downloadUrl()` addresses the original.
  The 100-pixel ceiling in §9 #3 is a property of the media *tab*, not of
  webtrees.
- **Labels and tags can both be had.** `Registry::elementFactory()->make($tag)
  ->label()` gives the translated label for any tag and `->value($v, $tree)` the
  translated form of an enumerated value. This is what `FactTagIndex` exists to
  approximate from chart-box classes — and unlike the dictionary, it can name a
  tag no chart box ever rendered.
- **Relationship *naming* is public; relationship *path-finding* is not.**
  `RelationshipService::nameFromPath()` is public, so the site's own wording
  survives. But `RelationshipsChartModule::calculateRelationships()` is
  `private`, along with `allAncestors()` and `excludeFamilies()` — roughly 150
  lines of Dijkstra over the `link` table that a module must reimplement.
  `fisharebest/algorithm` is already a core dependency, so the algorithm is
  available; the graph construction and the exclusion loop are not. It would be
  the module's **only** duplicated core logic, and therefore its only silent
  drift risk.
- **Tree privacy is a column, not a preference.** Schema 45 moved
  `REQUIRE_AUTHENTICATION` out of `gedcom_setting` and into a `private` column
  on `gedcom`. 2.2.6 kept a deprecated shim that redirects the write (with no
  `WHERE` clause, so it makes *every* tree private); 2.3 removed it, and the
  write lands in a table nothing reads. Anything setting it must write the
  column. `Tree::private()` reads it correctly in both, which is what the
  module uses.
- **A module may set CORS headers.** `SecurityHeaders` sets five headers, none
  of them CORS, and only fills in what a response has not already set — so a
  module route can add `Access-Control-Allow-Origin`. Flutter Web is ruled out
  on a stock instance (§3, Platform) and would become possible with one.

Full treatment, with the endpoint set and the migration order, in
`api_eval.md`.

### Charts

webtrees draws twelve charts, and the app cannot show any of them as they
arrive: they are HTML for a wide screen, positioned with floats, background
images and a reading direction baked into the stylesheet. What the app takes
is the **shape** — who descends from whom — and draws it again.

- **The generations count is in the route and is not clamped by the tree.**
  An ancestors or descendants route ends `{kind}-{style}-{generations}/{xref}`
  and the handler reads that segment with
  `isBetween(MINIMUM_GENERATIONS, MAXIMUM_GENERATIONS)` — 2 to 63 — with no
  tree preference narrowing it. So asking for a different depth is a request
  the server means to answer. Rewritten in the *address* rather than in the
  decoded route: the two URL styles differ only in how the slashes are
  written, and `ancestors-tree-4` appears verbatim in both.
- **A d'Aboville number runs across all of a person's families.** webtrees
  declares `$child_number` before its family loop and never resets it, so a
  second marriage continues the count. Numbering per family gave two children
  `1.1` (§7, bug 26).
- **A relationship's "ancestors" setting is in the route and is *not* clamped
  by the tree.** `relationships-{ancestors}-{recursion}/{xref}{/xref2}`, and
  the handler reads the first number with
  `Validator::attributes(...)->integer('ancestors')`. `RELATIONSHIP_ANCESTORS`
  is only used to fill in the form on the page webtrees does not send. So a
  site set to blood lines only — which `tree.almou.sa` is — can still be asked
  "any relationship", and that is the only way a link through a marriage is
  ever found. The **recursion** beside it *is* clamped, by
  `min($recursion, $max_recursion)`, and is left alone: it is what stops a
  deep search costing the server a minute.
- **There is no server-side "mother's side".** webtrees offers exactly the one
  choice above. But it answers with *every* path it found, and a path's first
  step says which of the subject's own relatives it leaves through — so
  matching that against the parents and spouses the record already names sorts
  the answers into the ways a person actually asks the question. Structural,
  so it works the same in both languages.

- **A site states which charts it runs, per person.** Every link webtrees makes
  to a chart carries a class naming it: `menu-chart-ancestry`,
  `menu-chart-descendants`, `menu-chart-fanchart`, `menu-chart-compact`,
  `menu-chart-hourglass`, `menu-chart-familybook`, `menu-chart-pedigree`,
  `menu-chart-pedigreemap`, `menu-chart-relationship`, `menu-chart-tree`,
  `menu-chart-timeline`, `menu-chart-lifespan`, `menu-chart-statistics`. The
  same vocabulary in 2.2.6 and 2.3. The page menu (`li.menu-chart`) holds the
  links for *this* person; the identical classes also appear inside every
  chart box on the page, each pointing at whoever that box holds.
- **The URL is the site's, settings and all.** A chart route carries its
  parameters as path segments — `/tree/{t}/ancestors-{style}-{generations}/{x}`
  — so the number of generations is the administrator's choice, in the link.
  Rebuilding that URL would quietly overrule them. Live, this instance offers
  `ancestors-tree-4`, `descendants-tree-3`, `fan-chart-3-4-100`,
  `hourglass-3-0`, `family-book-2-5-0`, `pedigree-right-4`,
  `relationships-1-3`, `compact`.
- **`?ajax=1` answers the chart alone**, which is how webtrees' own JavaScript
  asks; without it every chart route sends a whole page — form, menu, footer —
  around the same markup.
- **The ancestors chart states the structure twice**, and only one of them can
  be read safely. Each box is followed by a `div.wt-sosa-number` holding its
  Sosa-Stradonitz number — rendered with `I18N::number`, so in Arabic it
  arrives as `٤` — while the nesting says the same thing in every language.
  The app reads the nesting and computes the numbering itself, by webtrees'
  own rule (parents of *n* are 2*n* and 2*n*+1, the even slot going to whoever
  is *not* recorded female). The parser tests check that derivation against the
  numbers the server printed.
- **The descendants chart numbers people in plain digits**, because a
  d'Aboville number (`1.2.1`) is built by joining integers rather than
  formatting a number. Two numbering schemes on two charts, one localized and
  one not — which is exactly why neither is depended on.
- A descendants family block holds the spouse's box directly, before the rows
  holding the children: it is the one chart box there that is nobody's
  subtree. Each family is announced by a control carrying webtrees' own
  summary — *Marriage 1925 — 2 children* — already translated.
- The two charts' markup is identical in 2.2.6 and 2.3 but for one thing: 2.3
  keeps the calendar link inside a marriage date on that control, where 2.2.6
  strips the tags. Read as text, both say the same.
- **A chart can hold the same person twice.** Cousins marry, and this project's
  own tree is a family where that is ordinary — so anything that looked a box
  up by person rather than remembering where it placed it would find the wrong
  one of them.
- **A relationship is a path, and the path is walkable.** webtrees lays the
  chart out as a grid of positioned cells — lines drawn in background images,
  a shape that says nothing on a phone — but it prints *every* cell, empty
  ones included, so a row and column index is a position rather than a guess.
  Each step's name sits between the two people it links, one cell away in a
  straight line or on a diagonal where the path turns a corner, so walking
  from a known starting box recovers the order. The `<h3>` above the grid
  carries webtrees' own phrase for the whole relationship — *القرابة: إبن* —
  which no app should try to compose for itself: Arabic separates an older
  brother from a younger one, and English has no word for the difference.
- **`relationships-{ancestors}-{recursion}` decides what counts as related.**
  With `ancestors` set — as it is on `tree.almou.sa`, which serves
  `relationships-1-3` — the site searches only through common ancestors, so
  two people linked by a marriage answer *no link found*. That is a correct
  answer, and looks like a failure unless the app reads the setting out of the
  URL and says so.
- **The relationship route is the one address the app edits.** It ends
  `…/{xref}` and takes an optional second xref after it, and a page only ever
  links to one person at a time — so the app appends the other. Every other
  part of the URL, both settings included, is left as the site wrote it.
- **A statistics page says everything twice.** Its counts are in the markup —
  `<h4>Total individuals <span class="badge">١٬٤٦٣</span></h4>`, rendered in
  the reader's own numerals — and the data behind each of its charts is in a
  `<script>` beside it, handed to the site's charting library as **plain
  numbers**. So the counts are shown exactly as they arrived and the charts
  are redrawn from the numbers, which is also why a chart's numerals have to
  be written by the app: `NumberFormat` for `ar` produces Latin digits, and a
  screen that changed numerals halfway down would look broken.
- The page itself holds only tabs, each naming its fragment in `data-wt-href`
  exactly as a record's tabs do — including one that holds a *form* for
  building a chart rather than a chart. It is read and found to contain no
  figures, rather than skipped by its name.
- **The data is JSON; the options beside it are not** — *on 2.2.x*. webtrees
  writes some option objects by hand, with comments and unquoted keys, so a
  parser that decoded both would drop every chart whose options were
  hand-written, which is most of the pie charts (§7, bug 23).
- **2.3 replaced Google Charts with Chart.js, and moved the data out of the
  script entirely.** It is now on the canvas: `data-wt-chart-type`,
  `data-wt-chart-data` and `data-wt-chart-options`. The data is Chart.js's own
  shape — `labels` down the side, one `datasets` entry per series holding a
  `data` array parallel to them — which is the *transpose* of what Google
  Charts took, so rows are rebuilt rather than copied. A break and an
  improvement at once: the options are now **strict JSON**, which retires bug
  23 on 2.3. Read from a fixture captured off a running 2.3, because the
  hand-written one that preceded it was the reason nobody noticed (§7, bug 30).
- A map chart names each place twice, `{"v": "KW", "f": "الكويت"}`: the code it
  plots by and the name a reader wants.
- **A timeline states its own scale.** Every year label is a `div` whose id
  carries the year in plain digits — `id="scale1938"` — and whose style
  carries its position; every event is a `div#factN` positioned the same way.
  So the app compares positions with positions and never reads a date: the
  event's label already carries one, written by the server in whichever
  calendars the tree converts to. Reading a year *out of* a box's position
  would also be wrong by one — the box sits a few pixels above the line it
  points at.
- 2.3 rewrote the fact box with classes and `data-wt-timeline-*` attributes,
  and kept the ids and the positions. A parser keyed on either survives both.
- **Not every chart is a fetch.** A fan chart is an ancestors chart bent round
  a circle, a compact chart is the same one with smaller boxes, and an
  hourglass is the two charts either side of a person stitched at the middle.
  webtrees renders all three itself; asking for them would mean three more
  parsers describing families the app has already read. What is fetched and
  what is drawn are therefore different sets — a distinction the live check
  learned the hard way (§7, bug 22).

### Languages

The interface is English and Arabic, and both are first class — the tree this
was built against is Arabic, so RTL is the case the layout was designed for
rather than a late adaptation.

- **The server, not the app, writes the dates.** Fact labels, month names and
  numerals all come from webtrees, in the language held in **its own session**
  — which `Login::doLogin` seeds from the *account's* stored preference.
  `Accept-Language` is consulted only before that value exists, so it is
  useless after sign-in. The app therefore posts `/language/{tag}` after every
  sign-in and whenever the reader switches: CSRF-exempt in both versions,
  answers `204`, verified live. **It also writes the account's own preference**
  — `SelectLanguage` sets both and there is no stock route that sets only the
  session — so the website greets that user in the same language afterwards.
  The settings sheet says so rather than letting it be a surprise.
  `en` maps to `en-GB`, which orders a date day-first as Arabic does.
- **Latin runs inside Arabic need isolating.** A lifespan is all digits and a
  dash, so the bidirectional algorithm takes its direction from the paragraph:
  `1875–1940` renders as `1940–1875`, and the person dies before they are
  born. `features/shared/bidi.dart` wraps such runs in U+2066/U+2069, which is
  what webtrees itself does in the markup it sends.
- **The data layer never writes a sentence.** `domain/notice.dart` carries the
  facts of a caveat and `core/errors.dart` the facts of a failure; both are
  sealed, and `features/shared/messages.dart` turns them into words with
  exhaustive switches. A new case fails to compile until it has been given
  words in both languages.
- **Tracking is Latin-only.** `letterSpacing` inserts space *between* glyphs.
  Arabic is cursive and joins, so the negative tracking that sharpens a Latin
  headline pulls Arabic words apart. `AppTheme` therefore takes the resolved
  locale and zeroes tracking for Arabic, and adds a little leading.
- **Identifiers stay LTR inside an RTL page.** A hostname, an xref and a
  version are Latin whichever way the interface reads, so those specific runs
  pin `TextDirection.ltr`; the rows around them still mirror.
- **Directional icons must mirror.** `Icons.chevron_right` points right in
  Arabic too, which is backwards; `Icons.arrow_forward_ios` follows the
  reading direction.
- Language and theme are chosen in a sheet reachable from the **first** screen,
  because someone who reads Arabic should not have to work through an English
  sign-in form to find the switch. Both default to following the device.

### Typography

**Cairo** (SIL OFL, `assets/fonts/Cairo-OFL.txt`) covers Arabic and Latin in
one family, so the interface keeps one voice in both directions instead of
falling back to a system face for Arabic. Instanced from the upstream variable
font at five static weights: a variable font needs `fontVariations` on every
style, and any widget calling `copyWith(fontWeight:)` would silently ignore it.

### Platform

- **Gradle's heap must fit the machine.** The Flutter template writes
  `org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G` into
  `android/gradle.properties`. This machine has 5G of RAM, so the daemon was
  killed by the kernel partway through `assembleRelease` — which Gradle
  reports as "build daemon disappeared unexpectedly", a message that reads
  like a crash and is really a heap it was never going to be given. Sized down
  to 2G; a project this small has never come close to needing more.

**No CORS headers → Flutter Web cannot work.** Mobile and desktop only. This
is a property of the stock instance rather than of webtrees: `SecurityHeaders`
sets no CORS header at all, so a module could add one on its own routes.
`local_auth` has no Linux support, so the biometric gate degrades to an open
gate on desktop — the sign-in screen now says so in as many words, rather than
promising a fingerprint prompt that will never appear.

#### iOS packaging

`Info.plist` carries `NSFaceIDUsageDescription` (without it iOS kills the app
the first time Face ID is requested) and an App Transport Security policy.
`NSAllowsLocalNetworking` permits the app's deliberate `http://` support for
**local** addresses only; unlike Android's blanket `usesCleartextTraffic`, a
public `http://` site stays blocked on iOS. Neither has been exercised on a
real device — see §9.

#### Android packaging

Four things `flutter create` does not set up correctly for this app. All are
committed; listed here because each fails silently or only on a real device.

| Problem | Fix |
|---|---|
| `INTERNET` permission is only in the **debug** manifest, so a release build has no network at all | Added to `app/src/main/AndroidManifest.xml` |
| `local_auth` needs a fragment host; the default `FlutterActivity` throws at runtime when the biometric prompt opens | `MainActivity : FlutterFragmentActivity` |
| Android 9+ blocks cleartext, killing the app's deliberate `http://` support for LAN instances | `android:usesCleartextTraffic="true"` — the sign-in screen already warns before sending a password over http |
| `flutter_secure_storage` 11 hardcodes `compileSdk = 37`; the SDK manager installs that as `android-37.0` (new minor-version scheme) which Gradle's `android-37` lookup cannot resolve | Root `build.gradle.kts` pins plugin modules to the installed SDK 36. Must be registered **before** the existing `evaluationDependsOn(":app")`, or `afterEvaluate` is too late to hook |

Release builds are signed with the **debug key** (Flutter's default), which is
fine for sideloading but means a differently-signed build cannot upgrade over
it. A real signing config is needed before any distribution.

---

## 4. Architecture

```
webtrees_mobile/
  lib/
    core/      webtrees_url · webtrees_client · errors · response_status
               secret_store · unlock_gate
    l10n/      app_en.arb · app_ar.arb  (generated AppText)
    data/      transport (the interfaces) · capabilities (the composer)
               instance_probe · session · access_probe
               credential_store · session_manager · settings_store
      stock/   dom · chart_box · record_parser · records_repository
               chart_parser · charts_repository · media_cache
      module/  module_api · module_decode · module_records
               module_charts · module_access
      local/   store (the schema) · store_open (the only Flutter in here)
               records_page · sync · local_records
    domain/    instance · access · records · charts · dates · notice
    features/  launch · connect · auth · access · browse · charts · shared
  server/webtrees-mobile-api/   the optional webtrees module (PHP)
    src/Compat/                 the whole 2.2-vs-2.3 surface: eleven methods
    src/Http/                   Json · ApiException · middleware · handlers
    src/Presenters/             person · fact · date · place · family · media
    src/Support/                parameter validation · one whole record
                                the sync fingerprint · the relationship graph
```

`data/transport.dart` says what the app needs from an instance;
`data/capabilities.dart` decides, **per capability**, which implementation
answers it. A site with no module — which is every real site today — takes the
stock path for everything, and that is the floor rather than a fallback.

`data/local/` is a **third implementation of the same interfaces**, not a
cache bolted to the side. That was `sync_eval.md` §10's finding and it held:
the screens depend on `RecordsTransport`, the composer already chooses per
capability, and chart screens already take opaque *handles* from whoever
minted them — so a store answers by implementing the interface and no screen
changes. Two things pass straight through it, and neither is a shortcoming: a
thumbnail's bytes, because a signed URL is not an authorization token and
`MediaFileThumbnail` checks the viewer before the signature; and the tree's
statistics, which are read from the page on purpose.

`data/module/module_decode.dart` has one entry point for a whole record, used
by the module transport *and* by the store. That is what makes "the store
cannot disagree with the server about what a record says" a property of the
code: the store keeps the endpoint's own bytes and decodes them with the same
function — the client-side twin of `RecordComposer`, which is why
`/individual` and `/records` cannot disagree either.

`data/stock/chart_box.dart` is shared on purpose: `chart-box` is the one piece
of markup every part of webtrees agrees on — the relatives tab, a pedigree, a
fan chart and a relationship path all draw a person with it — so one reader
serves every parser.

`features/charts/chart_layout.dart` holds no widgets. Where a box lands is
arithmetic, and arithmetic can be tested without pumping a frame; mirroring
the finished layout for Arabic is then one flag rather than a second
algorithm.

`domain/dates.dart` is the one place the app reasons *about* a date without
re-formatting it: webtrees' own rendering is kept verbatim, and the structure
beside it exists only to drop a calendar the reader did not ask for.
`features/shared/bidi.dart` is its counterpart for layout — the Latin runs that
an Arabic paragraph would otherwise reorder.

Repositories depend on a transport **interface**; a capability probe at connect
time selects the implementation. v1 ships stock only — adding the module later
is a new implementation, not a rewrite. Compose at the level of *capabilities*
rather than swapping one global transport: a module might serve structured
person detail while stock routes still handle search and media.

`SessionManager` owns authentication and nothing else. Phase 3 browsing state
belongs elsewhere — it is the obvious place for a god object to form.

Per `CLAUDE.md`: built-in state management (`ChangeNotifier` / `ValueNotifier` +
`ListenableBuilder`), `go_router`, manual constructor injection, `snake_case`
files, 80-column lines, `dart:developer` for logging.

Multi-instance support is designed in from the start (saved connections, one
active) — cheap now, painful to retrofit.

---

## 5. Phases and status

Legend: ✅ done · 🚧 in progress · ⏸ deferred · ⬜ not started

| Phase | Deliverable | Status |
|---|---|---|
| **0** | Wire spike — validate every assumption against a real server | ✅ |
| **1a** | Connection + session **data layer** | ✅ |
| **1b** | Credential store (keystore + biometric gate) | ✅ |
| **1c** | Session manager (keep-alive, silent re-login) | ✅ |
| **1d** | Connect + sign-in **screens** | ✅ |
| **2a** | Access detection **data layer** (trees, roles, account) | ✅ |
| **2b** | Capability probe for the optional module | ✅ — `GET /mobile-api/v1/capabilities`, selected per capability |
| **2c** | "Your access" screen | ✅ |
| **2d** | Stabilization — status interpretation, resume, credential semantics | ✅ |
| **3a** | Vertical slice — search → person → facts → relatives → photo | ✅ |
| **3b** | Rest of the read model (families, sources, notes, media tab, paging) | ✅ |
| **4** | Interface (Material 3 Expressive theme, Arabic/RTL, navigation) | ✅ |
| **4a** | Getting out of the way — resume, one-tree, back stack, calendar choice | ✅ |
| **5** | Hardening (golden tests, CI, failure states, diagnostics) | ✅ |
| **6a** | Charts: discovery, ancestors and descendants, drawn natively | ✅ |
| **6b** | Charts: fan/circle, compact, hourglass — the same data, redrawn | ✅ |
| **6c** | Relationships — how any two people in a tree are connected | ✅ |
| **6d** | Statistics — the counts, and the datasets behind its charts | ✅ |
| **6e** | Timeline — a life against a scale of years | ✅ |
| **6f** | Lifespans — several lives compared against one scale | ⬜ |
| **7a** | Identity — who a person is, seen before it is read | ✅ |
| **7b** | Charts — grouping, marital status, controls, export | ✅ |
| **7c** | Relationships — the path drawn, and the ways through it | ✅ |
| **8a** | The server module — a read-only JSON API, and the transports to use it | ✅ |
| **8b** | The lab: 2.2.6 and 2.3 installs, the module running, both transports diffed | ✅ — then against the real tree, see §9 #18 |
| **8c** | What a reader saw: family facts, the mourning ribbon, the whole chart, a PDF drawn as shapes | ✅ |
| **8d** | The capability ledger: every remaining capability diffed transport against transport, and a lab with a photograph in it | ✅ — nine cleared, `statistics` deliberately not |
| **9a** | Relationships drawn: a path as a family tree, and the direction each step runs | ✅ |
| **9b** | Narrowing a page of search results — sex, age or year of birth, birthplace | ✅ |
| **10a** | The sync wire: the whole tree in pages, then only what changed | ✅ — module `/records`, measured on 1,469 people |
| **10b** | Drift schema, a local transport, the sync loop off the UI isolate | ✅ — the store fills from the real tree; nothing composes it yet |
| **10c** | The store answers `individual`, `individuals`, `family` — **tree-wide filters** | ✅ — encrypted at rest, composed, and filled on first use |
| **10d–f** | Charts and timeline from the store · thumbnail blobs and a sync screen · a ceiling for large trees | ⬜ — `sync_eval.md` §12. 10f is the one with a deadline: the search page cap is 2,000, which is a placeholder, not a design |
| **v2** | Offline sync · editing · moderation · device tokens | ⬜ — the read-only module is done; §8 of `api_eval.md` covers the rest |

**Phase 6 shape.** webtrees offers twelve charts; the app draws none of their
markup, because all of it is HTML for a wide mouse-driven screen. What it takes
is the shape, and what it does with the shape is its own business — which is
the only way a chart mirrors for Arabic, fits a phone, and lets a reader walk
from a box to the person.

| webtrees chart | Where its shape comes from | State |
|---|---|---|
| Ancestry, Pedigree | the ancestors chart, read from its nesting | ✅ 6a |
| Descendancy | the descendants chart, read from its nesting | ✅ 6a |
| Interactive | not a fetch: pan, zoom, and tap to redraw around anyone | ✅ 6a |
| Circle (fan), Compact | the same ancestors data, laid out differently | ✅ 6b |
| Hourglass | ancestors *and* descendants of one person, stitched at the subject | ✅ 6b |
| Family book | the hourglass with every spouse's family drawn too | 6c |
| Relationships | the server's own path between two people, walked out of its grid | ✅ 6c, drawn as a tree in 9a |
| Timeline | event boxes and year labels, each stating its own position | ✅ 6e |
| Lifespan | bars positioned against a scale of decades, the same way | 6f |
| Statistics | plain counts in the markup, **and** chart data as JSON inside `statistics.draw*Chart(…)` calls | ✅ 6d |
| Pedigree map | a map. Out of scope for v1 — no map dependency is worth the weight yet | — |

### Which capabilities are cleared for the module

`api_eval.md` §13 rule 6: a capability moves to the module only once its
endpoint has passed live against real data. This is that ledger — and it is
**not** a list of parsers to delete. §11's rule is permanent: every capability
keeps its HTML path, because the first constraint in §1 is that the app works
against an untouched instance. "Cleared" means the capability composer may
prefer the module where one is installed, which it already does automatically;
the parser behind it stays, fixtures and all, and stays tested.

| Capability | What both transports were asked | Evidence | Cleared |
|---|---|---|---|
| `access` | account, admin, tree count, role, own record | the real tree | ✅ |
| `individual` | name, sex, deceased, lifespan, parents, siblings, spouses, children, primary facts, tags, family events, dates in both calendars | the real tree | ✅ |
| `individuals` | same result count for the same query; enumeration; each person's birth year and birthplace, and an age where one can be computed | the real tree | ✅ |
| `notes`, `sources` | how many of each a record carries, and which hang off a fact | both labs — the real site runs neither tab | ✅ |
| `media` | how many items, which are on a fact, and the bytes of every thumbnail | both labs — this account can see none of the real tree's 86 | ✅ |
| `family` | each family's membership by xref — kind, spouses, children | the real tree | ✅ |
| `ancestors`, `descendants` | how many people, how many generations, and **the shape**: who sits at which Sosa or d'Aboville number | the real tree | ✅ |
| `relationship` | how many paths, the site's own phrase for the whole relationship, each step's word and person, and which way each step runs | the real tree | ✅ |
| `timeline` | which events, in what order | the real tree | ✅ |
| `statistics` | the figures both state — and the module answers **four** sections where the page publishes seventeen | the real tree | ❌ **read from the page** |
| `records` | the whole tree in pages, then a delta: every record identical to the one `/individual` answers, nobody handed over twice, a fingerprint that refuses what it cannot follow | both labs, 19 people and then 1,469 — **and the real tree: 1,463 people in 30 requests, filling a real store** | ✅ **composed since 10c** — the store answers `individual` and `individuals`; everything else stays online |

All of them have now been run against **`tree.almou.sa`** — the real
1,463-person tree with the module installed — as well as against both labs on
both webtrees versions. What the real tree adds, capability by capability: a
family's membership by xref, a nine-person descendant chart with its
d'Aboville numbering, a seven-person pedigree with its Sosa numbering, a path,
a timeline, and the statistics total. It found one disagreement, on a name
(§7, bug 48), which is the fourth time a real record has told the two
transports apart and the fourth time one of them was simply right.

One caveat the table cannot carry: **`tree.almou.sa` runs module 1.0.1** and
this repository is at **1.2.0**, so the real-tree evidence for `relationship`
and `timeline` is evidence about the *previous* module. Both differ there
exactly as this session's fixes predict — the bare kinship word, and a
timeline event without its calendar conversion — and both agree on the labs,
which run the code here. The same goes for the two module fixes the real tree
itself produced (§7, bugs 48 and 49): a name and a burial, both corrected
here, neither deployed there. **1.2.0 adds a step's direction** and **1.2.1
adds an age**; a module older than each falls back honestly — a relationship
tree drawn on one flat row, saying so on the screen, and a filter offering the
printed years instead of an age. **Updating the instance is the one
outstanding action, and it is not something this machine can do.**

Two capabilities are cleared on labs alone and cannot be more than that here:
`notes` and `sources` — `tree.almou.sa` runs neither tab module — and `media`,
which it runs no tab for and shows this account none of its 86 objects.

Clearing them cost three fixes, all found the first time the two were asked
the same question (§7, bugs 45–47): the module's relationship description was
the bare kinship word where the page writes the site's own *"Relationship: X"*;
its timeline had dropped both the calendar conversion and the couple a
marriage belongs to, so a man's two marriages were two identical rows; and the
app was preferring the module for statistics, which shows less.

**`statistics` is the one capability the app reads from the page on purpose.**
Not a disagreement — every figure both state matches — but the module sends a
chosen set where the page publishes everything the site computes. The rule
lives in `Capability.readFromThePage`, and the diagnostics screen reads the
same rule, so it reports where a figure actually came from. It moves when the
endpoint covers the page.

**Exit criteria**

- *Phase 1* — connect to `tree.almou.sa`, sign in, restart the app, still signed
  in. A wrong password shows a specific error, not a generic failure.
- *Phase 2* — the app shows the real role for each tree, matching the web UI.
- *Phase 3* — open an individual and see name, facts, dates, places, parents,
  spouses, children and photo, matching the web UI.

**Phase 3 shape.** One thin vertical slice first — search by name → open a
person → parse facts and relatives → load the thumbnail *through the
authenticated session* — with the same parser tests run against sanitized
fixtures from both 2.2.6 and 2.3. Only then generalize; the slice is what
reveals the real domain shape. Parsing moves to DOM selectors (`package:html`,
already a dependency): the current regexes depend on attribute order and quote
style, which was acceptable for a protocol spike and is not for record
documents. Responsibilities stay separate — transport and status interpretation,
one parser per fragment type, domain mapping, and diagnostics naming the
webtrees version, the parser and the failed selector.

Core tabs can be disabled or access-restricted per tree, so the transport must
**discover** which fragments exist rather than assuming `personal_facts`,
`relatives` and `media`. Arabic, RTL, non-Latin and multi-name fixtures go in
early — this tree is Arabic, and name order and calendar assumptions surface
immediately.

---

## 6. Progress log

### 2026-08-22 — Evaluation, plan, Phase 0, Phase 1a/2a

**Evaluated** webtrees internals and `webtrees-API`; rejected the latter as the
mobile foundation (§2). Published the assessment as an artifact.

**Phase 0 complete.** `webtrees_mobile/tool/probe.dart` — a dependency-free
(`dart:io` only) CLI that validates the whole wire protocol. All checks pass
against the live instance. Confirmed: pretty URLs, webtrees 2.2.6, cookie
`__Secure-WT-ID`, tree `main`, role Member.

**Phase 1a + 2a complete.** Flutter project scaffolded (Flutter 3.44.2, Dart
3.12.2; linux/android/ios — no web). Data layer built and tested:

| File | Purpose |
|---|---|
| `core/webtrees_url.dart` | Input normalization, both URL styles, subdirectories |
| `core/errors.dart` | 12 typed errors with user-facing messages |
| `core/webtrees_client.dart` | dio + cookie jar, no auto-redirects, bot-block detection |
| `data/instance_probe.dart` | Style detection, health, version, UA safety check |
| `data/session.dart` | Sign-in, 302 discriminator, liveness, sign-out |
| `data/access_probe.dart` | Trees, roles, account, own-record XREF |

**61 unit tests** green, analyzer clean. `tool/live_check.dart` exercises the
shipping stack end to end against a real server and passes.

**Verified the biggest Phase 1 risk:** dio + `cookie_jar` handle webtrees'
cookie correctly, including the session-id rotation inside the sign-in redirect.

**Improved on the plan:** the Member-vs-Visitor gap, documented as unsolvable,
turned out to be decidable for private trees (§3).

### 2026-08-22 (later still) — Phase 3b: the rest of what a record says

Phase 3a read a person. This reads the rest of what a stock site publishes
about them — the families they belong to, the notes and citations a tree keeps,
the photographs, and the results past the first fifty.

**Almost all of it was already on the wire.** Every core tab returns
`canLoadAjax() === false`, so webtrees renders notes, sources and media *into*
the individual page it has already sent. The app was parsing two panes out of
that page and discarding the rest. Reading them costs nothing extra.

**A marriage belongs to the family, not to either person.** The relatives tab
is the only place a stock page states it, in a row the parser had been using
purely as a divider between spouses and children. Now the couple's own facts
are kept — and with them, the reason to show a family as a *block*: someone who
married twice has two sets of children, and one merged list of children puts
them under the wrong marriage. Birth families stay flat under *Parents* and
*Brothers and sisters*, which is what anyone calls them; the families a person
made are shown one at a time under the site's own heading, which already names
the spouse.

**"Birth of a brother" names an event and no brother.** `.wt-fact-record` was
being dropped, so every one of these secondary rows was anonymous and led
nowhere. It now names the relative and opens them.

**Paging turned on a trap.** webtrees answers `nextUrl` when more results
exist — and builds that URL without the query, so following it searches for
nothing. The app pages by number instead, and dedupes: the search joins the
name table, so a person recorded under two names is two rows, and webtrees
drops those duplicates only within the page it is building.

**A module a site does not run is not a missing section.** The target runs
neither notes, sources nor media, so warning about their absence would have put
a caution on every record it will ever show. A tab that is *offered* and fails
still says so.

**Text a tree wrote gets the direction it deserves.** A note is in the
family's language whatever language the reader chose, so an Arabic note on an
English screen now sets its own paragraph direction — the same thing webtrees
does with `dir="auto"` — rather than ending with its full stop on the wrong
side.

Released as **0.3.0**. **275 tests** green (234 → 275), analyzer clean, and
`tool/live_check.dart` passes against `tree.almou.sa`: 50 results then 50 more
with no overlap, and the sections that instance actually offers reported by
name. The rendered previews now walk further down a person's page, which is
where all of this lives.

**Verified against live markup, not only fixtures.** Real pages from
`tree.almou.sa` were captured and run through the parsers directly. The
relatives parser reads that instance's markup — its chart boxes carry a whole
facts dropdown the fixtures do not — and its one recorded marriage arrives with
an empty field, which is what a marriage with no date and no place looks like.
The notes, sources and media parsers have **no live evidence at all**: that
instance runs none of those modules (§9).

### 2026-08-22 (later still) — Phase 6a: charts, drawn again

The app has read a person for two phases. This one gets it out of a list and
onto a canvas: the ancestors above someone, the descendants below them, drawn
by the app rather than shown as the site drew them.

**Nothing of webtrees' own chart markup survives, and nothing of it needs to.**
Its charts are HTML for a wide screen — floated boxes, background images for
the joining lines, a reading direction in the stylesheet. What they also
contain is the *shape*, stated by nesting one recursion of a template inside
the next, and the shape is all the app wants. It arrives as a `ChartParser`
answer and leaves as arithmetic in `chart_layout.dart`, which is why mirroring
the whole thing for Arabic is one flag and not a second algorithm.

**Two numbering schemes, neither of them read.** The ancestors chart prints a
Sosa-Stradonitz number beside every box — in the reader's own numerals, so `٤`
here — and the descendants chart prints a d'Aboville number in plain digits,
because one is formatted and the other is built by joining integers. A parser
keyed on either would have worked in English and failed in Arabic, or worked
today and failed on a site rendering in Hindi. The nesting says the same thing
in every language, so the app reads that and *computes* the numbering by
webtrees' own rule. The tests then check the computed numbers against the ones
the server printed — the fixtures carry Arabic numerals precisely so that
check means something.

**A chart can hold the same person twice.** Cousins marry, and in this family
that is ordinary rather than a curiosity. The first layout looked each box up
by person to draw a line to it, which finds the wrong one of them the first
time a tree folds back on itself. Positions are now carried out of the
recursion that computed them, and nothing is ever looked up by who it is.

**What a site runs is the site's business.** Chart links carry a class naming
the chart, so the person's own page — already fetched — says which of the
twelve this instance offers and at what address, generations and all. The app
shows buttons only for the charts it can actually draw: offering one it cannot
would be a promise the next tap breaks. `tree.almou.sa` offers all thirteen
kinds; the app draws two of them and says nothing about the rest.

**The first view answers "where am I".** A pedigree is wider than a phone, and
in Arabic it is mirrored — so an untouched canvas would open on the oldest
generation with the person the reader asked about somewhere off the right-hand
edge. The chart is fitted to the screen first, and zoomed after.

Released as **0.4.0**. **331 tests** green (275 → 331), analyzer clean, and
`tool/live_check.dart` passes against `tree.almou.sa`, where it now reports the
thirteen charts that instance offers and reads two of them: seven people over
four generations of ancestors, nine people over three of descendants. The
previews walk into both charts, in both languages and both themes.

### 2026-08-22 (later still) — Phase 6b: the same family, three more ways

Three more of the charts on webtrees' list, and not one of them cost a
request: a fan is the ancestors chart bent round a circle, a compact chart is
the same one with the photographs traded for smaller boxes, and an hourglass
is the two charts either side of a person stitched where they meet.

**A fan is geometry, and geometry is testable.** `fan_layout.dart` answers
which slice of which ring a person occupies, and `FanLayout.at` answers the
opposite question — who is under this finger — from a radius and an angle.
Both are arithmetic, so both are tested without pumping a frame: that the
father's line takes the right-hand half, that each generation's slice is
exactly half its child's, that a tap outside the outermost ring finds nobody,
and that an ancestor the tree does not record leaves their slice **empty**
rather than letting the chart close the gap. A fan that rearranged itself
around a missing great-grandmother would be saying something the tree does
not.

**Ring width is a legibility decision, not a spacing one.** The first fan
gave each ring 58 pixels, which fits `محمد ال…` and tells the reader nothing
they did not already know. Names run along the radius, so the ring has to be
as wide as a family name is long.

**The hourglass had one thing to get right.** Both halves contain the person
in the middle, and stitching two charts is exactly where a second copy of
somebody comes from. The subject is drawn once, from the half that decided
where the middle is, and the other half is translated to meet it.

**What the app fetches and what it draws are different sets.** The live check
learned this by asking `tree.almou.sa` for an hourglass — a chart the app
never requests — and being refused by its own repository (§7, bug 22).

Released as **0.5.0**. **350 tests** green (331 → 350), analyzer clean, and
the live check reads both charts and the hourglass stitched from them against
`tree.almou.sa`. The previews now walk into four charts in each language and
theme.

### 2026-08-22 (later still) — Phase 6c: how two people are related

The question a family tree gets asked more than any other, and the one the app
cannot answer for itself: working out kinship means walking a graph a record at
a time, and webtrees already knows.

**What it knows is a grid, and a grid can be walked.** The relationship chart
is laid out as positioned cells with the joining lines drawn in background
images — meaningless on a phone — but every cell is printed, empty ones
included, so a row and column index is a position rather than a guess. Each
step's name sits between the two people it links; walking outwards from the
person whose page it was recovers the order. Four real paths captured from
`tree.almou.sa` — up three generations, down to a daughter, across to a
sibling, and a grandmother by two steps — all read correctly the first time.

**The words are the site's.** *القرابة: إبن*, and each step named as webtrees
names it — including the distinction between an older and a younger brother,
which Arabic makes and English has no word for. An app that composed these
sentences itself would be inventing kinship terms in two languages.

**"No link" is sometimes the right answer, and sometimes a setting.** The live
check compared two people the tree records as married and was told there was
no link — which turned out to be correct: `relationships-1-3` means this site
searches only through common ancestors. The app now reads that setting out of
the URL and says so, rather than leaving the reader with an empty screen and
no explanation. The check compares blood relatives now, because a comparison
that cannot find a link proves nothing.

**One URL is edited rather than obeyed.** The relationship route takes an
optional second xref and a page only ever links to one person, so the app
appends the other. It is the only address it does not use exactly as it
arrived, and both of the site's own settings inside it are left alone.

Released as **0.6.0**. **363 tests** green (350 → 363), analyzer clean, and the
live check reads a real path — *son*, one step — against `tree.almou.sa`.

### 2026-08-22 (later still) — Phase 6d: what a site says about the whole tree

A statistics page is not a family shape, so none of the chart work applied to
it. What it turned out to be is a page that says everything twice: its counts
are in the markup, in the reader's own numerals, and the data behind each of
its charts is in a `<script>` beside it — plain numbers, written for a
JavaScript library that was never meant to have a reader.

**So the counts are shown as they arrived and the charts are drawn again.**
`tree.almou.sa` publishes seventeen sections and sixteen datasets: the split
of sexes, births by century, the commonest surnames, average lifespan by
century, where in the world its events happened.

**The chart forms are not webtrees' own.** It draws pies; a phone reads a
share far better as one bar cut into its parts, with every part named and
counted beside its swatch — identity never carried by colour alone. Counts by
category are bars of one hue, because the length already says the number and
colouring by value would spend the identity channel saying it twice.

**The palette was computed, not chosen.** The app's own scheme fails as chart
colours: its secondary and tertiary sit 1.2 ΔE apart under deuteranopia and
below the chroma floor where a hue stops carrying identity at all. The four
used instead pass the lightness band, chroma floor, colour-vision separation
and contrast checks against *both* of this app's surfaces — verified by
running the checks rather than by looking.

**Two bugs a picture caught, again.** The share bar rendered as eighteen
pixels of empty surface, because a coloured box has no height of its own and a
row centres it into nothing. And every chart number came out in Latin digits
beside the site's own Arabic-Indic ones, because `NumberFormat` for `ar` uses
the Latin numbering system. Neither would have failed a test that asked
whether the widget was there.

**A standing risk turned out to be wrong.** §9 said this tree has no media at
all. Its own statistics say 86 media objects, 83 of them photographs — but not
one is visible to this account as a highlighted thumbnail (0 of 50 people
searched), so the authenticated image path *still* cannot be proven here. The
risk is the same size; its description was simply false.

Released as **0.7.0**. **384 tests** green (363 → 384), analyzer clean, and the
live check reads the real statistics page — three parts, seventeen sections,
sixteen charts.

### 2026-08-22 (later still) — Phase 6e: a life against a scale

The last of the charts that is about a person: their events, in order, spaced
as far apart as they actually happened.

**Nothing here is converted.** webtrees positions each year label and each
event box in its own pixels, so the app keeps both as positions and draws them
in proportion. No date is parsed, no numeral has to be understood, and the
label a reader sees is the one the server wrote — the date in both calendars
included. Converting a box's position to a year would also have been wrong by
one: the box sits a few pixels above the line it points at, which is the sort
of detail that looks like a rounding error and is really a misread.

**Two events a month apart must not be drawn a year apart.** Where cards would
overlap, the later one is pushed down and a line still points back at the
moment it belongs to. Even spacing would be a chart that lied about time; a
collision would be a chart that hid an event.

**A picture caught a third bug of the same family.** The chart buttons on a
person's page were being filtered by hand rather than through
`ChartKind.drawnFrom`, so they appeared in whatever order the site's menu
happened to list them — and the rule that an hourglass needs both of its
halves was never applied to them. The rule had a test; nothing checked that
the screen used it. A `const Set` of enum values does not iterate in the order
it was written, which is how the ordering looked deliberate and was not
(§7, bug 25).

Released as **0.8.0**. **400 tests** green (384 → 400), analyzer clean, and the
live check reads a real timeline against `tree.almou.sa`.

---

### 2026-08-23 — Phase 7a: who a person is, seen before it is read

Everyone in the app looked the same. The same neutral tile whether the record
said man, woman or nothing; no sign anywhere of who had died; a profile page
that was one long run of grey rounded rectangles with no edge between a first
marriage and a second. All of it was information the tree had been stating and
the app had been throwing away.

**The parser could not see any of it, and the reason was language.** Every
label webtrees prints — `Death`, `الوفاة`, `Divorce` — is translated by the
server before it arrives, and `INDI:SEX` is rendered as the *word* for the
sex. A parser keyed on those words works in English and quietly does nothing
in the language this app was built for.

**`chart-box` gives it away.** `Fact::summary()` writes the GEDCOM tag into
the class and the site's own translation into the label beside it, and
webtrees prints a run of those into every chart box — the person's own events
in `.wt-chart-box-facts`, and everything including their families' events in
the hidden zoom dropdown. So a page teaches the app what *this* site calls a
death and what it calls a divorce, and that dictionary then names every other
fact on the same page. `FactTagIndex` (§3) is the whole mechanism, and it is
what makes three separate features possible at once: the mourning ribbon, the
per-fact icons, and knowing which of two marriages ended.

**A person's own sex was never populated at all** — `IndividualRecord.sex`
existed and nothing ever set it. It comes from the relatives tab now: the
viewer appears in their own family tables as a chart box like anybody else,
and that box carries the sex class, the lifespan and the death.

**Blue and pink, derived rather than fixed.** `PersonColors` is a
`ThemeExtension` beside `SemanticColors`, with separate light and dark pairs;
text on them clears 8.7:1 in both. A pastel that reads correctly on paper
turns to mud on a dark surface, and the generated expressive scheme offers
nothing dependably blue or dependably pink to borrow. The avatar placeholder
used to pick its colour by hashing the name — variety with no meaning, while
the answer sat unread in a CSS class.

**The header is built from the flexible space's own height, not from
`FlexibleSpaceBar`'s title.** That widget lays a title out at `width / scale`
and then magnifies it, so an Arabic name wraps to two lines and its romanized
form truncates at exactly the moment there is most room for both — and, tall
enough, the title grows up into the back button. Interpolating the portrait
size and the text style against the measured height instead means every state
is laid out at the width it is really drawn at.

**Four copies of the same row became one.** Search results, relatives, a
relationship step and its picker each wrote out their own card-avatar-name
tile. `PersonTile` replaced all four, which is why a gender colour and a
ribbon arrived everywhere in one change rather than four.

Search results are the one place a person is still drawn without a sex:
webtrees' autocomplete sends a name, a lifespan and sometimes a photograph,
and nothing else. Their lifespan is recovered now, which it was not before.

The fixtures gained a second marriage, ending in divorce, because the feature
this phase is about is exactly the one a single family cannot exercise.

Released as **0.9.0**. **419 tests** green (400 → 419), analyzer clean.

---
### 2026-08-23 — Phase 7b: what a chart is for, and who decides

**A chart was putting children under the wrong mother.** `layoutDescendants`
centred a parent over *all* of their children regardless of which marriage
each came from, so a man with two wives got one undifferentiated row beneath a
couple half of them did not belong to. Not a crowded chart — a false one, and
the sort of falsehood a family notices.

Each family's children are now laid out as a contiguous block, and the couple
strip above them is built so that each family's line hangs over its own block:
a slot is pushed along when its children demand it, and never allowed to land
on the slot before it. The reverse case — a woman with children by two
husbands — falls out of the same rule.

**A marriage and a divorce were drawn identically.** They are not the same
thing, and a chart is where the difference belongs: the children still belong
to both parents, and the parents no longer belong to each other. A parted
couple gets the mark genealogists have used on paper for a century — two
strokes across a break in the line — drawn *next to the spouse* rather than
halfway along, because a family pushed sideways to reach its own children can
be a long way from the person it belongs to.

Reading it needed no new vocabulary: the caption webtrees writes above a family
runs the marriage, the divorce and the child count together as one sentence
with no markup between them, and `FactTagIndex` (§3) already knew what this
site calls each of those.

**The reader decides how a chart is drawn.** Depth, shape, photographs, dates,
colour by sex, boxes that fit their names, and which line to follow — all in
one sheet, all kept between charts, and only the depth costs a request. Hiding
a sex cuts the branch rather than the box: everyone above a mother is reached
through her, so a pedigree showing only men is the paternal line, which is the
view an Arab family tree is usually drawn in.

**Fitting the whole chart is not always the right opening.** Six generations
scaled to a phone is a picture of a tree rather than a tree anybody can read.
The viewport fits the chart while its smallest text stays above nine logical
pixels, and otherwise opens at that scale with the subject centred — which
also fixed a long-standing bug where an unfitted Arabic chart opened against
the wrong edge.

**A chart can be shared.** The whole chart, at twice its logical size, from a
boundary *outside* the viewport — a picture of the window would be a picture
of whatever happened to be on screen. PDF is the same picture on a page shaped
to fit it, with nothing typeset, which keeps Arabic shaping out of a library
that would have to reimplement it. Three new dependencies, named and reasoned
in `pubspec.yaml`.

**`graphview` was considered and rejected.** It offers Buchheim–Walker and
Sugiyama layouts for generic graphs; these charts are not generic graphs. A
couple is two boxes with their children hanging from *between* them, and
`ChartLayout.mirrored()` — the single most important property of these charts
— has no counterpart in it. Everything asked for was reachable inside the
existing layout, and the per-family placement above is a change the package
could not have made.

Two bugs, both about fixtures (§7, 26 and 27).

Built as **0.10.0**. **450 tests** green (419 → 450), analyzer clean. Committed
together with 7c below, which is why the released version jumps 0.9.0 → 0.11.0:
0.10.0 was built and exercised on this machine but never tagged.

---

### 2026-08-23 — Phase 7c: the question a family tree is really for

"How are we related?" is the question this app exists to answer, and the
answer was a list of names. A reader had to hold the order in their head and
work out which way it ran.

**It is a path, so it is drawn as one.** A spine down the page, each link
named on a rung of it, the far end flagged. The words on the rungs stay the
site's own — `father`, `أخ أكبر` — because composing them here would mean
inventing kinship terms in two languages, and Arabic distinguishes an older
brother from a younger one where English has no word at all.

**And it can be asked four ways.** Closest, father's side, mother's side,
through a spouse. webtrees has no idea what any of those mean — it offers one
setting, and it is a tree preference rather than a question the reader is
asked. But it answers with *every* path it found, and a path's **first step**
says which of the subject's own relatives it leaves through. Matched against
the parents and spouses the record already names, that sorts the answers into
the ways a person actually asks. Nothing reads a kinship word, so it works the
same in both languages.

A side with no path is shown disabled, not hidden. "There is no link on your
mother's side" is an answer; a missing button is not.

**The blood-lines switch turned out to be real.** The app had been *reporting*
that setting — the reason two people in one tree can come back unrelated — as
something the reader could only be told about. It is in the route, and
webtrees reads it straight off the route, so it is a request rather than a
report (§3). Which also means a link through a marriage can now be found at
all on a site configured the way this project's own target is.

The search result the reader picks carries no sex, so the person they chose
was drawn grey at the top of a screen that drew them pink further down. The
header now prefers whichever chart box a path reached them through.

**The release build had been failing on this machine, and it was not the
code.** The Flutter template asks Gradle for `-Xmx8G` with 4G of metaspace;
this machine has 5G of RAM in total, so the daemon was being killed by the
kernel partway through `assembleRelease`. Gradle reports that as "build daemon
disappeared unexpectedly", which reads like a crash and is really a heap it
was never going to be given.

Released as **0.11.0**. **464 tests** green (450 → 464), analyzer clean, and
`tool/live_check.dart` run against `tree.almou.sa` — which is what turned the
whole of 7a from a careful reading of a template into a fact (§3). It grew a
section of its own for it: sex, lifespan, death, how many relatives carry each,
and how many facts the dictionary could name.

---

### 2026-08-23 — What an API would be worth, and what it would cost

No code changed. The app has spent seven phases learning to read HTML well, and
the question this answers is whether it should have to: `api_eval.md` is a
full architectural evaluation of a purpose-built webtrees module for this
client, written to be the design basis if one is ever built.

**The scraping is not the whole cost, but it is most of it.** 2,168 lines in
`lib/data/stock/`, ~1,700 lines of parser tests, 212 KB of two-version
fixtures — and nine of the twenty-seven bugs in §7. Every one of those bugs is
the same shape: markup said something the parser did not expect, or a fixture
said something a real server never sends.

**`webtrees-API` was already rejected; this says why in file and line.** Two of
the reasons hardened. It does not boot on 2.3 for **two** independent reasons,
not one — the Aura router is gone *and* `Auth::PRIV_*` is gone — so it is not
one upgrade away from working. And `TestApi`'s "1000-year token" is literally
`'P1000Y'`, minted from a route registered with no middleware at all. The
upstream report still needs a lab reproduction first.

**The interesting finding was how small the compat problem is.** 2.3's
`InvokeController` opens by short-circuiting to
`RequestHandlerInterface::handle()`, which is all 2.2.6's `RequestHandler` ever
did — so a PSR-15 handler is version-neutral, and the entire 2.2-vs-2.3 surface
a module touches is seven differences, now tabulated in §3. Privacy, search,
charts, media, facts, names and statistics have identical public APIs in both.
That turns "webtrees breaks custom modules" from a reason not to build one into
a bounded, testable adapter.

**Three open risks turn out to be properties of the *markup*, not of webtrees.**
A photograph is stuck at 100 pixels because that is what the media tab signs —
`MediaFile::imageUrl($w, $h, $fit)` will sign any size (§9 #3). The app has to
rewrite the account's language preference because no stock route sets only the
session — a module middleware runs after `UseLanguage` and can call
`I18N::init()` for one request (§9 #16). A tree cannot be enumerated over HTTP,
but `SearchService::searchIndividualNames` with an empty term array walks one
in `n_sort` order, deduped and privacy-filtered before the offset is counted
(§3) — which is both halves of the paging trap, fixed upstream all along.

**And one thing a module would not fix for free.**
`RelationshipsChartModule::calculateRelationships()` is `private`, so the
Dijkstra that finds a path between two people — about 150 lines — would have to
be reimplemented. It would be the module's only duplicated core logic and
therefore its only silent-drift risk. The *naming* is safe:
`RelationshipService::nameFromPath()` is public, so `أخ أكبر` stays the site's
word and not the app's invention.

**A real 2.3 bug fell out of the reading.** `Date::display()` puts the whole
calendar-conversion block inside `if ($this->date2 !== null)`
(`app/Date.php:160-176`), so an ordinary single date loses its conversion — on
the website, not just here. §9 #15 had this as an unverified suspicion; it is
now confirmed from source and needs reproducing on a running 2.3 install before
it is reported.

**The recommendation is a separate module, adopted per capability.** Not a
replacement: §1's first constraint is that the app works against an untouched
instance, so every capability keeps its HTML path permanently. The migration
starts with something that is valuable even if no module is ever written —
extracting transport interfaces from the two concrete repositories — and
proceeds one capability at a time with both live and `tool/live_check.dart`
comparing them. Which is the lesson of bugs 5 and 14–16 applied in advance,
for once, instead of afterwards.

---

### 2026-08-23 (later) — Phase 8a: the module `api_eval.md` designed

Written, and not yet run. There is no PHP, no composer and no webtrees install
on this machine, so the module has been verified by reading source rather than
by executing it — a limit that governs everything below and decides the
migration order.

**`server/webtrees-mobile-api/` is the whole of it: 37 files, no vendored
dependencies.** Thirteen `GET` endpoints, one handler each, every one a PSR-15
`RequestHandlerInterface` — which is what makes the handler layer
version-neutral, because 2.3's `InvokeController` opens by short-circuiting to
exactly that and 2.2.6's `RequestHandler` never did anything else.

**The compat surface is eleven methods, and it is not the seven `api_eval.md`
predicted.** Three of its rows turned out to be unnecessary and five
differences it had not found turned out to matter. The most useful discovery is
the first of those: **the module never names an access level at all.**
`canShow()`, `canShowName()`, `facts()` and `Fact::canShow()` all default to
the current user's, so `Auth::PRIV_*` versus the `AccessLevel` enum — the
difference that kills `webtrees-API` on 2.3 — simply never comes up for code
that lets webtrees decide. What does need adapting is listed in §3, and the
full accounting is in `api_eval.md` §14.

**Three claims in the design document were wrong, and one of them would have
shipped a module that did not boot on 2.2.6.** `formatDate()` — recommended
there as the version-neutral way to render a converted date — does not exist in
2.2.6 at all; it arrived with `Contracts\LanguageInterface` in 2.3. The
version-neutral answer is `Date::display(null, null, false)` with its tags
stripped, which renders the whole date in the reader's language with no links
and no conversions. `sosaStradonitzAncestorPaths()` is likewise 2.3-only.

**`tool/check_module.py` is what stands in for a compiler.** It checks every
file's structure, flags unused imports, and — the part that earns its keep —
resolves every `Fisharebest\Webtrees\…` import against **both** the 2.3
working tree and the `2.2.6` tag, failing if anything outside `src/Compat/`
names a class that exists in only one. That is the rule the compat layer exists
to enforce, and it is now enforced rather than intended.
`.github/workflows/module.yml` runs it in CI alongside `php -l` on 8.3 and 8.4.

**On the app side the valuable half was step one, which needed no module at
all.** `data/transport.dart` names what the app needs from an instance —
`RecordsTransport`, `ChartsTransport`, `AccessTransport` — and the two stock
repositories now implement it. Every screen takes the interface. That refactor
is worth having whether or not a module is ever installed, which is exactly why
`api_eval.md` §13 puts it first.

The one wrinkle: `ChartsRepository.bloodLinesOnly` was a *static* that parsed a
URL, and a site's answer to "do you search blood lines only" is not something
every transport can read from an address. It is an instance method now, and the
module answers it from the `settings` the server echoes back.

**Selection is per capability, and nothing is all-or-nothing.**
`data/capabilities.dart` composes the two: a feature the module advertises goes
to JSON, everything else to HTML, and a site with no module at all — which is
every site today — behaves exactly as before. Charts are routed by their
*handle* rather than by the capability list, because a record fetched by one
transport carries addresses only that transport can read.

**One suite now runs against both.** `test/data/transport_contract_test.dart`
asserts the same fifteen behaviours of each, over two fixture sets describing
the same sanitized family — and it earned itself immediately by catching a
fixture that gave the subject one spouse where the HTML gave him two. A
difference between the transports is not a bug in a parser; it is a difference
the interface was supposed to hide.

`tool/live_check.dart` gained the other half of that check: against a real
instance it reads the same person through both transports and diffs them field
by field — name, sex, lifespan, every relative count, and the same date in
both calendars. Run against `tree.almou.sa`, which does not have the module
installed, it correctly reports *not installed* and every stock check still
passes, which is the regression this refactor most needed to not cause.

**What the module can say that a page cannot.** Every fact's bare GEDCOM tag,
including a relative's death under its own translated label — the one case the
chart-box dictionary provably cannot learn, because no box ever printed it.
Which of five lists a fact came from, where the markup offers one `collapse`
class. Whether a family is the one a person was born into. A person's own sex,
without going to their relatives tab to find their chart box. A role, stated,
where the probe ladder has to infer one and cannot separate Member from Visitor
on a public tree at all. A whole tree enumerated in name order, deduplicated
and privacy-filtered *before* the offset is counted. And a photograph at
whatever size the screen wants.

**A date is where it pays best.** The module sends the raw GEDCOM, the
Julian-day bounds, the qualifier, and one rendered string per calendar with its
escape attached — so `CalendarView` finally works on 2.3, where the markup
names no calendar at all. It also sidesteps the 2.3 bug in §9 #15: webtrees
puts its whole conversion block inside `if ($this->date2 !== null)`, so a single
date loses its conversion on the website, while the module converts from
`convertToCalendar()` and is not affected.

**The relationship finder is the one thing that could silently drift.**
`RelationshipsChartModule::calculateRelationships()` is `private`, along with
`allAncestors()` and `excludeFamilies()`, so about 150 lines of Dijkstra over
the `link` table had to be reimplemented. They are byte-identical in 2.2.6 and
2.3 but for a trailing comma, and `src/Support/RelationshipFinder.php` is a
deliberate line-for-line port rather than an improvement — because the moment
it is improved it starts answering something the website does not, and no test
on either side would notice. The *naming* is safe:
`RelationshipService::nameFromPath()` is public, so `أخ أكبر` stays the site's
word.

**None of this retires a parser.** `api_eval.md` §13 rule 6 says a parser goes
only after its endpoint has passed live against real data, and no endpoint has
run at all yet. The stock path is the floor, permanently, and today it is also
the only path any real instance uses.

### 2026-08-23 (later still) — Phase 8b: running it, and what that cost

PHP was installed, so the module was executed for the first time. `tool/lab/`
stands up throwaway webtrees installs on SQLite — 2.2.6 on `:8622`, 2.3 on
`:8623` — with the module symlinked into each and a synthetic Arabic tree in
which every person is invented. `tool/live_check.dart` then reads the same
person through both transports and diffs them field by field.

**The verdict is good, and it is the first evidence of any kind.** On both
versions the module and the HTML parsers agree on name, alternate name, sex,
deceased, lifespan, every relative count, primary facts, tags named, and the
same date in both calendars. All thirteen endpoints answer on both, and the
payloads are identical between versions. d'Aboville numbers continue across a
second marriage — bug 26's exact case, now positively confirmed rather than
merely fixed. Cousins yield two distinct paths. The relationship wording is the
site's own, including `شقيق أكبر`, the older-brother distinction Arabic makes
and English cannot.

**Six bugs in an afternoon (§7, 30–35), after a document argued from source,
508 green tests and a live 2.2.6 run had all passed the same code.** That ratio
is the point of this entry. Reading found five errors in `api_eval.md`; running
found six more, and none of them was subtle once seen:

- `capabilities.languages` was a JSON *object*, because `findByInterface()`
  keys its collection by module name. The client decoded it as empty.
- `I18N::init()` changed the *dates* and not the *labels*. The global stack
  registers every GEDCOM tag's label between `UseLanguage` and `Router`, and
  `Gedcom::registerTags()` evaluates them eagerly — so by the time module
  middleware runs, the element factory is already holding the session's
  language. The tags have to be registered again. **§9 #16 is now closed and
  demonstrated**: `?lang=en-GB` answers `Birth | 21 Dhū al-Qiʿdah 1318`, the
  next request is Arabic again, and the account's stored preference is
  untouched — which no stock route can do.
- Only an anonymous `404` proved a tree private. 2.3 answers `400` for the same
  condition, so every private tree there was silently downgraded to
  `memberOrVisitor`.
- The site version was read only from a `200`. 2.3 answers `400` for
  `GET /login` and renders the whole page regardless, so 2.3 sites lost the
  version the parsers key on — while sign-in kept working purely because it
  read the CSRF token out of the body without checking the status.
- **The statistics parser found zero charts on 2.3, and had done all along.**
  2.3 replaced Google Charts with Chart.js and moved the data out of the
  `<script>` onto the canvas as `data-wt-chart-*` attributes. The `v2_3`
  fixture had been written by hand in 2.2.6's shape, so the tests were green
  and the app was broken. It now reads both roads, from a fixture *captured*
  off a running 2.3, and answers 14 charts there where it answered none.
  The new options are strict JSON, which retires bug 23 on 2.3.

**And one that was not a bug at all, which is the one worth remembering.** For
about an hour the module appeared to serve a private tree to an anonymous
caller on 2.3 — which reads exactly like a privacy hole, and would have been
the worst finding here. It was the *lab* that was wrong: schema 45 moved tree
privacy from a setting row to a `private` column, 2.2.6 kept a shim that
redirects the write and 2.3 removed it, so the tree had never been private.
With the column set, anonymous access is refused `404` on both. A frightening
finding deserves the same scepticism as a convenient one, and the database was
one query away.

**Three of the six were stock-path bugs, not module bugs** — the statistics
charts, the private-tree status and the site version. All three are
version-specific breaks on 2.3 that had been shipping unnoticed, because until
today nothing had ever run this app against a 2.3. That is now §9 #20: assume
there are more, and that only running against both finds them.

**Nothing has been retired, and nothing will be.** `api_eval.md` §11 is
permanent — every capability keeps its HTML path, because the first constraint
is that the app works against an untouched instance. What §13 rule 6 actually
gates is which capabilities the composer may *prefer* the module for, and that
is now a ledger in §5. Three are cleared: `access`, `individual`, `individuals`.
All on fourteen invented people — the entry below is what happened when it met
1,463 real ones.

---

### 2026-08-23 (later still) — the real tree

The module was installed on `tree.almou.sa` and answered against 1,463 real
people rather than fourteen invented ones. **Two disagreements between the
transports, both on one woman's record, and nothing else across the tree.**

- Her lifespan read `…–`. `Individual::lifespan()` always writes something —
  a chart box wants the same height for everybody — so the HTML path showed an
  ellipsis and a dash under a person the tree records no dates for. The module
  answered null. **Null is right**, and the stock path now agrees: a lifespan
  with no digit in it, in any script, is a rendering decision rather than
  information.
- The module read no second name for her. `GedcomRecord::alternateName()` is
  narrower than it looks — it answers only when the primary and secondary names
  differ by **character set**, so a person recorded twice in the same script
  has none by that rule. She has two Arabic `NAME` lines, the second with an
  unknown given name (`@N.N.` → `…`). **The accordion's reading is right**: it
  is what the tree records, and the module now reads `getAllNames()` instead.

One fix on each side, which is the honest split: neither transport was simply
wrong, and the interface is what has to hide the difference. Both are now
contract-tested, and `tool/lab/make_gedcom.py` grew a person with two
same-script names so the case cannot regress unnoticed.

`tool/live_check.dart` gained `--person XREF`. Chasing a disagreement means
going back to the one record that showed it, and twice now that record has been
neither the account's own nor the first search hit.

**What the real tree did *not* find is worth as much as what it did.** Search
counts matched at 50 and 50. Enumeration returned a first page of 1,463 —
something no stock route can do at all. Sex, deceased, every relative count,
the fact tags, the role, and the statistics all agreed. The relationship,
chart, timeline and statistics endpoints answered. After a document argued from
source got five things wrong and a first execution got six more, the real tree
finding only two is the first evidence that this is converging.

Still unexercised, and now the top of §9 #18: a manager's or editor's view,
pending edits, and the notes/sources/media capabilities — this site runs none
of those three tab modules, so nothing has ever read them from a real server.

### 2026-08-23 (later still) — Phase 8c: four things a reader saw

The module had passed everything that could be automated — 509 tests, both
labs, the real tree diffed record by record — and then somebody used the app
and found four faults in one sitting (§7, 40–43). Two were in the module, two
in the interface, and none was reachable by any check the project owns.

**A family's members were being sent as facts.** `Family::facts()` returns
`HUSB`, `WIFE` and `CHIL` beside a marriage, so a presenter that asked for
"the facts" and sent them all answered a family's *membership* as though it
were its *history*. The parents card then listed the marriage and then
"husband · wife · son · son" underneath it, and every family card wore a pill
per member. webtrees answers this itself, twice and differently: its family
page filters those three tags out, and its relatives tab prints only
`MARRIAGE_EVENTS + DIVORCE_EVENTS`. `FamilyPresenter` now has both — `record()`
for a family in its own right, `summary()` for a family shown inside somebody
— and the client drops the pointers again on the way in, because which version
of the module a site runs is the site's choice and not the app's.

The fixture is why it survived: the module fixture was written from the design
rather than captured from a server, so it never held the pointers a server
actually sends. `tool/live_check.dart` now diffs **the family events both
transports report**, which is the check that fails on the old module — and it
passes on all fourteen lab records on 2.2.6 and 2.3, both versions.

**The mourning ribbon was a smudge.** It was drawn as a parallelogram between
two points on the avatar's edges, offset along both axes — so it stopped short
of the border at each end and, at the 40 pixels a chart box gives a face, read
as a black mark floating over a corner rather than as a ribbon lying across
one. It is now the region between two forty-five-degree lines, drawn far past
the avatar and cut back by the clip, so the clip rather than the path decides
where it meets the border. Lit along its outer edge and falling away into the
corner, which is what makes it read as cloth over the picture.

**Sharing a chart shared the window.** `_capture` wrapped `ChartCanvas` —
whose `build` returns the `InteractiveViewer` that looks *at* the chart — so
the boundary's natural size was the phone's, and the file held whatever was on
screen at whatever the reader had pinched to. The boundary moved inside the
viewport, around the content at its own size; the fan, which had never had one
at all, got the same one. The test asserts the boundary is wider than the
device it is drawn on, which is the property that was actually wanted.

**A PDF is drawn now, not photographed.** The page used to be the captured
picture on a sized page: a screenshot with a border, fixed at the resolution
it was taken at, and a family chart is exactly the kind of document somebody
prints large. `features/charts/chart_pdf.dart` draws it again from the same
layout — rounded boxes, borders, elbow joins, the parted-couple mark, ring
slices and the ribbon, all as vectors — and the only raster left on the page
is a photograph, which was one to begin with.

Arabic is why that was not obvious. PDF has no shaping engine: a library has
to join the letters and reorder the runs itself before it writes glyphs, which
is what the old comment meant by keeping Arabic "out of a library that would
have to reimplement it". `package:pdf` *has* implemented it — it runs the
bidirectional algorithm and substitutes presentation forms — and the app's own
Cairo face carries them, so the same file the interface is set in produces
`عبد الله الموسى` correctly shaped on the page, right-aligned, in a chart
mirrored the way the screen mirrors it. Rendered and looked at, both shapes,
in both directions.

### 2026-08-23 (later still) — Phase 5: the checks the last phase proved were missing

Phase 8c ended by opening §9 #22 — *nothing the project owns can see the
screen* — after four faults were found by a person using the app that 509
tests, a static checker, two labs and a walk of the real tree had all passed.
This is that risk answered, and it is the phase the plan has called
"hardening" since before any of it was written: golden tests, CI, error-state
coverage and a diagnostics screen.

**CI, at last, for the app.** `module.yml` has checked the PHP since Phase 8a
while the Dart — most of the project — had nothing. `.github/workflows/app.yml`
runs three jobs, deliberately separate because a red build should say which
kind of wrong it is: `analyze`, `test` (with `dart format` enforced, and the
generated localizations regenerated and diffed so the ARB files and the Dart
cannot drift), and `goldens`. Making format a gate meant formatting the
repository once; twelve files that had never been through the formatter moved,
which is churn worth taking exactly once.

**Goldens, of the parts a person judges rather than asserts on.** Fourteen
small pictures — avatars in every combination of sex and death, in both
directions and both themes; a person in a list; a family whose marriage ended;
the message panels — at 200 KB for the set. Component-level on purpose: a
whole-screen golden fails whenever anything moves, which teaches everyone to
accept the diff without reading it, and these fail for one reason each. Whole
screens are still rendered by `tool/preview/render_preview.dart`, as pictures
to look at rather than as assertions.

What a golden can and cannot do is worth stating plainly, because it is easy
to oversell: **it catches a change, not a mistake.** The first picture is only
as good as the eye that approved it — a golden taken a day earlier would have
frozen the smudged mourning ribbon of bug 41 as correct. Its value is that the
ribbon, now looked at and agreed, cannot quietly become a smudge again.
Approving these meant looking at all fourteen, and that turned up nothing
wrong, but it did make one thing visible that no screenshot had: at the
default `coupleGap` of 10 points the parted-couple mark is drawn into a gap
barely wider than itself, which is legible but cramped.

**Failure states, screen by screen.** Eight tests that break one route each
and assert the reader is told: a search that answers `500` says so rather than
finding nobody; a person who cannot be fetched is named as missing; markup no
parser recognises names the parser and mentions the theme; a tab that will not
load is a *warning* beside a readable record rather than a silently empty
family. Every one was confirmed to fail against a working site before being
kept — three were re-run with the breakage removed, and all three went red.
The connect and sign-in paths already had this; everything past sign-in had
none of it.

**And a diagnostics screen**, which the plan has asked for since Phase 0 as
the mitigation for §9 #7. The app discovers the address style it settled on,
the version it read, the server's health, whether a module answered and what
it can do — and showed none of it. It now shows all of it, plus the one thing
nothing else in the app states: **which transport is answering each
capability.** "The module is installed" and "this screen used the module" are
different questions, and the second one is what a reader wondering why a date
is in the wrong calendar actually needs. `Copy report` puts a plain-text
version on the clipboard, deliberately untranslated because it is written for
whoever reads the issue rather than whoever files it, carrying the site
address and the account name and no password, no cookie and no real name.

The honest limit: this closes the *tooling* half of #22 and not the other
half. Goldens catch regressions in what has been looked at; nothing here makes
anybody look at something new. A device (§9 #13) and the habit of opening the
app after changing it are still the only things that do.

### 2026-08-23 (later still) — the capabilities nobody had compared

Phase 8b cleared three capabilities of twelve and left the ledger in §5 saying
so. Nine sat at ⬜ — not because anything was wrong with them, but because
nothing had ever asked both transports the same question about them. This
closes that, and it cost four bugs, one of them webtrees' own.

**It started with a file that did not exist.** The lab's GEDCOM had declared a
media object since the lab was written — `@M1@ OBJE`, pointing at
`lab-portrait.png` — and `wt_media_file` held the row, and the media tab
rendered it. There was no image on disk. So `MediaFileThumbnail` had never run
in this project's whole history: not the signed URL, not `canShow()` before
the signature, not the watermark decision, and not `AuthenticatedImage` or
`MediaCache` on the app's side. §9 #1 had blamed the *data* — the target site
runs none of the three optional tabs — and it was half right. The labs run all
three, and one generated PNG was the difference between "this site runs the
media module" and "this site has a photograph in it".

**Then the PNG turned out to be a 500 on 2.3.** Not the app's: webtrees 2.3
added `ImageFactory::autoRotateImage()`, which calls `exif_read_data()` on
every image it resizes, and PHP warns `File not supported` for anything that
is not a JPEG or a TIFF — which webtrees' own `ErrorHandler` turns into an
exception. Proved by storing the same picture twice at the same URL: as a PNG,
`500`; as a JPEG, `200`. It breaks the website's own media tab, and it is
worth reporting upstream (§7, bug 44). The lab now holds one of each on
purpose, and the check reports the failure rather than tolerating it silently.
The app was already right: a photo it cannot fetch draws the placeholder.

**With a real photograph and real notes, the diffs could be written.**
`comparePerson` now compares the notes, the citations, the media items, which
of them hang off a fact rather than off the person, and each family's
membership by xref. A new section compares what nothing had compared: the
ancestors and descendants charts by size, depth and **shape** — who sits at
which Sosa or d'Aboville number, which is also a check on the app's own
derivation of those numbers against the server's — the relationship by path
count and by the words on each step, the timeline by which events and in what
order, and the statistics by the figures both state.

**Three of the four faults were the module's, and each was a reader's
problem rather than a value's.** Its relationship path was headlined `أب`
where the page writes the site's own `Relationship: أب`. Its timeline had
dropped the calendar conversion — `١٩٧٤` where every other module payload says
`١٩٧٤ (١٣٩٤)` — and the couple a marriage belongs to, so a man's two marriages
were two identical rows on a chart that exists to tell them apart.

**And one changed a rule.** The module's statistics endpoint answers four
sections and eight datasets; a statistics page publishes seventeen and
fifteen. Both agree on every figure they state — the module is not wrong, it
says less — and the app had been preferring it, so installing the module cost
a reader thirteen sections of their own tree. Preferring the module is now
conditional on it knowing *more*, in one place (`Capability.readFromThePage`),
which the diagnostics screen reads too: a screen whose whole job is to say
which transport answered must not say "Module" for something the module no
longer answers.

Released as **0.16.0**. **543 tests** green (541 → 543), analyzer clean, and
`tool/live_check.dart --sample 14` passes against **both** labs on both
webtrees versions: fourteen records walked, no differences, every capability
diff green. Nine capabilities move to ✅ in §5 and `statistics` moves to a
deliberate ❌.

**Then the real tree, which found the thing fourteen invented people could
not.** Every new diff holds against 1,463 real records — family membership,
the descendants chart across nine people and three generations, the notes and
citations and media counts, the statistics total of ١٬٤٦٣, the search counts —
and one disagreed. A woman whose record carries a married name as a **subtag**
of her only name: `getAllNames()` answers a row per name *form* rather than
per name, so the module reported `جواد حسن محمد` as a second name where the
page shows it as a field inside the name block, labelled *الإسم ما بعد
الزواج*. That is bug 37's fix overshooting in the opposite direction, and it
is the third time this project has learnt that a name in webtrees is not one
thing (§7, bug 48). The lab now has a person with a married name, and the
module counts `1 NAME` lines rather than name rows.

The other two differences the real tree reported are **not** faults: the
module installed there is 1.0.1, so it answers the relationship and the
timeline the way they were answered before this session's fixes. That is the
check doing its job — `capabilities.module` states a version and a client must
not assume the module it is talking to is the module it was written against.
They close when `tree.almou.sa` is updated to 1.1.1.

**And then the walk, which is where the shapes are.** One record is a
witness; forty are a survey, and forty real ones turned up two more classes
neither lab could produce.

A man the tree records a **burial** for and no death: dead to every chart box
on the website, living to the module, because `deceased` asked for a `DEAT`
fact where `Gedcom::DEATH_EVENTS` is `DEAT`, `BURI`, `CREM` (§7, bug 49).

And a family with children, no marriage recorded and **no second spouse
recorded at all** — whose eldest son the HTML parser read as the second
spouse, because the divider between a couple and its children *is* the
marriage row and there was none. Nothing in the rows says otherwise: a father
and a son both render `wt-sex-m`, and the `<th>` between them is a translated
relationship name (§7, bug 50).

The caption does say, and it took three attempts to read it correctly —
each attempt caught by a different record, one lab and two real:

- `X + Y` **lists** the couple, with `… …` for a spouse the tree does not
  record. A row named there is a spouse; the rest are children.
- *Family with X* and *Father's family with X* **name the other one** and
  leave the subject or their parent understood — so where one of those names
  somebody, the couple really is the leading pair.
- Only a birth family names nobody, and that is the one table whose first two
  rows were always reliably the parents.
- Underneath all three: **children never precede the couple**, so one row
  known to be a spouse makes every row above it one too. That is what pulls a
  father into a couple when only the mother was recognised.
- And the rung that needs no caption at all: a child row prints the gap since
  its elder sibling's birth, `$prev` is empty until a marriage fills it, so
  the first child of an unmarried couple never carries one — and a row that
  does proves the row above it is a child. That is what tells a lone father
  from a father and a mother, which two real records and one lab record each
  needed a different answer to.

A page also settles its own ambiguities — a step-family hangs off a parent or
a spouse whose marriage is stated in another table — but only what a table
*states* may be learnt from, never what a positional guess produced, and never
the subject themselves: they are a spouse in their own family and a child in
the one they were born into, so their marriage says nothing about which row
they occupy here.

**A fourth finding is about the lab rather than the tree.** Building a record
for bug 50 meant hiding a spouse, and hiding a spouse did nothing:
`canShowRecord()` returns true for everybody before it reads a restriction
unless `HIDE_LIVE_PEOPLE` is `'1'`, which the lab had never set. So privacy
had been switched off there for its whole life, and every privacy claim this
project has written down had been resting on a tree that applied none of them
(§7, bug 51). It is on now, with the two visibility levels open, so that one
`RESN confidential` bites and nothing else does — and `canShowName()` is
demonstrably true where `canShow()` is false, which is the case api_eval §9
predicted and nothing had ever exercised.

Every rung was found by a record that broke the rung before it: a real
step-family, a lab birth family, a real birth family with two parents, and a
real one with a lone father. The ladder is in `_FamilyRows.statedCouple`, and
`PROJECT.md` §9 #7 carries what is left — a lone parent whose children the
tree records no dates for, where the leading pair is still a guess and still
wrong by one. The module answers that correctly, which is the argument for it
in a sentence.

Released as **0.16.1** with the module at **1.1.1**. **548 tests** green
(543 → 548), analyzer clean, both labs walked in full through both transports
with no differences, and the real tree walked **sixty records** deep: one
difference left, on one field, and it is `deceased` on the buried man —
because `tree.almou.sa` runs module 1.0.1 and the fix is here. The
relationship wording differs there for the same reason. Neither is a fault;
both close when the instance is updated.

### 2026-08-24 — Phase 9a: a relationship has two shapes, and a path only shows one

A relationship screen answered one question well and a second one not at all.
*What is the link?* is a sentence — `القرابة: حفيد`, two steps — and the path
down the page says it perfectly: a spine of names with the site's own word on
every rung, read top to bottom. *Where do these people sit in the family?* is
a picture, and a list has no up and no down to draw it with. Two branches
leaving one grandfather and meeting again three generations later is the shape
a reader is actually asking about, and nothing on the screen could show it.

So the screen has two modes now, and each gets the whole body — a chart under
a column of controls is a picture of a family rather than one anybody can
read. The path keeps the ways of asking (`closest`, father's side, mother's
side, through a spouse, blood lines only); the tree gets a switch back and,
where a side offers several, a way to step between them. Beside every
relationship the screen states — the closest one, and each of the *other ways*
a family where cousins marry produces — there is a button that draws that
particular one.

**The whole feature turns on one fact the app did not have: which way each
step goes.** The word on a step is the site's own and cannot be switched on;
`أب` and `father` are the same step and a client that matched on either would
work in one language and quietly fail in the other. It has to be structural,
and both transports can now state it:

- **The module** asks the family record the same three-way question
  `RelationshipsChartModule::chart()` asks before deciding whether to move up,
  down or right in its grid: the two people either share this family as
  children, share it as spouses, or one is a spouse in it and the other a
  child.
- **The page** states it in the geometry of that grid, and the grid is walked
  already. webtrees prints its table from the top row down, so a smaller row
  index is further up the page: a parent. The parser was recording the
  direction it moved and throwing it away.

A sibling and a spouse answer the same `sideways`, deliberately. The grid
moves right for both, so the stock path genuinely cannot tell them apart, and
a distinction only one transport could make would be a *disagreement* between
them rather than a fact about the family. The label between the boxes says
which, in the site's own words.

**The two versions draw that grid differently, and only running both showed
it.** 2.2.6 turns the corner with a diagonal cell only where the previous step
ran the other way — `if ($n > 2 && preg_match('/fat|mot|par/', …))` — and 2.3
dropped that test and uses a diagonal for every step after the first. The same
four people are three columns wide on 2.2.6 and five on 2.3. Reading the
*sign of the row change* rather than a column position is what makes both
answer the same thing, and `test/fixtures/*/relationship_cousin.html` is the
first pair of fixtures in this repository **captured from a running server on
each version** rather than transcribed. `live_check` now diffs directions
alongside the wording; both labs agree, on both versions.

The layout itself (`features/charts/relationship_layout.dart`) is ordinary
arithmetic over that: a step to a parent is a row up, a step to a child is a
row down, sideways stays on the row, and a column advances when it must —
either because the step moved along the page, or because the box it would
otherwise take is occupied. That last rule is the one that matters: up to a
grandparent and down the other branch has to put the cousin *beside* the
subject, not on top of them. It reuses `ChartCanvas`, so the tree pans, zooms,
mirrors for Arabic and opens a person exactly as every other chart does — with
one addition, an optional label on an edge, because a route that does not say
`father` at each turn is a row of boxes.

### 2026-08-24 — Phase 9b: what a search row was already saying

A common surname in this family matches hundreds of people and the app could
only offer them as one list. The three things a reader wants next — the women,
a generation, the branch that stayed in one town — are all properties of rows
already on screen, so the question was never *how to ask the server again*. It
was what the rows actually carry.

**More than anyone here had noticed.** `Individual::lifespan()` does not write
`1901–1974`; it writes two spans, and each carries the *place* and the full
date of that event in its `title`:

```html
<span title="الكويت، الكويت ⁨about 1901⁩">1901</span>–<span title=" ⁨1974⁩">1974</span>
```

The autocomplete endpoint renders that view verbatim. So a stock instance —
the floor, with no module and no extra request — has been sending a birth year
and a birthplace with every search result since the beginning, and the parser
was taking the text and dropping the attributes. The two halves of the title
are separable because the date is wrapped in Unicode isolates
(`U+2068 … U+2069`); without them the attribute is one run of words in the
site's language with no separator this app would be entitled to assume.

**Sex is the one thing the page does not say**, and the module does. So the
filter sheet is built from the *rows* rather than from the transport that
fetched them: a control appears when some row can answer it. On a stock
instance that is years and places; with the module installed a sex chip row
appears beside them, and nothing has to ask which transport answered. Both
transports are now diffed on all three, per person, in `live_check` — 17
people, both webtrees versions, all agreeing.

Three decisions worth keeping:

- **A slider over the year of birth, not over an age.** webtrees renders a
  year in the calendar the record is kept in, so a Hijri tree answers `1318`
  where a Gregorian one answers `1901`, and subtracting either from a
  Gregorian *today* would produce a number that is simply wrong. The ends of
  the slider are two years the site itself printed, taken from the results in
  view, so one control works for either kind of tree and its labels always
  match what the rows show. The sheet says so in a line under it.
- **A row that does not say is kept.** A person with no recorded birth is not
  a person born outside the range; a tree records a birth for maybe half its
  people, and hiding the rest would assert something it never said. A
  birthplace is the exception, and deliberately: asking for people born in
  Kuwait is asking about a stated place.
- **The count is of the rows loaded.** A filter that hides everything and a
  search that found nobody look identical from outside, so the bar says
  `Showing 1 of 2 loaded` and the empty state says another page may yet hold a
  match. The button in the sheet counts before it applies, too.

Reading a year meant reading a number in the site's own numerals, which is a
thing the app had gone out of its way never to do — a chart computes its own
Sosa numbers precisely so it never has to read the printed ones.
`domain/numerals.dart` is therefore as narrow as it can be: it answers a year
or nothing, across every numeral system `fisharebest/localization` renders in.
Chinese numerals are deliberately absent, because `ScriptHani` is not a
contiguous run — a site rendering in it answers no year, and a filter with no
year to filter on leaves every row alone.

**And then the pictures showed bug 19 was never fixed.** The new fixture is a
real capture, so its lifespan is `١٣١٨–١٩٧٤` in Arabic-Indic digits — and
every one of them rendered backwards. `ltrRun` isolates a run so the paragraph
around it cannot reorder it, which is the right fix for `1901–1974` and no fix
at all for Arabic numerals: an isolate sets the run's *base* direction and the
algorithm still classifies what is inside it, so the dash between two Arabic
numbers resolves right-to-left and the run is reordered around it. An override
inside the isolate leaves nothing for that rule to decide. It has been wrong
for every lifespan on `tree.almou.sa` since the first one was drawn, in both
languages, and nothing but a rendered picture of real digits was ever going to
say so (§7, bug 52). A component golden now holds an Arabic-Indic lifespan.

Released as **0.17.0** with the module at **1.2.0**. **595 tests** green
(548 → 595) plus 14 goldens, analyzer clean, `live_check` walked against both
labs on both webtrees versions with no differences — including the two new
comparisons, each step's direction and each search row's birth year and
birthplace, the latter over seventeen people at a time.

### 2026-08-24 (later) — An age, and why it beats the year it replaces

The birth-year slider was the honest answer to a question the rows could
answer, and on **this** tree it is close to useless. `عبد الله الموسى` has a
Hijri birth and a Gregorian death, so his lifespan reads `١٣١٨–١٩٧٤` — and a
slider built from printed years puts him six hundred years from his own
grandchildren. That is not an edge case here; it is what a tree kept partly in
one calendar and partly in another looks like.

An age has no such problem, because an age is measured in **days**.
`Age::ageYears()` is webtrees' own class — the one the individual list prints
in its *Age* column — and it works off Julian days, so a Hijri birth and a
Gregorian death subtract correctly. The module states it; the slider is an age
wherever a row carries one and falls back to the printed years where none
does, which is every search against an untouched instance. Only one slider is
ever shown: they answer the same question and one answers it better.

**One number, two questions.** A reader asking for people in their forties
means the living and the dead alike, so `age` is age *at death* for somebody
the tree records one for and age *today* for everybody else — with `deceased`
saying which. That is the app's own synthesis; webtrees prints them as two
separate columns.

Two things it took running to find:

- **"Age today" for the long dead is arithmetic, not a fact.** A tree this old
  is full of people born in 1850 with no death recorded, and measuring those
  to today answers **176** — enough to stretch the scale past every real age
  in the tree. `isDead()` is webtrees' own test for exactly that, tree
  preference (`MAX_ALIVE_AGE`) and all, so an age is stated for a recorded
  death, or for somebody the site would still call living, and otherwise not
  at all. The lab's spread went from 56–176 to 56–116 the moment that landed.
  This is deliberately *not* the rule behind `deceased`, which is the narrower
  "the tree recorded a death event" and drives the mourning ribbon; the two
  answer different questions and only the narrow one has an HTML path.
- **An age is counted in the calendar of the *birth*.**
  `AbstractCalendarDate::ageDifference()` says so outright — "perform all
  calculations using the calendar of the first date" — so a Hijri birth is
  counted in Hijri years, which run about eleven days short. It is what the
  website prints, so the app agrees with the website, which is the rule. It is
  also why the number for a Hijri-born man is a couple of years higher than a
  Gregorian reader expects.

Both webtrees versions answer identically across the whole lab tree, and
`live_check` now reports age *coverage* beside the birth-year diff rather than
comparing it: the page states none and the module states fourteen of
seventeen, which is §9 #23's shape — saying less, not saying otherwise.

### 2026-08-24 (later still) — Whether to keep the tree on the device

Evaluated in **`sync_eval.md`**, at the user's suggestion and in the spirit of
`api_eval.md`: dump the tree into SQLite, sync it daily, read it offline.

The recommendation is **yes, with one change of shape**. Not a server-built
`.sqlite` the app downloads — that puts a multi-megabyte build inside one PHP
request on somebody else's shared host, which is the most likely way the whole
feature fails, and it fails at install time. Instead the *client* owns the
database and fills it from paged record requests, which is resumable, needs no
server-side state, and makes the first sync and the daily delta the same code
path.

Measured rather than guessed: **6.2 KB per person** through the module's own
endpoints over eighteen real records, so ~9 MB for 1,463 people as an upper
bound and ~2 MB over the wire. The `change` table gives an incremental token
for free, and a re-import deletes those rows — which makes a
backwards-moving fingerprint the right trigger to resync from scratch.

What the document is most useful for is what it says *cannot* be local:
relationship **wording** (the path is a graph walk the store could do; the
Arabic kinship terms are a large piece of webtrees nobody should port twice),
statistics as the site publishes them, and the media bytes behind a signature.
And what is genuinely hard is not the sync — it is the **privacy snapshot**,
because a store is one user's view of the tree, frozen, on a device.

Drift over ObjectBox, for one reason that is not speed: SQLite is a format a
server *could* write, and ObjectBox's is not, so choosing Drift keeps a door
open that choosing ObjectBox closes forever.

Nothing was built. Phase 10a in §5 is the first step and it is a single
handler.

Released as **0.18.0** with the module at **1.2.1**. **604 tests** green
(595 → 604) plus 14 goldens, analyzer clean, both labs walked through both
transports on both webtrees versions with no differences, and the age checked
across the whole lab tree — identical on 2.2.6 and 2.3, person for person.

### 2026-08-24 (later still) — Phase 10a: the wire a local copy is filled from

`sync_eval.md` §12 said to start here and said why: *"It is a single handler
over machinery that already exists, it can be verified against both labs the
same afternoon, and it answers the only question the rest depends on: does a
real server hand over 1,463 records in eight requests without falling over."*
It does — **8 requests, 4.69 MB, 6.8 seconds, inside a 16 MB `memory_limit`** —
and getting there cost one real bug and corrected three documents.

`GET /tree/{t}/mobile-api/v1/records` answers the same record
`/individual/{xref}` does, in pages, with `sections` and `charts` stated once
per page rather than once per person because they describe the tree and not
anybody in it. With `since=<token>` it answers only what a change has touched.
The record itself moved into `RecordComposer`, which is what makes "the same
payload" a fact about the code rather than a promise: `/individual` and
`/records` now compose from one place, and `live_check` diffs a page against
the single-record endpoint field by field to keep it that way.

**The bug is the part worth keeping.** The first walk of the lab tree in pages
of five returned 22 people from a tree of 18, and four of them twice — the four
with a romanized second name.
`SearchService::searchIndividualNames($trees, $terms, $offset, $limit)` invites
being paged by its own arguments, and `paginateQuery()` dedupes against the
collection it is *building* while counting the offset down over rows it has not
deduped. So an offset counts *rows* and a page counts *people*, and the
difference arrives again on the next page. This is the trap §3 has always
described in the stock autocomplete — and `api_eval.md` §4, `PROJECT.md` §3 and
`sync_eval.md` §3 had all recorded it as *fixed* by the very method that has
it. Three documents, one careless reading, and it survived because nothing had
ever walked a whole tree in small pages. The search endpoint is fixed by asking
from the top every time, where the dedup set is everything walked, and taking
the page in the module; the sync endpoint does not use that walk at all,
because ordering by xref makes paging an indexed SQL `LIMIT` — `O(1)` in the
offset instead of `O(offset)`, no join to `name`, and duplicate-free by
construction.

**The fingerprint is `MAX(change_id)` and the tree's counts**, and both halves
were confirmed rather than assumed. Every edit writes a `change` row, so the
largest id is a watermark and a delta is everything above it. But an import
*deletes* the tree's change rows before reading the first record — on 2.2.6, on
2.3, and from the command line — so the watermark moves backwards after a
re-import, which is exactly the signal to throw a local copy away; and it
cannot see the import at all, which is why the counts are in the fingerprint
too. A fingerprint this tree cannot describe a path from answers
`resync: true`, which is not an error and carries no records.

Two things only running it settled:

- **A changed person is not one changed record.** A payload names their
  parents, spouses, siblings and children, so renaming one man restates a
  dozen other records — and a store that missed that would show his old name
  beside his children until something else touched them. So a delta expands
  every changed xref two hops through `LinkedRecordService`: what it links to,
  and everybody in every family it belongs to. The `link` table holds both
  directions (`F1 CHIL X42` *and* `X42 FAMC F1`), which is what makes one
  method answer both questions. Changing X42 in the lab answers 13 people;
  changing his family answers its 4; changing the note, the photograph or the
  source on him answers him alone.
- **A record this reader may not see is a tombstone, not a gap.** The lab's one
  `RESN confidential` person, touched, comes back in `deleted` — because for
  one reader's copy of a tree "you may no longer see this" and "this is gone"
  are the same instruction. An xref that has left the tree altogether comes
  back the same way, and a tombstone a client does not recognise costs it
  nothing.

Measured, on a lab rebuilt with 1,450 more invented people (`setup.sh 2.2.6
8622 1450`, kept out of the default lab on purpose):

| | |
|---|---|
| Full walk, 1,469 people | 8 requests at `limit=200`, **6.8 s**, 4.6 ms/person |
| On the wire | **4.69 MB**, 3.2 KB/person |
| Peak memory for a 200-record page | under **16 MB** — nothing accumulates |
| A page of 50 full records | 0.26 s at offset 0, **0.26 s at offset 1,400** |
| The search walk, same tree | 0.05 s → 0.13 s over the same offsets |

The 3.2 KB is a *floor* rather than a figure: the bulk people carry a name, a
sex, a birth and a death and nothing else, where `sync_eval.md` §8 measured
6.2 KB over eighteen people who each have notes, a citation and photographs. A
real tree sits between them, which brackets 1,463 people at **4.7–9 MB** and
corroborates §8's "realistically 4–6 MB". The gzip figure from this tree is
meaningless — 1,450 people drawn from eight given names compress absurdly well
— so §8's ~2 MB estimate stands unverified.

Released as **0.19.0** with the module at **1.3.0**. **604 tests** green plus
14 goldens — unchanged, and worth saying why: nothing in `lib/` moved, because
Phase 10a is deliberately server-side. What checks it is `tool/check_module.py`
(40 files, both webtrees versions), a new `=== Sync ===` section in
`live_check` that walks the tree, diffs every record against `/individual`,
and asserts a stale fingerprint is refused, and both labs run end to end on
both webtrees versions with every check passing.

### 2026-08-24 (later still) — Phase 10b: the tree, on the device

The module was updated on `tree.almou.sa`, which closed the one outstanding
action in §9 #18 and made the first thing worth doing a real-tree run rather
than a new feature. It passes, whole: **1,463 people, 40 records diffed field
by field with no differences**, and the two things the instance's old 1.0.1
could not say — a relationship's direction and a timeline event's calendar
conversion — now agree with the page. Then Phase 10b, which `sync_eval.md` §12
scoped as *"the store fills; nothing reads it yet"*.

**It fills, from the real tree**: 1,463 records in 30 requests, 37.7 s, into a
Drift database with 13,701 membership rows across 438 families. Every record
read back out of it is identical to the one `/individual` answers, compared as
raw payloads rather than as decoded objects — and the second sync costs **one
request and writes nothing**.

Four decisions worth the words:

- **A record is stored as the module sent it.** `payload` holds the endpoint's
  own JSON verbatim and every other column is derived from it for the sake of a
  `WHERE`. So the store is not a second model of a record that could disagree
  with the first; it is the same bytes, indexed. `module_decode.dart` grew one
  entry point for a whole record and both the module transport and the store
  use it — the client-side twin of `RecordComposer`, which is what makes
  `/individual` and `/records` incapable of disagreeing on the server.
- **The schema does not import Flutter.** Saying where the file lives needs
  `path_provider`, which needs Flutter, and the first attempt put that in
  `store.dart` — which broke `tool/live_check.dart` outright, because it runs
  on the Dart VM. So the executor is handed in and `store_open.dart` is the one
  file with an engine behind it. The tool now fills a *real* store from a real
  server, which is the third column `sync_eval.md` §10 asked for.
- **live_check uses the app's own sync engine.** The Phase 10a version of that
  section was a second implementation of the walk, written in the tool. It is
  now the shipping `TreeSync` with a `SyncSource` wrapped around it to watch
  what goes past — because a check that reimplements the thing it checks drifts
  away from it, and the drift is invisible.
- **Membership rows are kept per stating person.** The module states, per
  person, every family they belong to with *all* of its spouses and children —
  the subject included — so a membership needs no inference at all, which is
  the ambiguity §7 bug 50 came from. A family of four is therefore stated four
  times, and the row remembers by whom: a delta re-sends one person, and only
  that person's statements may be replaced. Four times 438 families is 13,701
  rows on the real tree, which SQLite does not notice.

Measured against `tree.almou.sa`, filling a file-backed store:

| | |
|---|---|
| Filling it | 1,463 people, 15 requests at `limit=100`, **29.8 s** |
| On disk | **10.70 MB** — `sync_eval.md` §8 estimated ~9 MB |
| Reading a whole record back | **0.61 ms** |
| Searching the whole tree by name | **12 ms** for 50 hits |
| Walking all 1,463 in pages of 50 | **541 ms** |

The last three are the point of the whole phase, and they are the numbers
`sync_eval.md` §2 predicted mattered: not the request *count*, which was never
high, but the round trip every tap pays. 0.61 ms against a network fetch is a
different kind of application — and 12 ms to look at every name in the tree at
once is a question the app has never been able to ask (§9 #24).

**What is deliberately absent is the reason 10c is gated.** `sync_eval.md` §6
says encryption at rest is *"a decision to take before the first byte is
written, not after"*, and no byte has been written on a device: nothing in the
app constructs a store, so the only stores that exist are in this machine's
memory and in a test. That is the honest place to stop, and §9 #29 is the gate.

Sixteen new tests, all against a real SQLite database in memory and a scripted
server — because the behaviour worth testing is not "does the endpoint answer"
but what happens when a page fails halfway, when a record is deleted, when the
reader changes, and when the server says the copy cannot be caught up. A live
run produces none of those on demand. One of them reads a **captured** page
from a running 2.2.6 lab, which is the first module fixture in this project not
written from the design (§9 #26).

Released as **0.20.0**. **620 tests** green (604 → 620) plus 14 goldens,
analyzer clean, both labs walked on both webtrees versions, and the real tree
end to end. CI grew a step: `build_runner` runs there and the
build fails if the committed generated file disagrees with its source, which
was the price `sync_eval.md` §9 named for choosing Drift and is now paid.

---

### 2026-08-24 (later still) — Phase 10c: the copy is locked, and it answers

Phase 10b left a store that filled and was never read, and said why: the
encryption question was *"a decision to take before the first byte is written,
not after"* (`sync_eval.md` §6 #3), and no byte had been written on a device.
This phase answers it and lets the composer in.

**The gate cost almost nothing, which was not the expectation.** `sync_eval.md`
§6 pointed at `package:sqlite3` 3.x's build hooks and the plan assumed a native
toolchain step — a compile per ABI, a new class of CI failure, OpenSSL on
Android. It is four lines of `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlite3mc
```

`sqlite3` 3.5.2 ships pre-compiled SQLite3MultipleCiphers binaries beside the
plain ones, sha256-verified from its own sources, so choosing encryption is a
*selection* and not a build. `sqlite3mc` over `sqlcipher` for two reasons: the
SQLCipher build links OpenSSL on Android, Linux and Windows, and it lags
upstream SQLite. Both answer `PRAGMA key`. Nothing was added to CI.

**The key is per connection, and never leaves the device.** 256 bits from
`Random.secure`, kept under the site *and* account in the same keystore as the
password, passed to SQLite as a blob literal — `PRAGMA key = "x'…'"` — rather
than as a passphrase, because the key is already uniformly random and a KDF
over it would add cost and no entropy. Written `deviceOnly`, which is new on
`SecretStore.write`: a Keychain item with the default accessibility rides an
encrypted iCloud backup and can be restored onto another phone, and a key that
travels with the ciphertext makes the encryption ceremonial. The password is
deliberately *not* device-only — restoring a phone and finding the app still
signed in is what a reader expects, and a password is a secret they can retype.
A tree is not.

**A file this key cannot open is deleted, before drift ever sees it.** Three
ordinary ways to get one — another account signed in, the keystore lost the key
to a reinstall, a device that ran out of space mid-sync — and in all three the
honest answer is that there is no copy here and the next sync will make one.
Nothing is lost the server does not still have, which is what makes deleting
right rather than drastic. Probed with a real statement rather than with
`PRAGMA key` alone: the pragma reads nothing, so it succeeds against a file it
cannot open, and the failure would otherwise surface as
`SqliteException(26): file is not a database` at whatever screen read first.

**What is composed, and what is deliberately not.** `Capability.answerableLocally`
is `{individuals, individual}` and nothing else. A capability belongs there only
where the store holds *the bytes the server sent* — true of a record, because
the payload is kept verbatim. `relationship` and `statistics` stay online
permanently (`sync_eval.md` §5); the charts and the timeline are computable from
the stored links and are Phase 10d. One fallback, on `individual` only: a record
absent from the store means either that the reader may not see them or that the
copy is behind, only the server can tell those apart, and it applies the same
privacy either way — so asking is safe and the alternative is telling a reader
that somebody who exists does not. A search deliberately does **not** fall back:
a search that found nothing locally has searched the whole tree, which is the
point of the phase.

**The download policy is the half a reader actually meets.** Agreed with the
user: 10 MB is nothing on a modern plan, so the copy is made on first use in
the background — but on a cellular network the app waits, says *"the download
will start on its own the next time you are on Wi-Fi"*, and offers a
**Download now** that always wins. `TreeStore` watches
`onConnectivityChanged` rather than re-checking when a screen opens, because a
promise the reader has to come back and collect is not one. A *delta* never
waits: the protection is for the first copy, which is megabytes, and making
somebody wait for wifi to see yesterday's edits would be protecting them from
nothing.

**And it closes §9 #24, in a way that did not need the store.** The store
answers a search with up to 2,000 matches in one page instead of 50 —
affordable because a search row is now built from the **columns** the sync
already derived rather than by decoding the payload, so a thousand rows is one
indexed `SELECT` and no JSON. That puts every match in the filter's hands. But
the visible fix is smaller and better: the screen keys its wording on
`!hasMore` rather than on which transport answered, so *any* search paged to
its end now says *"Nobody in this tree matches"* and drops the word "loaded"
from the count. The apology survives exactly where it is true. The store is
what makes the good case ordinary rather than the end of a long scroll.

**Signing out takes the tree with it.** `sync_eval.md` §6 #2 asked for it and
10b left `TreeSync.wipe` with no caller. `TreeStore.destroy` now runs from the
shell's sign-out path and deletes the file, its `-wal` and `-shm`, *and* the
key — a deleted key alone leaves ciphertext, which is close to destruction and
is not it. Android is closed too: `allowBackup="false"`,
`fullBackupContent="false"` and a `data_extraction_rules.xml` excluding every
domain from both cloud backup and device transfer. **iOS is the residue** and
§9 #29 says so: the documents directory is backed up by iCloud, the key is not,
so a restored copy is unreadable ciphertext rather than a leak — but the
ciphertext still leaves the device, and `NSURLIsExcludedFromBackupKey` needs a
platform channel nobody has written because nobody ships iOS from this repo.

Two defects found reading the new code back, both in the wiring rather than in
the store, and both logged as §7 bugs 54 and 55: a **session expiry** would
have destroyed the copy exactly as a deliberate sign-out does, and opening a
**second tree** would have inherited the first one's `ready`. The second is the
phase's own staleness rule being broken one level above where it was written,
which is the more interesting of the two.

**Fifty-four new tests**, and the ones worth naming are in
`test/data/store_encryption_test.dart`, because they are the evidence the gate
is shut rather than assertions that SQLite works: against a **real encrypted
file**, a name written into it is not on the disk in the clear, the header is
not `SQLite format 3`, and an unkeyed, wrongly-keyed or other-account open is
refused. A mock of a cipher would prove nothing at all.

Released as **0.21.0**. **674 tests** green (620 → 674) plus 14 goldens,
analyzer clean.

---

## 7. Bugs found, and what they taught

| # | Bug | Caught by |
|---|---|---|
| 1 | URL-style detection ran *after* other checks, so they used the wrong style | Phase 0 live run |
| 2 | Writing a POST body freezes Dart's headers — `followRedirects` must be set first | Phase 0 live run |
| 3 | Maintenance mode reported as "not webtrees"; style detection ignored health | Unit test |
| 4 | `WebtreesUrl.call` folded a query string into the URL path | Unit test |
| 5 | `getAnonymous` closed the *shared* HTTP adapter, killing all later requests | **Live run only** |
| 6 | `connections()` returned a `const []` that `remember()` then tried to mutate | Unit test |
| 7 | Sign-in validation message was word-for-word the always-visible subtitle, so the error told the user nothing new | **Widget test** |
| 8 | The keep-alive timer outlived the widget tree; a non-positive interval now disables it | Widget test |

| 9 | Silent re-login posted the CSRF token that died with the expired session, so recovery never worked | **External review** |
| 10 | `resume()` was never called by anything — the returning-user path did not exist | **External review** |
| 11 | Every non-`200` read as a definitive answer about the account | **External review** |
| 12 | `tom-select-individual` documented as an enumeration API; it requires a query | **External review** |
| 13 | Tab discovery keyed on an `id` that only 2.3 emits, so 2.2.6 found no tabs | **Two-version fixtures** |
| 14 | Search omitted the required `at` parameter — every live search was a `400` | **Live run only** |
| 15 | A record URL without its slug answers `301`; the app read that as a dead session | **Live run only** |
| 16 | The 2.2.6 fixture's tab URLs were invented, not what a 2.2.6 server emits | **Live run only** |
| 17 | The 2.2.6 date fixture was 2.3's markup, so no 2.2.6 date structure had ever been parsed | **Live capture** |
| 18 | The person route was declared beside the search route, so the first back gesture left the app | **Widget test** |
| 19 | A lifespan rendered `1940–1875` in Arabic — bidi reordering a run of digits | **Rendered preview** |
| 20 | The calendar escape was read from a decoded URL, whose `#` swallowed the query | **Parser test** |
| 21 | Submitting a search left its debounce pending, so every search ran twice | **Widget test** |
| 22 | The live check asked the server for a chart the app never fetches | **Live run only** |
| 23 | Every statistics chart was dropped: one *options* argument is JavaScript, not JSON | **Live markup** |
| 24 | A stacked bar drew as empty surface — a coloured box has no height of its own | **Rendered preview** |
| 25 | Chart buttons appeared in the site's menu order, and skipped their own rule | **Rendered preview** |
| 26 | d'Aboville numbers restarted at each family, so two children were `1.1` | **A richer fixture** |
| 27 | `fact_INDI:DEAT` was read out of the 2.3 template; the class is bare, `fact_DEAT` | **A captured fixture** |
| 28 | `api_eval.md` recommended `I18N::language()->formatDate()` as version-neutral; it does not exist in 2.2.6 at all | **Reading both versions while writing the code** |
| 29 | The contract suite's fixture gave the subject one spouse where the HTML fixture gave him two | **The contract suite, on its first run** |
| 30 | The `v2_3` statistics fixture was hand-written in **2.2.6's** shape, so the parser was green while every chart on a real 2.3 site came back empty | **A 2.3 lab install** |
| 31 | `capabilities.languages` was a JSON *object*: `findByInterface()` keys its collection by module name | **A 2.3 lab install** |
| 32 | `I18N::init()` did not change a label — only a date. Tag labels are registered eagerly *before* `Router`, so they were already Arabic | **A 2.3 lab install** |
| 33 | Only an anonymous `404` proved a tree private; 2.3 answers `400`, silently downgrading every private tree there to `memberOrVisitor` | **A 2.3 lab install** |
| 34 | The version was read only from a `200`; 2.3 answers `400` for `GET /login` and renders the page anyway | **A 2.3 lab install** |
| 35 | The lab set tree privacy through `setPreference('REQUIRE_AUTHENTICATION')`, which schema 45 turned into a column — so the tree was never private, and it looked exactly like the module leaking one | **Checking the database rather than believing the symptom** |
| 36 | Every undated person carried a lifespan of `…–`. `Individual::lifespan()` always writes something so a chart box keeps its height; the app showed it | **The real tree** |
| 37 | The module read no second name for a person recorded twice in the *same* script. `GedcomRecord::alternateName()` answers only when the two differ by character set | **The real tree** |
| 38 | `deceased` was `Individual::isDead()`, which *infers* death from age — so a person born in 1850 with no death recorded was dead to the module and unknown to a chart box | **`live_check --sample`** |
| 39 | A converted date repeated its qualifier: `about 1875 (about 1292)` where webtrees writes `about 1875 (1292)` | **`live_check --sample`** |
| 40 | A family's `HUSB`, `WIFE` and `CHIL` lines came back as *facts*, so the parents card listed "husband · wife · son · son" under the parents and every family card wore a pill per member | **Reading the screen** |
| 41 | The mourning ribbon was a parallelogram that stopped short of both borders, so at 40 pixels it read as a black smudge floating over a corner rather than as a ribbon | **Reading the screen** |
| 42 | Sharing a chart captured the **viewport**: the `RepaintBoundary` was around `ChartCanvas`, whose build returns the `InteractiveViewer`, so what reached the file was the part of the family on screen at whatever the reader had pinched to | **Reading the screen** |
| 43 | A chart shape the app draws with its own painter — the fan — had no capture boundary at all, so sharing one could only ever have failed | Found while fixing 42 |
| 44 | webtrees **2.3** answers `500` for the thumbnail of any non-JPEG. `ImageFactory::autoRotateImage()` calls `exif_read_data()` on every image, PHP warns for a PNG, and webtrees' own error handler turns a warning into an exception — so a scanned certificate breaks on the website too | **Putting a file on disk in the lab** |
| 45 | The module's relationship `description` was the bare kinship word — `أب` — where the page writes the site's own `Relationship: %s`, so the two transports headlined the same path differently | **The capability diff, on its first run** |
| 46 | The module's timeline had dropped the calendar conversion *and* the couple: `١٩٧٤` where the page says `١٩٧٤ (١٣٩٤)`, and two marriages with nothing to tell them apart | **The capability diff, on its first run** |
| 47 | The app preferred the module for statistics, which answers four sections where the page publishes seventeen — and the diagnostics screen, whose job is to say which transport answered, said "Module" for a capability the module was about to be taken off | **The capability diff, on its first run** |

| 48 | The module answered a second name for a woman who has one. `getAllNames()` adds a row for every `ROMN`, `FONE` and `_XXX` **subtag** as well as for each `NAME` line, so a `2 _MARNM` under her only name read as an alternate name — which webtrees renders as a *field inside* the name block and never as a name | **The real tree, on the first record with a married name** |

| 49 | The module called a buried man living. `deceased` asked for a `DEAT` fact; `Gedcom::DEATH_EVENTS` is `DEAT`, `BURI`, `CREM`, and a chart box prints a tag for whichever it finds — so the page mourned him and the module did not | **The real tree, walking 40 records** |
| 50 | A family with children, no marriage recorded and **no wife recorded at all** had its eldest son read as the second spouse. Nothing in the rows says which is which — a father and a son both render `wt-sex-m`, and the `<th>` beside them is a translated relationship name | **The real tree, walking 40 records** |
| 51 | The lab had privacy **switched off** for its whole life: `canShowRecord()` returns true for everybody before it examines anything unless `HIDE_LIVE_PEOPLE` is `'1'`, so a `1 RESN confidential` in the GEDCOM did nothing and no privacy rule had ever been exercised | Found while building a record for bug 50 |
| 53 | **The module's own paging handed the same person over twice.** `SearchService::searchIndividualNames($trees, $terms, $offset, $limit)` invites being paged by its own parameters, and `paginateQuery()` dedupes against the collection it is *building* while counting the offset down over rows it has not deduped — so `offset=5&limit=5` skips five *rows* and answers five *people*. Four of the lab's nineteen have a romanized second name, and browsing them in pages of five produced 22 rows for 18 people. Same code in 2.2.6 and 2.3, and the same trap §3 describes in the stock autocomplete: inherited, not avoided, and the design documents had all recorded it as fixed | **The first walk of a whole tree through the new sync endpoint** |
| 52 | **Bug 19 again, and only half fixed the first time.** `ltrRun` isolates a lifespan so the paragraph around it cannot reorder it — which works for `1901–1974` and *not* for `١٣١٨–١٩٧٤`. An isolate sets the run's base direction; it does not change what is inside it, and Arabic-Indic digits are **Arabic** numbers rather than European ones, so bidi rule N1 resolves the dash between two of them as right-to-left and the run is reordered around it. Every lifespan on a site rendering in Arabic — which is every lifespan on `tree.almou.sa` — read `١٩٧٤–١٣١٨`: the man died before he was born, in an English interface and an Arabic one alike | **Rendered preview, from a fixture captured off a real server** |
| 54 | **A session that expired would have deleted the tree.** The shell wired "the store is destroyed" to *not signed in*, which is the same state webtrees leaves the app in when its idle timer fires and a silent re-login fails — so a phone left in a pocket would have thrown away a 5 MB copy through no decision of the reader's, and re-downloaded it. Deliberate sign-out and session expiry are different events and only one of them means "I am done here"; the destroy now hangs off the sign-out *callback* rather than off the session's state. An expired session leaves the copy alone, which is safe because it is encrypted under a key belonging to one account | **Reading the new code back before committing it** |
| 55 | **One store holds several trees, but the phase describes one.** `TreeStore.bind` short-circuits when the reader has not changed — right, because the file has not changed — and that path skipped re-reading the state. Opening a second tree therefore inherited the first tree's `ready`, so `isReadable` said yes and every search in the new tree would have answered "nobody" out of a store that simply had no copy of it. The exact failure the phase's own staleness rule exists to prevent, one level up from where the rule was written | **Reading the new code back before committing it** |

50 is the interesting one, because the markup genuinely does not say. The
divider that separates a couple from its children is the marriage row, and a
family that records no marriage has none. What does say — sometimes — is the
**caption**: webtrees titles a family *Family with X*, *Father's family with
X*, or `X + Y`, and every one of those names the other spouse. A birth family
is the exception, and it names nobody — which is also the only case where the
old rule was reliably right, because there the first two rows really are the
parents.

So the parser reads a page's families in two passes: the ones stating a
marriage settle themselves, and what they settle — *this person is half of a
couple* — is then available to the ones that do not. A step-family hangs off a
parent or a spouse, and the page has already drawn that person's marriage
elsewhere. The subject's own row joins the couple only where the caption named
somebody, which is what separates *Family with X* from *Parents and siblings*;
the lab caught the first version of that rule making a man the spouse of his
own father.

51 is bug 35 again, and worth the same sentence: a lab setting quietly made a
whole dimension untestable. Every privacy claim this project has written down
— *a hidden record is absent, not empty*, *a name may be visible where details
are not* — was resting on a tree where `canShow()` returned true before it read
anything. With privacy on and only one restricted person, both transports
agree, and `canShowName()` really is true where `canShow()` is false.

48 is bug 37 overshooting. That fix moved the module off
`GedcomRecord::alternateName()` — too narrow, it answers only for a name in a
different script — and onto `getAllNames()`, which turns out to be too wide in
the other direction: it holds a row per name *form*, not per name. The page
counts `span.NAME` inside the names accordion, which is one per `NAME` line,
and the module now counts `1 NAME` lines in the record's own GEDCOM to match.
Neither transport had ever met the case, because no fixture and no lab had a
married name in it; the lab has one now, and reverting the guard turns it red.

Bugs 44–47 are what happens when the two transports are asked the same
question about the capabilities nobody had compared yet. Three are the
module's and one is webtrees' own — and 44 could only ever have been found by
a lab with a *file* in it: the GEDCOM had declared a media object since the
lab was written, the media tab had rendered it, and nothing had ever asked for
the bytes, because there were none.

47 is the one that changes a rule rather than a value. Every figure the two
transports both state agrees; the module simply sends **less**. So "the module
is faster and more truthful" is not enough on its own to prefer it — the test
is whether it knows *more*, and where it knows less the page answers. That now
lives in one place, `Capability.readFromThePage`, because the diagnostics
screen has to state the same answer the transports act on.

Bugs 40–43 were all found the same way: **somebody looked at the screen.** Not
one of them was visible to 509 green tests, to `live_check`, to the module's
static checker or to a `--sample` walk of the real tree, and between them they
cover the two most-used screens in the app.

40 is the one worth the lesson. `HUSB`, `WIFE` and `CHIL` are facts like any
other to webtrees — `Family::facts()` returns them beside a marriage — so a
presenter that asked a family for its facts and sent them all answered a
marriage *and* one pointer per member. The client already had those people as
`spouses` and `children`, so it drew both: the word "son" once per son. webtrees
itself filters exactly those three on its family page, and prints only marriage
and divorce events on the relatives tab; the module now does both, one for the
family endpoint and one for a family shown inside a person. The **fixture is
why nothing caught it**: `test/fixtures/module/individual_X42.json` was written
from the design rather than captured from the server, so it never contained the
pointers the server actually sent. That is bug 27 and bug 30 for the third
time, and this time the check went in on the wire — `live_check` now diffs the
family events both transports report, which fails loudly on the old module.

42 is the same kind of error in the interface: the boundary named
`_capture` really did wrap "the chart", and the chart's `build` returns the
`InteractiveViewer` that looks at it — so the thing captured at natural size
was a window, and the export was a screenshot with extra steps. The comment
above it had said "at its **natural size**, outside the viewport" since it was
written. A comment describing intent is not a test, and the test that now
exists asserts the boundary is *wider than the phone it is drawn on*.

Bugs 26 and 27 are the same lesson from two directions. 26 only appeared once
the fixtures held a second marriage — a fixture that reproduces exactly what
the parser expects proves nothing, which is what `test/fixtures/README.md`
had been warning about since the beginning. 27 was the reverse: the *captured*
2.2.6 markup had `fact_BIRT` all along, and a first reading of the 2.3
template invented a qualified form that webtrees has never emitted. Read the
capture before believing the template.

Bugs 38 and 39 are what **one record could not find**. 36 and 37 came from
diffing a single person; `--sample` walks the tree instead, and the first run
of it turned up two more classes on the fourteen-person lab — an inferred death
and a doubled date qualifier — which a 60-record sample of the real tree then
confirmed on four of its own. Both are cases where a hand-picked record is the
worst possible witness: they need someone born long ago with no death recorded,
and an `ABT`/`EST` date. Neither is rare, and neither was in the record the
first diff happened to choose.

That is now the standing check: `--sample` against both labs, which is the only
thing that reads real markup through both transports across many shapes at
once.

Bugs 36 and 37 are the two the *real* tree found on the first request the
module ever served against 1,463 people rather than fourteen invented ones —
and neither could have come from anywhere else. Both were disagreements between
the transports on one woman's record: a lifespan of `…–` where she has no
dates, and a second Arabic name that the HTML path read from the names
accordion and `alternateName()` refused to report because it only ever reports
a name in a *different script*. One was fixed on each side. Nothing else
differed, on any of the 1,463.

That is the argument for the contract suite in one line: two transports over
the same tree, and the only thing that could have told them apart was running
both over data neither had seen.

Bugs 30–35 all arrived in one afternoon, from the same cause: **the module was
executed for the first time.** Every one had survived a document argued from
source, 508 green tests and a live run against a real 2.2.6 instance. Five were
found within an hour of the first lab install, and the sixth (35) was found by
disbelieving the other five for long enough to check.

30 is the sharpest, because it is bug 27 again with the versions swapped: a
fixture *transcribed from an assumption* rather than captured, and green tests
certifying it. It hid a total failure — not a wrong value, but **zero charts on
every 2.3 site**, for as long as the app has claimed to support 2.3.

35 is the one worth remembering for next time. The symptom was a private tree
readable by an anonymous caller through the module on 2.3, which reads exactly
like a privacy hole. It was the *lab* that was wrong: schema 45 moved tree
privacy from a setting row to a column, 2.2.6 kept a shim and 2.3 dropped it,
so the tree had never been private at all. The lesson is not "check the
fixture" — it is that a frightening finding deserves the same scepticism as a
convenient one, and the database was one query away.

Bugs 28 and 29 are the previous pair, and they are about *documents* rather than
markup. 28: `api_eval.md` is argued from source and cites a file and a line for
every claim, and it still got `formatDate()` wrong — because the method exists,
and the reading checked that rather than checking *which version* it exists in.
Nothing but writing the code against both trees would have found it. 29 is the
contract suite paying for itself before it had run twice: it compares the two
transports over two fixture sets, so a fixture that quietly disagreed with the
captured HTML failed immediately instead of hiding until a live run.

Bugs 3–4 and 6 were found by unit tests; **5 was invisible to them** — keep
`tool/live_check.dart` current and run it after transport changes. Bugs 14–16
make the same point a second time and more sharply: 185 tests were green while
**search was broken against every real webtrees instance**, because the fake
server answered a request the real one rejects. A fake that is more permissive
than the thing it stands for cannot fail. The fake now enforces `at` exactly as
`AbstractTomSelectHandler` does. Bug 7 is the
argument for widget tests carrying assertions about *copy*, not just structure.

Bug 17 is bug 16 again, one layer down, and worth the repetition: the 2.2.6
fixture said `1901 [1318]` as plain text because that is what the *2.3* source
emits. A real 2.2.6 server sends a calendar link per date — the thing that
makes choosing a calendar possible at all. The fixture had been written from
the wrong version's template and agreed with a parser that never looked.
Bugs 18 and 19 are the two the tests could not have been expected to catch
from copy alone: one needed the system back button simulated, the other needed
somebody to look at a picture.

Bug 25 is worth the entry for its cause: `ChartKind.drawnFrom` decides which
charts a person's page may offer *and in what order*, and the screen was still
filtering the map by hand — so the rule that an hourglass needs both halves
went unapplied, and the buttons came out in the order the site's menu happened
to list them. What made it look deliberate is that a `const Set` of enum
values does not iterate in the order it is written. The rule had a unit test;
nothing tested that the screen used the rule, and only walking the preview to
that screen showed it.

Bug 23 is the fixture lesson in a new coat: the *data* argument of every
`statistics.draw*Chart` call is strict JSON, and the options argument beside it
is hand-written JavaScript — comments, unquoted keys and all. A parser that
decoded both threw on the second and dropped the chart, and no fixture written
from the data alone would ever have shown it. Bug 24 is bug 19 again: the
tests said the widget was there, and the picture said it was invisible.

Bug 22 is small and the lesson is not: "charts the app can draw" and "charts
the app fetches" became different sets the moment an hourglass was stitched
from two others, and a loop written when they were the same set went on
asking a real server for a page nothing would ever parse. The unit tests were
green — they know what the app draws — and only a live run put the question
to a site.

Bug 21 had been there since search was written and cost only a duplicate
request, which is why nothing noticed. Paging gave it teeth: the second,
debounced run reset the results, so the page the reader had just asked for
vanished a moment after arriving. A harmless waste and a visible fault were
the same defect, and only the second one was ever going to be reported.

Bugs 9–12 share one cause, and it is the important lesson here: **the suite was
green for all of them.** Tests were written against the fixtures the code
already agreed with. The fake server flipped a boolean instead of modelling a
session, so no test could express "the session expired"; the returning-user
test asserted that a heading appeared rather than that anyone got signed in;
and the endpoint claim was never checked against upstream source at all. A
passing suite measures the questions asked, not the ones that matter — every
fix above therefore ships with a test that was *confirmed to fail* against the
old code.

### 2026-08-22 (later) — Phases 1b, 1c, 1d, 2c

**Credential storage.** `core/secret_store.dart` and `core/unlock_gate.dart`
wrap the platform keystore and device authentication behind interfaces, each
falling back to a working no-op when the platform lacks support — Linux has no
`local_auth`, and a headless box often has no keyring. `data/credential_store.dart`
keeps a list of saved connections plus one password each, and **discloses its own
limits**: `canRemember` and `isGated` drive interface copy so the app never
implies protection it is not providing.

**Session manager.** `data/session_manager.dart` is a `ChangeNotifier` owning
the connect → sign-in → signed-in lifecycle, with a 10-minute keep-alive and
`withSession()`, which retries once after a silent re-sign-in when the server
drops the session. A stored password that stops working is discarded so the
user is asked once rather than on every request.

**Interface.** Material 3, seeded from a muted archival green, light and dark.
Three screens — connect, sign in, your access — wired with `go_router`, whose
`refreshListenable` is the session, so an expired session cannot strand a
signed-out user on a signed-in screen.

**89 tests** green (61 → 89), analyzer clean, live check still passing. Thirteen
of the new ones are widget tests driving the whole flow against the fake server.

**Not yet run as a GUI.** The Linux desktop toolchain is absent here — no
`cmake`, `ninja`, `pkg-config`, GTK3 or libsecret. See §8 for what to install.

### 2026-08-22 (later still) — External review, and Phase 2d

An independent review by Codex was checked claim by claim against the source
and the live server. **Every finding held.** The lesson is in §7: the suite was
green throughout because it never asked the questions that mattered.

**One documented constraint was simply wrong.** §3 claimed
`tom-select-individual` enumerates a tree 50 at a time. It does not — the
handler returns an empty collection for an empty query, in both supported
versions. Had Phase 3 started on that assumption, its central browsing story
would have been built on an endpoint that cannot do it. Corrected in §3, and
v1 is now explicitly search-driven (§2).

**The Phase 1 exit criterion was not actually met.** `resume()` existed and
nothing called it: tapping a recent site only refilled the address box. The
criterion says *restart the app, still signed in*, and that had never happened.
Now wired, and covered by a widget test that fails without it.

**Fixed, each with a test that fails against the old code:**

| Fix | Why it mattered |
|---|---|
| Silent re-login fetches a fresh CSRF token and retries once | The cached token dies *with* the session, so re-login after a real expiry — the one case it exists for — always failed and signed the user out |
| Central status interpretation (`core/response_status.dart`) | `302`/`5xx` were read as "role not held", "not administrator", "tree is private". A failing server could report a public tree as private, i.e. invent a membership |
| Single-flight reauthentication | Concurrent requests meeting one expiry each raised a biometric prompt and posted its own sign-in |
| Client-side sign-in backoff | Promised in §3, never implemented; webtrees has no rate limiting at all |
| Unlock *before* reading the keystore | The password was read into memory, then the gate asked — the wrong order for the thing the gate exists to protect |
| `remember(password: null)` now deletes | Turning "stay signed in" off left the old secret in the keystore |
| Keystore probe writes, reads back and deletes | A store that reads but cannot write was reported as usable |
| `connect()` clears the old site before probing the new one | A failed reconnect left the previous instance on display beside a client pointing elsewhere |
| `resume()` discards a password the server rejects | Otherwise every future launch failed identically |
| Sign-in copy discloses an open gate | §6 claimed `isGated` drove interface copy; it was not exposed at all |
| iOS `NSFaceIDUsageDescription` + ATS | Face ID would have killed the app on first use |
| `AccessSummary` lists copied unmodifiable | `@immutable` was decorative |
| Analyzer strictness on; version identity aligned; `path_provider` dropped | UA said `0.1`, pubspec said `1.0.0`, the APK said `0.1.0` |

**110 tests** green (89 → 110), analyzer clean under `strict-casts`,
`strict-inference` and `strict-raw-types`.

`test/support/fake_site.dart` is new: a site that actually keeps a session and
enforces the CSRF token, so an expiry can be simulated honestly. The older
`workingSite()` fixture flips a boolean and ignores the token — fine for
testing what a screen shows, useless for testing recovery.

### 2026-08-22 (later still) — Phase 3a, the vertical slice

Search a tree → open a person → read their facts and relatives → load their
photo through the session. Wired into the interface: a tree card on the access
screen opens search; a result opens the person; a relative opens *them*, so a
family can be walked.

**The individual page states its own tabs.** The most useful thing found in the
source: each tab is rendered as `<a data-wt-href="…" href="#{module}">`, so the
server supplies the exact fragment URL and the list of tabs this tree actually
has (§3). Nothing is constructed or assumed, which is why the version
difference below costs nothing and a disabled tab degrades instead of failing.

**Fixtures caught a real compatibility bug before any device did.** The tab
anchor carries no `id` in 2.2.6 — 2.3 added it. The first parser keyed on that
id, so it found **zero tabs on 2.2.6**, the version `tree.almou.sa` runs. Every
parser test runs against both versions; reverting the fix fails the 2.2.6 cases
and passes the 2.3 ones, which is exactly what the matrix is for.

**Structure over language.** This tree is Arabic. Roles come from
`data-wt-chart-xref` and document position, never from the translated captions
and relationship names, and dates are kept as webtrees rendered them so the
Hijri conversion survives. Fixtures are Arabic and RTL throughout.

**Photos go through the session.** `MediaFileThumbnail` checks `canShow()` for
the current user *before* validating the signature, so `Image.network` would
fetch as a stranger. `AuthenticatedImage` fetches bytes through the signed-in
client, and `MediaCache` is memory-only, bounded, and cleared whenever the
session ends — family photographs must not outlive the account that fetched
them.

**A lost section is named, not blank.** A tab that is disabled, restricted or
failing costs that section and adds a warning the person screen shows;
`ParseFailure` carries the parser, the selector and the webtrees version so a
bug report is actionable.

**182 tests** green (110 → 182), analyzer clean under the strict modes.

**The fixtures' limitation is real and recorded** in `test/fixtures/README.md`:
they are transcribed from the upstream templates, not captured from a running
server, so they prove the parsers handle what the templates emit and nothing
more. They cannot catch a theme that restructures a page. Replace them with
sanitized real captures once a password is available.

**Not verified:** the authenticated live check has not been run against
`tree.almou.sa` since these transport changes, because `WEBTREES_PASSWORD` is
not set in this environment. Bug #5 was invisible to unit tests, so **run
`tool/live_check.dart` before trusting Phase 2d or 3a on real hardware.** The
anonymous status codes the new privacy logic depends on *were* re-confirmed
live, and the tool now exercises search, opening a person, the parsers and an
authenticated photo fetch as well.

### 2026-08-22 (later still) — Phase 3a verified against the live server

`WEBTREES_PASSWORD` became available, so `tool/live_check.dart` ran
authenticated for the first time since the Phase 2d and 3a transport changes.
**It failed three times before it passed**, and every failure was a real defect
that 185 green tests had not seen (bugs 14–16).

| Found | Consequence |
|---|---|
| `tom-select-individual` needs `at` | Every search against a real site was a `400`. The endpoint the whole v1 browsing story rests on had never once succeeded |
| `/individual/{xref}` answers `301` to the canonical slug URL | No person could be opened. The redirect was read as `SessionExpired`, so the app would have signed the user out instead |
| The 2.2.6 fixture's tab URLs were invented | The documented "version difference" in tab routing did not exist; both versions use `/module/{m}/Tab/{tree}?xref={x}` |

**Now passing end to end against `tree.almou.sa`:** connect, sign in, session
rotation, roles, search (50 hits for `محمد`, more available), opening a person,
Arabic names including an alternate name, facts, and relatives.

**Checked more widely than the live check does.** Forty records were opened
against real Arabic data: 27 had facts, all parsed, and no record produced a
single parser warning. Records showing facts but no *primary* facts are honest
— they hold only relatives' events (`Birth of a son`), which is exactly the
primary/secondary split working.

**What is still unproven, and why.** `tree.almou.sa` has **no media at all**
(`/tree/main/media-list` returns a page with zero thumbnails), so the
authenticated image path — `AuthenticatedImage`, `MediaCache`, and the
`canShow()`-before-signature rule that motivated them — has never run against a
real thumbnail. This is a limitation of the data, not of the code. It needs an
instance that has media before it can be called verified.

**A live site carries non-stock modules.** The target serves a custom
`_vytux_cousins_` tab alongside the core ones. Discovery handled it without
changes, which is the design working: the page states its tabs, the app does
not guess.

### 2026-08-22 (later still) — Phase 4: Material 3 Expressive, and Arabic

**Expressive is not one flag.** Flutter 3.44 offers
`DynamicSchemeVariant.expressive` and little else of the 2025 update — no
button group, split button or FAB menu yet. So the idiom is assembled in
`app/theme.dart` from the parts that carry it: the expressive scheme, a type
scale with real weight contrast (800 at display, 400 at body), a *varied*
shape scale rather than one radius everywhere, stadium buttons and pill
fields, the 2024 progress indicator, and `FadeForwards` page motion — which
also happens to be the transition that reads correctly mirrored.

**The seed no longer decides the colour, and that is the point.** The
expressive variant rotates hues far from the seed: the project's archival
green comes out as warm sepia and amber, with cyan as tertiary. For a
genealogy app that reads as aged paper, so it stays — but it is recorded here
because a reader of `AppTheme` would otherwise expect green.

**One thing had to be taken back from the scheme.** With tertiary rotated to
cyan, `MessagePanel.warning` was rendering caution in *cyan*, which reads as
information. Caution is amber in almost every interface anyone has used, so it
is now a `ThemeExtension` (`SemanticColors`) with fixed amber for both themes,
tested at **9.8:1** and **9.1:1** against WCAG's 4.5:1.

**Arabic is a first-class language, not a translation pass.** See §3 for what
that cost: locale-dependent tracking, LTR islands for identifiers, mirroring
icons, and a data layer that emits typed `Notice`s instead of English
sentences. Terminology follows webtrees' own Arabic translation
(`resources/lang/ar/messages.po`) — شجرات العائلة, معلومات وأحداث, الوالدان —
so the app reads like the site the family already uses.

**The interface can now be looked at without a device.**
`tool/preview/render_preview.dart` renders real screens to PNGs, with the app's
own fonts *and* the icon font loaded — a test binding registers neither, and
without them Arabic renders as boxes and every icon as an empty square. It
lives outside `test/` and is not named `*_test.dart`, so a normal run does not
collect it. This caught both colour problems above before any build.

**201 tests** green (186 → 201), analyzer clean. The new ones assert the things
that would otherwise only be noticed on a device: that the tree mirrors, that
a hostname does not, that Arabic drops tracking, and that every sealed error
and notice has words in both languages.

### 2026-08-22 (later still) — Phase 4a: getting out of the way

Six things stood between the reader and their family tree. All six are fixed,
and all six turned out to be about the same thing: **the app was asking
questions it already knew the answers to.**

| Was | Is |
|---|---|
| Type the address, then pick the site from a list of one | Launch signs straight back in to the site used last |
| Choose the only tree the account can reach | Straight into it; the account screen is one tap away from the tree |
| Back left the app from the first person opened | Back walks the record trail, then the search, then out |
| Everyone without a photo was the same grey silhouette | The first letter of their name, coloured from it |
| Arabic interface, English dates | The app tells the server which language to render in |
| Every date shown twice | Both, Gregorian or Hijri — chosen in settings |

**The back button was a routing bug, not a gesture bug.** `person` was declared
*beside* `search` rather than inside it, so `go()` built a stack one page deep
and the first back gesture had nothing to pop. Nesting the route fixes both the
walk between people and the walk back to the results. The test drives
`handlePopRoute` — what Android's gesture actually calls — and returns `false`
against the old code, which is precisely "the app would have exited".

**Dates were never translated because the app never asked.** webtrees renders
in the language held in *its own* session, seeded from the account's stored
preference — `Accept-Language` is consulted only before that value exists, so
after sign-in nothing the app sends in a header can change it. One
CSRF-exempt `POST /language/{tag}` fixes it, and the same call is what makes
the reader's language switch reach the dates. It writes the account preference
too, so the settings sheet says so (§3).

**Choosing a calendar is possible because 2.2.6 says which calendar it used.**
Each rendered date is a link to its own calendar page, and the `cal` parameter
carries the GEDCOM escape — `@#DGREGORIAN@`, `@#DHIJRI@`. So the app can drop
one calendar without ever guessing which half of `١٩٧٧ (١٣٩٧)` is which, and a
qualified date keeps its words: `بين ١٣٩٤ و ١٣٩٥`, not two bare years. 2.3
names no calendar at all, and there the app shows both rather than inventing
an answer (§9).

**The fixture was lying about 2.2.6 again.** Its date markup was 2.3's plain
`1901 [1318]`, transcribed from the wrong version's source — so no 2.2.6 date
structure had ever been parsed by anything. Replaced with a sanitized capture
from the live server. This is bug 16's lesson a second time (§7).

**Two bugs only a picture could have caught.** The rendered previews now walk
all the way to a person, and showed a lifespan reading `1940–1875` in Arabic —
a run of digits taking its direction from the paragraph around it. And they
showed the home screen titled `main`, the identifier webtrees routes on, when
the tree calls itself `الموسى الصائغ` in the heading of its own page.

Released as **0.2.0**. **234 tests** green (201 → 234; several existing ones had to be updated
because signing in no longer lands on the account screen), analyzer clean, and `tool/live_check.dart` passes against
`tree.almou.sa` — now reporting the tree's title, the language switch, and the
same date in both calendars and each one alone.

---

## 8. Tooling

```bash
# Validate the wire protocol against any instance (dependency-free)
dart run tool/probe.dart --url tree.almou.sa --user NAME

# Exercise the app's own data layer end to end
WEBTREES_PASSWORD=... dart run tool/live_check.dart --url tree.almou.sa --user mobile
#   --search TERM     what to look for   --language TAG   what to render in
#   --person XREF     diff this record specifically, when one disagrees
#   --sample N        walk N records and diff every one — the check that
#                     finds what a single hand-picked record cannot
# Diffs name, sex, death, every relative count, the primary facts, the GEDCOM
# tags, the family events and a date in both calendars. Family events are
# there because they were once the only thing that differed (§7, bug 40).
# Then the capabilities the ledger in §5 had never compared: the notes, the
# citations, the media items and which of them hang off a fact; each family's
# membership by xref; the ancestors and descendants charts by size, depth and
# *shape*; the relationship by its wording and its steps; the timeline by
# which events and in what order; and the statistics by the figures both
# state — with coverage reported beside them, because a transport can be
# right and still say less (§9 #23).
# Then `=== Sync ===`, which fills a real local store from the tree using the
# app's **own** sync engine — not a loop written in the tool, because a check
# that reimplements the thing it checks drifts away from it. It is the only
# check that pages far enough to have found bug 53; it diffs every record the
# store kept against the single-record endpoint, which is the third column
# `sync_eval.md` §10 asks for; and it holds the fingerprint to the whole walk
# and asks the server to refuse three it cannot follow.

flutter test          # 620 tests, plus 14 goldens
flutter analyze       # must stay clean
dart format lib test tool   # CI fails if this changes anything

# The store's schema is generated. CI regenerates it and fails on a diff: the
# app compiles perfectly well against a stale one, so nothing else would say.
dart run build_runner build

# Pictures of the parts a person judges rather than asserts on: avatars with
# and without the mourning ribbon, a person in a list, a parted couple, the
# message panels — each in both directions and both themes. Tagged, so the
# other 534 can run without them and a red golden is never confused for a
# wrong value.
flutter test --tags golden
flutter test --exclude-tags golden
# A failure means LOOK at the picture. Only then:
flutter test --tags golden --update-goldens

# The server module. Static first — structure, unused imports, and every
# webtrees class it names checked against BOTH 2.2.6 and 2.3, failing if
# anything outside src/Compat/ exists in only one:
python3 tool/check_module.py [../webtrees]
find server -name '*.php' -print0 | xargs -0 -n1 php -l

# Then actually run it. Two throwaway installs on SQLite, the module symlinked
# into each, and a synthetic Arabic tree in which every person is invented —
# notes, a citation, and two media files drawn by the installer: a JPEG
# photograph, and a PNG scan that webtrees 2.3 refuses to thumbnail at all
# (§7, bug 44). Both are why the media path has ever run. Privacy is **on**
# there, with one `RESN confidential` person, which it silently was not until
# bug 51; and the tree holds a family with no marriage and no second spouse,
# which is the shape bug 50 came from.
# Requires: php8.4-cli php8.4-{sqlite3,mbstring,intl,gd,xml,curl,zip} composer
tool/lab/setup.sh 2.2.6 8622
tool/lab/setup.sh main  8623
# A third argument appends that many more invented people, which is how the
# sync figures in §6 were measured rather than extrapolated. Deliberately not
# the default: a check that walks a whole tree should walk the small
# deliberate one, where every shape is there on purpose.
tool/lab/setup.sh 2.2.6 8622 1450
php -S localhost:8622 -t ../lab/webtrees-2.2.6 ../lab/webtrees-2.2.6/index.php &

# live_check reads the same person through BOTH transports and diffs them
# field by field — which is the only check that has ever caught a difference
# between them. Note the explicit scheme: a bare host defaults to https.
WEBTREES_PASSWORD=lab-member-password \
  dart run tool/live_check.dart --url http://localhost:8622 --user mobile
flutter run -d linux  # web is not viable — no CORS

# Render real screens to build/preview/*.png, in both languages and themes.
# Walks connect → sign-in → tree → person (twice: the top, and scrolled down
# to family, photos, notes and sources) → account → settings, and into the
# ancestors, descendants, fan and hourglass charts, the chart options sheet,
# a relationship (both ways it can be drawn), the search filter sheet — twice,
# because a site running the module offers two controls a page cannot —
# a timeline and the site's statistics. One shot is rendered
# on a wide surface — a chart that will not fit a phone legibly opens showing
# a corner of itself, and reviewing the layout needs the whole family.
# Not collected by `flutter test`: it writes files and asserts nothing.
flutter test tool/preview/render_preview.dart --update-goldens

# Sideloadable builds, one per ABI (~25MB each, against 54MB fat)
flutter build apk --release --split-per-abi
```

CI runs `.github/workflows/app.yml` (analyze · test · goldens) and
`module.yml` (`php -l` on 8.3 and 8.4, plus `check_module.py` against both
webtrees versions). The goldens job is pinned to one Flutter version and one
runner on purpose: a golden compares rendered pixels, and text rendering is
not identical across engines or platforms.

Running the GUI on Linux needs a toolchain this machine does not yet have:

```bash
sudo apt install cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev
```

`libsecret-1-dev` is what gives `flutter_secure_storage` a real keystore on
Linux; without it the app runs but reports that it cannot remember passwords.

Both tools read the password from the terminal with echo disabled, or from
`WEBTREES_PASSWORD`. Neither writes it anywhere.

---

## 9. Open questions and risks

1. **Notes, sources and photographs have been read, but only from a lab.**
   *(Narrowed 2026-08-23.)* Both labs run all three optional tabs and now hold
   two media files — a JPEG photograph and a PNG scan — so `parseNotes`,
   `parseSources`, `parseMedia`, `AuthenticatedImage`, `MediaCache` and the
   `canShow()`-before-signature rule have all run against a real webtrees for
   the first time, on both versions, and agree with the module field for
   field. What is still true is that no *real* server has ever published one:
   `tree.almou.sa` runs none of the three tab modules, and although its own
   statistics report **86 media objects, 83 of them photographs**, this
   account can see none of them. So the parsers stand on a synthetic tree and
   the upstream templates, and a site that keeps its media differently — an
   external URL, a folder per person, a watermark — has never been met.

2. **A divorce has never been seen from a real server.** Sex, death and the
   tag dictionary were all confirmed against `tree.almou.sa` on 2026-08-23
   (§3), but that tree records no divorce on any record the live check
   reached, so the per-family divorce mark and the parted couple line rest on
   fixtures alone. Both degrade to silence where the page says nothing, which
   is the same behaviour as a marriage that held — so a site that *does*
   record one would be the first proof either way.
3. **A photograph can only be shown at thumbnail size.** The media tab signs
   its URLs at 100 pixels, and the signature covers those dimensions, so the
   app cannot ask for a bigger copy — the full image lives behind the media
   *record* page, which v1 has no screen for. The gallery therefore shows
   thumbnails that do not open. Worth revisiting with a media record screen.
   **This is a limit of the media tab, not of webtrees**:
   `MediaFile::imageUrl($w, $h, $fit)` mints a signed URL at any size and
   `downloadUrl()` addresses the original, so a module closes this outright
   (§3).
4. **A chart is only as small as the tree it draws.** The app places one
   widget per person, which a chart of a few dozen handles without noticing.
   A large family at three generations of descendants is already ninety-odd
   boxes on this instance, and a site whose administrator allows nine
   generations could ask for thousands. Nothing bounds that yet: no limit on
   what is fetched, no culling of what is off screen. Worth measuring on a
   real device before it is worth solving.
5. **A relationship is read out of a layout, not a structure.** The path is
   recovered by walking a grid of table cells: robust against the lines and
   images webtrees draws between them, but not against a theme that changed
   the grid itself. The parser answers an empty path rather than a wrong one
   when the walk finds nothing, and the screen says the site found no link —
   which would be indistinguishable from a theme it could not read.
   A module removes the grid but not the whole problem:
   `RelationshipService::nameFromPath()` is public, so the wording stays the
   site's, but `RelationshipsChartModule::calculateRelationships()` is
   `private` — so ~150 lines of Dijkstra would have to be reimplemented, and
   that reimplementation could drift from what the website answers (§3).
6. **The charts have been read on 2.2.6 only — except the relationship
   chart.** Both parsers run against fixtures for 2.2.6 and 2.3, and the two
   versions' chart templates differ by one attribute — but 2.3 has never
   answered a real request here for the ancestors or descendants charts, so
   that much is an argument from source, not evidence.
   *(Narrowed 2026-08-24.)* The **relationship** chart has now been read live
   on both, and the two do not merely differ by an attribute: 2.2.6 turns a
   corner with a diagonal cell only where the previous step ran the other way
   (`if ($n > 2 && preg_match('/fat|mot|par/', $relationships[$n - 2]))`) and
   2.3 dropped that test, so the same four people are three columns wide on
   one and five on the other. Both are now fixtures captured from a running
   server (`relationship_cousin.html`), and the parser reads the sign of the
   row change rather than a column position, which is what makes them agree.
   Assume the other charts hold a difference of the same size.
7. **HTML parsing is theme- and version-coupled.** Mitigated so far by parsing
   tab fragments rather than whole pages, a two-version fixture matrix, and
   `ParseFailure` naming the parser, selector and version — which a reader can
   now *see*, along with the version and address style the app settled on, on
   the diagnostics screen Phase 5 added. Eight failure-state tests check that
   each screen says so rather than going blank. **Still open:** the
   fixtures are transcribed from upstream templates, not captured from a live
   site, so no non-default theme, language or module configuration has ever
   been parsed. Narrowed a little in Phase 3b — real pages from
   `tree.almou.sa` were captured and run through the facts and relatives
   parsers, which read them correctly, including a chart box carrying a whole
   facts dropdown no fixture has. Sanitized real captures in `test/fixtures/`
   are still the right next step.
   **And sometimes the markup simply does not say.** A family with no marriage
   recorded has no divider between its couple and its children, and a father
   and a son render identically (§7, bug 50). The caption resolves every shape
   met so far (§3) and one it cannot: a *birth* family — whose caption names
   nobody — with one parent recorded or visible and no marriage. There the
   leading pair is still a guess, and it would be wrong by one. The module
   answers correctly, so this is a limitation of the floor rather than a
   defect the app can fix, and it is written down because the next real tree
   is where it will turn up.
8. **Cookie `Domain` mismatch** when a site is reached via a hostname other than
   its configured `base_url` (LAN IP, Tailscale). The app adopts the canonical
   base from the 308 and warns when it differs from what was typed.
9. **Tree list unavailable** when `ALLOW_CHANGE_GEDCOM != 1`. Falls back to the
   default tree; consider letting the user enter a tree name manually.
10. **`local_auth` has no Linux support** — the biometric gate must degrade
   gracefully on the development machine.
11. **Upstream module API churn.** webtrees does not guarantee stability for
   custom modules; 2.3 changed routing substantially. If the optional PHP module
   is built, isolate volatile core APIs behind one adapter and run CI against
   both 2.2.x and 2.3. **The size of that adapter is now measured** — eleven
   methods, tabulated in §3 — and PSR-15 handlers are portable across both
   versions unchanged, which is what makes a single adapter class realistic.
   `webtrees-API` is the counter-example: it took the churn head-on and is
   dead on 2.3 (§2).
   *(Mitigation now built rather than planned.)* `src/Compat/` is the only
   place a version may be named, and `tool/check_module.py` fails the build if
   anything outside it imports a class that exists in only one version.
   `.github/workflows/module.yml` runs that plus `php -l` on 8.3 and 8.4. What
   neither can catch is a *method* that changed behaviour without changing its
   signature — for that there is no substitute for a lab install.
12. **Only the app is version-controlled.** The repository is `webtrees_mobile/`
   (this document included). The parent workspace, `CLAUDE.md` and the two
   upstream clones have no shared history.
13. **Nothing has run on a real device.** This is now the largest gap by some
   way: three of the six things Phase 4a changed — resuming through the
   biometric gate at launch, the Android back gesture, and the keystore that
   makes resuming possible at all — are *device* behaviours that a widget test
   can only approximate. The screens can be *seen* —
   `tool/preview/render_preview.dart` renders them with the real fonts — but
   secure storage, biometrics, backgrounding, session renewal and cleartext
   networking still cannot be validated without hardware. Sideloadable builds
   exist (`flutter build apk --release --split-per-abi`, ~20MB for arm64), so
   this is now waiting on a device rather than on the toolchain.
14. **"Works against any webtrees instance" is a goal, not a tested claim.**
   What is actually verified: 2.2.6 **live end to end** — connect, sign in,
   roles, search and its second page, opening a person, facts, relatives and
   family facts across 40 real records, the language switch and the calendar
   structure of real dates — and 2.3.0-dev by source; both URL styles; both
   tab-route shapes; one private tree; the default theme; one non-stock tab
   module (`_vytux_cousins_`), which discovery handled without changes; and
   the ancestors and descendants charts, read live from that instance.
   Untested: non-default themes, subdirectory installs, multiple trees, notes,
   sources, media, and 2.3 against a running server. The app now reports the
   sections an instance offers (`sections offered` in `tool/live_check.dart`),
   which is the raw material for the compatibility matrix this still needs
   before release.
15. **Choosing a calendar works on 2.2.6 and not on 2.3, and one half of that
   is an upstream bug.** The choice depends on the `cal` parameter of the
   calendar links webtrees wraps each date in; 2.3's rewritten `Date::display`
   emits no links, so nothing states which calendar a rendered date is in and
   the app shows both.
   **Confirmed from source 2026-08-23** while writing `api_eval.md`: 2.3 puts
   the whole conversion block *inside* `if ($this->date2 !== null)`
   (`app/Date.php:160-176`), so an ordinary single date loses its conversion
   entirely — not merely for this app, but on the website. That is a defect
   rather than a design change, and it is worth reproducing on a running 2.3
   install and **reporting upstream**. The bracketing (`[…]` rather than
   `(…)`) is deliberate and needs no report.
   **Closed by the module, demonstrated on both labs.** It reads
   `convertToCalendar()` directly and states each calendar with its GEDCOM
   escape, so `CalendarView` works on 2.3 where the markup names nothing: on
   the 2.3 lab the stock path answers `dates naming their calendar: 0 of 1`
   and the module answers `٢١ ذو القعدة ١٣١٨` for the same fact. Open, and
   permanently so, on the stock path — 2.3's markup simply does not say.
16. **The app writes the account's language preference.** *(Closed by a module;
   open on stock.)* Aligning the server's
   rendering language is the only way to get Arabic dates on a stock site
   (§3), and `SelectLanguage` sets the session *and* the user preference
   together. So using the app in English changes what the website greets that
   account with. Disclosed in the settings sheet; nothing stock can avoid it.
   **The module does, and it is demonstrated on both labs.** Module route
   middleware runs inside `Router`, i.e. after `UseLanguage`, so it calls
   `I18N::init($tag)` from `?lang=` or `Accept-Language` for one request and
   touches neither the session nor the stored preference: asking in `en-GB`
   answers `Birth | 21 Dhū al-Qiʿdah 1318`, the next request is Arabic again,
   and the account's `language` row still reads `ar`.
   `I18N::init()` **alone was not enough**, which only running it showed: the
   global stack registers every GEDCOM tag's label between `UseLanguage` and
   `Router`, and `Gedcom::registerTags()` evaluates them eagerly — so the first
   attempt answered English dates beside Arabic labels (§7, bug 32). The tags
   have to be registered again after the language changes.
17. **The Android compile-SDK override** rewrites every plugin subproject
   through a deprecated Gradle API (§3). It works against the SDK installed
   here and should be treated as a temporary, version-specific workaround —
   it needs CI on a clean machine to stay honest.
18. **The module runs against the real tree.** *(Was "written and has never
   answered a request", then "synthetic data only"; narrowed three times,
   still open.)* It is installed on a
   2.2.6 and a 2.3 lab (§8), every endpoint answers on both, and
   `tool/live_check.dart` reads the same person through both transports and
   finds them identical — name, sex, deceased, lifespan, every relative count,
   primary facts, tags named, and the same date in both calendars. Executing it
   cost six bugs in an afternoon (§7, 30–35) after a document argued from
   source, 508 green tests and a live 2.2.6 run had all passed it.
   **It is now installed on `tree.almou.sa`** and has answered against
   the real 1,463-person tree. Two disagreements, both on one record, both
   fixed (§7, 36–37); nothing else differed. That is the strongest evidence
   the project has, and it is still not proof: one account, one tree, one
   afternoon, and a reader whose role is Member. What has *not* been exercised
   is a manager's view, a tree with pending edits, notes/sources/media tabs
   (this site runs none of the three), or a photograph — this account can see
   none, though the tree reports 86.
   **Every capability has now been diffed against it** (§5), one record at a
   time and then sixty at a time, which found four more disagreements: a
   married name that is a subtag rather than a name (§7, bug 48), a burial the
   module did not count as a death (49), and two families whose couple the
   HTML could not state (50). Three were the module's and one the parser's,
   and all are fixed here. Two differences remained on the instance and were
   not faults: it ran module **1.0.1**, so its relationship wording and its
   timeline dates were the ones that session fixed.
   **Closed 2026-08-24: the instance now runs 1.3.0**, and a full run against
   it passes — 40 records diffed field by field with no differences, the
   relationship direction and the timeline conversion now agreeing with the
   page, and the sync endpoint handing over all 1,463 records into a real
   store. What that does *not* close is the rest of this entry: still one
   account, one tree, a reader whose role is Member, and no manager's view, no
   pending edits, no notes/sources/media tabs (this site runs none of the
   three) and no photograph this account may see.
   Two things remain true regardless: running two transports doubles the
   meaningful test surface for as long as both exist, which is forever; and no
   capability is cleared until its endpoint has passed live against real data
   (see the ledger in §5).
19. **`RelationshipFinder` is the module's only duplicated core logic.**
   `RelationshipsChartModule::calculateRelationships()` and its two helpers are
   `private`, so ~150 lines of Dijkstra over the `link` table are ported rather
   than called. They are byte-identical in 2.2.6 and 2.3 today, and the port is
   deliberately literal — but nothing makes upstream keep them that way, and a
   divergence would be silent on both sides. Mitigate by testing module output
   against the rendered chart for a set of known pairs, which needs a lab
   install (see 18).
20. **The stock path is losing ground on 2.3, and only a lab shows it.** Three
   version-specific breaks turned up the first time the app met a real 2.3:
   the statistics charts (bug 30), the private-tree status (33) and the site
   version (34). All three are fixed, and none was visible to 508 tests or to
   the 2.2.6 instance the project was built against. Assume there are more, and
   that the only thing that finds them is running against both.
   **A fourth is not the app's at all** (bug 44): 2.3 answers `500` for the
   thumbnail of any non-JPEG, because `autoRotateImage()` reads EXIF from
   everything and webtrees turns PHP's warning into an exception. Nothing here
   can fix that — the app already draws the placeholder — but it means a 2.3
   site with PNG or GIF media shows a gallery of placeholders, and it is worth
   reporting upstream.
21. **The module's surname index and enumeration have now met a large tree —
   a synthetic one.** *(Narrowed 2026-08-24.)*
   `searchIndividualNames()` walks a PHP cursor rather than a SQL `LIMIT`, so
   a deep offset is `O(offset)`; `searchIndividualsAdvanced()` fetches a whole
   surname partition (webtrees caps it at 5,000) and pages it in PHP. Both are
   bounded and both are what the website itself does.
   Measured on a 1,469-person lab (§6, Phase 10a): a page of fifty costs
   0.05 s at the top and 0.13 s at offset 1,400, and the whole browse walks in
   1.2 s. **Fixing bug 53 made the search walk `O(offset)` in memory as well**
   — the page is taken after a walk from the top, so the prefix is held — which
   is why `Individuals::MAX_OFFSET` refuses past row 5,000 and names the
   surname index instead. At offset 1,400 the request still runs inside a
   16 MB `memory_limit`, so the ceiling is a guard rather than a limit anybody
   meets. Still untested: a tree ten times that, and the surname index on one.
22. **Nothing the project owns can see the screen.** *(Half closed by Phase
   5.)* Four faults (§7, 40–43)
   were found by a person using the app, after 509 tests, a static checker
   across both webtrees versions, two lab installs, a field-by-field diff of
   both transports and a 60-record sample walk of the real tree had all
   passed. Two were module bugs the fixtures could not hold, because the
   fixtures were written from the design rather than captured from a server;
   two were interface bugs where a comment described the intent and no
   assertion checked it.
   **Phase 5 answered the tooling half**: fourteen component goldens freeze
   the parts a person judges — the mourning ribbon among them — eight tests
   check that every screen says so when what it needs does not arrive, and CI
   runs all of it. **What that does not do is make anybody look at something
   new.** A golden catches a change, not a mistake: taken a day earlier it
   would have frozen bug 41's smudge as correct. So the other half stands, and
   the only things that close it are a device (see 13) and the habit of
   opening the app after changing it.
23. **A transport can be *right* and still say less.** The module's statistics
   endpoint agrees with the page on every figure it states and sends a quarter
   of the sections; the app had been preferring it, and nothing noticed until
   the two were asked the same question (§7, bug 47). Correctness diffs cannot
   see this — both answers are true — so the rule is now explicit
   (`Capability.readFromThePage`) and `live_check` reports coverage beside
   every capability it compares. Assume the same shape exists elsewhere: a
   payload that is accurate, narrower than the page, and preferred anyway.
   The timeline was the other half of it and was fixed rather than demoted
   (bug 46).
24. **A filter narrows the rows in hand, not the tree.** The three filters on
   the search screen run over the results already fetched, because everything
   they run on is already in those rows — which is what makes them free. The
   consequence is that "no matches" can mean "none in the first fifty", and
   the screen says exactly that. **Phase 10c closes it, conditionally, and the
   condition is the honest part.** Two halves. The store answers a search with
   up to 2,000 matches in one page rather than 50 — affordable because
   `LocalRecordsTransport._refFrom` builds each row from the **columns** the
   sync already derived, so a thousand rows is one indexed `SELECT` and no
   JSON at all — which puts every match in the filter's hands. And the screen
   now keys its wording on `!hasMore` rather than on the transport: with no
   further page it says *"Nobody in this tree matches"* and *"Showing 3 of
   40"*, and with one outstanding it keeps the old *"None of the results
   loaded so far"* and *"of 40 loaded"*. So the apology did not go away, it
   became conditional — true on a store, true after paging any transport to
   its end, and still shown to every reader whose copy is filling or whose
   site has no module. That is a better outcome than the risk asked for,
   because the fix turned out not to need a store at all; the store is what
   makes the good case the ordinary one. Neither transport is asked to filter:
   `searchIndividualsAdvanced()` could do sex and a place *id* server-side,
   and neither maps onto what a phone can offer without a place index the
   stock floor does not publish. Worth revisiting only if a real tree makes
   paging-then-filtering feel wrong; on 1,463 people it does not.
   **And a stock instance offers no sex filter at all**, because its search
   rows state no sex. The sheet is built from the rows rather than from the
   transport, so this appears as a control that is simply absent rather than
   as one that does nothing — but it does mean two instances of the same app
   offer different filters, and only the diagnostics screen explains why.
25. **An age is the site's arithmetic, and it carries two surprises.**
   `Age::ageYears()` works on Julian days, which is what makes it right where
   subtracting two printed years is wrong — but
   `AbstractCalendarDate::ageDifference()` performs "all calculations using
   the calendar of the first date", so a Hijri birth is counted in *Hijri*
   years and reads about 3% high to a Gregorian reader. And 2.3 answers the
   maximum plausible age where 2.2.6 answers a single computed one, so the two
   versions can differ by a year on a date recorded as a range. Both are
   webtrees' own answers and both are what the website prints, which is the
   rule this project follows — but a reader comparing the app to a calculator
   will find neither.
   Neither has been seen on `tree.almou.sa`; both were confirmed on the labs,
   where one person has a Hijri birth and a Gregorian death.
26. **The module fixtures are still written from the design.**
   `test/fixtures/module/` was transcribed from `api_eval.md` §7 rather than
   captured from a server, which is why bug 40 survived everything — and the
   labs can now produce the real thing for a family whose every member is
   invented, so there is nothing left to sanitize. Capturing them is the
   cheapest remaining way to move a live-only check into the offline suite.

27. **The sync fingerprint has one blind spot, and it is a re-import.**
   `MAX(change_id)` plus the tree's individual and family counts notices every
   edit (each writes a change row) and every import that changes how many
   records there are. What it cannot see is a re-import of a *modified* GEDCOM
   with the **same** number of individuals and families and no edits since:
   the import deletes the change log rather than adding to it, so both halves
   of the fingerprint are unchanged and a delta is honestly empty. The cheap
   alternatives are worse — a content digest is a full scan of every record on
   every sync, and the counts that would catch more (`name`, `link`) are not
   indexed by tree. So the answer is a client that offers "sync again from
   scratch", and this note, which exists because a client cannot work it out.
   Nothing else about the token is guesswork: a backwards watermark, a token
   this module never minted, and a delta larger than `MAX_DELTA` all answer
   `resync` and were exercised at the boundary on both labs.

28. **A delta is only as complete as its two hops.** A changed record expands
   to what it links to and to everybody in every family it belongs to, which
   covers every shape the data takes on a person's page. A third hop — a
   citation on a note on a family — is not followed. The record is picked up
   the next time the person themselves is touched, which on a tree edited
   normally is soon, and never if that family is never edited again. A full
   walk is the only thing that closes it, and it is what `resync` exists for.
   Worth stating plainly because the alternative reading — "a delta is
   complete" — is what a client would assume.

29. **The store is encrypted, and Phase 10c is no longer gated.** *(Was "the
   store is not encrypted, and that gates Phase 10c".)* `sqlite3` 3.5.2 ships
   pre-compiled SQLite3MultipleCiphers binaries beside the plain ones, so the
   route `sync_eval.md` §6 named — build hooks — turned out to be four lines
   of `pubspec.yaml` rather than a native toolchain step: no per-ABI build, no
   OpenSSL, nothing new in CI. The key is 256 bits from `Random.secure`, one
   per *connection* (site and account), kept in the same keystore as the
   password and written `deviceOnly` so it cannot ride a backup to another
   phone. `test/data/store_encryption_test.dart` asserts against a real file
   that a name is not on the disk in the clear, that the header is not
   `SQLite format 3`, and that an unkeyed, wrongly-keyed or other-account
   open is refused. Both halves §6 asked for are also done: `TreeStore.destroy`
   runs on sign-out and takes the file *and* the key, and a changed role
   re-stamps on the next bind.
   **What is still open, and is now the honest residue:** iOS. The store lives
   in the documents directory, which iCloud backs up; the *key* no longer
   travels, so a restored copy is unreadable ciphertext rather than a leak,
   but the ciphertext still leaves the device. `NSURLIsExcludedFromBackupKey`
   needs a platform channel and nobody ships iOS from this repo yet (§10 builds
   APKs only). Android is closed: `allowBackup="false"`,
   `fullBackupContent="false"` and a `data_extraction_rules.xml` that excludes
   every domain from both cloud backup and device transfer.

30. **Two sources of truth became three, and the answer is in place — but it
   is the risk to keep watching.** *(Narrowed once.)* `sync_eval.md` §11 #1
   names it: every screen answered from a store owes the reader a "synced at",
   and the diagnostics screen has to learn a third answer. Both are now built.
   `Capability.sourceOf` is the single place that decides, so the screen and
   the transports cannot disagree; the report says `individual=store` and a
   `store: 1463 people, synced <iso>` line; and `SyncFreshness` states it in
   words under the results it produced. `live_check` diffs all three.
   Still worth watching, because none of that is *proof*: the honest test is
   whether the next real bug report is diagnosable, and no real bug has been
   filed against a store yet.

Related: the full plan lives at `~/.claude/plans/warm-drifting-umbrella.md`.

---

## 10. Finishing a milestone

**Standing instruction, agreed 2026-08-22. Do this every time a milestone is
finished, without being asked.** A milestone is a piece of work worth naming —
a phase, or a batch of fixes that changes what the app does. Not every edit.

1. **Bump the version**, in `pubspec.yaml` *and* `kAppVersion` in
   `core/webtrees_client.dart`. Both, always: they have drifted apart before,
   and the User-Agent is what a site administrator reads in their access log.
   `test/core/version_test.dart` fails if only one moves.
   - `0.1.0` — new behaviour, a phase, anything a user would notice.
   - `0.0.1` — fixes, refactors, documentation, tests.
   - Raise the build number (`+N`) too, or Android will refuse the upgrade.
2. **Update this document.** The status table in §5, an entry in the progress
   log (§6) saying what changed and *why* — not a changelog — plus §3 for
   anything newly confirmed against a real server, §7 for a bug worth the
   lesson, and §9 for a risk that opened or closed.
3. **Verify.** `flutter analyze`, `flutter test`, and — after any change to the
   transport, the parsers or the module — `tool/live_check.dart --sample 14`
   against **both** labs (§8) and then against a real instance. One record is
   not a sample: bugs 38 and 39 were invisible to a single-record diff and
   obvious to the first walk of a whole tree.
   Bug #5 was invisible to unit tests, and bugs 14–16 were invisible to 185 of
   them.
4. **Build the APKs.** `flutter build apk --release --split-per-abi`. It is the
   only thing that exercises the release toolchain, and four separate Android
   packaging problems in §3 each failed silently or only on a device.
5. **Commit**, with a message that says what changed and why it mattered.

Release builds are still signed with Flutter's debug key (§3), so the version
number is for the log and the upgrade check, not yet for distribution.
