---
allowed-tools: Bash(bash:*)
argument-hint: [--light] [--uncommitted]
description: Review this working tree with the CLI — its own allowance, no pull request
---

## The local pass

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/coderabbit/scripts/cr-local.sh" $ARGUMENTS`

## Your task

Report the findings, most serious first, in the language the person is
speaking. For each one, say what would actually go wrong — not the rule it
breaks.

Then do the thing this skill exists for: **treat every finding as a sample of
a class.** Reduce it to its predicate — not "line 12 says X" but "prose states
a single-implementation detail where several now exist" — and sweep the whole
tree for that predicate before fixing anything (`/cr-sweep`). A finding fixed
only where it was reported comes back next round, in another file, costing
another review out of the hourly allowance.

This pass draws on its OWN allowance, separate from the pull request's. Run it
again after a round of fixes: a round of fixes is a new draft, and on one pull
request eleven of thirteen findings were in the files that pull request had
just written.
