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
| `../webtrees/` | Upstream webtrees source, read-only reference (2.3.0-dev, `2.2.6` tag available); its own clone |
| `../webtrees-API/` | Third-party API module, **evaluated and rejected** — see §2; its own clone |
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

Classified **Category 4 — not suitable as the main mobile API**. It is competent
work for what it was built for (server-side automation and AI/MCP access), but
the mismatch is structural, not a matter of missing endpoints:

- Its only OAuth2 grant is **client credentials with confidential clients**. A
  shipped mobile binary cannot keep a secret.
- Every request runs as one shared **technical user**, collapsing per-user
  privacy, tree access and edit attribution into a single identity.
- Data arrives as raw GEDCOM, pushing calendar, name and label logic into Dart.
- No pagination anywhere; writes pass whole records through the query string.
- It does not boot on webtrees 2.3 (the routing API changed).
- `TestApi` mints a 1000-year, all-scope, non-revocable token from a route with
  no auth middleware. **Report upstream after reproducing in a lab install.**
  Not currently exposed on `tree.almou.sa` — the module is not installed there.

### Decisions taken with the user

| Question | Decision |
|---|---|
| Data strategy | **Hybrid.** Stock HTTP/HTML transport always works; probe for an optional module and switch to a JSON fast path when present |
| Staying signed in | Password in the OS keystore, biometric-gated, silent re-login on expiry |
| v1 scope | **Read-only browsing.** Editing, moderation and offline sync deferred to v2 |
| Finding people (v1) | **Search, not enumeration.** The only JSON endpoint requires a non-empty query (§3), and no stock route paginates a whole tree cheaply |
| Where the app opens | **The last site, signed in.** An address typed once should not be typed again, and a list of one saved site is not a choice. The launch screen resumes it and steps aside; the connect screen is what you see when there is nothing to resume |
| Where the tree list goes | **Skipped when there is one tree.** The account screen keeps its diagnostic job and stays one tap away, but it is not a destination when it holds a single card |
| Which calendar to show | **The reader's, per the markup.** A tree's `CALENDAR_FORMAT` is a manager-level preference no member can change, so the choice is made in the app, over dates the server has already rendered — never by converting anything |
| Module capability probe | **Deferred** until a module contract exists. Probing for something undefined has nothing to test against; and any future module must reuse the webtrees session or OAuth **authorization code with PKCE** — never client credentials in a shipped binary |

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
`404` on `/tree/{t}` while signed-in access works **proves membership**. Public
trees stay ambiguous, and the UI must say so rather than guess.

**Only these statuses carry meaning.** A probe answers a question about the
*account*; a `302` or a `5xx` answers a question about the *session* or the
*server*. Folding those into "the role is not held" states something false
about the user, so `core/response_status.dart` enumerates what each operation
accepts and turns anything else into a typed error. Only an anonymous `404`
proves a tree private — re-confirmed live 2026-08-22, along with `302` from an
anonymous `/my-account`.

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
  so it is not a pagination API.
- Thumbnails are HMAC-signed with a server-side `glide-key` and are
  **unforgeable**; signed URLs must be harvested from HTML or that endpoint.
- **A signed thumbnail URL is not an authorization token.**
  `MediaFileThumbnail` checks `$media->canShow()` for the current user *before*
  validating the signature, and picks watermarking per user. Images must
  therefore be fetched through the authenticated session, and any cache
  partitioned by site and account and cleared on sign-out.
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
  `<div class="fact_INDI:DEAT"><span class="label">…</span>: …</div>`, and
  `chart-box.phtml` prints a run of those into `.wt-chart-box-facts` (the
  person's birth and death) and into the hidden `.wt-chart-box-zoom-dropdown`
  beside it (*everything*, their spouse families' facts included).

  This is the only structural statement a stock site makes about what kind of
  event a row is. Every label on a record page — the facts table, the family
  blocks, a chart's captions — is already translated, and `INDI:SEX` is
  rendered as the *word* for the sex rather than as a class. So the app reads
  a page's chart boxes into a label → tag dictionary
  (`data/stock/fact_tags.dart`) and uses it to name every other fact on that
  same page. That is what makes "is this person dead", "did this marriage end
  in divorce" and "which icon does this row get" answerable in Arabic.

  **Read from the upstream templates, not yet from a captured page** — see §9.
- **A person's own sex, lifespan and death come from the relatives tab, not
  from their page.** They appear in their own family tables as a chart box
  like anybody else, and that box carries `wt-chart-box-{m,f,u}`, the
  lifespan, and the death fact. The individual page states the sex only as
  the translated word for it, and the silhouette class
  (`wt-individual-silhouette-m`) exists only for someone with no media on a
  tree with silhouettes on — kept as a fallback, relied on for nothing.

### Charts

webtrees draws twelve charts, and the app cannot show any of them as they
arrive: they are HTML for a wide screen, positioned with floats, background
images and a reading direction baked into the stylesheet. What the app takes
is the **shape** — who descends from whom — and draws it again.

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
- **The data is JSON; the options beside it are not.** webtrees writes some
  option objects by hand, with comments and unquoted keys, so a parser that
  decoded both would drop every chart whose options were hand-written — which
  is most of the pie charts (§7, bug 23).
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

**No CORS headers → Flutter Web cannot work.** Mobile and desktop only.
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
webtrees_mobile/lib/
  core/      webtrees_url · webtrees_client · errors · response_status
             secret_store · unlock_gate
  l10n/      app_en.arb · app_ar.arb  (generated AppText)
  data/      instance_probe · session · access_probe
             credential_store · session_manager · settings_store
    stock/   dom · chart_box · record_parser · records_repository
             chart_parser · charts_repository · media_cache
    module/  ModuleTransport  (JSON)                           ← v2
  domain/    instance · access · records · charts · dates · notice
  features/  launch · connect · auth · access · browse · charts · shared
```

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
| **2b** | Capability probe for the optional module | ⏸ deferred — see §2 |
| **2c** | "Your access" screen | ✅ |
| **2d** | Stabilization — status interpretation, resume, credential semantics | ✅ |
| **3a** | Vertical slice — search → person → facts → relatives → photo | ✅ |
| **3b** | Rest of the read model (families, sources, notes, media tab, paging) | ✅ |
| **4** | Interface (Material 3 Expressive theme, Arabic/RTL, navigation) | ✅ |
| **4a** | Getting out of the way — resume, one-tree, back stack, calendar choice | ✅ |
| **5** | Hardening (golden tests, CI, diagnostics) | ⬜ |
| **6a** | Charts: discovery, ancestors and descendants, drawn natively | ✅ |
| **6b** | Charts: fan/circle, compact, hourglass — the same data, redrawn | ✅ |
| **6c** | Relationships — how any two people in a tree are connected | ✅ |
| **6d** | Statistics — the counts, and the datasets behind its charts | ✅ |
| **6e** | Timeline — a life against a scale of years | ✅ |
| **6f** | Lifespans — several lives compared against one scale | ⬜ |
| **7a** | Identity — who a person is, seen before it is read | ✅ |
| **7b** | Charts — grouping, marital status, controls, export | 🚧 |
| **7c** | Relationships — the path drawn, and the ways through it | ⬜ |
| **v2** | Offline sync · editing · moderation · PHP module | ⬜ |

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
| Relationships | the server's own path between two people, walked out of its grid | ✅ 6c |
| Timeline | event boxes and year labels, each stating its own position | ✅ 6e |
| Lifespan | bars positioned against a scale of decades, the same way | 6f |
| Statistics | plain counts in the markup, **and** chart data as JSON inside `statistics.draw*Chart(…)` calls | ✅ 6d |
| Pedigree map | a map. Out of scope for v1 — no map dependency is worth the weight yet | — |

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

flutter test          # 419 tests
flutter analyze       # must stay clean
flutter run -d linux  # web is not viable — no CORS

# Render real screens to build/preview/*.png, in both languages and themes.
# Walks connect → sign-in → tree → person (twice: the top, and scrolled down
# to family, photos, notes and sources) → account → settings, and into the
# ancestors, descendants, fan and hourglass charts, a relationship, and the
# site's statistics, a relationship and a timeline.
# Not collected by `flutter test`: it writes files and asserts nothing.
flutter test tool/preview/render_preview.dart --update-goldens

# Sideloadable builds, one per ABI (~25MB each, against 54MB fat)
flutter build apk --release --split-per-abi
```

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

1. **Notes, sources and photographs have never been seen from a real site.**
   `tree.almou.sa` runs none of those three tab modules — it offers
   `personal_facts`, `relatives`, `tree`, `places` and `_vytux_cousins_` — and
   although its own statistics report **86 media objects, 83 of them
   photographs**, not one is visible to this account: no highlighted thumbnail
   appears on any of 50 people searched, and `/tree/main/media-list` renders
   none either. So
   `parseNotes`, `parseSources`, `parseMedia`, `AuthenticatedImage`,
   `MediaCache` and the `canShow()`-before-signature rule that motivated them
   stand on fixtures transcribed from the upstream templates and nothing else.
   Needs an instance that runs those modules and holds media. This is a gap in
   the *data* available, not in the code — but it is the largest untested
   surface the app now has.
2. **The chart-box fact blocks have not been seen from a real server either.**
   `FactTagIndex` (§3) — and with it the death ribbon, the fact icons and the
   per-family divorce mark — reads `.wt-chart-box-facts` and
   `.wt-chart-box-zoom-dropdown`, both transcribed from `chart-box.phtml`
   rather than captured. `tool/live_check.dart` against `tree.almou.sa` is
   what would settle it, and needs a password.

   Every reader of the index degrades on its own: an empty index means "this
   page said nothing", so a site that renders no fact blocks loses the icons
   and the divorce mark, and death falls back to whether the rendered lifespan
   has a year after its dash. Nothing fails, and nothing is claimed that was
   not read — but the difference between the two paths is currently unmeasured.
3. **A photograph can only be shown at thumbnail size.** The media tab signs
   its URLs at 100 pixels, and the signature covers those dimensions, so the
   app cannot ask for a bigger copy — the full image lives behind the media
   *record* page, which v1 has no screen for. The gallery therefore shows
   thumbnails that do not open. Worth revisiting with a media record screen.
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
6. **The charts have been read on 2.2.6 only.** Both parsers run against
   fixtures for 2.2.6 and 2.3, and the two versions' chart templates differ by
   one attribute — but 2.3 has never answered a real request here, so that is
   an argument from source, not evidence.
7. **HTML parsing is theme- and version-coupled.** Mitigated so far by parsing
   tab fragments rather than whole pages, a two-version fixture matrix, and
   `ParseFailure` naming the parser, selector and version. **Still open:** the
   fixtures are transcribed from upstream templates, not captured from a live
   site, so no non-default theme, language or module configuration has ever
   been parsed. Narrowed a little in Phase 3b — real pages from
   `tree.almou.sa` were captured and run through the facts and relatives
   parsers, which read them correctly, including a chart box carrying a whole
   facts dropdown no fixture has. Sanitized real captures in `test/fixtures/`
   are still the right next step.
8. **Cookie `Domain` mismatch** when a site is reached via a hostname other than
   its configured `base_url` (LAN IP, Tailscale). The app adopts the canonical
   base from the 308 and warns when it differs from what was typed.
9. **Tree list unavailable** when `ALLOW_CHANGE_GEDCOM != 1`. Falls back to the
   default tree; consider letting the user enter a tree name manually.
10. **`local_auth` has no Linux support** — the biometric gate must degrade
   gracefully on the development machine.
11. **Upstream module API churn.** webtrees does not guarantee stability for
   custom modules; 2.3 changed routing substantially. If the optional PHP module
   is built (v2), isolate volatile core APIs behind one adapter and run CI
   against both 2.2.x and 2.3.
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
15. **Choosing a calendar works on 2.2.6 and not on 2.3.** The choice depends
   on the `cal` parameter of the calendar links webtrees wraps each date in;
   2.3's rewritten `Date::display` emits no links, so nothing states which
   calendar a rendered date is in and the app shows both. Two further 2.3
   observations, unverified against a running server: the conversion is
   appended only when the date has a *second* part (`$this->date2 !== null`),
   which would drop it from ordinary single dates; and it is bracketed rather
   than parenthesised. Worth reproducing on a 2.3 install and reporting
   upstream before building around it.
16. **The app writes the account's language preference.** Aligning the server's
   rendering language is the only way to get Arabic dates on a stock site
   (§3), and `SelectLanguage` sets the session *and* the user preference
   together. So using the app in English changes what the website greets that
   account with. Disclosed in the settings sheet; an optional module could
   avoid it, nothing stock can.
17. **The Android compile-SDK override** rewrites every plugin subproject
   through a deprecated Gradle API (§3). It works against the SDK installed
   here and should be treated as a temporary, version-specific workaround —
   it needs CI on a clean machine to stay honest.

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
   transport or the parsers — `tool/live_check.dart` against a real instance.
   Bug #5 was invisible to unit tests, and bugs 14–16 were invisible to 185 of
   them.
4. **Build the APKs.** `flutter build apk --release --split-per-abi`. It is the
   only thing that exercises the release toolchain, and four separate Android
   packaging problems in §3 each failed silently or only on a device.
5. **Commit**, with a message that says what changed and why it mattered.

Release builds are still signed with Flutter's debug key (§3), so the version
number is for the log and the upgrade check, not yet for distribution.
