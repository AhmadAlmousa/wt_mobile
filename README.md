# webtrees Mobile

A Flutter client for [webtrees](https://webtrees.net) genealogy sites.

You give it a site address, a username and a password. It works against an
**untouched** webtrees instance — nothing needs to be installed on the server,
and you sign in as yourself, so the privacy rules and tree permissions your
account already has are the ones that apply.

It is not a wrapper around the web interface. The app owns its own navigation
and screens, and reads the site over plain HTTP the way a browser would.

Android, iOS and desktop. **Not web** — webtrees sends no CORS headers, so a
browser cannot talk to it from another origin.

## Status

Read-only browsing is being built. Connecting, signing in, staying signed in
and reporting your access work today; opening records is next.

**`PROJECT.md` is the real documentation** — the plan, the verified wire
protocol, every decision and why it was taken, and an honest status table. Read
it before changing anything here; much of what looks arbitrary in this code is
load-bearing, and that file says which parts and why.

## Working on it

```bash
flutter test          # 110 tests
flutter analyze       # must stay clean

# Validate the wire protocol against any instance (dependency-free)
dart run tool/probe.dart --url tree.example.com --user NAME

# Exercise the app's own data layer end to end against a real server
WEBTREES_PASSWORD=... dart run tool/live_check.dart \
  --url tree.example.com --user NAME
```

Run `live_check` after any transport change. One early bug — a shared HTTP
adapter being closed out from under later requests — passed every unit test and
only ever showed up against a real server.

Both tools read the password from the terminal with echo disabled, or from
`WEBTREES_PASSWORD`. Neither writes it anywhere.

## Data

Real genealogy data stays out of this repository. `.gitignore` excludes GEDCOM
and SQL dumps, build output and signing material; parser fixtures are
sanitized before they are committed.
