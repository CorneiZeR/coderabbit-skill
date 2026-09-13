---
allowed-tools: Bash(bash:*)
argument-hint: 109
description: Is the head commit actually reviewed, and what is still open
---

## Where pull request $ARGUMENTS stands

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/coderabbit/scripts/cr-status.sh" $ARGUMENTS`

## Your task

Answer the only question this asks: **is the head reviewed?** A green check is
not evidence — the check reports `pass` for "review completed", "rate limited"
and "skipped" alike. The proof is the walkthrough's `up to <sha>` line
matching the head, which is what this compares.

If they differ, say so plainly: the latest commits are unreviewed whatever the
check says, and asking for a full review (`/cr-await`) is the next step rather
than merging.
