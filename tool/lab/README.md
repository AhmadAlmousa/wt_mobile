# The lab

Two throwaway webtrees installs — one 2.2.6, one 2.3 — on SQLite, with
`server/webtrees-mobile-api/` symlinked into each. They exist to answer the one
question no amount of reading can: **does the module actually work?**

`PROJECT.md` §9 #18 names this as the prerequisite for retiring any parser, and
`api_eval.md` §13 rule 6 says the same thing: an endpoint has to pass live
against real data before the HTML path it replaces can go.

## Requirements

```sh
sudo apt install -y php8.4-cli php8.4-sqlite3 php8.4-mbstring php8.4-intl \
    php8.4-gd php8.4-xml php8.4-curl php8.4-zip composer
```

No database server and no Apache: webtrees supports SQLite, and PHP's built-in
server is enough for a client that only speaks HTTP.

## Use

```sh
tool/lab/setup.sh 2.2.6 8622     # the version the real instance runs
tool/lab/setup.sh main  8623     # 2.3.0-dev

php -S localhost:8622 -t ../lab/webtrees-2.2.6 ../lab/webtrees-2.2.6/index.php &

WEBTREES_PASSWORD=lab-member-password \
  dart run tool/live_check.dart --url localhost:8622 --user mobile
```

`live_check` reads the same person through **both** transports and diffs them
field by field, so a lab run is not "did it answer" but "did it answer the same
thing the HTML says".

Re-running `setup.sh` rebuilds the database from scratch and leaves `vendor/`
alone. The installs land in `../lab/`, beside the upstream checkout on the big
volume — `/` has under 2 G free and must not be filled.

## The data

`make_gedcom.py` generates it, and **every person in it is invented**. Real
genealogy data stays out of this repository (`PROJECT.md` §1) — but that is
only half the reason. A tree built on purpose can hold every shape the parsers
were written for, where a real one holds whatever it happens to hold:

| In the tree | Because |
|---|---|
| Arabic names with a romanized second form | `alternateName`, and bidi in the interface |
| A Hijri birth, a `BET … AND`, an `ABT` | the calendar picker, and date qualifiers |
| A man with two marriages, one divorced | d'Aboville numbering across families (bug 26); `endedInDivorce` |
| Cousins marrying | the same person reached twice in one chart |
| A living person and a dead one | `isDead`, and the `…–` lifespan |
| A person with a name and no facts | "absent, not empty" |
| A shared note, an inline note, a citation with a page | two of the three optional tabs |
| **A JPEG photograph on the person and a PNG scan on their birth** | the media tab, the signed thumbnail, `AuthenticatedImage` — and, in the PNG, webtrees 2.3 answering `500` for anything that is not a JPEG (PROJECT.md §7, bug 44) |
| A relative's death | the one fact the chart-box tag dictionary provably cannot learn |

The tree is also **private**, converts dates to **Hijri**, and searches **blood
lines only** — the three settings that make the target instance's behaviour
reproducible rather than accidental.

## Accounts

Disposable, and written down on purpose: this is a scratch SQLite file on
localhost holding an invented family.

| User | Password | Role |
|---|---|---|
| `admin` | `lab-admin-password` | site administrator |
| `mobile` | `lab-member-password` | member of `main`, read-only, own record `X42` |
