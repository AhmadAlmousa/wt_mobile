#!/usr/bin/env python3
r"""Static checks for server/webtrees-mobile-api, for a machine with no PHP.

Three things it can prove without an interpreter:

1. The files are structurally sound - brackets balance, and every `use
   function` / `use const` import is actually used.
2. Every `Fisharebest\Webtrees\...` class the module imports exists in the
   webtrees source, in BOTH 2.2.6 and 2.3 - except inside `src/Compat/`,
   which is the one place allowed to name a version.
3. Nothing outside `src/Compat/` imports a class that exists in only one of
   them, which is the rule the compat layer exists to enforce.

Usage:  python3 tool/check_module.py [path-to-webtrees-checkout]
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
MODULE = HERE / "server" / "webtrees-mobile-api"
DEFAULT_WEBTREES = HERE.parent / "webtrees"
TAG_22 = "2.2.6"

PAIRS = {"}": "{", ")": "(", "]": "["}


def strip_php(source: str) -> str:
    """Blank out strings, comments and heredocs so brackets can be counted."""
    out = []
    i = 0
    n = len(source)
    while i < n:
        c = source[i]
        two = source[i : i + 2]
        if two == "//" or c == "#":
            j = source.find("\n", i)
            i = n if j == -1 else j
            continue
        if two == "/*":
            j = source.find("*/", i + 2)
            i = n if j == -1 else j + 2
            continue
        if c in "'\"":
            quote = c
            j = i + 1
            while j < n:
                if source[j] == "\\":
                    j += 2
                    continue
                if source[j] == quote:
                    break
                j += 1
            i = j + 1
            out.append('""')
            continue
        m = re.match(r"<<<'?\"?(\w+)'?\"?\r?\n", source[i:])
        if m:
            label = m.group(1)
            end = re.search(r"\n\s*" + label + r"\b", source[i:])
            i = n if not end else i + end.end()
            out.append('""')
            continue
        out.append(c)
        i += 1
    return "".join(out)


def check_brackets(path: Path, code: str) -> list[str]:
    stack: list[tuple[str, int]] = []
    line = 1
    for ch in code:
        if ch == "\n":
            line += 1
        elif ch in "{([":
            stack.append((ch, line))
        elif ch in "})]":
            if not stack or stack[-1][0] != PAIRS[ch]:
                return [f"{path.name}: unbalanced '{ch}' on line {line}"]
            stack.pop()
    if stack:
        ch, line = stack[-1]
        return [f"{path.name}: '{ch}' opened on line {line} is never closed"]
    return []


def check_unused_imports(path: Path, source: str, code: str) -> list[str]:
    problems = []
    # Docblocks are stripped from `code`, but a `use` that exists only for a
    # @param or @return annotation is still a real use, so search the source
    # with the import lines themselves removed.
    body = re.sub(r"^use .*;$", "", source, flags=re.M)
    for kind, name in re.findall(r"^use (function|const) [\w\\]*?(\w+);", source, re.M):
        # The import line itself mentions the name once.
        if not re.search(r"\b" + re.escape(name) + r"\b", body):
            problems.append(f"{path.name}: `use {kind} {name}` is never used")
    for name in re.findall(r"^use ([\w\\]+);", source, re.M):
        short = name.rsplit("\\", 1)[-1]
        if not re.search(r"\b" + re.escape(short) + r"\b", body):
            problems.append(f"{path.name}: `use {name}` is never used")
    for full, alias in re.findall(r"^use ([\w\\]+) as (\w+);", source, re.M):
        if not re.search(r"\b" + re.escape(alias) + r"\b", body):
            problems.append(f"{path.name}: `use {full} as {alias}` is never used")
    return problems


def webtrees_classes(root: Path) -> tuple[set[str], set[str]]:
    """Fully-qualified class names present in 2.3 (working tree) and 2.2.6."""
    modern = set()
    for php in (root / "app").rglob("*.php"):
        rel = php.relative_to(root / "app").with_suffix("")
        modern.add("Fisharebest\\Webtrees\\" + str(rel).replace("/", "\\"))
    listing = subprocess.run(
        ["git", "-C", str(root), "ls-tree", "-r", "--name-only", TAG_22, "app/"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.splitlines()
    legacy = {
        "Fisharebest\\Webtrees\\" + line[len("app/") : -len(".php")].replace("/", "\\")
        for line in listing
        if line.endswith(".php")
    }
    return modern, legacy


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_WEBTREES
    problems: list[str] = []

    files = sorted(MODULE.rglob("*.php"))
    if not files:
        print(f"no PHP files under {MODULE}")
        return 1

    modern, legacy = webtrees_classes(root)

    for path in files:
        source = path.read_text()
        code = strip_php(source)
        problems += check_brackets(path, code)
        problems += check_unused_imports(path, source, code)

        in_compat = path.parent.name == "Compat"
        for name in re.findall(r"^use (Fisharebest\\Webtrees\\[\w\\]+);", source, re.M):
            if name not in modern and name not in legacy:
                problems.append(f"{path.name}: `{name}` exists in neither version")
            elif not in_compat and name not in modern:
                problems.append(f"{path.name}: `{name}` is 2.2-only - belongs in Compat/")
            elif not in_compat and name not in legacy:
                problems.append(f"{path.name}: `{name}` is 2.3-only - belongs in Compat/")

    for problem in problems:
        print(problem)

    print(f"\n{len(files)} files checked, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
