---
allowed-tools: Bash(bash:*)
argument-hint: 109
description: Ask for a FULL review and wait it out, until the head is covered
---

## Waiting on pull request $ARGUMENTS

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/coderabbit/scripts/cr-await.sh" $ARGUMENTS`

## Your task

This one takes minutes, not seconds: it asks for a full review, waits out rate
limits, and keeps reading until the walkthrough reaches the head — then holds
a little longer for late findings.

Report what it concluded. If it came back rate limited, say when the limit
resets rather than asking again: a second request while one is in flight
spends a slot for nothing, and the reply itself is edited in place from
acceptance to refusal, so only the walkthrough reaching the head is proof.

Never ask for a review while the branch has conflicts or red CI. That spends
the scarce allowance on a diff the reviewer cannot read properly.
