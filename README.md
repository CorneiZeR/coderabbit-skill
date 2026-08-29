<h1 align="center">coderabbit-skill</h1>

<p align="center"><em>“A green check is not a review. The only proof is the SHA.”</em></p>

<p align="center">An operating procedure for <strong>CodeRabbit</strong> reviews, as a skill for coding agents.<br>
What counts as evidence that a review happened, which of its three surfaces to spend,<br>
and how to answer what it finds.</p>

---

## What this is

CodeRabbit reviews pull requests through a GitHub App. Driving it well is not hard, but it is full
of failure modes that look exactly like success: a check-run that reports `pass` for *"Review
skipped"*, a walkthrough timestamp that moves because of an automatic pass while the full review you
asked for was refused, a thread reply claiming a fix that never landed in the diff.

This skill is the procedure that survives those. It is `SKILL.md` plus seven scripts that enforce
the parts a human — or an agent — reliably forgets.

## What it teaches

- **A green check is not a review.** The evidence is the SHA in the walkthrough (`up to <sha>`),
  compared against the head. And the SHA alone does not say *which* pass covered it: an incremental
  review leaves the same line as a full one.
- **A finding is a sample, not the population.** CodeRabbit reports what it happened to look at. The
  same defect sits in files that pass never opened, and comes back next pass as new information —
  one slot out of the hourly allowance, one CI run and one wait each time. Sweep the class in the
  same commit as the instance.
- **The verdict is held, not declared.** Inline threads and the pre-merge table arrive *around* the
  walkthrough, not before it. A merge went out 93 seconds after the SHA matched, and the evidence
  read clean afterwards — which is what made it dangerous.
- **One waiter, ever.** Two waiters on one PR sent four `@coderabbitai full review` comments in
  three minutes, each accepted, each spending the allowance. This is now a lock, not a note: a
  guard whose only effect is output is not a guard.
- **Never push while a review you asked for is in flight.** The pass reads the head as it was when
  the request was accepted; the slot is spent and the head stays uncovered. A rate-limit window is
  not idle time — it is the moment for a local pass, which comes out of a different column.
- **Never say "fixed in `<sha>`" without reading that sha's diff.** A commit message that describes
  the repair proves nothing; grep the pushed commit for the change itself.

The whole procedure, with the mechanism behind each rule: [`SKILL.md`](SKILL.md). Where the rules
came from: [`WHY-IT-EXISTS.md`](WHY-IT-EXISTS.md).

## Three surfaces, three allowances

Pull request reviews, the `coderabbit` CLI and the IDE extension reach the same reviewer on
**separate hourly allowances**. That is the whole reason to choose deliberately: a finding caught
locally costs nothing from the pull request's column, and the pull request's column is the one that
gates a merge.

## Install

The repository root *is* the skill directory, so one clone installs it:

```bash
git clone https://github.com/CorneiZeR/coderabbit-skill.git ~/.claude/skills/coderabbit
```

Prerequisites: [`gh`](https://cli.github.com) authenticated against the repositories you review,
`python3` for `cr-sweep.py`, and the [`coderabbit` CLI](https://docs.coderabbit.ai/cli) for
`cr-local.sh`. Two environment variables, both optional:

| variable | effect |
| --- | --- |
| `CR_REPO` | `owner/repo` to act on; defaults to the current checkout's `origin` |
| `CR_LOGIN` | which `gh` account must be the one writing; defaults to the repository's owner |
| `CR_SETTLE` | seconds to hold after the SHA matches, re-reading for late findings (default 180) |

A machine with several `gh` logins has a single global "active account" pointer that has been
observed to flip mid-run, so every script asserts the identity before it writes — see
`cr_ensure_account` in [`scripts/_common.sh`](scripts/_common.sh).

## Scripts

They live in `scripts/`; `SKILL.md` refers to them by bare name, so either call them by path or put
that directory on `PATH`.

| script | what it does |
| --- | --- |
| `cr-status.sh` | whether a PR is genuinely reviewed and what is still open; exit 0/1, so it can gate a merge |
| `cr-await.sh` | wait until CodeRabbit has actually run *this* request, ride out rate limits, hold for late findings |
| `cr-threads.sh` | unresolved findings, with the comment id to reply to |
| `cr-nits.sh` | everything said outside a thread — pre-merge checks and collapsed nitpicks, the ones that get missed |
| `cr-reply.sh` | reply inside a finding's thread, which is where an answer belongs |
| `cr-local.sh` | a CLI review of the working tree, out of the CLI's own allowance |
| `cr-sweep.py` | sweep the whole checkout for the *class* a finding belongs to, before answering it |

`references/config.md` covers `.coderabbit.yaml` — the settings worth knowing, and why a change to
it only takes effect once merged into the base branch.

## A note on delivery

[`benjamin-plus`](https://github.com/JetBrains/benjamin-plus-skill) measured that a skill shipped as
a discoverable folder saves nothing, because agents burn a median three steps finding `SKILL.md`,
and shipped itself as an injected payload instead. That is not available here: this is ~30× the size
and carries executables. So it stays a skill folder, and the mitigation is the frontmatter
`description` — written to name the situations that should trigger it (a PR waiting on CodeRabbit, a
review that looks stuck, a merge decision, an edit to `.coderabbit.yaml`) rather than the topic.

## Integrity

`SHA256SUMS.txt` pins every shipped file:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

Regenerate it in the same commit as any content change — a stale checksum file is a false claim, not
a missing one.

## Feedback

Found a rule that misfires, a CodeRabbit behaviour that has since changed, or a failure mode this
procedure does not cover? [Open an issue](../../issues) — ideally with the pull request and the
comment that showed it.

## License

MIT.
