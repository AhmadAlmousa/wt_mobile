# webtrees Mobile Client

A cross-platform Flutter client for [webtrees](https://webtrees.net) genealogy
sites. A real mobile application, not a wrapper around the web interface.

**Living document.** Update the status table and the progress log as work
happens, and add to *Verified constraints* whenever something new is confirmed
against a real server.

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
- Record detail comes from AJAX tab fragments (~10× less markup than a full
  page). **Do not build these URLs.** The individual page renders every tab it
  offers as `<a data-wt-href="…" href="#{module}">`, so the server states the
  exact URL, and which tabs this tree actually has. That matters twice over:
  core tabs can be disabled or access-restricted per tree, and a site can carry
  custom tab modules (`tree.almou.sa` serves `_vytux_cousins_`). Both versions
  route a tab as `/module/{m}/Tab/{tree}?xref={x}`; 2.2.6 additionally declares
  `module-no-tree` (`/module/{m}/{action}`), so the tree may appear in the
  query instead. **The `xref` query parameter is part of the URL** — dropping
  it yields a 200 carrying `The parameter “xref” is missing.`
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
- **Dates stay text.** webtrees has already formatted them in the tree's
  language and calendar, and appends conversions in brackets — `12 مارس 1901
  [٢١ ذو القعدة ١٣١٨ هـ]`. Parsing to `DateTime` would drop the second
  calendar and the `about`/`between` qualifiers.
- Relatives carry **no machine-readable role**. The family view emits its
  `FAMC`/`FAMS` type only inside editor-only link text, and the `<th>`
  relationship names are translated. Role is therefore derived structurally:
  spouses render before any marriage-fact row, children after, and the family
  is a birth family or the person's own according to which block holds them.
- **No machine-readable tree list.** Sources, in order: the post-sign-in
  redirect (default tree), the header menu `a[class*=menu-tree-]`, the search
  page `input[name="search_trees[]"]`. The latter two need
  `ALLOW_CHANGE_GEDCOM=1` and more than one tree.
- The user's own XREF is **not** on the account page (disabled control, empty
  value). Read `a.menu-myrecord[href]` from any page of that tree.

### Languages

The interface is English and Arabic, and both are first class — the tree this
was built against is Arabic, so RTL is the case the layout was designed for
rather than a late adaptation.

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
    stock/   dom · record_parser · records_repository · media_cache
    module/  ModuleTransport  (JSON)                           ← v2
  domain/    instance · access · records · notice
  features/  connect · auth · access · browse · shared
```

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
| **3b** | Rest of the read model (families, sources, notes, media tab, paging) | ⬜ |
| **4** | Interface (Material 3 Expressive theme, Arabic/RTL, navigation) | ✅ |
| **5** | Hardening (golden tests, CI, diagnostics) | ⬜ |
| **v2** | Offline sync · editing · moderation · charts · PHP module | ⬜ |

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

Bugs 3–4 and 6 were found by unit tests; **5 was invisible to them** — keep
`tool/live_check.dart` current and run it after transport changes. Bugs 14–16
make the same point a second time and more sharply: 185 tests were green while
**search was broken against every real webtrees instance**, because the fake
server answered a request the real one rejects. A fake that is more permissive
than the thing it stands for cannot fail. The fake now enforces `at` exactly as
`AbstractTomSelectHandler` does. Bug 7 is the
argument for widget tests carrying assertions about *copy*, not just structure.

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

---

## 8. Tooling

```bash
# Validate the wire protocol against any instance (dependency-free)
dart run tool/probe.dart --url tree.almou.sa --user NAME

# Exercise the app's own data layer end to end
WEBTREES_PASSWORD=... dart run tool/live_check.dart --url tree.almou.sa --user mobile

flutter test          # 201 tests
flutter analyze       # must stay clean
flutter run -d linux  # web is not viable — no CORS

# Render real screens to build/preview/*.png, in both languages and themes.
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

1. **HTML parsing is theme- and version-coupled.** Mitigated so far by parsing
   AJAX fragments rather than whole pages, a two-version fixture matrix, and
   `ParseFailure` naming the parser, selector and version. **Still open:** the
   fixtures are transcribed from upstream templates, not captured from a live
   site, so no non-default theme, language or module configuration has ever
   been parsed. Sanitized real captures are the next step.
2. **Cookie `Domain` mismatch** when a site is reached via a hostname other than
   its configured `base_url` (LAN IP, Tailscale). The app adopts the canonical
   base from the 308 and warns when it differs from what was typed.
3. **Tree list unavailable** when `ALLOW_CHANGE_GEDCOM != 1`. Falls back to the
   default tree; consider letting the user enter a tree name manually.
4. **`local_auth` has no Linux support** — the biometric gate must degrade
   gracefully on the development machine.
5. **Upstream module API churn.** webtrees does not guarantee stability for
   custom modules; 2.3 changed routing substantially. If the optional PHP module
   is built (v2), isolate volatile core APIs behind one adapter and run CI
   against both 2.2.x and 2.3.
6. **Only the app is version-controlled.** The repository is `webtrees_mobile/`
   (this document included). The parent workspace, `CLAUDE.md` and the two
   upstream clones have no shared history.
7. **Nothing has run on a real device, or as a GUI at all.** Secure storage,
   biometrics, backgrounding, session renewal and cleartext networking cannot
   be validated by widget tests. Device smoke-testing should move ahead of
   Phase 5 rather than waiting for it.
8. **"Works against any webtrees instance" is a goal, not a tested claim.**
   What is actually verified: 2.2.6 live and 2.3.0-dev by source; both URL
   styles; both tab-route shapes; one private tree; the default theme. Parsers
   are exercised against Arabic/RTL fixtures. Untested: non-default themes,
   subdirectory installs, multiple trees, and module configurations other than
   the stock set. This belongs in an explicit compatibility matrix before
   release.
9. **The Android compile-SDK override** rewrites every plugin subproject
   through a deprecated Gradle API (§3). It works against the SDK installed
   here and should be treated as a temporary, version-specific workaround —
   it needs CI on a clean machine to stay honest.

Related: the full plan lives at `~/.claude/plans/warm-drifting-umbrella.md`.
