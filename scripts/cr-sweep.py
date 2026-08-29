#!/usr/bin/env python3
"""Sweep a whole checkout for the *class* a review finding belongs to.

    cr-sweep.py --base origin/main                  # derive the classes from the diff
    cr-sweep.py 'is deprecated' 'at all'             # sweep phrases you were handed
    cr-sweep.py --base main --exempt src/legacy 'old_name'

A finding names one site. The defect is almost always a class with more members, and fixing the
named site leaves the rest to be found by the next review pass -- one per hour, with a CI run
each. This exists so the class is swept in the same commit as the instance.

Two things it does that hand-rolled greps kept getting wrong:

* **Flattens whitespace before matching.** A phrase wrapped across a line break does not match
  a plain grep, and prose is where these defects live. Offsets are mapped back to real line
  numbers, so every hit still points somewhere you can open.
* **Looks everywhere by default.** Not the file the finding named: `src`, `tests`, `docs`,
  `scripts`, the workflows and the root markdown. Most members of a reported class turn up in
  files that review never opened.

With `--base`, the patterns are derived rather than guessed: every identifier the diff *deleted*
and every quoted phrase it removed becomes a pattern, so a name or a sentence the change was
supposed to retire is reported wherever it still stands.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys

SUFFIXES = {'.py', '.md', '.yml', '.yaml', '.toml', '.txt', '.sh', '.cfg', '.ini'}
ROOTS = ('src', 'tests', 'docs', 'scripts', '.github')
SKIP = ('.venv', 'node_modules', '.git', 'dist', 'build', '__pycache__', '.measure', '.tox')

#: an identifier worth chasing: long enough not to match everything, and not a keyword
IDENTIFIER = re.compile(r'\b[a-z_][a-z0-9_]{5,}\b|\b[A-Z][A-Za-z0-9_]{5,}\b')
NOISE = frozenset(
    """
    import return assert lambda except finally global nonlocal continue
    self kwargs args request response settings default defaults value values
    method function module package version
    """.split()
)


def files(exempt: tuple[str, ...]) -> list[pathlib.Path]:
    """Every text file worth searching, minus what the caller excused."""
    found: list[pathlib.Path] = []
    for root in ROOTS:
        base = pathlib.Path(root)
        if base.is_dir():
            found += [p for p in base.rglob('*') if p.is_file() and p.suffix in SUFFIXES]
    found += [p for p in pathlib.Path().glob('*') if p.is_file() and p.suffix in SUFFIXES]
    return sorted(
        {
            p
            for p in found
            if not any(part in SKIP for part in p.parts)
            and not any(p.as_posix().startswith(e) for e in exempt)
        }
    )


def removed_from_the_diff(base: str) -> list[str]:
    """Identifiers and quoted phrases the diff took away, as patterns to hunt for.

    Only deletions: a name the change *added* is supposed to be everywhere, and reporting it
    would bury the handful of names that are supposed to be nowhere.
    """
    try:
        diff = subprocess.run(  # noqa: S603 - a git invocation with a caller-supplied ref
            ['git', 'diff', '-U0', f'{base}...HEAD'],  # noqa: S607 - git from PATH is the point
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    except subprocess.CalledProcessError as error:
        sys.exit(f'cannot diff against {base}: {error.stderr.strip()}')

    gone, kept = set(), set()
    for line in diff.splitlines():
        if line.startswith('-') and not line.startswith('---'):
            gone |= {m.group(0) for m in IDENTIFIER.finditer(line)}
        elif line.startswith('+') and not line.startswith('+++'):
            kept |= {m.group(0) for m in IDENTIFIER.finditer(line)}
    # a name on both sides was moved or reworded, not retired
    return sorted(n for n in gone - kept if n.lower() not in NOISE)


def sweep(patterns: list[str], exempt: tuple[str, ...]) -> int:
    """Report every hit, grouped by pattern. Returns the number of patterns that matched."""
    hits: dict[str, list[tuple[str, int, str]]] = {p: [] for p in patterns}
    compiled = [(p, re.compile(p, re.IGNORECASE)) for p in patterns]

    for path in files(exempt):
        raw = path.read_text(errors='replace')
        flat = re.sub(r'\s+', ' ', raw)
        # where each line begins once the file is flattened, so an offset becomes a line number
        marks, offset = [], 0
        for number, line in enumerate(raw.splitlines(), 1):
            marks.append((offset, number))
            offset += len(re.sub(r'\s+', ' ', line + '\n'))

        def line_of(at: int, marks: list[tuple[int, int]] = marks) -> int:
            found = 1
            for start, number in marks:
                if start > at:
                    break
                found = number
            return found

        for pattern, regex in compiled:
            for match in regex.finditer(flat):
                context = flat[max(0, match.start() - 55) : match.start() + 75].strip()
                hits[pattern].append((path.as_posix(), line_of(match.start()), context))

    matched = 0
    for pattern in patterns:
        found = hits[pattern]
        if not found:
            continue
        matched += 1
        print(f'\n### {pattern}  ({len(found)} in {len({f for f, _, _ in found})} files)')
        for name, number, context in found:
            print(f'  {name}:{number}  …{context}…')

    silent = [p for p in patterns if not hits[p]]
    if silent:
        print(f'\n### nothing left: {", ".join(silent)}')
    return matched


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('patterns', nargs='*', help='regexes or plain phrases to hunt for')
    parser.add_argument('--base', help='derive the patterns from what this diff deleted')
    parser.add_argument(
        '--exempt',
        action='append',
        default=[],
        metavar='PREFIX',
        help='a path prefix where the pattern is legitimately correct; repeatable',
    )
    args = parser.parse_args()

    patterns = list(args.patterns)
    if args.base:
        derived = removed_from_the_diff(args.base)
        print(f'# {len(derived)} name(s) this diff removed and nothing added back')
        patterns += [rf'\b{re.escape(name)}\b' for name in derived]
    if not patterns:
        parser.error('give a pattern, or --base to derive them')

    matched = sweep(patterns, tuple(args.exempt))
    print(f'\n# {matched} of {len(patterns)} pattern(s) still have hits to triage')
    return 0


if __name__ == '__main__':
    sys.exit(main())
