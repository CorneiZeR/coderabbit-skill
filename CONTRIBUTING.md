# Contributing

This repository holds an operating procedure, not a library. What it accepts and
what it refuses follow from that.

## A rule needs a failure behind it

`SKILL.md` opens with a claim — *every rule here exists because its absence cost
something on a real release stack* — and `WHY-IT-EXISTS.md` is that claim,
itemised. So a proposed rule is judged on its provenance before its wording:

- **What went wrong**, concretely. The command, the output, the moment it was
  believed. "This seems safer" is a preference; preferences belong in your own
  configuration rather than here.
- **What it cost.** A wasted review slot, a merged unreviewed head, four hours
  of a waiter that was alive and doing nothing.
- **Why the existing rules did not catch it.** If one did and was skipped, the
  fix is usually to make the rule enforceable rather than to add another.

A rule that cannot name a cost is the argument for deleting it, not for writing
it down.

## Add the provenance in the same change

Every rule lives in two places: the instruction in `SKILL.md`, and the failure
it came from in `WHY-IT-EXISTS.md`, ending with a `→` pointer back to the
section it belongs to. A pull request that adds one and not the other is
incomplete.

## Scripts

`scripts/` runs under `set -euo pipefail` against `gh`, and everything in it has
to survive the ways that combination lies:

- **A failed read is not an answer.** An empty string, a `null`, a zero count —
  each has to be distinguished from a real result before anything is concluded
  from it. `jq -s add` on an empty stream is `null`; `gh pr checks` exits 8 when
  anything is pending; `pgrep -fc` does not exist on macOS.
- **Reads may be retried; writes may not.** `cr_gh` refuses to retry anything
  carrying `-f`/`-F` or a non-`GET` method, because a retried write is a second
  write, and that has been measured posting a duplicate review request.
- **Guards live in the command they guard.** A check whose only effect is
  output is not a check: it was printed, ignored, and the thing it forbade
  happened anyway.
- **macOS first.** There is no `flock` here, `lockf` refuses with exit 75, and
  zsh aborts a command whose glob matches nothing — quote the patterns.

Document a bug in these scripts *and* fix it in the same change. A note explains
the next failure; the patch prevents it.

## The manifest

`SHA256SUMS.txt` covers the files a user installs. Regenerate it whenever one of
them changes:

```shell
shasum -a 256 SKILL.md README.md WHY-IT-EXISTS.md CODE_OF_CONDUCT.md \
  CONTRIBUTING.md SECURITY.md LICENSE references/config.md scripts/* > SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
```

It excludes itself and `.github/`. A stale manifest is worse than none, because
it reads as a check that passed.

## Style

British-neutral English, sentences that survive being read once, and no
enthusiasm. Numbers are measured rather than estimated, and a claim a reader can
count — a line count, a method count, a number of files — is either checked at
the moment of writing or left out.

## Reporting a problem instead

An issue is welcome for anything you cannot fix yourself, and the two templates
ask for the same thing this page does: what happened, what it cost, and what you
expected instead. Security issues go through `SECURITY.md`, not through an
issue.
