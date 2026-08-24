#!/usr/bin/env python3
"""Fail if the documentation cites something that does not exist.

Two classes of citation rot, both silent because nothing in CI reads prose:

  1. An invariant id (CORE-*/SUB-*/RESIDUAL-*/ASSUME-*) cited by one document
     but not defined in 04-GUARANTEES-AND-RESPONSIBILITIES.md.
  2. A test name cited as evidence in 04 that no longer exists in the suite —
     the failure mode that makes an evidence column worse than no evidence.

Run from the repo root:  python3 .github/scripts/check-doc-citations.py
"""
import glob
import os
import re
import sys

ID = r"(?:CORE-[A-Z]+-\d+|SUB-\d+|RESIDUAL-\d+|ASSUME-\d+)"
GUARANTEES = "documentation/04-GUARANTEES-AND-RESPONSIBILITIES.md"


def read(path):
    # newline='' so a CRLF file is neither rejected nor rewritten
    with open(path, "r", newline="") as handle:
        return handle.read()


def defined_ids(text):
    """An id is DEFINED by a `### <id>` heading or by being a table row's first cell."""
    found = set(re.findall(rf"^#{{2,6}}\s+`?({ID})`?", text, re.M))
    found |= set(re.findall(rf"^\|\s*`({ID})`\s*\|", text, re.M))
    return found


def cited_ids(text):
    return set(re.findall(rf"`({ID})`", text))


def main():
    if not os.path.exists(GUARANTEES):
        print(f"FAIL: {GUARANTEES} is missing")
        return 1

    guarantees = read(GUARANTEES)
    known = defined_ids(guarantees)
    if not known:
        print(f"FAIL: no invariant ids defined in {GUARANTEES}")
        return 1

    problems = []

    # 1. every cited id resolves
    docs = ["README.md"] + sorted(glob.glob("documentation/*.md"))
    for path in docs:
        for ident in sorted(cited_ids(read(path)) - known):
            problems.append(f"{path}: cites {ident}, which {GUARANTEES} does not define")

    # 2. every test cited as evidence still exists
    tests = set()
    for path in glob.glob("validators/**/*.ak", recursive=True) + glob.glob("lib/**/*.ak", recursive=True):
        tests |= set(re.findall(r"^\s*(?:test|bench)\s+([a-z0-9_]+)\s*\(", read(path), re.M))

    # Only the "Evidence" column, of tables that declare one. Convention: inside an
    # Evidence cell a backticked name IS a test name, so anything else there is a defect.
    evidence_col = None
    for row in guarantees.splitlines():
        if not row.lstrip().startswith("|"):
            evidence_col = None
            continue
        cells = [c.strip() for c in row.strip().strip("|").split("|")]
        if any(c.lower() == "evidence" for c in cells):
            evidence_col = next(i for i, c in enumerate(cells) if c.lower() == "evidence")
            continue
        if evidence_col is None or set("".join(cells)) <= set("-: "):
            continue
        if evidence_col >= len(cells):
            continue
        # any backticked token here must be a test — the convention makes a
        # malformed citation (a typo, a stale name, a field name) fail loudly
        for name in re.findall(r"`([^`]+)`", cells[evidence_col]):
            if name not in tests:
                problems.append(f"{GUARANTEES}: evidence cites '{name}', which is not a test in this suite")

    for problem in problems:
        print("FAIL:", problem)
    if problems:
        print(f"\n{len(problems)} citation problem(s).")
        return 1

    print(f"ok: {len(known)} ids defined, all citations resolve, all evidence tests exist")
    return 0


if __name__ == "__main__":
    sys.exit(main())
