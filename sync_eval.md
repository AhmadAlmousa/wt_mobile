# A local database, and what it would really buy

*Written 2026-08-24, against webtrees 2.2.6 and 2.3.0-dev, with every number
in §8 measured against a running lab rather than estimated.*

The proposal: the tree changes rarely — every few months, at most once a day —
so dump the whole thing into SQLite, download it daily, and answer everything
locally. This evaluates that, and it says **yes, with one change of shape and
three things it cannot do.**

---

## 1. Summary and recommendation

**Build it. Not as a downloaded file — as a local database the *client* fills
from paged record requests.** Everything else about the idea survives contact
with the details; that one part does not, and §3 says why.

| | |
|---|---|
| **Worth doing** | Offline, tree-wide filtering, real browsing, instant everything |
| **Not the reason** | Request reduction. The app is already frugal — §2 |
| **Shape** | Client-owned SQLite, filled by `GET …/records?offset=&limit=`, not a server-built `.sqlite` download |
| **Package** | **Drift.** ObjectBox is the wrong tool here for one decisive reason — §9 |
| **Cannot be local** | Relationship *wording*, statistics as the site publishes them, anything a signature covers — §5 |
| **Hardest part** | Not the sync. The **privacy snapshot** — §6 |
| **Second hardest** | Language. Everything the app shows is server-rendered per language — §7 |
| **Size** | ~6 KB/person measured; **~9 MB for 1,463 people**, ~2 MB over the wire — §8 |
| **Blocks** | Nothing. It is additive, and the floor in §1 of `PROJECT.md` is untouched |

The single most valuable thing it does is not on the list above because it is
easy to miss: it **closes §9 #24**. The filter shipped in 0.17.0 narrows the
rows already fetched, so "no matches" can mean "none in the first fifty". With
a local database the filters become tree-wide and instant, and the sentence
apologising for that goes away.

---

## 2. What is actually slow today, honestly

A fair evaluation has to start by admitting the premise is half wrong. The app
is not chatty:

| Action | Requests today |
|---|---|
| A search | 1, then 1 per further page |
| Opening a person | 1 (module) or 1–5 (stock, one per tab) |
| A chart | 1 |
| A relationship | 1 |
| A thumbnail | 1, then cached for the session |

Nothing here is a request storm, and "reduce the need to hit the server for
every bit of data" describes a problem the app mostly does not have. So the
case for a local database has to rest on what is **impossible** today rather
than on what is slow:

1. **Offline.** Today the app is a window onto a server. Away from signal it
   shows nothing. This is the stated goal and it is a real one.
2. **Browsing.** `PROJECT.md` §2 records that a stock instance cannot
   enumerate a tree, which is why the app is search-driven. The module can
   (`/individuals` with no `q`), but paging a whole tree over the wire to sort
   or filter it is not something to do on a phone.
3. **Tree-wide filtering** — §9 #24, above.
4. **Latency.** Not the request count but the *round trip*: 40 ms per record
   against a lab on localhost (§8), and rather more over a mobile network to a
   shared host. Every tap in the app pays it. A local read pays none.
5. **Things nobody has proposed yet** because they are unaffordable over HTTP:
   a surname index, "everyone born in this place", "the ten longest lives",
   an offline chart of the whole tree.

That is a good list. It is worth being clear that it is the list, because it
changes what the design has to optimise for: **completeness of the local copy**
matters, and **freshness within the hour** does not.

---

## 3. Why not a downloaded `.sqlite`, and what instead

The proposal's natural shape is: PHP builds a SQLite file, the app downloads
it, opens it, done. PHP *can* do this — `pdo_sqlite` and `sqlite3` are both
present on the lab's PHP 8.4, and they are near-universal — and it is
appealing because the client has no import step at all.

It is still the wrong shape, for reasons that are all about the server:

- **One request has to build the whole thing.** For 1,463 people that is a
  multi-megabyte file built by walking every record through
  `IndividualFactsService` and the presenters. Shared hosting typically caps
  `max_execution_time` at 30 s and `memory_limit` at 128 M. This is the single
  most likely way the feature fails on somebody else's server, and it fails
  *at install time*, which is the worst moment.
- **It needs somewhere to put the file.** A temp file the next request can
  find means server-side state, cleanup, and a job token — three things the
  module does not have and should not grow for this.
- **It is all-or-nothing.** A dropped connection at 90% starts again.
- **It cannot be incremental** without building a second, different endpoint
  for the daily delta — so the "first sync" and the "daily sync" become two
  code paths with two sets of bugs.

**The alternative is the same idea with the file on the other side.** The
client owns the database; the server owns the records:

```
GET /tree/{tree}/mobile-api/v1/records?offset=0&limit=200[&since=<token>]
→ { "token": "...", "total": 1463, "hasMore": true, "people": [ …full records… ] }
```

The client opens its own SQLite, writes each page into it as it arrives, and
stores the token. Tomorrow it sends `since=<token>` and gets only what changed.

Everything that was hard becomes easy: no server-side file, no temp storage,
no job, no timeout risk (each page is bounded), resumable by construction, and
the *first* sync and the *daily* sync are the same code path with a different
parameter. It also reuses `paginateQuery`, which `api_eval.md` §4 already
established dedupes multi-name rows across the whole cursor and applies
`canShow()` before counting down the offset.

The cost is a client-side write loop instead of a file copy. Against 1,463
records that is seconds, in an isolate, once.

---

## 4. What the local store can answer

Given full records for every visible person, the app can serve locally:

| Capability | Local? | How |
|---|---|---|
| `individuals` (search, browse, enumerate) | ✅ | A `LIKE` over stored names — and for the first time, sorting and tree-wide filters |
| `individual` | ✅ | The stored record |
| `family` | ✅ | Stored with the record |
| `ancestors`, `descendants`, `hourglass` | ✅ | The shapes are walks over the stored family links. The app already owns every layout; only the *shape* was ever fetched |
| `timeline` | ✅ | Derived from the stored facts, which already carry rendered dates |
| `notes`, `sources`, `media` (list) | ✅ | Stored with the record |
| media *bytes* | ✅ with work | Thumbnails must be downloaded and stored as blobs — see §5 |
| `relationship` | ❌ **path yes, wording no** | §5 |
| `statistics` | ❌ on purpose | §5 |

That is nine of eleven, which is more than it looks: the two exceptions are
the two capabilities where the *server* is doing something the app was never
going to reimplement.

---

## 5. The three things that stay online

**Relationship wording.** The path between two people is a graph walk over the
link table, and the local store would have the links — so the *path* is
computable offline. The **words on it** are not. `nameFromPath()` produces
`أخ أكبر` where English has no term at all, from a table of kinship rules per
language that is one of the largest things in webtrees. `PROJECT.md` §9 #19
already flags the module's 150-line Dijkstra port as its riskiest code because
upstream could change it silently; a second port, of a much larger thing, into
Dart, is not a trade worth making.

*Recommendation:* keep relationships online in the first version. Offline, the
screen says the site is needed for this one answer — which is honest, and is
one screen out of nine.

**Statistics.** `PROJECT.md` §5 records a deliberate decision: the app reads
statistics from the *page*, because the page publishes seventeen sections
where the module answers four. A local store could compute a great deal more
than either — but it would then be showing *the app's* arithmetic where every
other screen shows the site's. That is a different product decision, and it
should be made on purpose rather than as a side effect of caching.

**Anything a signature covers.** A thumbnail URL is
`md5(glide_key . ':?' . query)` (`MediaFile::signature()`) — verified: there
is **no expiry in it**, so a cached URL keeps working until the site rotates
its `glide-key`. Two consequences. The URLs cache safely. But the signature
covers `mark`, which is `Auth::needsWatermark($tree)` — a property of the
*viewer* — which is one more reason the local store is per-user (§6). For true
offline the bytes have to be stored too: at 160 px the real tree's 86 media
objects are on the order of 1 MB, which is nothing.

---

## 6. Privacy is the hard part, and it is not close

Everything else in this document is engineering. This is the part that can go
wrong in a way that matters.

webtrees privacy is **per user and per record**: `canShow()` depends on the
viewer's role, on `HIDE_LIVE_PEOPLE`, on `RESN` tags, on per-fact
restrictions, and on relationship-based rules. `api_eval.md` §9 is emphatic
that the module never computes any of it — it calls the same methods as the
same user and presents what survives. A dump inherits that for free at the
moment it is built, and then it **freezes it on a device**.

Four consequences the design has to answer:

1. **The file is a snapshot of one user's view.** Stamp it — tree, user id,
   role, language, module version, `glide-key` fingerprint — and refuse to
   read a store whose stamp does not match the current session. A user who
   signs in as somebody else gets a new store, not a filtered one.
2. **A role can be revoked, and the stale copy is stale in the permissive
   direction.** A member demoted to visitor still holds everything they could
   see yesterday. Nothing can prevent that — the data is already on the device
   today, in memory — but the store makes it durable, so the app should drop
   the store on sign-out and on any change in the access summary it already
   probes for (`data/access_probe.dart`).
3. **The device now holds the tree.** Today the app holds only what was
   fetched, in RAM. This is a genuine change in exposure: a backed-up or
   shared phone gives up the whole visible tree. Encryption at rest is the
   answer, and the current route is `package:sqlite3` 3.x's build hooks —
   note that `sqlcipher_flutter_libs` is **end-of-life** and its own page now
   says to use `package:sqlite3` 3.x instead. Either way this is a decision to
   take before the first byte is written, not after.
4. **Pending edits are a second axis.** A moderator sees them; a member does
   not. `api_eval.md` §9 already asks for `pending` on records; the store must
   carry it and the stamp must include the role that produced it.

**A hidden record is absent, not empty** (`api_eval.md` §9 #1). That rule
holds locally too, and it is what makes a locally-computed chart correct: the
walk cannot reach what was never stored, so privacy pruning happens by
construction. It also means the local store can never be used to answer "how
many people are in this tree" — only "how many I can see", which is what the
app should be saying anyway.

---

## 7. Language, the other thing that does not cache cleanly

The app shows almost nothing it composed itself. Fact labels, rendered dates
in six calendars, kinship words, place names, the site's own phrase for a
relationship — all of it arrives translated, and `PROJECT.md` §7 bug 32
records what happened the one time that was taken for granted.

So a local store is per **(tree, user, language)**. Three options:

- **Store one language, resync on switch.** Simplest; costs a full sync when
  somebody changes language, which is rare.
- **Store both.** Not 2× the size: xrefs, names, places, links and years are
  language-independent, so the duplicated part is roughly the labels and the
  rendered dates. Call it 1.4×.
- **Store the structure and render locally.** This means reimplementing
  `Fact::label()`, `Date::display()` across six calendars, and the kinship
  tables. It is the option that looks cheapest on a whiteboard and is by a
  wide margin the most expensive, and it would undo the central decision of
  this project. **No.**

*Recommendation:* one language, resync on switch, with the language in the
stamp. Revisit if anyone actually switches.

---

## 8. Size and time, measured

Against the 2.2.6 lab, through the module's own endpoints, 18 real records:

| | |
|---|---|
| Full individual payload | **6,247 bytes/person**, mean |
| Largest single record | 13,997 bytes (four families, notes, a citation, two media) |
| One search-list row | 240 bytes |
| Round trip, per record | **40 ms** (localhost, PHP dev server, cold each time) |

The lab's people are *richer* than average — every one carries notes, sources
and media, which `tree.almou.sa` runs no tabs for at all — so 6 KB is an upper
bound rather than a typical figure.

Extrapolated to the real tree, **1,463 people**:

| | |
|---|---|
| Full local copy | **~9 MB** upper bound; realistically 4–6 MB |
| Over the wire, gzipped | **~2 MB** |
| Media thumbnails at 160 px | ~1 MB for 86 objects |
| First sync, 200 per page | 8 requests |
| Daily delta | Almost always **zero records** |

For scale: 9 MB is a third of one of the APKs this project already builds.
The first sync is a few seconds of network and a few seconds of writing.

**Where it stops being free.** A 100,000-person tree is ~600 MB at the same
rate, which is not a phone-sized artefact. If "works against any webtrees
instance" is to keep meaning something, the design needs a ceiling: sync a
*subset* — a surname partition, or everyone within N steps of the user's own
record, which is a query the module can already answer. Worth designing for
from the start rather than discovering at 50,000 people.

The 40 ms figure is a *round trip*, and most of it is webtrees booting its
framework once per request. Inside one request that walks many records the
per-record cost is far lower — which is exactly why §3's paged design (200
records per boot) is the right shape and a per-record fetch loop would not be.

---

## 9. Drift, not ObjectBox

| | Drift | ObjectBox |
|---|---|---|
| Version, licence | 2.34.3, MIT | 5.3.2, Apache-2.0 |
| Likes / downloads | 2,454 / 1.14 M | 1,577 / 153 k |
| Store format | **SQLite** | Proprietary, native-only |
| Query model | SQL, typed, streams | Object queries |

Both are healthy, maintained packages, and on raw object throughput ObjectBox
is the faster of the two. It is still the wrong choice here, for one reason
that has nothing to do with speed:

**SQLite is a format the server could write, and ObjectBox's is not.** Even
though §3 recommends *not* shipping a server-built file today, keeping that
door open is worth real money: if a future instance turns out to be able to
build one (a VPS, a cron job, a nightly artefact behind a URL), Drift can open
it with no import step at all. With ObjectBox that path does not exist in any
future.

Three more, smaller:

- The data is **relational** — people, families, links, facts, places. Charts
  are recursive walks and filters are `WHERE` clauses. This is SQL's home
  ground, and `WITH RECURSIVE` does an ancestor walk in one statement.
- Drift runs on Linux desktop, which is where `tool/preview/` renders and
  where `flutter run -d linux` happens. One fewer platform-specific native
  library to get working.
- Encryption has a route (§6), and `package:sqlite3` — Drift's own foundation,
  2.2 M downloads — is where it now lives.

The one honest cost: Drift uses code generation (`build_runner`), which this
project currently does not. That is a new step in CI and a new class of merge
conflict. It is a small price and it is worth naming.

---

## 10. Where it plugs in — and the good news

It is **not a third transport**. That matters, because `PROJECT.md` §4's rule
is to compose at the level of capabilities, and a cache is not a capability.

The seam already exists. `RecordsTransport` and `ChartsTransport` (`lib/data/transport.dart`)
say what the app needs without saying how, and `CapabilityRecordsTransport`
already picks a source per capability. A local store is one more implementation
of those interfaces:

```
CapabilityRecordsTransport
  ├── local   (Drift)   — where the store has the answer and the stamp matches
  ├── module  (JSON)    — where it does not
  └── stock   (HTML)    — the floor, permanently
```

Every screen is untouched. The chart screens already take opaque *handles*
from whichever transport minted them, so a local transport mints its own — the
one design decision in `charts_repository` that looked over-careful at the
time and turns out to have been exactly right.

Two things the composer needs that it does not have:

- **A staleness rule** beside `Capability.readFromThePage`: which capabilities
  may be answered from a store, and how old is too old. `relationship` and
  `statistics` say never (§5).
- **A "this came from the store" signal** for the diagnostics screen, which
  already reports which transport answered each capability. A reader wondering
  why a figure looks wrong needs to be told it is from last night.

And `tool/live_check.dart` grows a third column: local against module against
page. The discipline that has caught fourteen bugs so far is diffing two
sources of truth; adding a third makes that discipline more valuable, not
less — provided it is actually run.

---

## 11. Risks, in the order they will bite

1. **Two sources of truth become "is it stale or is it wrong?"** Every bug
   report acquires an extra question. Mitigated by the stamp, by a visible
   "synced at" line, and by `live_check` diffing all three.
2. **The privacy snapshot** (§6). The one that could actually harm somebody.
3. **A re-import silently replaces the tree.** Verified:
   `TreeService::deleteGenealogyData()` deletes the `change` rows for that
   tree, so an incremental token that refers to them becomes meaningless. That
   is *detectable* — the fingerprint goes backwards — and the rule is simple:
   a token the server no longer recognises means resync from scratch. Worth
   writing down because the failure mode without it is silent and permanent.
4. **Large trees** (§8). Design the ceiling early.
5. **Sync on a bad network.** Eight requests is eight chances to fail. The
   paged design is resumable; the code has to actually resume.
6. **Code generation in CI** (§9).
7. **Scope.** The store makes editing look close. It is not: `api_eval.md` §8
   is clear that writes need per-device tokens and a conflict story, and v1 of
   the module is read-only by design. Offline *reading* is a feature; offline
   *editing* is a different project.

---

## 12. A phased plan

Each phase is useful on its own and none of them requires the next.

| | Phase | What it delivers |
|---|---|---|
| **10a** | `GET …/records?offset=&limit=&since=` in the module; a `token` derived from `MAX(change_id)` and the tree's counts | The wire, testable with `curl` before any client work |
| **10b** | Drift schema, a `LocalRecordsTransport`, and the sync loop in an isolate | The store fills. Nothing reads it yet |
| **10c** | The composer prefers the store for `individual`, `individuals`, `family`; diagnostics say so; `live_check` diffs three ways | Instant person and search — and **tree-wide filters**, which closes §9 #24 |
| **10d** | Charts and timeline computed from the store | Nine of eleven capabilities local |
| **10e** | Thumbnail blobs; a sync screen; the stamp and its invalidation rules | Genuinely offline |
| **10f** | The ceiling for large trees (§8) | "Any webtrees instance" keeps meaning something |

**Start with 10a.** It is a single handler over machinery that already exists,
it can be verified against both labs the same afternoon, and it answers the
only question the rest depends on: does a real server hand over 1,463 records
in eight requests without falling over.

---

## 13. What was verified for this document

Against the running 2.2.6 and 2.3 labs, and against upstream source at
`2.2.6-264-gf2a4bb693e`:

- **Payload sizes and round-trip time** — measured through the module's own
  endpoints over 18 real records (§8). Not estimated.
- **PHP can write SQLite** — `pdo_sqlite` and `sqlite3` both present on the
  lab's PHP 8.4.
- **webtrees has a change log** — the `change` table carries `change_time`,
  `xref`, `status` and a per-tree `gedcom_id` with an index on all three
  (`app/Schema/Migration0.php`). An incremental token is straightforward.
- **A re-import wipes it** — `TreeService::deleteGenealogyData()` deletes
  `change` rows for the tree (`app/Services/TreeService.php:261`). This is what
  makes a backwards-moving fingerprint the right resync trigger.
- **Thumbnail signatures do not expire** — `MediaFile::signature()` is
  `md5($glide_key . ':?' . http_build_query($params))` with no time component;
  the params include `mark`, which is per-viewer.
- **Package facts** — versions, licences, likes and download counts from
  pub.dev, and that `sqlcipher_flutter_libs` is end-of-life and points at
  `package:sqlite3` 3.x.

**What was not verified, and matters.** Nothing here has been run against
`tree.almou.sa`. The 1,463-person figures are extrapolations from 18 records —
sound for size, weaker for time, and silent about what a shared host does when
asked for 200 records in one request. Phase 10a exists to answer exactly that,
and until it has, every number in §8 should be read as an argument rather than
as evidence.
