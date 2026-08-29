# Why each rule exists

`SKILL.md` opens with a claim: *"Every rule here exists because its absence cost something on a real
release stack."* This file is that claim, itemised. No rule here was reasoned out in advance; each
one is the scar of a specific failure, and most of them are failures that looked like success at the
time.

Read it as provenance rather than evidence. There is no A/B measurement behind this skill — what
there is instead is a list of things that went wrong once, in a way specific enough to write down.

## The evidence rules

**A green check is not a review — the proof is the SHA.**
The `CodeRabbit` check-run reports `pass` for *"Review completed"*, *"Review rate limited"* and
*"Review skipped"* alike. Reading the check instead of the walkthrough means merging on the word of
a signal that cannot say no.
→ `SKILL.md`, *The one rule that matters*

**The exit condition is CodeRabbit's answer to *this* request, nothing else.**
Two weaker conditions were tried, and both merged an unreviewed head. *"The head is covered"* — an
incremental pass leaves the same `up to <sha>` line as a full one, so a full review that never ran
looks identical to one that did. *"The walkthrough changed after I asked"* — every push triggers an
automatic incremental review that edits the same walkthrough, so a request refused for rate limits
still sees the timestamp move while the refusal stays invisible.
→ `scripts/cr-await.sh`, header

**Hold the verdict after the SHA matches.**
Inline threads and the pre-merge table arrive *around* the walkthrough rather than before it, and on
a large diff they have been seen to land after it. A merge went out 93 seconds after the walkthrough
reached the head; read afterwards, its evidence was genuinely clean. The procedure had been followed
and the window between "reviewed" and "everything a review posts" was simply assumed to be zero.
`CR_SETTLE` (180s by default) is that assumption removed.
→ `SKILL.md`, *The walkthrough at head is not the last thing a pass posts*

**Ask which threads are open, never which comments are recent.**
A review posts its comments in one burst, so a `created_at` filter depends on knowing when the last
round was — and a guess there drops a whole batch in silence. In one case the missed batch contained
a warning that CI would not install a dependency the new tests needed. The legs went red for exactly
that an hour later; the reviewer had said so before CI ran.
→ `SKILL.md`, *Ask which threads are open*

**Three kinds of finding never open a thread.**
Pre-merge checks are a table in the walkthrough and fail as *warnings* — no check-run goes red, no
thread opens. Nitpicks and outside-diff-range comments live in the **review** object
(`pulls/{pr}/reviews`), a different endpoint from the walkthrough issue comment. A script that reads
only the walkthrough is blind to that class by construction — not unlucky on one pull request, blind
on every one. Measured: `cr-nits.sh` reported "none" while a Major outside-diff finding and a nitpick
sat unread in the review body the whole time. Worse, its single-source version could not even reach
its own "none" fallback: the first marker check exited the script.
→ `SKILL.md`, *What is not a thread*; `scripts/_common.sh`, `cr_latest_review_body`

## The allowance rules

**A finding is a sample, not the population.**
CodeRabbit reviews a diff and reports what it happened to look at. The other members of the same
defect sit in files that pass never opened and come back on the *next* pass, in a different file,
phrased as new information. The cost is not the fix, it is the round trip: one review out of the
hourly allowance, one CI run and one wait, each time. Seen repeatedly — a phrase reported in a source
comment and fixed there, then reported word for word two passes later in a documentation page one
directory over.
→ `SKILL.md`, *A finding is a sample*; `scripts/cr-sweep.py`

**One waiter, ever.**
Two waiters on one pull request sent four `@coderabbitai full review` comments inside three minutes,
each accepted, each a review that had to run past the included allowance. The skill had carried the
advice — *look for one already running and kill it* — for a while, and the check kept being written
into the same command that starts the waiter: it ran in the background, printed `live waiters: 1`,
and started a second one anyway, because nothing read the line. **A guard whose only effect is
output is not a guard.** It is a per-PR `lockf` now. (`flock` is not on macOS; `lockf` refuses with
exit **75**, measured, not the 73 its man page prose implies.)
→ `SKILL.md`, *One waiter, ever*; `scripts/cr-await.sh`

**Never push while a review you asked for is in flight.**
A review reads the head as it was when the request was *accepted*. Push after that and the pass lands
on the old SHA: the slot is spent, the walkthrough moves, and the head is still uncovered. Seen twice
in one day, both times the same way — the waiter was holding out a rate limit, the wait looked like
idle time, so more fixes went in, and each push cost a full hour re-reading what the last slot had
already read. The corollary: a refusal is a local pass, every time, because the CLI comes out of a
different column.
→ `SKILL.md`, *Never push while a review is in flight*

**One slot per push, not per pull request.**
Every push triggers an automatic review, so on a stack — review, fix, review, fix — the allowance is
gone quickly, and the reviews you lose are the ones on your fixes.
→ `SKILL.md`, *Budget*

**Rate limits do not resume on their own, and the unit changes.**
*"Review rate limited"* is not terminal — but nothing restarts it either; it has to be triggered
again. And the interval it names is in seconds, minutes or hours depending on how close the next slot
is. A parser that only knows minutes matches nothing on *"available in 33 seconds"*, and under
`set -euo pipefail` that empty match took the whole script down mid-wait.
→ `SKILL.md`, *Rate limits*; `cr_wait_seconds`

## The plumbing rules

Three of these are bash and GitHub, not CodeRabbit — and each one failed in a way that read as an
answer about the review.

**Access is not identity.**
A machine with several `gh` logins has one **global** active-account pointer, shared by every `gh`
invocation system-wide, and it has been observed to flip between two calls seconds apart with nothing
in this skill touching it. The check used to be *"can the active account read this repository"* — and
several accounts can: a review was requested on a personal repository by a second account of the same
person's, which is a write to a public thread under a name nobody chose. The gate has to live in the
same command as the write, for the same reason the waiter lock does.
→ `SKILL.md`, *The wrong `gh` account*; `scripts/_common.sh`, `cr_ensure_account`

**`local a="$1" b="${a%%/*}"` does not work.**
Bash declares every name in a `local` first — emptying it — and assigns afterwards, so `b` was
derived from an empty `a`. The owner came out blank, and the identity check fell through to the
access-only path in silence. Found only because the fast path prints the login it is using.
→ `scripts/_common.sh`, `cr_ensure_account`

**github.com fails transiently, and `set -e` turns that into a lie.**
`gh` answers `HTTP 503 No server is currently available` in bursts. Under `set -euo pipefail` one
unlucky call kills the caller, and what you see depends on where it died: `cr-await.sh` died on the
very request it exists to post — nothing asked, nothing waited for — which reads as "the review was
refused"; `cr_repo` said *"not in a GitHub checkout"* from inside a checkout; `cr-reply.sh` failed
three of four replies in a batch, so three findings looked answered and were not. Retries are reads
only: github.com once answered 503 *after* accepting a `@coderabbitai full review` comment, and the
retry posted it again — two requests, the duplicate consuming the next slot.
→ `SKILL.md`, *github.com fails transiently*; `scripts/_common.sh`, `cr_gh`

**A waiter needs a git checkout, or it lies quietly.**
Started from a scratch directory, every `gh pr` call fails with *"failed to run git: fatal: not a git
repository"* — which is not fatal to the loop. It read that failure as a check list with nothing
pending, printed `CI settled: pass=0 fail=0`, and walked on.
→ `SKILL.md`, *One waiter, ever*

**Not every 404 is the account.**
A review comment is addressed *without* the pull request number: `repos/O/R/pulls/comments/<id>`
works, `repos/O/R/pulls/<pr>/comments/<id>` is a flat 404 no matter who is signed in. The number
belongs on the listing and nowhere else — which is what makes it easy to misread as a permissions
gap. Check the shape of the path first; the account story is the right one only when a correctly
shaped call returns nothing.
→ `SKILL.md`, *The wrong `gh` account*

## The answering rules

**Never say "fixed in `<sha>`" without reading that sha's diff.**
A reply in a thread is a claim to a reviewer, checked by nobody else. Seen once, and once is enough:
a commit's subject named the repair, its body explained the mechanism, the thread reply said the
same — and the diff contained only a new test. The edit had never landed. CodeRabbit accepted the
reply, resolved the thread, the pull request merged, and the finding was still true in the merged
code. A file-level check is too coarse: that commit *did* touch that file, with something else.
→ `SKILL.md`, *Never say "fixed in `<sha>`"*

**Say what you verified, not that you fixed it.**
And when a fix cannot be proved, name the unobservable part instead of producing a proof. A claim
that overstates is worse than a gap that is named: the gap gets tracked, the claim closes the thread.
→ `SKILL.md`, *Answering findings*
