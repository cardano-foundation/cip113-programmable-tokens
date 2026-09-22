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
QUALIFIED = re.compile(
    r"\b((?:lib|validators|env)/[A-Za-z0-9_/]+(?:\.test)?\.ak):(\d+)(?:-(\d+))?\b"
)

# The continuation form: prose names a file once, then cites further lines in it
# as a bare `:NN` or `:NN-MM`. These rot exactly like the qualified form and are
# the MAJORITY of citations in some documents, so a checker that skips them
# reports "all citations resolve" over a document full of dead anchors.
# Resolved against the nearest qualified path ON THE SAME LINE, and only
# there: a heuristic that reaches back across lines binds silently to whatever
# file happened to be named last, which is how `:74` came to be checked against
# a 217-line file when the author meant a 72-line one. A bare anchor with no
# path beside it is reported, not guessed at.
BARE = re.compile(r"`:(\d+)(?:-(\d+))?`")

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


NOISE = {"}", ")", "]", "},", ")}", "})", "{", "(", "[", "and {", "or {", ") {"}


def is_empty_span(lines, start, end):
    """True iff the span carries no code a reader could be pointed at.

    Blank lines, bare delimiters (opening ones too -- `) -> Bool {` is no more
    useful as a citation target than the `}` that closes it), and spans that
    are nothing but comment. A comment-only span is occasionally deliberate,
    but far more often it is a citation that used to name a function body and
    now names the doc comment above it.
    """
    for raw in lines[start - 1:end]:
        stripped = raw.strip()
        if not stripped or stripped in NOISE:
            continue
        return False
    return True


def is_comment_only(lines, start, end):
    """True iff the span is nothing but comment.

    Sometimes deliberate -- prose legitimately points at a rationale written in
    a doc comment. More often it is a citation that named a function body and
    now names the comment above it. Reported, never fatal: the distinction
    needs a reader, and a gate nobody can make green gets deleted.
    """
    saw = False
    for raw in lines[start - 1:end]:
        stripped = raw.strip()
        if not stripped or stripped in NOISE:
            continue
        if stripped.startswith("//"):
            saw = True
            continue
        return False
    return saw


def main():
    problems = []
    warnings = []
    checked = 0

    for doc in prose_files():
        with open(doc, "r", newline="") as handle:
            text = handle.read()
        for lineno, line in enumerate(text.splitlines(), 1):
            current_path = None
            # Qualified citations set the context bare ones resolve against, so
            # walk both in one pass, qualified first on any given line.
            spotted = [
                (m.start(), m.group(0), m.group(1), m.group(2), m.group(3))
                for m in QUALIFIED.finditer(line)
            ]
            qualified_spans = [(m.start(), m.end()) for m in QUALIFIED.finditer(line)]
            for m in BARE.finditer(line):
                # a bare match inside a qualified one is not a separate citation
                if any(a <= m.start() < b for a, b in qualified_spans):
                    continue
                spotted.append((m.start(), m.group(0), None, m.group(1), m.group(2)))
            for _pos, cite_text, qualified_path, start_s, end_s in sorted(spotted):
                if qualified_path is not None:
                    current_path = qualified_path
                path = qualified_path or current_path
                if path is None:
                    warnings.append(
                        (
                            f"{doc}:{lineno}",
                            cite_text,
                            "bare anchor with no file path on the same line -- "
                            "qualify it so it cannot bind to the wrong file",
                        )
                    )
                    continue
                start = int(start_s)
                end = int(end_s) if end_s else start
                checked += 1
                lines = source_lines(path)
                where = f"{doc}:{lineno}"
                cite = cite_text if qualified_path else f"{cite_text} (-> {path})"
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
                        (where, cite, "EMPTY: cited span is blank or delimiters only")
                    )
                elif is_comment_only(lines, start, end):
                    warnings.append(
                        (where, cite, "cited span is comment only -- may have "
                         "drifted off the code it names")
                    )

    print(f"checked {checked} line citations across {len(prose_files())} prose files")

    if warnings:
        print(f"\n{len(warnings)} warning(s) -- not fatal:\n")
        for where, cite, why in warnings:
            print(f"  {where}\n    {cite}  ->  {why}")

    if not problems:
        print("\nno broken citations")
        return 0

    print(f"\n{len(problems)} bad citation(s):\n")
    for where, cite, why in problems:
        print(f"  {where}\n    {cite}  ->  {why}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
