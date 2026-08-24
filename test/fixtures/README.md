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

| `chart_ancestors.html` | `modules/ancestors-chart/tree.phtml`, `chart-box.phtml` |
| `chart_descendants.html` | `modules/descendancy_chart/tree.phtml`, `chart-box.phtml` |

The two chart fixtures were written from markup **captured from the live
2.2.6 server** and then given this project's invented family — including the
Sosa numbers in Arabic-Indic digits, which is the detail that makes the
parser tests worth running: the app computes its own numbering and the tests
check it against what the server printed.

None of the three tab fixtures has been seen from a running server: `tree.almou.sa` runs
none of those modules (§9 of `PROJECT.md`), so these fixtures are the only
thing standing behind those parsers.

| `relationship_cousin.html` | **captured** from a running 2.2.6 and a running 2.3 lab |

The cousin fixtures are the first pair in this directory that were *both*
captured rather than transcribed. They exist because the relationship grid is
where the app recovers each step's **direction** — the one structural thing
that markup states — and because the two versions lay that grid out
differently: 2.2.6 turns the corner with a diagonal only where the previous
step ran the other way
(`if ($n > 2 && preg_match('/fat|mot|par/', $relationships[$n - 2]))`), while
2.3 dropped that test and uses a diagonal for every step after the first. So
the same four people are three columns wide on one version and five on the
other, and a parser that read column positions rather than the *sign of the
row change* would answer differently on each.

Everything the parser reads is as the server sent it — the table geometry, the
box classes and xrefs, the names, the lifespans and each connector cell's own
markup. The thumbnails, the facts dropdown and the absolute URLs were removed,
which is the whole of the difference between 8KB here and 78KB on the wire.
Every person in them is invented by `tool/lab/make_gedcom.py`.
