---
allowed-tools: Bash(bash:*)
argument-hint: 109
description: The unresolved findings, with the comment id to reply to
---

## Open threads on pull request $ARGUMENTS

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/coderabbit/scripts/cr-threads.sh" $ARGUMENTS`

## Your task

List what is still open and what each one would actually break.

Answer every one before merging — a thread left unanswered is a finding
nobody decided about. Where you disagree, say why in the thread rather than
resolving it silently:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/coderabbit/scripts/cr-reply.sh" <pr> <comment-id> "Confirmed and fixed — …"
```

And before replying, sweep your own diff for the finding's class
(`/cr-sweep`): the reviewer reports one instance per pass, so answering only
the line it named hands back the same defect from another file next round.
