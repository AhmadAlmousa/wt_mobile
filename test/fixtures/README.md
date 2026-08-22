# Parser fixtures

HTML the parsers are tested against, one directory per supported webtrees
version. The point of holding two is that the versions really do differ: in
2.2.6 a tab anchor carries no `id`, which 2.3 added — a parser keyed on that
id finds no tabs at all on 2.2.6.

**These are transcribed from the upstream view templates, not captured from a
running server.** That is a real limitation, and the one Codex warned about:
hand-written markup tends to reproduce exactly what the parser expects, so it
proves the parser handles the shape the templates emit and nothing more. It
cannot catch a theme that restructures a page, a module that injects markup, or
anything the templates do that was misread here.

Replace them with **sanitized captures** from a real instance as soon as a
password is available — real names replaced, real XREFs replaced, signed
thumbnail URLs truncated. Real genealogy data must not enter this repository.

Sources, all under `webtrees/resources/views/`:

| Fixture | Templates |
|---|---|
| `individual_page.html` | `individual-page.phtml`, `-title`, `-names`, `-images`, `-tabs` |
| `tab_personal_facts.html` | `fact.phtml`, `fact-date.phtml`, `fact-place.phtml` |

The date markup in `v2_2_6/tab_personal_facts.html` is the exception: it was
**captured from `tree.almou.sa`** and then rewritten with invented dates. The
transcribed version had the 2.3 shape — `1901 [1318]` as plain text — which
2.2.6 never emits. What it really sends is a link to the calendar page per
date, with the converted date in a `dir`-bearing span beside it, and the `cal`
parameter of those links is the only place a stock site says which calendar a
rendered date is in.
| `tab_relatives.html` | `modules/relatives/tab.phtml`, `family.phtml`, `chart-box.phtml` |
| `tab_notes.html` | `modules/notes/tab.phtml`, `fact.phtml` |
| `tab_sources.html` | `modules/sources_tab/tab.phtml`, `fact-gedcom-fields.phtml` |
| `tab_media.html` | `modules/media/tab.phtml`, `MediaFile::displayImage`, `XrefMedia::labelValue` |

The notes, sources and media tabs are **identical markup in both versions**
bar a handful of attributes: 2.3 adds `aria-expanded` to the "show all" control, marks a
gallery link with `data-wt-gallery` where 2.2.6 used `class="gallery"`, and
targets a collapse with `data-bs-target` rather than `href`. The v2_3 copies
carry those differences so a parser that keyed on any of them would fail one
version and pass the other.

2.3 renamed the sources tab's *view directory* from `sources_tab` to
`sources-tab`. The **module name** — which is what the tab anchor and the
fragment URL carry, and therefore all the app ever sees — stayed `sources_tab`
in both.

None of the three has been seen from a running server: `tree.almou.sa` runs
none of those modules (§9 of `PROJECT.md`), so these fixtures are the only
thing standing behind those parsers.
