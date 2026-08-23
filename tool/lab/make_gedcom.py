#!/usr/bin/env python3
r"""Generates the synthetic tree the lab installs are tested against.

**No real family data.** Every person here is invented. That is not only a
privacy rule (PROJECT.md §1) — it is what makes the fixture useful, because a
tree built on purpose can hold every shape the parsers were written for and a
real one holds whatever it happens to hold.

Deliberately included, each because something in the app depends on it:

  * Arabic names with a romanized second name  - alternateName, bidi
  * Hijri and Gregorian dates, and a `BET .. AND` range and an `ABT`
                                             - the calendar picker, qualifiers
  * A man with two marriages                 - d'Aboville numbering across
                                               families (bug 26), spouses list
  * A divorce                                - endedInDivorce, drawn lines
  * Cousins marrying                         - the same person twice in a chart
  * A living person and a dead one           - isDead, lifespan `…–`
  * A person with a name but no facts        - "absent, not empty"
  * A shared note, an inline note, a source
    citation with a page, a media object     - the three optional tabs
  * A relative's death                       - the fact the chart-box tag
                                               dictionary provably cannot learn

Usage:  python3 tool/lab/make_gedcom.py > /path/to/lab.ged
"""

from __future__ import annotations

import sys

LINES: list[str] = []


def out(level: int, tag: str, value: str = "") -> None:
    LINES.append(f"{level} {tag} {value}".rstrip())


def header() -> None:
    out(0, "HEAD")
    out(1, "SOUR", "webtrees-mobile-lab")
    out(2, "NAME", "Synthetic test data")
    out(2, "VERS", "1")
    out(1, "DEST", "webtrees")
    out(1, "GEDC")
    out(2, "VERS", "5.5.1")
    out(2, "FORM", "LINEAGE-LINKED")
    out(1, "CHAR", "UTF-8")
    out(1, "SUBM", "@SUB1@")


def individual(
    xref: str,
    given: str,
    surname: str,
    sex: str,
    *,
    latin: tuple[str, str] | None = None,
    second_name: tuple[str, str] | None = None,
    married_name: str | None = None,
    birth: str | None = None,
    birth_place: str | None = None,
    death: str | None = None,
    death_place: str | None = None,
    burial: str | None = None,
    restriction: str | None = None,
    occupation: str | None = None,
    famc: str | None = None,
    fams: list[str] | None = None,
    note: str | None = None,
    shared_note: str | None = None,
    source: tuple[str, str] | None = None,
    media: str | None = None,
    fact_media: str | None = None,
) -> None:
    out(0, f"@{xref}@", "INDI")

    # `confidential` hides a record from everybody below a manager — the
    # member this lab signs in as included. It is the only way to produce the
    # shape bug 50 came from: a family whose spouse the reader cannot see.
    if restriction is not None:
        out(1, "RESN", restriction)

    out(1, "NAME", f"{given} /{surname}/")
    out(2, "GIVN", given)
    out(2, "SURN", surname)

    # A married name recorded as a *subtag* of the name, which is how a real
    # tree records one. webtrees renders it as a field inside the name block —
    # `الإسم ما بعد الزواج: …` — and gives it no `span.NAME`, so it is not a
    # second name to the page. It *is* a second row in `getAllNames()`, which
    # is what made the module answer an alternate name nobody had recorded
    # (PROJECT.md §7, bug 48).
    if married_name is not None:
        out(2, "_MARNM", married_name)

    # A second name form, which an Arabic tree commonly carries. webtrees
    # returns it from getSecondaryName(), and the app shows it under the first.
    if latin is not None:
        out(1, "NAME", f"{latin[0]} /{latin[1]}/")
        out(2, "TYPE", "romanized")
        out(2, "GIVN", latin[0])
        out(2, "SURN", latin[1])

    # A second name in the same script. `@N.N.` is GEDCOM's "name unknown",
    # which webtrees renders as an ellipsis.
    if second_name is not None:
        given = second_name[0] or "@N.N."
        out(1, "NAME", f"{given} /{second_name[1]}/")
        out(2, "SURN", second_name[1])

    out(1, "SEX", sex)

    if birth is not None:
        out(1, "BIRT")
        out(2, "DATE", birth)
        if birth_place is not None:
            out(2, "PLAC", birth_place)
        if source is not None:
            out(2, "SOUR", f"@{source[0]}@")
            out(3, "PAGE", source[1])
            out(3, "QUAY", "3")
        # A note hanging off a fact rather than off the person: the "level two"
        # row the notes tab collapses and marks differently from the rest.
        if note is not None:
            out(2, "NOTE", note)
        # Media hanging off the fact rather than off the person: the
        # `tr.wt-level-two-media` row, whose `th.rela` carries *that fact's*
        # label and no `.wt-fact-label` at all (PROJECT.md §3).
        if fact_media is not None:
            out(2, "OBJE", f"@{fact_media}@")

    if death is not None:
        out(1, "DEAT")
        out(2, "DATE", death)
        if death_place is not None:
            out(2, "PLAC", death_place)

    # A burial and no death line. `Gedcom::DEATH_EVENTS` is DEAT, BURI, CREM,
    # and a chart box prints a tag for whichever it finds — so a transport
    # that looked only for DEAT called a buried man living (PROJECT.md §7,
    # bug 49).
    if burial is not None:
        out(1, "BURI")
        out(2, "DATE", burial)

    if occupation is not None:
        out(1, "OCCU", occupation)

    if shared_note is not None:
        out(1, "NOTE", f"@{shared_note}@")

    if media is not None:
        out(1, "OBJE", f"@{media}@")

    if famc is not None:
        out(1, "FAMC", f"@{famc}@")

    for family in fams or []:
        out(1, "FAMS", f"@{family}@")


def family(
    xref: str,
    husband: str | None,
    wife: str | None,
    children: list[str],
    *,
    marriage: str | None = None,
    marriage_place: str | None = None,
    divorce: str | None = None,
) -> None:
    out(0, f"@{xref}@", "FAM")
    if husband is not None:
        out(1, "HUSB", f"@{husband}@")
    if wife is not None:
        out(1, "WIFE", f"@{wife}@")
    for child in children:
        out(1, "CHIL", f"@{child}@")
    if marriage is not None:
        out(1, "MARR")
        out(2, "DATE", marriage)
        if marriage_place is not None:
            out(2, "PLAC", marriage_place)
    if divorce is not None:
        out(1, "DIV")
        out(2, "DATE", divorce)


def build() -> None:
    header()

    KUWAIT = "الكويت, الكويت"
    RIYADH = "الرياض, السعودية"

    # --- generation 1: the grandparents -----------------------------------
    individual(
        "X7", "سليمان", "الموسى", "M",
        birth="12 MAR 1870", birth_place=KUWAIT,
        death="4 JUN 1940", death_place=KUWAIT,
        occupation="تاجر",
        fams=["F1"],
    )
    individual(
        "X8", "لطيفة", "البقشي", "F",
        birth="ABT 1875", birth_place=KUWAIT,
        death="1945",
        fams=["F1"],
    )

    # --- generation 2 -----------------------------------------------------
    # The subject. Two marriages, one of which ended in divorce; a Hijri
    # birth, so the calendar picker has something to pick between.
    individual(
        "X42", "عبد الله", "الموسى", "M",
        latin=("Abdullah", "Almousa"),
        birth="@#DHIJRI@ 21 DHUAQ 1318", birth_place=KUWAIT,
        death="1974", death_place=KUWAIT,
        occupation="معلم",
        famc="F1", fams=["F2", "F3", "F6", "F7"],
        shared_note="N1",
        source=("S1", "الصفحة ٤٢"),
        media="M1",
        fact_media="M2",
        note="سُجّل الميلاد بعد سنة من وقوعه.",
    )
    # His sister, who marries into the other branch — which is what makes a
    # cousin marriage possible two generations down.
    individual(
        "X43", "نورة", "الموسى", "F",
        birth="1903", death="BET 1980 AND 1982",
        famc="F1", fams=["F4"],
    )
    individual("X50", "سارة", "العنزي", "F", birth="1905", fams=["F2"])
    individual("X51", "منيرة", "الصائغ", "F", birth="1910", fams=["F3"])
    individual("X52", "خالد", "الصائغ", "M", birth="1900", fams=["F4"])

    family("F1", "X7", "X8", ["X42", "X43"],
           marriage="1899", marriage_place=KUWAIT)
    family("F2", "X42", "X50", ["X60", "X61", "X63", "X64"],
           marriage="@#DHIJRI@ 1343", marriage_place=KUWAIT,
           divorce="1940")
    family("F3", "X42", "X51", ["X62"], marriage="1941")
    family("F4", "X52", "X43", ["X70"], marriage="1925")
    family("F6", "X42", "X65", [], marriage="1950")
    # No wife and no marriage, so the relatives tab prints one spouse row,
    # then children, with no divider between them.
    family("F7", "X42", None, ["X66", "X67"])

    # --- generation 3 -----------------------------------------------------
    # X60, X61 and X63 are numbered 1.1 to 1.3; X62 continues at 1.4 rather
    # than restarting, because webtrees never resets the counter between
    # families.
    individual(
        "X60", "محمد", "الموسى", "M",
        latin=("Mohammed", "Almousa"),
        birth="1930", birth_place=KUWAIT,
        occupation="مهندس",
        famc="F2", fams=["F5"],
    )
    # Two names in the *same* script, the second with an unknown given name.
    # webtrees' own `alternateName()` answers null for this — it only reports a
    # second name in a different character set — while the names accordion the
    # HTML path reads shows it. A real tree had exactly this, and it is the one
    # record the two transports ever disagreed about.
    individual("X61", "هيا", "الموسى", "F", birth="1932", famc="F2",
               second_name=("", "الموسى الصائغ"))
    # Her sister, with a married name under her only name: one name to the
    # page, two rows to `getAllNames()`. The pair of them is the whole
    # distinction — X61 has a second name and she does not.
    individual("X63", "شيخة", "الموسى", "F", birth="1935", famc="F2",
               married_name="العنزي")
    # Buried, with no death recorded. Dead to a chart box and, until bug 49,
    # living to the module.
    individual("X64", "راشد", "الموسى", "M", birth="1928", burial="1990",
               famc="F2")

    # A third wife whose *details* the reader may not see. `RESN confidential`
    # is a manager-level restriction, so `canShow()` is false for a member
    # while `canShowName()` stays true — "a name may be visible where details
    # are not", which this project had written down and never once exercised,
    # because privacy was switched off in the lab until bug 51.
    individual("X65", "حصة", "الدوسري", "F", birth="1915", fams=["F6"],
               restriction="confidential")

    # A fourth family with **no wife recorded at all** and no marriage. Seen
    # from either of the other wives it renders as a step-family captioned
    # `عبد الله الموسى + … …` — one visible spouse row, then a run of children,
    # and nothing on the rows to say which is which. That is bug 50's shape,
    # taken from a real record.
    individual("X66", "طلال", "الموسى", "M", birth="1946", famc="F7")
    individual("X67", "نوف", "الموسى", "F", birth="1948", famc="F7")
    individual(
        "X62", "سارة", "الموسى", "F",
        birth="1945", death="2001", famc="F3",
    )
    individual("X70", "فاطمة", "الصائغ", "F", birth="1928", famc="F4",
               fams=["F5"])

    # Cousins marrying: X60 and X70 are both grandchildren of X7 and X8, so a
    # descendant chart reaches their children by two routes and a relationship
    # search finds more than one path.
    family("F5", "X60", "X70", ["X80", "X81"], marriage="1955")

    # --- generation 4 -----------------------------------------------------
    individual("X80", "أحمد", "الموسى", "M", birth="1960", famc="F5")
    # A person with a name and nothing else: the "a name may be visible where
    # details are not" case, without needing a privacy rule to produce it.
    individual("X81", "مريم", "الموسى", "F", famc="F5")

    # --- records the three optional tabs read ------------------------------
    LINES.append("0 @N1@ NOTE هاجر إلى الكويت في عام ١٩٢٠ وعمل في تجارة اللؤلؤ.")
    out(1, "CONT", "هذه ملاحظة مشتركة يمكن لعدة أفراد الإشارة إليها.")

    out(0, "@S1@", "SOUR")
    out(1, "TITL", "سجل قيد العائلة")
    out(1, "AUTH", "دائرة الأحوال المدنية")
    out(1, "REPO", "@R1@")

    out(0, "@R1@", "REPO")
    out(1, "NAME", "الأرشيف الوطني")
    out(1, "ADDR", RIYADH)

    # Two media objects, and the difference between them is deliberate.
    #
    # A photograph is a JPEG, which is what a family album holds and what both
    # webtrees versions serve. A scanned certificate is a PNG, which webtrees
    # 2.3 cannot make a thumbnail of at all: `ImageFactory::autoRotateImage()`
    # calls `exif_read_data()` on every image, PHP warns "File not supported"
    # for anything that is not a JPEG or a TIFF, and webtrees' own error
    # handler turns a warning into a 500. So the PNG is here to keep that
    # visible rather than to be avoided (PROJECT.md §7, bug 44).
    out(0, "@M1@", "OBJE")
    out(1, "FILE", "lab-portrait.jpg")
    out(2, "FORM", "jpeg")
    out(2, "TYPE", "photo")
    out(2, "TITL", "صورة عبد الله")

    out(0, "@M2@", "OBJE")
    out(1, "FILE", "lab-record.png")
    out(2, "FORM", "png")
    out(2, "TYPE", "document")
    out(2, "TITL", "شهادة الميلاد")

    out(0, "@SUB1@", "SUBM")
    out(1, "NAME", "lab")

    out(0, "TRLR")


if __name__ == "__main__":
    build()
    sys.stdout.write("\n".join(LINES) + "\n")
