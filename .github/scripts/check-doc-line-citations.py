#!/usr/bin/env python3
"""Fail if the documentation cites a source line that does not exist.

Prose cites the validators by `path/file.ak:NN` or `path/file.ak:NN-MM`. Nothing
in CI reads prose, so those anchors drift silently every time a validator is
edited: the citation still looks authoritative, and the line it names has moved
or stopped existing. A reader who follows one lands on a closing brace and
concludes the rule is not enforced.

Three classes, in descending severity:

  1. MISSING   -- the cited file does not exist.
  2. OUT-OF-RANGE -- the line number is past the end of the file. The citation
     cannot be right, and nothing else needs to be known to say so.
  3. EMPTY     -- every cited line is blank, or is nothing but a closing
     delimiter. Almost always drift: a citation that once named a function body
     and now names the brace after it.

What this CANNOT catch is a citation that is in range and non-empty but names
the wrong code. That still needs a reader. The point of the check is to make the
mechanical half free, so review attention goes to the half that needs judgment.

Run from the repo root:  python3 .github/scripts/check-doc-line-citations.py
"""
import os
import re
import subprocess
import sys

# `lib/foo.ak:12` / `validators/a/b.ak:12-34`, optionally inside backticks.
CITATION = re.compile(r"\b((?:lib|validators|env)/[A-Za-z0-9_/]+\.ak):(\d+)(?:-(\d+))?\b")

def prose_files(cache=[]):
    """Every TRACKED markdown file.

    Tracked only, deliberately: untracked design notes under documentation/
    are local historical records describing shapes the code no longer has, so
    their citations are expected to be stale and repairing them would be wrong.
    CI can only speak for what ships.
    """
    if not cache:
        listed = subprocess.run(
            ["git", "ls-files", "*.md"], capture_output=True, text=True, check=True
        )
        cache.extend(sorted(p for p in listed.stdout.splitlines() if p))
    return cache


def source_lines(path, cache={}):
    if path not in cache:
        if not os.path.exists(path):
            cache[path] = None
        else:
            # newline='' so a CRLF file is neither rejected nor rewritten
            with open(path, "r", newline="") as handle:
                cache[path] = handle.read().splitlines()
    return cache[path]


def is_empty_span(lines, start, end):
    """True iff every line in the span is blank or only a closing delimiter."""
    for raw in lines[start - 1:end]:
        stripped = raw.strip()
        if stripped and stripped not in {"}", ")", "]", "},", ")}", "})"}:
            return False
    return True


def main():
    problems = []
    checked = 0

    for doc in prose_files():
        with open(doc, "r", newline="") as handle:
            text = handle.read()
        for lineno, line in enumerate(text.splitlines(), 1):
            for match in CITATION.finditer(line):
                path, start_s, end_s = match.group(1), match.group(2), match.group(3)
                start = int(start_s)
                end = int(end_s) if end_s else start
                checked += 1
                lines = source_lines(path)
                where = f"{doc}:{lineno}"
                cite = match.group(0)
                if lines is None:
                    problems.append((where, cite, f"MISSING: no such file {path}"))
                elif start < 1 or end > len(lines):
                    problems.append(
                        (where, cite, f"OUT-OF-RANGE: {path} has {len(lines)} lines")
                    )
                elif start > end:
                    problems.append((where, cite, "INVERTED: start line is after end line"))
                elif is_empty_span(lines, start, end):
                    problems.append(
                        (where, cite, "EMPTY: cited span is blank or a closing delimiter only")
                    )

    print(f"checked {checked} line citations across {len(prose_files())} prose files")
    if not problems:
        print("all citations resolve")
        return 0

    print(f"\n{len(problems)} bad citation(s):\n")
    for where, cite, why in problems:
        print(f"  {where}\n    {cite}  ->  {why}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
