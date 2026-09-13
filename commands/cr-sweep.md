---
allowed-tools: Bash(python3:*)
argument-hint: --base origin/main [--exempt path]
description: Find every other place a finding's class lives — free, no allowance
---

## The sweep

!`python3 "${CLAUDE_PLUGIN_ROOT}/skills/coderabbit/scripts/cr-sweep.py" $ARGUMENTS`

## Your task

Treat every hit as a finding. It costs no allowance at all, which is why it
runs before pushing rather than after a reviewer has spent a round telling you
the same thing in a different file.

It searches what the diff DELETED — every name the change meant to retire —
and reports wherever one still stands: sources, tests, documentation, scripts,
workflows, the changelog. Whitespace is flattened first, so a phrase broken
across a line break still matches.

Some places are entitled to the old phrase — the module that IS the thing
being described, a section documenting its own release. Name them with
`--exempt` so the exemption is a decision on the record rather than a silence.
