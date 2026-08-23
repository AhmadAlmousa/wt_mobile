# webtrees-mobile-api

A read-only JSON interface to webtrees, built for the `webtrees_mobile`
client. **Optional**: the app works against an untouched instance by reading
HTML, and every capability this module adds keeps that path. Installing it
makes the app faster, cheaper and more truthful; not installing it costs
nothing.

Design basis: `../../api_eval.md`. Decisions and constraints: `../../PROJECT.md`.

## Install

```sh
cp -r webtrees-mobile-api /path/to/webtrees/modules_v4/
```

Then enable **Mobile API** in *Control panel → Modules → All modules*. No
configuration, no dependencies, no database changes.

Supported: webtrees **2.2.x** and **2.3**. PHP 8.3+.

## Authentication

The webtrees session the client already holds. Module routes run inside the
ordinary middleware pipeline, so `Auth::user()` *is* the reader and every
privacy rule applies unchanged — including relationship privacy and per-fact
restrictions.

There is no shared secret, no client id and nothing to configure, which is
deliberate: a shipped mobile binary cannot keep a secret. If OAuth2 is ever
added it must be **authorization code with PKCE**, never client credentials.

`BadBotBlocker` runs before the router, so it applies to these routes exactly
as it does to pages: a request with an empty or blocked `User-Agent` gets a
`406` before any of this code runs.

## Endpoints

All `GET`. `Router` injects `CheckCsrf` unconditionally and its exclusion list
is a `private const` a module cannot extend, so read-only endpoints avoid the
question entirely.

| Endpoint | Answers |
|---|---|
| `/mobile-api/v1/capabilities` | what this installation implements — anonymous |
| `/mobile-api/v1/access` | the account, its trees, roles and modules |
| `/tree/{tree}/mobile-api/v1/individuals` | search (`q`), browse (no `q`), or a surname index (`surname`) |
| `/tree/{tree}/mobile-api/v1/individual/{xref}` | one person: facts, families, notes, sources, media |
| `/tree/{tree}/mobile-api/v1/family/{xref}` | one family |
| `/tree/{tree}/mobile-api/v1/ancestors/{xref}` | the pedigree, as a tree of people |
| `/tree/{tree}/mobile-api/v1/descendants/{xref}` | descendants, with d'Aboville numbers |
| `/tree/{tree}/mobile-api/v1/relationship/{a}/{b}` | every path between two people |
| `/tree/{tree}/mobile-api/v1/timeline/{xref}` | dated events and the range they span |
| `/tree/{tree}/mobile-api/v1/statistics` | counts and datasets for the whole tree |
| `/tree/{tree}/mobile-api/v1/media/{xref}` | a media object, signed at any size |
| `/tree/{tree}/mobile-api/v1/record/{xref}/notes` | notes on any record |
| `/tree/{tree}/mobile-api/v1/record/{xref}/sources` | source citations on any record |

Common parameters: `offset`, `limit` (capped at `limits.maxPageSize`),
`generations`, `recursion`, `thumb`, `w`, `h`, `fit`, and `lang`.

### Errors

One shape, always, and **never a redirect**:

```json
{ "error": "forbidden", "message": "…", "detail": null }
```

`400 invalid_parameter`, `401 not_signed_in`, `403 forbidden`,
`404 not_found`, `500 server_error`.

One exception, on 2.2.x only: when `{tree}` names a tree that does not exist
or that this reader may not see, webtrees' 2.2 router hands the request to its
own not-found handler *before* module middleware runs, so the `404` arrives as
an HTML page. 2.3 answers the JSON envelope. A client should treat any `404`
as `not_found` regardless of the body.

## What this module does not do

- **It does not compute privacy.** `canShow()`, `canShowName()`,
  `facts($filter, $sort, $access_level)` and `TreeService::all()` are called as
  the signed-in reader, and whatever survives is what is sent. A hidden record
  is *absent*, not empty — a family may list two children where the tree
  records four, and no placeholder is invented. A name may be visible where the
  details are not.
- **It does not write.** No `POST`, no editing, no moderation.
- **It does not translate.** Every human-readable string is the site's own,
  already worded by webtrees in the language of the request.
- **It does not re-format dates.** It converts them (which webtrees' own
  `convertToCalendar()` does) and then asks webtrees to render each one.

## Both halves, always

Every payload carries what webtrees *rendered* and what it *means*:

```json
{ "tag": "BIRT", "label": "الميلاد", "origin": "self",
  "date": { "gedcom": "12 MAR 1901", "text": "١٢ مارس ١٩٠١ (٢١ ذو القعدة ١٣١٨)",
            "julianDay": [2415466, 2415466], "qualifier": null,
            "rendered": [
              { "calendar": "gregorian", "escape": "@#DGREGORIAN@", "text": "١٢ مارس ١٩٠١" },
              { "calendar": "hijri", "escape": "@#DHIJRI@", "text": "٢١ ذو القعدة ١٣١٨" }
            ] } }
```

A client draws the first and reasons about the second. Neither is derivable
from the other, which is why both are sent.

Two consequences worth knowing:

- The calendars offered are the ones the **tree** converts to
  (`CALENDAR_FORMAT`). A manager's choice, honoured rather than overruled.
- webtrees 2.3 puts its calendar-conversion block inside
  `if ($this->date2 !== null)` (`app/Date.php`), so an ordinary single date
  loses its conversion **on the website**. This module converts from
  `convertToCalendar()` directly and is not affected, so 2.2.x and 2.3 answer
  the same thing. That upstream bug still needs reporting.

## Versioning

- `/v1` changes only for a breaking change.
- `capabilities.features` announces additive ones, so an old client and a new
  module — or the reverse — degrade **per capability**, not per release.
- Within a version: new fields yes; renamed or removed fields no.
- `capabilities.module` states this module's own version, and a client should
  read it as information rather than as a promise. **1.0.1** stopped sending a
  family's `HUSB`, `WIFE` and `CHIL` lines as facts: they are already answered
  as `spouses` and `children`, and a client that drew both drew each member
  twice. No field changed, so no version scheme could have announced it — which
  is why a client should drop those three tags itself whatever the module says.
  **1.1.0** changed two more values without changing a field. A relationship's
  `description` is now `Relationship: X` — the phrase `RelationshipsChartModule`
  writes above its own chart — rather than the bare kinship word; and a
  timeline event's `summary` carries the calendar conversion (`1974 (1394)`,
  not `1974`) and, for a marriage or a divorce, the couple it belongs to,
  without which a person's two marriages are two identical rows.

## Known upstream defects a client will meet

- **webtrees 2.3 answers `500` for the thumbnail of any non-JPEG.**
  `ImageFactory::autoRotateImage()` calls `exif_read_data()` on every image it
  resizes, PHP raises `E_WARNING: File not supported` for a PNG, a GIF or a
  WebP, and `ErrorHandler` turns an un-silenced warning into an exception. This
  module mints the URL and does not fetch the bytes, so nothing here can fix
  it: a client must draw its placeholder for a picture it cannot fetch, exactly
  as it would for one it is not allowed to see. 2.2.6 is unaffected.

## Layout

```
module.php                 returns the module
autoload.php               PSR-4 for this namespace only — nothing is vendored
src/WebtreesMobileApi.php  boot(): every route, in one place
src/Compat/                the entire 2.2-vs-2.3 surface: eleven methods
src/Http/                  Json, ApiException, middleware, one handler per endpoint
src/Presenters/            person, fact, date, place, family, note, source, media
src/Support/               parameter validation, shared fact gathering, the
                           relationship graph
```

**The rule:** no code outside `src/Compat/` may name a webtrees version, or a
class that exists in only one of them. `tool/check_module.py` in the parent
repository enforces it by checking every import against both versions of the
webtrees source.

### The one piece of duplicated core logic

`RelationshipsChartModule::calculateRelationships()` is `private`, along with
`allAncestors()` and `excludeFamilies()`. `src/Support/RelationshipFinder.php`
is a deliberate line-for-line port of all three, which are identical in 2.2.6
and 2.3 but for a trailing comma. It is the only place this module can silently
disagree with the website — so it is kept as a port, not as an improvement.

The *naming* of a path is not duplicated: `RelationshipService::nameFromPath()`
is public, so `أخ أكبر` stays the site's word.
