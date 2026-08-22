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
| `tab_relatives.html` | `modules/relatives/tab.phtml`, `family.phtml`, `chart-box.phtml` |
