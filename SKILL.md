---
name: coderabbit
description: Working with CodeRabbit reviews — pull request passes (proving a review actually covered the head commit, recovering from rate limits, answering findings in their threads) and local passes with the coderabbit CLI or the IDE extension, which draw on their own hourly allowances and so keep the scarce PR slot for code already cleaned. Use whenever a PR is waiting on CodeRabbit, a review looks stuck or skipped, you want a review before pushing, you are deciding whether a PR is ready to merge, or you are editing .coderabbit.yaml.
---

# CodeRabbit

CodeRabbit reviews pull requests through a GitHub App. This skill is the operating procedure:
what counts as evidence, how the limits behave, and how to answer what it finds.

Every rule here exists because its absence cost something on a real release stack.

## Which surface, and when

Three ways to reach the same reviewer, on **separate hourly allowances** — a pull request review,
a CLI review of a working tree, and the IDE extension. Separate allowances are the whole reason to
choose deliberately: a finding caught locally costs nothing from the pull request's column, and the
pull request's column is the one that gates a merge.

| When                          | What to run                         | Why this one                                                                               |
| ----------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------ |
| code written, nothing pushed  | `cr-local.sh` (CLI)                 | own allowance, no pull request needed, catches the cheap findings before they cost a round |
| about to push                 | `cr-sweep.py --base <ref>`          | free, and no allowance at all — see the next section                                       |
| pull request open, head moved | wait, then one **full review**      | the merge gate; incremental passes cannot stand in for it                                  |
| deciding whether to merge     | `cr-status.sh`, then prove the head | a green check is not a review                                                              |

The order that wastes the least: **write → sweep → local review → fix → push → full review → answer
every thread → prove the head → merge.** Each step removes work from the step after it, and only
the last three spend the scarce allowance.

Two things never to do, both of which spend a slot for nothing: asking for a review while the
branch has conflicts or red CI, and asking again while a review you already asked for is in
flight. The sections below give each of those its own reason.

## A finding is a sample, not the population

**Fix the class, in the same commit, everywhere. Never only the site it named.**

This is the rule that costs the most when it is missed, and it is missed by default, because
answering exactly what you were asked feels like diligence. It is not. CodeRabbit reviews a diff
and reports what it happened to look at, so what you are handed is one member of a set: one
docstring naming a method the change removed, one sentence describing behaviour the change
altered, one comment claiming a flag does more than it does. The other members sit in files that
pass never opened, and they come back on the _next_ pass, in a different file, phrased as new
information.

The cost is not the fix, it is the round trip. Each one spends a review out of an hourly
allowance, a CI run, and a wait — so a mechanical rename can run to dozens of comments across
half a dozen passes, every one of them the same defect wearing a different line number. Seen
repeatedly, in this shape: a phrase is reported in a source comment and fixed there, and two
passes later the identical phrase is reported **word for word** in a documentation page one
directory over.

None of those need a review to find. They need one search that is not aimed at the file named in
the finding.

### The procedure

1. **Reduce the finding to its predicate.** Not "line 12 says X" but _"prose states a
   single-implementation detail where the setting now allows several"_. Not "this docstring
   mentions `old_name`" but _"reference documentation cites a name this change removed"_. The
   predicate is the thing with more instances; the phrase is one of them.

   Getting this wrong is the most common way the sweep still misses. Search the predicate and a
   near-identical variant is caught; search the literal phrase and it is not — including the
   variant _you_ just created, when the fix at the reported site rewrote half the sentence and
   left the false half standing.

2. **Sweep the whole tree for the predicate** — sources, tests, documentation, scripts, the CI
   workflows, the root markdown, the changelog. `cr-sweep.py` does this, and does the two things
   hand-rolled greps keep getting wrong: it flattens whitespace first, so a phrase broken across
   a line break still matches, and it looks everywhere rather than in the file you were pointed
   at.
3. **List the exemptions out loud.** Some places are entitled to the phrase — the module that
   _is_ the thing being described, a historical section using the vocabulary of its own release.
   Pass them as `--exempt` so the list is a decision on the record rather than a silence.
4. **Fix every hit in one commit, and say how many.** A commit message that names the count is
   what tells the next reader the class was swept rather than sampled.

### A change that makes implementations differ invalidates every sentence about the family

The most expensive class this skill has met is not a renamed identifier. It is a **general claim
about a family of implementations that a change makes false for one of them** — and it is
expensive because each instance sits in a different file, reads perfectly well on its own, and
comes back one round at a time.

The shape, from four consecutive rounds on one pull request: a method gained per-implementation
behaviour, and the reviewer found, separately, that the reference page said the unnamed result
means one thing everywhere; that two implementations were described with one reason that fitted
only one of them; that the phrasing said "another one" where the rule is "any"; and that the
exception class's own docstring opened with a claim about "every implementation". Four findings,
four files, one predicate.

So when a change introduces or widens a difference between implementations, sweep for the
**family words** before pushing, and check each hit against every implementation:

- quantifiers — _every_, _all four_, _neither_, _both_, _any_, _always_;
- the family's own noun where the sentence means one member;
- "defaults to", "answers", "means" — verbs that hide a claim about behaviour;
- the _reason_ given for a shared conclusion, which is where two implementations get lumped
  together under one that fits only one of them.

Grep the family word, not the identifier you changed. And read each hit as a _claim about the
implementation you did not touch_ — that is the one the change makes false, and it is the one you
have no reason to open.

### Sweep your own diff for the class, before answering the finding

**A reviewer reports one instance per pass.** It reads a diff, names what it happened to look at,
and stops — so answering the line it named and pushing hands back the same defect from a different
file next round, at the cost of another review out of the hourly allowance, another wait, and
another CI run. Two or three rounds of that is the normal way a mechanical mistake gets fixed one
site at a time.

So before replying: take the finding's predicate and run it over **the whole change**, not the file
it landed in. `git diff <base>...HEAD` is the search space, and the hits inside your own new lines
are the ones that matter most — a defect introduced *while fixing the same defect* is the single
most common thing this pass turns up, and it is invisible from the finding.

Two predicates worth searching every time, because they recur and neither is caught by any gate:

* **A count in prose beside a list.** "these three", "all four", "the two cases below" — a number
  that has to be re-derived by hand whenever the list moves, and nothing fails when it stops being
  true. Search added lines for number words and digits, then check each against what it counts.
  The fix is almost never a corrected number: delete it, and let the list be the count. Where the
  count carries real meaning, pin it with a test that reads it from the list.
* **A pointer standing in for a reason.** "as above", "same as `X`", "see the helper" — fine when
  it refers to a full sentence on the line immediately before, which a reader meets on the way
  past; not fine when it points across the file, because the reader has to go and look, and what
  they find is written about something else. Check every pointer in the diff for *distance*, and
  give the distant ones the one-line invariant they actually need.

And when the finding is about an explanation rather than about code, verify the explanation you
replace it with. **A reason that is checkable and wrong is worse than a vague one** — it stops the
next reader from looking. The cheap check is to delete the suppression or the guard, run the tool,
and read what it actually says; if that does not match the sentence you wrote, the sentence is the
defect.

### A guard is as complete as the branches it was built from

The sweep above looks for other *sites*. This one is about the other *cases*, and it is the
shape that costs the most rounds when the change under review is a **check** — a validator, a
refusal, a "may this be replayed / retried / cached" predicate.

Seen across four passes on one command: a refusal was built from the three loss markers that
existed in the module it guarded. The module lost data in four more ways that left no marker —
a string cut to its cap, a mapping cut to its cap, a sequence cut to its cap, a `datetime`
rendered as text — and each arrived as its own finding, one round apart, all four in a function
that had been read while writing the guard.

The mistake is not skipped reading. It is building the list from **what is already marked**
instead of from what the guarded thing can do. So when the diff adds a check:

1. Open the function it is checking and walk **every `return`**, not the ones with a marker on
   them. Each branch either preserves the property or breaks it; the ones that break it and say
   nothing are the findings you have not had yet.
2. Prefer the invariant to the enumeration. Four of those findings were one property:
   *if the check says nothing was lost, the recorded value equals the input*. One property test
   over generated inputs covers every branch the function has now and every branch it grows,
   and it does not depend on anybody remembering to look. An enumeration is a snapshot of one
   afternoon's reading.
3. Where the property cannot be tested that way, write the enumeration **into the code** as the
   list the check is built from, so the next person edits one place rather than discovering
   there were two.

### Fixing the sentence is not fixing the claim

A finding that says a sentence is false has two fixes, and the cheap one is usually wrong.
Deleting or hedging the sentence removes the claim; the expensive one asks whether the claim was
the thing worth having.

Measured, twice on one pull request: the page said *"run it again for the next hundred"*, which
was false. The first fix made it true for one layer — a replayed failure was skipped — and left
it false for the layer above, where the bound was applied to the rows read rather than to the
messages sent, so a second run skipped the same hundred and never reached the hundred-and-first.
The second round found exactly that. A claim about *repetition* needs a case that repeats:
two runs, three runs, and an assertion about what the later ones reached.

So: when the finding is a false claim, name the property the sentence was promising, write the
case from **the sentence** rather than from the code path, and let the test's name be that
sentence. A case written from the diff tests the mechanism you just wrote; a case written from
the sentence tests the thing a reader will rely on. The two agree right up until the mechanism
is only part of the promise.

### A semantic fix can empty an older test

The rule everywhere else is that a change carries a test that fails without it. It does not
follow that the tests around it still fail without *their* code, and a fix that changes what a
command does can quietly turn an earlier case into one that passes for a new reason.

Measured: a de-duplication added in one round made a case about timezone parsing vacuous two
rounds later. The case ran the command twice and asserted the queue; after the change, the
second run skipped its row as already handled whatever window the parser produced. It passed
with the parser deliberately broken, and the next pass reported it.

So after a fix that changes behaviour rather than adding a branch, re-apply the swaps from the
**earlier** rounds of the same pull request, not only the newest one, and check each still fails
the case it was written for. Keeping those swaps in the commit messages as you go is what makes
this a loop rather than an act of memory. A case that no longer fails under its own swap is a
finding you can have before the reviewer does — and it is the one class of defect where the
reviewer is reading your tests rather than your code, so it comes back as *two* rounds: the
vacuous case, and then whatever it was supposed to be guarding.

### Sweep before the review, not only after

The same tool run against your own diff turns most of these findings into things you never hear
about. `cr-sweep.py --base <ref>` derives its patterns from what the diff _deleted_ — every
identifier the change was meant to retire — and reports wherever one still stands. Deletions
only: a name the change added is meant to be everywhere, and reporting it would bury the handful
that are meant to be nowhere.

Run it after the local pass and before pushing, and treat what it prints as findings.

**And run the local pass again after each round of fixes, not only before the first push.** It
draws on its own hourly allowance, so it costs nothing from the column that gates the merge, and
the fixes are where the next findings live: on one pull request, eleven of thirteen findings
were in the two files that pull request had just written, and the largest of them — four
unmarked loss modes in a guarded function — came from a *local* pass before the first push
rather than from any of the four pull request reviews that followed. A round of fixes is a new
draft. Review it like one.

### It also catches the damage a rename does on its way through

A mechanical substitution corrupts prose that was correct before it, and the diff reads clean
because every changed line is individually right. Two shapes to expect:

- a blanket rename writing a current name into a section that documents an old release — a
  section whose whole purpose is to use the vocabulary of its own time.
- a substitution that leaves the rest of its sentence standing, so the clause ends up repeating a
  noun, or stacking two verbs, or promising something the new subject cannot do.

And the sharpest one: **sweep the tests and their docstrings too.** A file whose cases pin a
name's removal had a module docstring stating that everything it describes still exists — false,
and proved false by the cases directly below it. A test file is documentation with an exemption
from nothing.

## Quick reference

```bash
S=~/.claude/skills/coderabbit/scripts

$S/cr-status.sh 109              # is the head actually reviewed? what is open?
$S/cr-await.sh 109               # ask for a FULL review, wait out limits, until head is covered
$S/cr-threads.sh 109             # unresolved findings, with the comment id to reply to
$S/cr-nits.sh 109                # pre-merge checks, nitpicks, outside-diff — none of them threads
$S/cr-reply.sh 109 3791801592 "Confirmed and fixed — …"
$S/cr-sweep.py --base origin/main    # the *class* each finding belongs to, across the whole tree

$S/cr-local.sh                   # review this working tree — no PR, a different allowance
$S/cr-local.sh --light --uncommitted
```

Those five take `OWNER/REPO` from the current directory's git remote, or from `$CR_REPO`.
`cr-local.sh` needs no repository at all: it reads the checkout you are standing in.

Three environment knobs, all optional:

|             |                                                                                                                                                                                                  |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `CR_REPO`   | `owner/repo`, when the working directory is not the checkout                                                                                                                                     |
| `CR_LOGIN`  | which gh account may write here. Defaults to the repository's owner when that owner is a person; an organisation repository has no single right author, so there any account with access will do |
| `CR_SETTLE` | seconds `cr-await.sh` keeps reading after the walkthrough reaches the head, before it will call a pull request clean. 180 by default; `0` only if you are going to read the threads yourself     |

## The one rule that matters

**A green check is not a review. The only proof is the SHA.**

The `CodeRabbit` check-run reports `pass` for _"Review completed"_, _"Review rate limited"_ and
_"Review skipped"_ alike. It is not evidence. The evidence is the walkthrough comment:

```
**Merge Risk:** _⚪ Minimal_ · up to `d640f`
```

That SHA is what was reviewed. If it differs from the head, your latest commits are **unreviewed**,
whatever the check says. `cr-status.sh` compares them for you.

Do **not** read the SHA from _"Reviewing files that changed … between X and Y"_ — that says what
CodeRabbit _intended_ to look at, not what it finished.

**And the SHA alone cannot tell you _which_ review covered it.** An incremental pass leaves exactly
the same `up to <sha>` line as a full one, so "the head is covered" is not evidence that the full
review you asked for ever ran.

**The walkthrough's `updated_at` is not evidence either**, though it looks like the obvious fix.
Every push triggers an _automatic_ incremental review, and that edits the same walkthrough — so
push a commit, ask for a full review, get refused for rate limits, and the timestamp still moves
while the refusal stays invisible. That exact sequence merged a head whose final commit no full
review had ever seen.

**Read all the comments, not the first page.** `gh api .../issues/N/comments` returns thirty,
oldest first. A pull request that has been through a few review rounds passes that in an afternoon,
and then every "is there a reply yet" question is answered from yesterday's traffic — so a granted
review reads as no answer, and the wait loop asks again for what it already has. Pass
`--paginate ...?per_page=100` and combine the pages (`jq -s add`); `cr_comments` does.

**And it edits that reply in place, from acceptance to refusal.** Seen on 2026-08-18: a comment
posted at `12:10:17` read _"✅ Action performed · Full review triggered"_ with a note about the
included limit, and by `12:10:23` — six seconds later, same comment, `updated_at` moved — it read
_"⚠️ Action not completed · Review rate limited"_. A classifier that reads the reply once, promptly,
records the acceptance and never sees the retraction. So: **sleep ~30s and re-read the body before
classifying**, and treat the reply as a hint rather than proof. The proof is the walkthrough
reaching the head, which is the check that caught this one — it reported "accepted but never landed
at head", which was the truth while the classification was not.

**The only evidence is CodeRabbit's reply to your own request**: `✅ Action performed` versus
`⚠️ Action not completed — Review rate limited`. Find the reply that came after the comment you
posted, and read it. Everything else — the check-run, the walkthrough, the SHA, the merge box — is
green in both cases. `cr-await.sh` posts the request, keeps its timestamp, waits for the first
CodeRabbit comment newer than it, and classifies that.

**A local pass can die on the transport, and that is a fourth answer again.** `cr-local.sh`
exits 1 with

```
✗ Connection error
Connection failed: WebSocket closed
```

which is neither a refusal nor a finding — the review never started. Retry it once; whether the
attempt was charged is not observable, so treat a second failure as a reason to stop rather than
a reason to keep paying. Read the transcript the script keeps before re-running, as it says: a
run that got as far as writing comments is worth reading even if the socket dropped afterwards.

**There is a third answer, and it is not a refusal.** Alongside those two, a request can come
back as:

```
> [!CAUTION]
> ## Review failed
> An error occurred during the review process. Please try again later.
```

Their side, transient, and the ask reviewed fine when repeated. What made it expensive is that
the classifier had never seen it: it fell through to `unrecognised reply` and exited 1, which in
a transcript is indistinguishable from an ask that was rejected — so the pull request sits with
nobody waiting on it and nothing obviously wrong. `cr-await.sh` now holds five minutes and asks
again, and the note and the patch landed together, for the reason the next section gives.

**A failed review still spends the slot.** Measured: the ask that came back `Review failed` was
followed by a re-ask two minutes later, and that one was refused with `59 minutes` — a full
window, so the failure had consumed the allowance it never delivered a review with. Do not treat
this state as free and do not retry it tightly; five minutes is the floor, and the answer may
well be a rate-limit refusal carrying its own wait, which is what the waiter is already built
to sit through.

Read the failure comment rather than the classification when this happens: the same
`## Review failed` box is also what a walkthrough turns into, so `cr-status.sh` will report
`reviewed: never` on a pull request whose check-run is green. That is the honest answer, not a
broken read.

**Restarting a waiter posts a fresh ask — so a restart is only safe when nothing is in flight.**
A waiter that dies mid-review is the ordinary case, and relaunching it is the ordinary reaction;
the ask it sends lands on a pull request whose review is already running, which is the thing this
section exists to prevent. Measured, four minutes after the rule above was written down: the
relaunch posted a second `@coderabbitai full review` while the first was still processing.

`cr-await.sh` now checks before asking — a walkthrough that says it is processing means the answer
is already coming, so it watches and never asks. If you write the loop yourself, check the same
thing: **read the walkthrough before you post anything.** A watcher is the right tool exactly when
a pass is alive; it is the wrong one only when the state needs a fresh trigger.

**Never push while a waiter is running.** The review it is watching covers the head it was
asked about, and a push moves the head out from under it — so the slot is spent on code that is
no longer there, and the waiter then compares its answer against a SHA it never saw. It is the
same failure as reading the walkthrough instead of the reply, arrived at from the other side.

The rule that prevents it is the one already here, applied in order rather than in spirit:
finish the local pass, push, _then_ ask. If a finding arrives while a push is already needed,
kill the waiter first and re-ask after the push — a deliberate re-ask costs the same slot the
accidental one wasted, and at least it lands on the right commit.

## The walkthrough at head is not the last thing a pass posts

**Do not merge the moment the SHA matches.** The inline threads and the pre-merge table arrive
_around_ the walkthrough rather than before it, and on a large diff they have been seen to land
after it. A merge went out 93 seconds after the walkthrough reached the head, with nothing having
looked for what appeared in between — and the evidence for that merge, read afterwards, was
genuinely clean. That is what makes it dangerous: the procedure was followed and the window
between "reviewed" and "everything a review posts" was simply assumed to be zero.

So the verdict is held rather than declared. `cr-await.sh` waits `CR_SETTLE` seconds (180 by
default) after the SHA matches, re-reads the unresolved threads, the failed pre-merge count and
the nitpick sections, prints both readings, and **exits non-zero when anything is open** — so a
caller that gates on its exit status cannot merge over a finding that arrived late. Set
`CR_SETTLE=0` only when you are going to read the threads yourself afterwards.

A count that grew during the hold is the interesting one. It means the pass was still writing
when the walkthrough said it had finished, and it is the only way to tell that apart from a pass
that finished with nothing to say.

## Which account is writing, not merely one that can

A review request is a **write**, published under a name. On a machine with more than one
logged-in account, "can this account read the repository" is not the question — several accounts
can, and a request went out under a second account belonging to the same person, on a public
thread, because the gate checked access and stopped there.

Access is not identity. `cr_ensure_account` now resolves _who_ should be writing — `CR_LOGIN`
when set, otherwise the repository's owner when that owner is a person rather than an
organisation — and pins the run to that login via `GH_TOKEN`, refusing when no login has it. An
organisation repository has no single right author, so there the access-only rule stands.

Every run prints the login it is acting as, on stderr. That line is the cheap part and the one
that matters: drift is invisible until something says the name out loud.

## A pass that is still running says so in the walkthrough — read the right comment

CodeRabbit edits **one** comment as it works, and while the pass is running that comment says

```
> [!NOTE]
> Currently processing new changes in this PR. This may take a few minutes, please wait...
```

with no `up to <sha>` line yet, because nothing is covered until it finishes. Which means a
selector that picks "the newest comment containing `up to <sha>`" cannot see the liveness note at
all: the note and the SHA never coexist. A waiter built that way looked for "currently processing",
found nothing, refused to extend its budget, and reported _"the walkthrough claims no pass in
progress"_ about a review that was in progress and saying so, sixteen minutes in.

So select the walkthrough by what makes it a walkthrough — the `summarize by coderabbit.ai` marker
every one of them carries — and read the SHA out of whatever that gives you. A walkthrough without
a SHA then means what it should mean: _nothing is covered yet_, which is different from _no
walkthrough exists_, and the two were indistinguishable before.

**And the check-run is a fourth signal, when it exists.** A `CodeRabbit` check-run reporting
`pending` is a live pass; the same check-run reporting `pass` still proves nothing about _what_
was reviewed, for the reason the section above gives. Whether it appears at all varies — do not
build the wait on it, and never report its absence as evidence either way.

## An accepted ask can still produce no review

`✅ Action performed — Full review triggered` is the acceptance, and it is not a promise. The pass
can end before it starts: the walkthrough is replaced by

```
> [!WARNING]
> ## Review limit reached
> **Next included review available in 41 minutes.**
```

and nothing further happens. Measured: an ask accepted at 00:26, and at 00:45 the walkthrough
carried that notice with no pass having run — so the acceptance, the check-run and the
`updated_at` all moved while the review never existed.

Which makes the walkthrough the place to read a limit as well as a SHA. `cr_stated_wait` finds the
number there as readily as in a refusal reply, and `cr-await.sh` holds it and asks again — this
being the one state where re-asking is right rather than forbidden, because nothing is in flight.

The reason it matters beyond the wasted wait: without recognising it, a loop spends its whole
budget on a review that was never going to run, and then reports it in the words reserved for a
pass that died quietly. Two different failures, one message, and the difference is what you would
do next.

## Separate the waiting from the asking, if anything can kill your process

A waiter that has already posted its ask is carrying something valuable: the slot is spent, and
only that process knows what the answer was. Anything that kills it — a harness that reaps
background tasks after twenty minutes, a suspend, a closed terminal — throws the answer away
while the cost stands. Seen twice in one session, both times inside a rate-limit hold, with 33
minutes still to run.

So when the environment can kill a long-running process, do the waiting in something **cheap** and
the asking in something **short**:

```shell
until [ "$(date +%s)" -ge "$window_end" ]; do sleep 120; done   # free to lose, relaunch at will
cr-await.sh <pr>                                                # started only once it can be granted
```

A killed sleeper costs nothing and is restarted without a thought. A killed waiter costs a review
out of the hour, and the temptation is to relaunch it, which posts a second ask — so the loss
compounds into noise on the pull request.

`cr_hold` already keeps a wall-clock deadline in short slices, which is what makes the sleeper
honest across a suspend. What it cannot do is survive being killed, and no loop can. Do not ask
until the ask can be granted.

## One waiter, ever

`cr-await.sh` loops for as long as the limits make it. Start a second one — a new
background run because the first "seemed stuck", or a fresh attempt after a push —
and both keep asking. Four `@coderabbitai full review` comments went out inside
three minutes that way, each accepted, each a review CodeRabbit then had to run
past the included allowance.

**This is enforced now rather than remembered, because remembering it failed.** The advice below
— look for a running waiter and kill it — was followed by writing that check into the _same_
command that launches the waiter. So it ran in the background, printed `live waiters: 1`, and
started the second one anyway: nothing ever read the line. A guard whose only effect is output
is not a guard, and this is the same shape as the account gate that has to live in the same
command as the write. `cr-await.sh` now takes a per-PR `lockf` and a second instance exits 3
naming the log to read. Two waiters on _different_ pull requests are still fine and still
compete for the same hourly column — that part is judgement, not a lock.

`flock` is the obvious tool and is **not on macOS**; this machine has `lockf` and `shlock` only.
Its refusal is exit **75**, measured — not the 73 its own man page prose implies.

**A waiter needs a git checkout, or it lies quietly.** Start one from a scratch directory
and every `gh pr` call in it fails with _"failed to run git: fatal: not a git repository"_ —
which is not fatal to the loop. It read that failure as a check list with nothing pending,
printed `CI settled: pass=0 fail=0`, walked into its ask, failed that too, and reported _"the
ask did not post"_ four times over. Nothing was asked and nothing was waited for, and the
first two lines of the transcript looked like a healthy start.

`pass=0 fail=0` is the tell: a pull request with CI configured never has zero of both. Treat
a zero count as a failed read, exactly as the empty-string comparison above is treated.

**A watcher can also finish before the legs it should be watching exist.** `gh pr checks
--watch` returns as soon as *the checks it can see* are done, and a freshly pushed head has
almost none of them registered yet: measured, it exited **0** reporting `1 pass` while the
same pull request showed `1 pass, 27 pending` seconds later — the one check it saw was the
review bot's own. A review was then asked for on a head whose CI had not started, which is
the thing the ask is supposed to wait for.

So a watch that ends is not a CI verdict either. **Count the checks, and compare the count
to what this repository actually runs** — a number that only moves when a workflow changes,
so a sudden drop is a failed read rather than a smaller matrix. The loop that survives this
polls until no line reads `pending` *and* the total matches:

```shell
gh pr checks "$pr" | awk -F'\t' '{print $2}' | sort | uniq -c   # 28 pass, or keep waiting
```

**And a zero count can come from the tool succeeding at reporting failure.** `gh pr checks`
exits **8** whenever any check is pending or failing — which is exactly the state a
merge gate exists to see. A wrapper that keeps stdout only on exit 0, retries, and returns
empty therefore turns "one leg still running" into "0 failing, 0 pending", and a gate reading
those two numbers says _ready to merge_. Measured on a pull request whose integration leg was
still queued.

Two rules follow, and they generalise past this one command: **read a non-zero exit for its
output, not only for its status**, when the non-zero _is_ the answer being asked for; and count
the rows, because a listing that came back empty is a failed read rather than a clean bill. A
gate must refuse to answer when it cannot see, and say so in the word it prints.

The fix is to make the script location-independent rather than to remember where to launch
it — pass `-R OWNER/REPO` to every `gh pr` call, since only `gh pr` infers the repository
from the working directory (`gh api` takes the path). The scripts here go through `cr_repo`,
which resolves it once and passes it explicitly.

**Documenting a bug in these scripts is not fixing it.** The `jq -s add` crash above was
written up here and the script was left as it was — and the next run died in the same place,
five seconds after posting its ask, costing the whole rate-limit window. If a script in this
skill has a bug, patch the script in the same breath as the note. The note explains the next
failure; the patch prevents it.

**When a waiter dies, replace its behaviour, not its observation.** The obvious repair is a
loop that watches the walkthrough — and a watcher is not a waiter. `Review rate limited`
means _ask again after the window it names_, so a loop that only reads sat through a 19-minute
window printing "waiting", and the window had been open a quarter of an hour before anyone
noticed. Whatever replaces `cr-await.sh` has to classify the reply and re-ask, or it is not
doing the job the dead one was doing.

**A live process is not progress, and a long `sleep` is where the two come apart.** A
waiter that had been refused printed `retrying in 2420s` and then printed nothing for four
hours and twenty minutes. It was alive the whole time, and so was its child: `sleep 2420`,
still running at `04:20:45` elapsed. A sleep long enough to cover a rate-limit window is long
enough to be caught by the machine suspending, and it comes back owing time it never counted
— so the re-ask never happened and the pull request sat idle through the window it was
waiting for.

**`cr-await.sh` cannot do this any more**, and that is the part that matters: waiting out a
window goes through `cr_hold`, which holds to a wall-clock deadline in 120-second slices and
prints a line with a clock in it each time, and the landing loop has a deadline of its own
instead of a count of sleeps. A suspend now costs at most one slice. Anything you write
yourself that waits should do the same — never `sleep "$window"` in one call.

Which makes the **log** the check rather than the process table: every waiting state prints
within two minutes, so a last line older than that is a dead waiter however healthy `ps`
looks.

```shell
tail -2 "$log"; date -u +%H:%M:%SZ      # newer than two minutes? it is working
```

**And match the executable, never the command line, when checking whether a review is running.**
`pgrep -f 'coderabbit review'` matches any process whose command *text* contains that phrase — a
shell in an unrelated directory, a heredoc being written, the guard itself quoted inside a
wrapper. Measured: a local pass was refused with nothing running, because another session's shell
mentioned the words. `pgrep -x coderabbit` asks about the binary, which is the question.

**Count waiters by the lock, never by `ps | grep`.** The `lockf` guard added above makes one
waiter _three_ processes matching `cr-await` — the outer shell, `lockf` itself, and the script
re-exec'd under it — so a grep-and-count reports 4 for a single healthy waiter, and following the
"kill the extra ones" advice would kill the only one there is. The fix for a check that invents
an answer is not a better regex; it is asking the thing that knows:

```shell
find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'cr-await-*.lock' | while read -r f; do
  echo "$(basename "$f"): $(lsof -t "$f" 2>/dev/null | tr '\n' ' ')"
done
```

`find` with a **quoted** pattern, so no shell globbing happens at all. That is not style either.
**zsh aborts a command whose glob matches nothing** — `no matches found: …/cr-await-*.lock`,
exit 1 — and it does so _before_ the loop body, so a `[ -e "$f" ]` guard inside a `for` never
gets a chance. Written the obvious way, the check killed the very `cr-await.sh` it was chained
ahead of, on the one condition that means "safe to start": no lock file at all. bash passes an
unmatched pattern through and the guard works, which is how a snippet like this survives review
and then fails on somebody else's shell. Piping `ls` does not fix it either: zsh expands the
glob before `ls` ever runs.

One pid per lock file, and a lock file with no pid is stale and harmless — `lockf` releases with
the process, so nothing has to clean it up. An empty listing means no waiter is running.

**Never pipe the waiter through `tail` or `head`.** `cr-await.sh 21 | tail -14` buffers: the
progress lines the script prints every 30 to 120 seconds reach the pipe and stop there until
the process exits, so the log stays empty and the one liveness check there is stops working —
by hand, on purpose, for the sake of a tidier final output. Seen twenty-five minutes into a
held window, with the waiter alive and correct and its log showing nothing but the line before
it started. Let it write straight to the task file and read the tail of that.

And come back to it on a schedule rather than on faith — that is the half no script can do
for you. Four hours passed because nobody looked, not because nobody was told. If the newest
line is stale, kill it, ask once by hand, and take over with a bounded loop.

**Start every long-running command here so the harness owns it, not `nohup`.** This applies
to `cr-await.sh` _and_ `cr-local.sh` — to anything in this skill that takes minutes. Launched
as `nohup … &` inside a foreground call, the process is invisible to whatever is supposed to
notice it finishing: a waiter wrote `reviewed at head` and exited, and the findings sat unread
for forty-two minutes because no notification was ever going to arrive. Then the same mistake
was made again with a local pass, which finished with `No findings` and went unread for half
an hour — the rule had been written down naming the _waiter_, so it was applied to the waiter
and not to the pass.

Hand the command to the background facility the harness actually tracks — in Claude Code that
is `run_in_background`, which reports the exit and hands back the output path. A detached
process you have to remember to poll is a process you will forget, and the second time it will
be a different command than the one the rule mentioned.

**Check liveness with `ps`, and never let the check invent an answer.** On macOS `pgrep` has
no `-c`: `pgrep -fc cr-await.sh` exits 2 as a usage error, and the idiomatic
`$(pgrep -fc ... || echo 0)` turns that into a printed `0` — indistinguishable from "nothing
running", for a process that is alive and sleeping out its window. Read the process table
instead, and look at the sleep:

```shell
ps -eo pid,etime,command | grep '[c]r-await'   # the pid and how long it has been asking
ps -eo pid,etime,command | grep '[s]leep'      # the window it is waiting out, if any
```

Before starting a waiter, **look for one already running** and kill it:

```bash
ps -eo pid,etime,command | grep '[c]r-await.sh'   # etime shows how long it has been asking
kill <pid>
```

Two things make the stale one worse than it looks. It holds no lock and prints
nothing while it sleeps, so "no output for twenty minutes" is indistinguishable
from dead. And it is running the **code it started with** — a fix to
`_common.sh` does not reach a process that sourced it an hour ago, so the old
loop keeps making the exact mistake you just repaired.

## The wrong `gh` account looks exactly like "nothing to report"

Every script here calls `cr_ensure_account "$R"` right after resolving the repo, and every
`gh`/`cr_gh` call after that point is transparently correct — nothing else here needs to
know this happened. It exists because a machine with several `gh`-logged-in accounts has a
single **global** "active account" pointer, shared by every `gh` invocation system-wide
(including ones this skill did not start), and that pointer has been observed to flip to an
account with no access to the target repo between two calls a few seconds apart with
nothing in this skill touching it.

**Not every 404 here is the account, and this section makes that the first suspicion.** A
review comment is addressed _without_ the pull request number:
`repos/O/R/pulls/comments/<id>` works, `repos/O/R/pulls/<pr>/comments/<id>` is a flat 404 no
matter who is signed in. The number belongs on the _listing_ — `repos/O/R/pulls/<pr>/comments`
— and on nothing else, which is what makes the mistake so easy to make and so easy to
misread as a permissions gap. Check the shape of the path before reaching for
`cr_ensure_account`; the account story is the right one only when a call that is shaped
correctly returns nothing.

The failure mode is not an error — it is silence. Several call sites here swallow `gh`'s
stderr on purpose (`2>/dev/null || true`, because a missing check-run is not a failure), so
a wrong-account 404 comes out as empty output, which every downstream check then reads as
"nothing found" rather than "could not look." Seen concretely on 2026-08-19: `cr-status.sh`
reported `reviewed: never` and `0 failing, 0 pending` on a PR that in fact had a
`coderabbitai` review with state `APPROVED` at head and a green `CodeRabbit — Review
completed` check. Both signals — the review state and the check-run — were real and
green; the script's own gh calls just never reached them.

`cr_ensure_account` fixes this without touching the shared pointer: it tests the currently
active account against the repo first (free, one call, the common case), and only if that
fails does it walk every other logged-in account (`gh auth status --json hosts`), find one
that can read the repo, and pin **this process** to it via `GH_TOKEN` — an env var `gh`
prefers over the on-disk active-account file, and one no other process can silently
overwrite. `gh auth switch` was tried first and rejected for exactly that reason: it writes
the same shared pointer that keeps flipping, so it does not fix the race, it just becomes
another write racing the same file.

If a script ever reports "no logged-in gh account can read X", that is a real permissions
gap — `gh auth login` an account that has one, or set `CR_REPO`/check org access — not
another instance of this issue.

## github.com fails transiently, and `set -e` turns that into a lie

`gh` answers `HTTP 503 No server is currently available` in bursts — four calls in a row,
then fine. Every script here runs under `set -euo pipefail`, so one unlucky call kills the
caller outright, and what you see depends on where it died:

- `cr-await.sh` died on the very request it exists to post — nothing asked, nothing waited for,
  exit 1. Easy to read as "the review was refused".
- `cr_repo` fell through to its fallback message and said **"not in a GitHub checkout"** from
  inside a checkout, which sends you to look at git remotes for a problem that is GitHub's.
- `cr-reply.sh` failed on three of four replies in one batch, so three findings looked answered
  and were not.

Every `gh` call in these scripts now goes through `cr_gh`, which retries 5xx and timeouts six
times with a growing pause and passes 4xx straight through — a bad comment id will fail the same
way for ever, and retrying it only hides the typo. It keeps stdout and stderr separate, because
merging them feeds gh's diagnostics to the `jq` on the other side of the pipe.

**Reads only.** A retried write is a second write, and that is not theoretical: github.com
answered 503 _after_ accepting a `@coderabbitai full review` comment, so the retry posted it
again. The duplicate consumed the next rate-limit slot and was refused, which then looked like
CodeRabbit being stingy rather than like my own second request. `cr_gh` now refuses to retry
anything carrying `-f`/`-F` or a `POST`/`PATCH`/`PUT`/`DELETE`; it fails once and says
`a write failed and is NOT retried; check whether it landed`. Then check — the write may well
have succeeded:

```bash
gh api --paginate "repos/$R/pulls/$PR/comments?per_page=100" | jq -s add \
  | jq -r '.[] | select(.user.login=="<you>") | "\(.created_at) reply_to=\(.in_reply_to_id)"'
```

**A failed read makes two empty strings, and empty equals empty.** The gate that proves the
head was reviewed compares two values fetched from the API. When github.com was unreachable both
came back empty, `[[ "" == "" ]]` matched, and a waiter printed
`REVIEWED at head  (newest non-empty pass)` — with nothing between `head` and the parenthesis —
for a pass that did not exist. Read the SHA in that line: a blank there is the tell. Any
comparison of two fetched values needs both sides asserted non-empty first, and a failed fetch
has to be retried rather than treated as an answer:

```shell
if [[ -z "$head" || -z "$last" || "$head" == null || "$last" == null ]]; then
  echo "  api unreachable — retrying, not concluding"; sleep 60; continue
fi
```

**`jq -s add` on an empty stream is `null`, and `.[]` on `null` kills the waiter.** Not a lie
this time — a death. `--paginate` emits one array per page and `jq -s add` concatenates them,
but a read that returned no pages at all makes `add` produce `null`, and every helper that then
writes `[.[] | select(...)]` fails with `Cannot iterate over null (null)`. Under
`set -euo pipefail` that ends the process, so a waiter that had already posted its ask exits
with the ask outstanding and nothing watching for the answer — seen on 2026-08-22, two lines
into the log:

```
asked: @coderabbitai full review  (…)
jq: error (at <stdin>:1): Cannot iterate over null (null)
```

Measured: `printf '' | jq -s add` prints `null`; adding `// []` prints nothing and exits 0. So
every paginated read guards the fold, not just the field after it:

```shell
gh api --paginate ".../comments?per_page=100" | jq -s 'add // []' | jq -r '[.[] | select(…)] | last // empty'
```

The tell in a transcript is an ask followed immediately by a jq error and nothing else. Check
that the ask landed — it usually did — and take over the waiting rather than asking again.

The same run also swallowed the `@coderabbitai full review` comment itself: the ask printed as
sent while nothing reached the pull request. Confirm the comment is _on_ the pull request before
waiting for a reply to it.

**When posting replies by hand, check what landed.** A 503 on a reply is silent afterwards:
list your own comments and read their `in_reply_to_id` rather than assuming the batch went out.

```bash
gh api --paginate "repos/$R/pulls/$PR/comments?per_page=100" | jq -s add \
  | jq -r '.[] | select(.user.login=="<you>") | "\(.created_at) reply_to=\(.in_reply_to_id)"'
```

## Ask which threads are open, never which comments are recent

`cr-threads.sh` and a `created_at` filter are both ways to _miss_ a finding. A review posts its
comments in one burst, so "everything newer than the last round" depends on knowing when the last
round was — and a guess there silently drops a whole batch. Seen more than once: a burst of findings goes
unread because the next look filters from a later timestamp than the one they were posted at. In
one case the missed batch included a warning that CI would not install a dependency the new tests
needed — the legs went red for exactly that an hour later, and the reviewer had said so before CI
ran.

Ask GitHub the question that matters instead — which threads are unresolved, and which of those
have no reply of yours in them:

```shell
gh api graphql -f query='
{ repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: N) {
      reviewThreads(first: 60) { nodes {
        isResolved
        comments(first: 20) { nodes { author { login } databaseId path } } } } } } }' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | {id: .comments.nodes[0].databaseId, path: .comments.nodes[0].path,
           authors: [.comments.nodes[].author.login]}'
```

A thread whose `authors` list holds only the reviewer has never been answered, whatever you did
to the code — acting on a finding and replying to it are two separate obligations, and the merge
gate counts the second.

## CI state comes from `gh pr checks`, and the read has to survive its exit code

`cr-status.sh` prints a check summary, and twice it printed a **false** one. On 2026-08-24 it said
`0 failing, 0 pending` while twelve test legs were failing, and that reading was repeated to the
user as "CI is green" three times. Later the same summary said `0 pending` with a leg still
queued, and the pull request merged.

Both had one cause, given its own section above: `gh pr checks` **exits 8** whenever anything is
pending or failing, and a wrapper that keeps stdout only on exit 0 turns the interesting case into
an empty read. The script calls it directly now, counts the rows, and prints
`UNREADABLE — no rows came back; do not merge on this` when there are none, because a pull request
with CI configured never has zero.

The habit that outlives the bug: **a zero is a claim, and a claim needs a row to stand on.** When
you are about to say "CI is green" out loud, say it from output you can see:

```shell
gh pr checks <pr> -R OWNER/REPO
```

## Rate limits

The included plan allows a few reviews per rolling hour (3 at the time of writing), with extra
throttling once your recent review volume is high. When limited, it names a number:

> **Next review available in:** **15 minutes**

**The unit changes with how close the next slot is** — seconds, minutes, or hours. A parser that
only knows minutes matches nothing on _"available in 33 seconds"_, and under `set -euo pipefail`
that empty match takes the whole script down mid-wait. Parse the number and the unit together;
`cr_wait_seconds` does.

Two facts that are easy to get backwards, and both cost time when you do:

1. **`Review rate limited` is not terminal.** Sleep the stated interval instead of concluding that
   nothing more will happen.
2. **It does not resume on its own.** From its own message:

   > After more reviews become available, a review can be triggered using the `@coderabbitai review`
   > command as a PR comment. Alternatively, push new commits to this PR.

So: read the stated wait → sleep it → trigger **once** → check the SHA. Asking more often than the
stated interval produces nothing but noise, and CodeRabbit replies to every one of them.
`cr-await.sh` implements exactly this loop.

**Ask what is left rather than probing for it.** `@coderabbitai rate limit`, posted as a PR
comment, reports the remaining capacity and does not consume a review. That beats "try one and
see", which spends the slot it is asking about.

`coderabbit usage` is **not** the CLI equivalent, whatever it looks like: it reports reviews
run so far in the billing period and when that period rolls over, and says nothing about the
hourly allowance or how much of it is left. Useful for "am I on a paid tier", useless for "may
I review now". For the CLI surface there is no free way to ask; run the pass and read the
refusal, which names its own wait.

**The allowance has a column per surface, not one pool.** The plans table sets a per-developer,
per-hour number for pull request reviews, IDE reviews and CLI reviews separately — and on the free
plan they differ (1 PR review an hour against 3 CLI reviews), which they could not if the three
shared one pool. Pro is 5/5/5, Pro+ 10/10/10, at the time of writing. Local passes are therefore
the cheap ones: see "Local reviews" and "The IDE surface", below.

The FAQ states the trial limit as _"3 PR, IDE, and CLI reviews per developer per hour"_, which
reads like a single shared pool and contradicts the table. Confirm which it is on **your** plan
with `@coderabbitai rate limit` and `coderabbit usage` before planning a round around it —
both answer for free, and neither is a guess.

## Local reviews: the `coderabbit` CLI

The same reviewer runs against a working tree, with no pull request involved:

```bash
brew install coderabbit          # a cask; it links `coderabbit` only, and no `cr` shim
coderabbit auth login            # browser OAuth, once per machine; --api-key for headless
coderabbit doctor                # install, auth, git state, connectivity — first stop when it misbehaves
```

**`auth status` exits 0 while signed out.** It prints `Status : signed out` and returns success
(CLI 0.7.5), so a script that reads only the exit code sends an unauthenticated review off to fail
a few seconds later. Read the word, not the code — `cr-local.sh` does.

**Signing in from an agent session: `--agent`, not `login`.** Plain `coderabbit auth login`
refuses outright where there is no TTY — _"Non-interactive environment detected. Use --api-key
for authentication"_ — which reads like "an API key is the only way" and is not true.
`coderabbit auth login --agent` does browser OAuth from exactly that environment: it emits
JSON, holds a loopback callback listener, and completes when the human opens the URL it
printed.

```bash
nohup coderabbit auth login --agent > login.log 2>&1 &   # then hand the authUrl to the human
```

Two ways to lose it, both silent:

- **Do not pipe it.** `coderabbit auth login --agent | head -20` buffers, so the URL never
  reaches the human, the listener sits there, and the whole thing looks hung. Redirect to a
  file and read the file.
- **The listener dies with the process.** It is a loopback port held for the duration of the
  call, so the command has to outlive the tool call that started it — background it. A 60-second
  timeout that kills the invocation also kills the callback the human is about to trigger.

It ends with `{"type":"complete","phase":"auth","status":"authenticated",...}`; anything
short of that line means nothing was stored, whatever the browser said.

`cr-local.sh` wraps the review itself: it picks the base the pull request would use, refuses to
start a second review while one is running, and keeps the transcript in `.git/coderabbit-local/`.

**Why it earns a section: it spends a different column of the allowance.** A local pass costs
nothing that the pull request needs, so the round becomes _review locally, fix, push once, spend
the one PR slot on code a reviewer has already been through_ — instead of burning the hourly
allowance discovering locally-findable things through GitHub. That is where the speed comes from.

**It is not fast in wall-clock.** CodeRabbit's own figure is 7 to 30+ minutes per local review,
which is the same order as waiting out a rate limit. The saving is in slots and in rounds, not in
seconds — so scope every pass and run it in the background rather than watching it:

| flag                     | what it reads                                                        |
| ------------------------ | -------------------------------------------------------------------- |
| `--uncommitted`          | staged changes and tracked edits                                     |
| `--committed`            | only what is committed on this branch                                |
| `--include-untracked`    | tracked changes plus files git does not know about                   |
| _(none)_                 | every tracked change against the base                                |
| `--base <branch>`        | what to diff against — a release branch, not just the default branch |
| `--base-commit <commit>` | a commit on this branch, when the interesting delta is mid-branch    |
| `--dir <path>`           | one subtree                                                          |
| `--light`                | reduced context work, for a pass mid-development                     |
| `-c, --config <files…>`  | extra instructions on top of `.coderabbit.yaml` — a `CLAUDE.md`, say |
| `--agent`                | findings as structured JSON, for an agent to act on                  |

**`--plain` and `--prompt-only` do not exist**, whatever the blog posts and the older write-ups
say. Plain text is the default mode in 0.7.5, and the only output switch is `--agent`. Passing a
flag the CLI does not know fails the invocation, which is a cheap mistake to make right before a
half-hour review.

**Read `coderabbit review --help` rather than the docs.** The published reference and the installed
binary disagree on flags, on whether the default mode is a TUI, and on which commands exist. The
binary is the one that runs.

**Re-read instead of re-running.** `coderabbit review findings` replays the last review's findings
and costs nothing; `cr-local.sh` keeps the transcript for the same reason. Re-running to see the
output again spends a review, exactly as a duplicate `full review` comment does.

**`--show-prompts` may have nothing to show, which makes it useless as verification.** It answered
`No saved AI prompts for this branch. Run 'coderabbit review' first to generate a review.` on a
branch that had just been through three passes, one of which wrote a finding. So it cannot be used
to confirm that `--config` instructions were applied — and nothing else in the output confirms it
either: the header names the diff, the compare and the directory, and never the extra
instructions. A pass given `--config` and a pass without it are indistinguishable from their
transcripts, so a clean result from the operating-rules lens is **unverified**, not clean. Say so
rather than counting it.

**What costs nothing, and the one thing that costs money.** These spend no review at all:
`coderabbit review findings` (replay), `coderabbit review --show-prompts` (the prompts of the last
review, when it has any — see above), `coderabbit usage`, `coderabbit stats`, `coderabbit doctor`, `coderabbit config validate`.
The exception is `--use-credits`, which lets a review that exceeds the included allowance bill
against the usage-based add-on — per file reviewed, in real money. Never pass it on someone's
behalf; `cr-local.sh` says so loudly if it sees it come through.

**`coderabbit pullrequest <number|url> --show-prompts [--agent]`** reads the CodeRabbit output of a
pull request from the terminal, as prompts an agent can act on. It needs the repository installed
in the active CodeRabbit organisation, and it is github.com only. It is a convenience over
`cr-threads.sh`, not a replacement: it carries no comment ids, so nothing can be replied to from it,
and it is not the merge-gate evidence either.

**`coderabbit skills` writes into `~/.claude/skills/`.** It installs CodeRabbit's own agent skills
(a review skill and an autofix one) into whichever agent directories it recognises, Claude Code's
among them. It asks before overwriting, and it leaves anything it did not install alone — this
skill included — but check `~/.claude/skills` afterwards, because two skills describing the same
tool is how one of them silently stops being read.

**Local findings are not evidence.** They never reach the pull request: no thread is opened, the
walkthrough does not move, no SHA is recorded, and `cr-status.sh` cannot see that the pass
happened. A local pass cannot resolve a thread and cannot satisfy the merge gate in "Order of
operations" — that gate is still the walkthrough reaching the head. It changes what you push,
never what you claim.

**It reads the repository's `.coderabbit.yaml`**, including `path_instructions`, so a local finding
genuinely predicts a pull request finding. Two consequences worth holding on to:

- `coderabbit config validate .coderabbit.yaml` checks the file against the schema before it is
  pushed. A malformed one otherwise surfaces as a review that quietly ignores your instructions.
- CodeRabbit resolves that file from the **base** branch for a PR, but from the working tree
  locally. Edit it on your branch and the two passes are reading different configuration — which
  is the first thing to check when local and PR findings disagree.

**One at a time**, for the reason in "One waiter, ever": two concurrent local reviews are two
reviews out of the same column, and neither finishes sooner for it.

### Sweep with several lenses, not the same review twice

A second pass over the same diff with the same scope mostly reproduces the first. What earns its
place is a _different lens_, and three of them cover a branch well:

| lens                     | invocation                                                                 | what only this one sees                                                          |
| ------------------------ | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| the whole change         | `cr-local.sh --committed --base <pr base>`                                 | the release read as one thing, the way the merge will read it                    |
| the newest commit alone  | `cr-local.sh --committed -- --base-commit <sha>^`                          | the fixes you just wrote, at full attention instead of diluted across the branch |
| your own operating rules | `cr-local.sh --committed --base <pr base> -- --config ~/.claude/CLAUDE.md` | whatever `.coderabbit.yaml` does not know it should demand                       |

The third is the one worth reaching for deliberately. `-c/--config` takes files of _additional_
instructions, so handing it the rules you are actually held to — every change carries a test that
fails without it, a behaviour lives in its defaults and its docs and its changelog, values go in
`extra=` and not into the message — gets the diff read against those, and `.coderabbit.yaml` never
mentions any of them. It is the only cheap way to have the reviewer check the things your own
instructions care about.

**`--base-commit` names the commit to diff _from_, and getting that backwards reviews nothing.**
Pass the commit you want _read_ and the delta is empty: the pass prints `No committed changes
detected` and `Nothing to review`, exits **0**, and a driver counting findings reports zero — which
reads as clean. It is the mirror of the refusal trap below, with an exit code that agrees with the
lie. Name the parent (`<sha>^`).

**The transcript's `Compare` line does not reflect `--base-commit`** — it prints
`branch → base-branch` whatever commit you scoped to, so it cannot be used to confirm the scope,
and reading it as evidence is how a per-commit pass gets mistaken for an ignored flag. What does
confirm the flag works: point it at `HEAD` and watch for `Nothing to review`, which is a free
answer because there is nothing to review.

**A wrapper that injects `--base` defeats it silently.** The CLI prefers `--base` and ignores
`--base-commit` when both arrive, so a script that helpfully supplies the pull request's base
turns a per-commit pass into a whole-branch one — which then answers `No new findings` in seconds,
because the branch was already read. A slot spent to be told nothing, with nothing in the output
saying so. `cr-local.sh` refuses the combination now rather than choosing for you.

Three passes in four minutes is the tell that something like this happened: a real pass over a
branch spends minutes in `Writing review comments`.

**`No new findings ✔ · N previous findings` is ambiguous, and the elapsed time is what resolves
it.** Seconds means deduplication against a diff already read — not a second opinion, and a slot
spent to tell you nothing. Minutes of `still working` means a genuine pass that found nothing,
which is the cleanest result available and worth saying out loud. The `N previous` is only the
replay cache either way, and `coderabbit review findings` shows what it holds for free; findings
already fixed still appear there, so the count says nothing about what is outstanding.

So: read the elapsed lines before believing either reading, and change the scope or the
configuration between passes if you want the second one to be worth its slot.

Two mechanics that cost a pass each to learn:

- **`cr-local.sh` knows its own flags and passes the rest through after `--`.** `--committed`,
  `--uncommitted`, `--all`, `--light` and `--base` are its own; anything else — `--base-commit`,
  `--config`, `--dir`, `--agent` — belongs after `--`, and an unrecognised flag before it exits 2
  rather than guessing.
- **Queue them, do not launch them.** They share one column and the script refuses to start a
  second while one runs, so a driver that waits for the process to clear and then starts the next
  is the whole trick:

  ```shell
  wait_free() { while pgrep -f 'coderabbit review' >/dev/null 2>&1; do sleep 15; done }
  wait_free; bash "$CR" --committed -- --base-commit "$sha"     > pass2.log 2>&1
  wait_free; bash "$CR" --committed --base "$base" -- --config ~/.claude/CLAUDE.md > pass3.log 2>&1
  ```

  Background the driver and read the transcripts when it finishes. A pass is minutes, not seconds,
  and watching it produces nothing a `tail` would not.

**Why it is worth the wall clock**, on the run that produced this section: a release branch that had
already been through four pull request review rounds gave **thirteen** findings to a local pass over
the whole diff. Ten were real, and four of those were one shape nobody had named yet — a setting read
somewhere its refusal cannot be handled: inside a `finally`, on a consumer thread, in a rule whose
`try` had grown narrower than the code beneath it. None of that was reachable from the per-commit
diffs the pull request passes had been reading.

**A refused pass counts zero findings, and zero reads as clean.** The local column runs out
like the pull request one, and a refusal lands _inside the transcript_: `✗ Review limit reached`,
a stated window to wait, and `Error: Rate limit exceeded`. Nothing about the shape of that
transcript says "no review happened" — it has the banner, the compare line, the file header — so
a driver that reports `grep -c` over the severity lines announces **0 findings** for a pass that
never ran. That is the same trap as the empty-string comparison above, in a place where it looks
like good news.

`cr-local.sh` exits 1 and says so, so the exit code is the tell. Check it, or grep the transcript
before believing a clean result:

```shell
grep -qiE 'Review limit reached|Rate limit exceeded' "$log" \
  && echo "refused, not clean — the count is meaningless" \
  || echo "$(grep -cE '^  (major|minor|critical|nitpick) \[' "$log") findings"
```

A refusal costs no review, so the pass is still there to be run once the stated window passes —
but only if you noticed. Queue three and read only the counts and you will merge on a pass that
was never taken.

**And verify them exactly as you would a pull request finding.** In one pass three findings of
thirteen were wrong, and each took a single command to disprove — a dependency said to be missing
was present, a branch said to be reachable had no input that could reach it, and a function said
not to perform a transformation performed it. A local finding carries the same authority as a PR
one, which is to say: none until measured.

**When two passes disagree, the configuration is the arbiter.** One finding asked for a British
spelling restored and another for an American one, on the same release — `.coderabbit.yaml`'s
`language:` settles it, and the exceptions worth keeping are the strings the code actually emits.
Say which rule you applied in the reply, or the next round reopens it.

**Where it fits the round.**

1. **Before the first push.** Then the automatic pass that opening the PR triggers reads cleaned
   code, and its slot buys something.
2. **While the branch is frozen** waiting on a PR review. That wait is the one stretch of time a
   local pass fits perfectly — but the freeze still holds: record what it finds and push it with
   the next batch, after the pass lands.
3. **Never instead of the pre-merge full review.** The question at merge time is whether a review
   covered the head commit, and a local pass leaves nothing that can answer it.

**Wrong-account failures look like the `gh` ones.** An account in the wrong organisation authenticates
fine and reviews with the wrong configuration; `coderabbit auth status` and `coderabbit auth org`
are the equivalents of `cr_ensure_account`, and neither is called for you.

## The IDE surface, and whether it is worth a column

The third surface is an editor extension, and it is the one to be deliberate about.

**It is VS Code and its forks — Cursor and Windsurf — and nothing else.** There is no official
JetBrains plugin at the time of writing, so a PyCharm workflow reaches this column only by keeping
a VS Code-family editor around for the purpose.

**What it does** is review uncommitted code in the editor as you work, apply the simple fixes in
one click, and hand the complex ones to an agent. On a paid plan it carries most of what a PR
review does; chat, docstrings and unit-test generation stay exclusive to pull requests.

**It has its own column**, on the same terms as PR and CLI reviews, so an IDE pass costs neither
of the other two.

**But a column is not a capability.** It is the same reviewer reading the same working tree as
`cr-local.sh`, driven by clicks instead of by a command: nothing it finds lands in a transcript,
in a thread, or anywhere this skill's scripts can read, and none of it can be scripted into a
round. So take the column if a VS Code-family editor is already open — it is free capacity for a
manual pass while the branch is frozen — and otherwise plan around the CLI column, which does the
same work and leaves a record.

## `review` vs `full review`

| command                          | what it does                                                                                                                                                                                                                                 |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `@coderabbitai review`           | **incremental** — only commits pushed since the last review. Declines if the head was already reviewed: _"does not re-review already reviewed commits"_                                                                                      |
| `@coderabbitai full review`      | re-reviews the whole PR from scratch. **Default to this before merging**: an incremental pass can leave most of the pull request unread, and the question at merge time is whether the whole change is sound, not whether the last commit is |
| `@coderabbitai pause` / `resume` | stop and restart automatic reviews on one PR                                                                                                                                                                                                 |
| `@coderabbitai help`             | the current command list — check it rather than guessing                                                                                                                                                                                     |

Both review commands consume a slot and both can be rate limited.

## A fresh pull request needs no `full review` command — unless nothing is automatic here

**Check first whether this repository gets automatic reviews at all.** A public repository below
CodeRabbit's popularity threshold does not: the check-run reports

```
CodeRabbit  pass  Review skipped: manual review required for this OSS repository
```

and the only other trace is one comment saying _"This repository does not receive automatic
reviews because it has fewer than 10 stars"_, carrying a `🔍 Trigger review` checkbox. `pass`
again, for a review that never happened — the fourth thing that colour means, alongside
completed, rate limited and base-branch skipped.

Where that applies, everything below about the automatic first pass is inverted: opening a pull
request triggers **nothing**, waiting for the walkthrough waits for ever, and every pass on
every push has to be asked for. It also makes the hourly allowance easier to plan, since no
slot is ever spent without you asking.

Read the check's message on the first pull request in a repository and know which regime you are
in before planning a round.

Where reviews _are_ automatic: opening a PR triggers one, and on the first pass there is nothing
"incremental" about it: the diff _is_ the whole pull request, so that review reads
everything. Asking for `@coderabbitai full review` straight after opening one buys
nothing and spends a slot.

The command earns its slot from the second push onwards, where an automatic pass
looks only at the new commits and the question at merge time is whether the _whole_
change is sound. So: open, wait for the walkthrough to reach the head, read the
findings, fix, push — and _then_ ask for a full review.

**Unless the allowance is spent, in which case the automatic pass never runs and never
retries.** Seen twice in one session, on two pull requests opened minutes apart: the PR opens, CI goes green, and
`cr-status.sh` says `reviewed: never` for as long as you are willing to wait. The only
trace is a comment — _"Review limit reached … Next review available in: N minutes"_ — and
a `CodeRabbit` check-run reading `pass` / _Review rate limited_, which looks like every
other green. So "opened it, the automatic review will come" is not a plan once the hourly
limit has been hit that day: read the comment for the window, wait it out, then ask.

Waiting first is worth the extra step. `cr-await.sh` handles a refusal by holding, so
asking early costs only noise — but the window is stated to the minute in that comment,
and sleeping to it means the first request is the one that lands:

```bash
gh api "repos/$R/issues/$PR/comments" --jq '.[0].body' | grep -o 'Next review available in:.*'
```

## Budget: one slot per _push_, not per pull request

Every push triggers an automatic review. On a stack — review, fix, review, fix — the hourly
allowance is gone quickly, and the reviews you lose are the ones on your fixes.

If that becomes the bottleneck, the fix is configuration, and CodeRabbit suggests it itself: pause
incremental auto-reviews and request a review when the PR is ready. That costs **one slot per PR**
instead of one per push.

```yaml
# .coderabbit.yaml
reviews:
  auto_review:
    enabled: false # then ask with @coderabbitai review when the PR is ready
```

This is a repository-wide policy change. Propose it; do not make it unilaterally.

Batching your own fixes into one push before asking again has the same effect and needs no config
change. So does reviewing locally first — `cr-local.sh` comes out of the CLI column, so the fixes
it finds cost the pull request nothing at all.

## Never push while a review you asked for is in flight

A review reads the head as it was when the request was **accepted**. Push after that and the pass
lands on the old SHA: the slot is spent, the walkthrough moves, and `cr-status.sh` still says
`covers head: no`. `cr-await.sh` reports it exactly — _"the review was accepted but never landed at
head"_ — which is the truth and not a failure of the script.

Seen twice on 2026-08-19, both times the same way: the waiter was holding out a rate limit, the wait
looked like idle time, so more fixes went in — and each push cost a full hour, because the next slot
had to be spent re-reading what the last one had already read.

So the wait is part of the round, not a gap in it:

- **Before asking**, push everything you have. The request should be the last thing that happens.
- **A refusal is a local pass, every time.** `Review rate limited` hands you the window it
  names — twenty minutes, fifty, whatever it says — and a local pass comes out of a
  different column, so it costs the held request nothing at all. Waiting it out with an idle
  branch is throwing away the one thing the wait is good for. Run at least one, scoped to
  the commits no local pass has read yet:

  ```shell
  bash "$S/cr-local.sh" --committed -- --base-commit <last locally reviewed sha>
  ```

  On the run that produced these notes, that habit was worth more than the pull request
  passes: local passes over the same branch found a payload able to overwrite validated
  envelope fields, a view answering an unauthenticated 500 for its own misconfiguration, and
  an import direction the package's own docstring forbade — none of which the PR passes had
  raised. And it costs nothing that the held ask needs.

- **While a request is outstanding or holding**, treat the branch as frozen. Reviewing your own diff
  again is the right use of that time — it is how three of the eleven findings on one release PR
  were caught before the reviewer saw them — and a local `cr-local.sh` pass is the other, since it
  spends none of the allowance the outstanding request is waiting on. Either way, _record_ what you
  find and push it with the next batch, after the pass lands.
- **If you must push anyway** (CI is red, or the finding is a data-loss defect), expect to pay
  another slot and say so, rather than being surprised when coverage does not move.

**A refusal and an acceptance freeze the branch for different reasons, and the difference is
worth reading before you push.** With a pass _accepted_, a push wastes that pass outright: it
reads the SHA it was given, the slot is gone, and coverage does not move. With the ask merely
_held_ — `Review rate limited`, nothing queued — there is no pass to waste, and a push is
survivable **provided the waiter re-reads the head at every attempt** rather than reusing the
SHA it captured before the wait. A waiter that captures the head once asks for a review of a
commit that is no longer there.

Survivable is not free, though: every push triggers an automatic incremental review, and that
comes out of the same allowance the held ask is waiting for. So a push during a hold trades a
slot for a shorter round, and it is worth it only when what you are pushing is worth a slot —
a batch of answered findings, not one more comment fix.

Which means the classification is operational, not trivia: read the reply body, and know which
of the two states you are in before you decide whether to push. The three-way rule under
"Order of operations" is where that reading is written down.

The exception is a finding that makes the review pointless: if the pass is going to read code you
have already decided to replace, push and re-ask deliberately. That is a choice, not an accident.

## Why a review was "skipped"

> Review skipped: reviews are disabled for this base branch

CodeRabbit only reviews pull requests whose **base** matches `reviews.auto_review.base_branches`,
which defaults to the repository's default branch alone. A release branch, or a PR stacked on
another feature branch, matches nothing and is skipped in silence.

See `references/config.md` for the settings worth knowing.

## What is not a thread, and so is easy to miss

`cr-threads.sh` shows findings that opened a review thread. Three kinds never do,
and none of them turn anything red:

- **Pre-merge checks.** A table in the walkthrough — title, description, linked
  issues, scope, docstring coverage. A failure is a **warning**: no check-run
  fails, no thread opens, `gh pr checks` says nothing. "0 threads, all green" can
  be true with one failed.
- **Nitpick comments**, collapsed per file. Individually small, and where "the
  documentation still describes the old behaviour" tends to land.
- **Outside diff range**, about code this pull request did not touch but its
  change affects.
- **File-level review comments**, which have no diff position and so are not
  threads at all.

`cr-nits.sh <pr>` prints all four, and `cr-status.sh` now reports counts for the
first two so a merge decision cannot be made without seeing them. Read them
before merging, and say which you are acting on and which you are deferring —
deferring is fine, silently not looking is not.

**Nitpicks and outside-diff-range comments live in the _review_ body, not the
walkthrough — and `cr-nits.sh` used to die silently before saying so.** Two
compounding bugs, found together on one pull request:

1. These two sections are posted inside a PR **review** object
   (`GET repos/{owner}/{repo}/pulls/{pr}/reviews`), never in the walkthrough
   **issue comment** (`issues/{pr}/comments`) that `cr_walkthrough`/`cr_comments`
   read. A script that only checks the walkthrough is blind to this class of
   finding by construction — not bad luck on one PR, every PR. `_common.sh` now
   has `cr_latest_review_body`, which reads the most recent non-empty-bodied
   review, and `cr-nits.sh` scans _both_ sources for all three markers.
2. Worse, the old single-source version could not even report "none": its
   `section=$(printf ... | sed ... | strip)` assignment was unguarded, and
   `strip()`'s trailing `grep -v` exits 1 whenever a marker genuinely has no
   match — the ordinary case, since a given marker usually matches in at most
   one of the two sources, if either. Under `set -euo pipefail`, that made the
   very first marker checked (`Nitpick comments` against the walkthrough, which
   never carries nitpicks) kill the whole script on the spot, so a Major
   outside-diff finding and a nitpick sat unread with the script printing
   nothing past the section header — not even its own "none" fallback. Fixed
   with `|| true` on the assignment.

Together these meant `cr-nits.sh` had never actually shown a nitpick or an
outside-diff finding on this branch — it silently exited on line one of the
loop every time. Found only by reading a review's raw `.body` by hand and
noticing content the script's own output didn't have. If `cr-nits.sh` (or any
script here) prints a suspiciously tidy "none" right after a header, read the
raw API objects once before trusting it — a script dying inside a loop and a
script that legitimately found nothing look identical from the outside.

**And a count of new comments is not the list of open findings.** A pass reported _5 new_
while 6 threads were open; the five newest comments were answered one by one, and the sixth
— a Major, on a deployment recipe — went unanswered through an entire round without
appearing anywhere. Counting is how a waiter notices _that_ a pass happened; it cannot tell
you _what_ is open, because a comment may be a reply, an edit, or a finding whose thread
predates the batch you are reading.

So enumerate the threads and reconcile: the ids you replied to must cover the unresolved
list, not merely match its length.

```shell
gh api graphql -f query="{repository(owner:\"$OWNER\",name:\"$REPO\"){pullRequest(number:$PR){
  reviewThreads(first:100){nodes{isResolved comments(first:1){nodes{databaseId path line}}}}}}}" \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved==false)
        |"\(.comments.nodes[0].databaseId) \(.comments.nodes[0].path):\(.comments.nodes[0].line)"'
```

`cr-status.sh` prints the count and `cr-threads.sh` the list with ids, which is the whole
reason to run them instead of trusting a tally.

## Answering findings

Reply **in the thread of the finding**, never as a fresh PR comment — `cr-reply.sh` does this.
CodeRabbit reads the reply, answers, and **resolves the thread itself** when it accepts the fix, so
"unresolved threads" is a reliable signal that something is still open.

In the reply, say what you _verified_, not merely that you fixed it: the reproduction, the measured
number, the test that now fails without the change. If you disagree, say so with evidence — its
findings are good but not infallible, and it accepts a measured counter-argument and marks the
thread resolved.

## Never say "fixed in <sha>" without reading that sha's diff

Replying in a thread is a claim to a reviewer, and it is checked by nobody else. A commit whose
_message_ describes the fix proves nothing. Seen once, and once is enough: a commit's subject
named the repair, its body explained the mechanism, the thread reply said the same — and the diff
contained only a new test. The edit itself had never landed. CodeRabbit accepted the reply and
resolved the thread, the pull request merged, and the finding was still true in the merged code.

Before replying, grep the pushed commit for the change itself, not the file:

```shell
git show "$sha" -- "$path" | grep -n '<the new line>'   # empty output means there is nothing to claim
```

A file-level check is too coarse — that commit _did_ touch that file, with something else.

If a fix cannot be proved by a test, say which part is unobservable and why, and put that in the
reply instead of a proof. A claim that overstates is worse than a gap that is named: the gap gets
tracked, the claim closes the thread.

## Take its findings seriously

It runs scripts against the checkout and searches the web to verify claims before filing. On one
release it correctly found:

- a URL parser treating `?decode_responses=false` as _off_, where the library treats any non-empty
  string as _on_ — so a check would have passed the exact URL someone writes to turn it off
- a global `close_old_connections()` reaching past the alias the guard was about
- `max(0, int(limit))` turning `--limit -1` into "no limit"
- `SCAN` returning duplicate keys, so a count could double
- three tests that exercised a helper but not the call to it, so deleting the call left them green

That last shape recurs. When it says a test would pass with the change reverted, check by reverting.

## Order of operations before merging

0. **Review locally first** if anything is still unpushed — `cr-local.sh` costs no PR slot, and a
   finding it catches here is one the pull request pass does not have to spend a round on.
1. **Resolve conflicts first** — rebase and push before asking for a review, or the slot is wasted.
2. Wait for CI to finish.
3. Ask for a **full review** and confirm from its reply that the review **ran**, not that the head
   looks covered. A refusal is a refusal no matter how green the rest of the page is.
4. Answer every finding in its thread; confirm no unresolved threads remain. Three checks
   belong to **this** step rather than to the first draft, because the fixes are the newest and
   least-read code on the branch — and on one pull request eleven of thirteen findings were in
   the files it had just written:
   - the fix's own diff swept for the finding's predicate — see
     **[Sweep your own diff for the class](#sweep-your-own-diff-for-the-class-before-answering-the-finding)**;
   - a check you added built from **every branch** of what it guards, not from the cases already
     marked — **[A guard is as complete as the branches it was built from](#a-guard-is-as-complete-as-the-branches-it-was-built-from)**;
   - the earlier rounds' swaps re-applied, since a behaviour change can empty a case written two
     rounds ago — **[A semantic fix can empty an older test](#a-semantic-fix-can-empty-an-older-test)**.

   Then `cr-local.sh` again before the push, for the reason step 0 gives: a round of fixes is a
   new draft, and its findings cost nothing from the column that gates the merge.
5. **Prove the head you are merging was reviewed.** The gate is
   `newest non-empty review body`.commit_id == current head — not "a review exists", and not
   "the waiter said reviewed at head". A review whose `body` is empty is the wrapper around a
   thread reply, not a pass; there are several per PR and they carry the head SHA.

   ```shell
   head=$(gh pr view "$PR" --json headRefOid --jq .headRefOid)
   gh api --paginate "repos/$R/pulls/$PR/reviews" \
     --jq "[.[]|select(.user.login|test(\"coderabbit\"))|select(.body|length>0)][-1]|\"\(.commit_id) \(.submitted_at)\""
   ```

   If those two SHAs differ, the delta between them is unreviewed — read
   `git diff <reviewed>..<head>` and decide, do not merge on the strength of the earlier pass.
   Anything that captures the head _before_ asking for a review is measuring the wrong commit:
   re-read it at the moment of the check.

   **A finding you argued down still means the pass had findings.** A pass that reported one
   finding, which you then refuted with a measurement and CodeRabbit agreed was invalid, is a
   pass with a finding and a resolved thread — not a clean pass. The thread closing says the
   _argument_ was accepted; it says nothing about what a fresh reading would turn up, and the
   reply itself changed the pull request's text. When the standing instruction is "merge on a
   pass with no findings", that is what it asks for: ask again and get a pass that reports
   none. Merging on "the finding was invalid" is the same shortcut as merging on a green
   check-run, one step further along.

   **A pass that finds nothing posts no review body at all**, so that check alone reports
   `NOT reviewed` for the cleanest possible outcome — it cost an hour of re-asking on one
   pull request. What a clean pass leaves is: `✅ Action performed / Full review finished.`
   as a reply to your ask, the walkthrough comment's `updated_at` moving, and **no new
   review comments**. Accept that as the pass:

   ```shell
   gh api --paginate "repos/$R/issues/$PR/comments?per_page=100" \
     --jq '[.[]|select(.user.login|test("coderabbit"))|select(.body|test("summarize by coderabbit"))]|last|.updated_at'
   ```

   Compare it against the same value read _before_ the ask, and confirm the review-comment
   count is unchanged. Two empty-bodied reviews at the head are thread-reply wrappers, not
   a pass, and are not evidence either way.

6. Merge.

**"Never landed at head" also means "still working", and `cr-await.sh` cannot tell the
difference.** Its landing loop waits ten minutes for the walkthrough to move _and_ cover the
head, then reports _"the review was accepted but never landed at head"_ — which on a
release-sized pull request is simply the budget running out. Seen on a branch of about
ninety files: the message printed while the walkthrough still carried
`Reviewing files that changed … between <base> and <head>` naming the right head, and the
pass finished afterwards with the walkthrough moving to it.

So do not act on that message without reading the walkthrough for a processing note:

```shell
gh api --paginate "repos/$R/issues/$PR/comments?per_page=100" | jq -s add \
  | jq -r '[.[]|select(.body|test("summarize by coderabbit"))]|last|.body' \
  | grep -oiE 'review in progress|currently processing|Reviewing files that changed[^<]*'
```

Anything there means the pass is alive and the only correct move is to keep waiting —
re-asking spends a slot on a review already running, and treating it as a refusal is how a
round gets paid for twice. The `up to <sha>` line is the _previous_ completed pass while a
new one is in flight, so it names a stale SHA for the whole duration and is not evidence of
failure either.

**The refusal for this has its own words, and they are not "rate limit".** Push while a pass
is starting and CodeRabbit answers with a collapsed `⚠️ Action not completed` whose whole body is
`Head commit changed.` — nothing is queued, nothing will arrive, and a waiter that greps only for
rate limits sits there until it times out. Grep for `head commit changed`, and treat it as
_ask again_ rather than as _wait longer_.

**`⚠️ Action not completed` is the wrapper around every refusal, so never match on it.** A
waiter that treated it as the head-changed case read `Review rate limited.` as _ask again_, and
asked six times in twelve minutes — each request refused, each one pushing the window further
out, and six `@coderabbitai full review` comments left on the pull request. Classify on the
_body_, rate limit first:

1. `rate limit` → sleep the window it names, plus a minute.
2. `head commit changed` → ask again, once two reads of the head agree.
3. `action not completed` and neither of those → **stop and read the thread.** A refusal the
   script does not recognise is not a retry.

Better still, do not create the race: an automated waiter that asks as soon as CI turns green
will ask while you are still committing. Have it confirm the head is unchanged across two reads
before it asks, and start it only when you have stopped pushing.

**Push after the review and you are back at step 3.** A late commit — even a test-only one — gets
an automatic incremental pass and nothing more. Batch the fixes and push once, so one full review
covers the state you actually merge.

## Stacked pull requests

If PR B is based on PR A's branch, do **not** merge A with `--delete-branch`. GitHub **closes** B
rather than retargeting it, and a closed PR whose base branch is gone cannot be reopened or
retargeted — it has to be recreated, losing its review history. Merge without deleting, retarget B,
then delete the branch.
