#!/usr/bin/env bash
# Wait until CodeRabbit has actually run the review you asked for.
#
#   cr-await.sh <pr> [inc]
#
# Full review by default. `review` is incremental — it looks only at commits
# pushed since the last one — so before a merge it can leave most of the pull
# request unread. Pass `inc` when an incremental pass is genuinely what you want.
#
# THE EXIT CONDITION IS CODERABBIT'S ANSWER TO *THIS* REQUEST, NOTHING ELSE.
#
# Two weaker conditions were tried and both merged an unreviewed head:
#
#   1. "the head is covered" — an incremental pass leaves the same
#      "up to <sha>" line as a full one, so a full review that never ran looks
#      identical to one that did.
#   2. "the walkthrough changed after I asked" — every push triggers an
#      automatic incremental review, which edits that same walkthrough. Push a
#      commit, ask for a full review, get refused for rate limits: the automatic
#      review still moves the timestamp and the refusal is invisible.
#
# So: post the request, find the reply *to that request*, and read it. Refused
# means refused however green everything else looks.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
PR=${1:?usage: cr-await.sh <pr> [inc]}
INC=$([ "${2:-}" = inc ] && echo 1 || echo 0)
CMD=$([ "$INC" = 1 ] && echo "@coderabbitai review" || echo "@coderabbitai full review")
R=$(cr_repo)
cr_ensure_account "$R"

# One waiter per pull request, enforced here rather than remembered by the caller.
#
# The skill has said "look for one already running and kill it" for a while, and the check kept
# being written into the *same* command that starts the waiter — so it ran in the background,
# printed `live waiters: 1`, and started a second one anyway, because nothing read the line it
# had just produced. A guard whose output is the only thing standing between you and the
# mistake is not a guard. Seen concretely: two waiters on one pull request, asks five minutes
# apart, both refused for rate limits, competing for the same slots.
#
# `lockf` re-execs this script holding an advisory lock on a per-PR file, so the lock is the
# process: a second waiter exits at once, and a waiter killed mid-window releases without
# leaving anything behind. `flock` would read better and is **not on macOS**, which ships `lockf`
# and `shlock` only — the tidier-looking version exits 127 there on every run.
# Pid files and `noclobber` were rejected for the opposite failure: both survive the process
# that wrote them and lock the pull request out for ever.
if [ -z "${CR_AWAIT_LOCKED:-}" ]; then
  LOCK="${TMPDIR:-/tmp}/cr-await-$(echo "$R" | tr /: --)-$PR.lock"
  status=0
  # `|| status=$?` rather than a bare call: `set -e` would take the script down on the very
  # refusal this is here to report, and the child's own exit code has to survive the wrapper
  CR_AWAIT_LOCKED=1 lockf -t 0 -k "$LOCK" "$0" "$@" || status=$?
  # 75, measured -- `lockf` exits EX_TEMPFAIL, which the man page's own prose numbers wrong
  if [ "$status" = 75 ]; then
    echo "a waiter already holds $R#$PR — NOT starting a second one." >&2
    echo "read its log instead. Kill it only if its last line is over two minutes old:" >&2
    echo "  ps -eo pid,etime,command | grep '[c]r-await'" >&2
    exit 3
  fi
  exit "$status"
fi

# How long to keep reading after the walkthrough reaches the head, before saying so.
#
# A walkthrough at head is NOT the last thing a pass posts. The inline threads and the
# pre-merge table arrive around it, and a merge has gone out 93 seconds after the SHA matched
# with nothing having looked for what landed in between. So the verdict is held, and what
# arrived during the hold is printed as part of it. Override with CR_SETTLE=0 only when you
# intend to read the threads yourself afterwards.
SETTLE=${CR_SETTLE:-180}

verdict() {
  local seen="$1" before after premerge nits
  before=$(cr_unresolved "$R" "$PR")
  echo "walkthrough reached the head ($seen); unresolved threads now: $before"
  [ "$SETTLE" -gt 0 ] && cr_hold "$SETTLE" "settling before the verdict"
  after=$(cr_unresolved "$R" "$PR")
  premerge=$(cr_failed_premerge "$R" "$PR")
  nits=$(cr_nit_sections "$R" "$PR")
  echo "reviewed at head ($seen)"
  echo "  unresolved threads: $after${before:+ (was $before before the settle)}"
  echo "  failed pre-merge checks: ${premerge:-0}; nitpick sections: ${nits:-0}"
  if [ "$after" != 0 ] || [ "${premerge:-0}" != 0 ] || [ "${nits:-0}" != 0 ]; then
    echo "  NOT clean: read them before merging — cr-threads.sh $PR and cr-nits.sh $PR"
    return 4
  fi
  echo "  nothing open — clean at this head"
  return 0
}

covers_head() {
  local head seen
  head=$(cr_head "$R" "$PR")
  seen=$(cr_reviewed_sha "$R" "$PR")
  [ -n "$seen" ] && [ "${head:0:${#seen}}" = "$seen" ] && { echo "$seen"; return 0; }
  return 1
}

# Is a pass already running, asked for by somebody (probably an earlier run of this script)?
#
# Restarting a waiter is the ordinary reaction to one dying, and it posts a fresh ask -- which is
# the one thing this skill says never to do while a review is in flight. It happened here, four
# minutes after the note about it was written. So the check is code now: a walkthrough saying it
# is processing means the answer is already coming, and the right move is to WATCH rather than to
# ask again.
if cr_walkthrough "$R" "$PR" | grep -qi 'currently processing'; then
  echo "a pass is already running on $R#$PR — watching it rather than asking again"
  watching=$(( $(date +%s) + 3600 ))
  while [ "$(date +%s)" -lt "$watching" ]; do
    if seen=$(covers_head); then
      verdict "$seen" || exit $?
      exit 0
    fi
    cr_walkthrough "$R" "$PR" | grep -qi 'currently processing' || break
    echo "  still processing at $(date -u +%H:%M:%SZ)"
    sleep 60
  done
fi

for attempt in $(seq 1 20); do
  # an incremental pass legitimately declines a head it has already read, so
  # there its own prior coverage is a real answer. A full pass never declines.
  if [ "$INC" = 1 ] && seen=$(covers_head); then
    verdict "$seen" || exit $?
    exit 0
  fi

  asked=$(cr_gh api "repos/$R/issues/$PR/comments" -f body="$CMD" --jq '.created_at')
  echo "asked: $CMD  ($asked)"
  before=$(cr_walkthrough_stamp "$R" "$PR")

  reply=''
  for _ in $(seq 1 24); do
    sleep 15
    reply=$(cr_reply_after "$R" "$PR" "$asked")
    # `[ ... ] && break` would leave the loop's exit status at 1 on the last
    # turn, and `set -e` kills the script on that — silently, mid-wait
    if [ -n "$reply" ]; then
      # it edits this comment in place, and has turned an acceptance into a refusal
      # six seconds later. Re-read before classifying, or the retraction is invisible
      sleep 30
      reply=$(cr_reply_after "$R" "$PR" "$asked")
      break
    fi
  done

  if [ -z "$reply" ]; then
    echo "no reply to the request after six minutes; asking again" >&2
    continue
  fi

  if printf '%s' "$reply" | grep -qiE 'rate limited|limit reached|limit is currently reached'; then
    wait=$(cr_wait_seconds "$reply")
    : "${wait:=300}"
    # a little past what it named, so the retry lands after the slot opens
    wait=$(( wait + 20 ))
    echo "refused (attempt $attempt): rate limited, retrying in ${wait}s"
    # cr_hold, never `sleep "$wait"`: one sleep that long was seen still running four hours
    # later, because the machine suspended inside it — and it printed nothing meanwhile, so
    # the pull request sat idle behind a process `ps` called healthy
    cr_hold "$wait" "rate limited, attempt $attempt"
    continue
  fi

  if printf '%s' "$reply" | grep -qiE 'review failed|error occurred during the review'; then
    # A third answer, neither acceptance nor refusal: "An error occurred during the review
    # process. Please try again later." Seen on a 15-file pull request that reviewed fine on
    # the next ask, so it is transient and theirs — but the classifier did not know it and
    # exited 1 as "unrecognised", which reads in a transcript exactly like a rejected ask.
    # It spends the slot: measured, a re-ask two minutes after one of these was refused with
    # a full 59-minute window. So the pause is real and the likely next answer is a rate-limit
    # refusal, which the branch below sits through properly.
    echo "review failed on their side (attempt $attempt); asking again in 300s" >&2
    cr_hold 300 "review failed, attempt $attempt"
    continue
  fi

  if printf '%s' "$reply" | grep -qi 'does not re-review already reviewed commits'; then
    # only reachable in inc mode, and only when the head moved under us
    echo "declined: nothing new to review" >&2
    exit 1
  fi

  if ! printf '%s' "$reply" | grep -qi 'action performed'; then
    echo "unrecognised reply — read it yourself:" >&2
    printf '%s\n' "$reply" | sed 's/<[^>]*>//g' | grep -vE '^\s*$' | head -8 >&2
    exit 1
  fi

  # accepted. "finished" is already done; "triggered" still has to land.
  #
  # A wall-clock deadline rather than a count of sleeps, for the reason cr_hold exists: a
  # suspend in the middle would otherwise stretch "ten minutes" into however long the lid
  # was shut, silently.
  #
  # The budget is a floor, not the verdict. A fixed one is wrong in one direction or the
  # other: ten minutes reported "never landed" on a pass that finished afterwards, fifteen
  # did the same on a larger diff, and raising the number again only moves the boundary. So
  # the deadline extends for as long as the walkthrough still carries its own processing
  # note — which is exactly what the old failure message told a human to go and read by
  # hand. Ask the state rather than guess the duration; the ceiling is what stops a pass
  # that died quietly from being waited on for ever.
  echo "accepted; waiting for the walkthrough to move"
  landing=$(( $(date +%s) + 900 ))
  ceiling=$(( $(date +%s) + 3600 ))
  while [ "$(date +%s)" -lt "$landing" ]; do
    now=$(cr_walkthrough_stamp "$R" "$PR")
    if [ "$now" \> "${before:-}" ] && seen=$(covers_head); then
      verdict "$seen" || exit $?
      exit 0
    fi
    # An accepted ask can still produce no review: the walkthrough turns into "Review limit
    # reached · Next included review available in N minutes" and nothing else happens. Measured
    # -- an ask accepted at 00:26 with "Full review triggered", and at 00:45 the walkthrough
    # carried the limit notice instead of a pass. Without this the loop spent its whole budget
    # waiting for a review that was never going to run, and then reported it as one that died.
    #
    # This is the one state where asking again is right rather than forbidden, since nothing is
    # in flight -- so it holds the stated wait and goes round the outer loop
    # only when the walkthrough has moved since the ask: the notice is left standing in that
    # comment after the window passes, so an unqualified match reads a stale sentence as the
    # current state and holds forty minutes it does not owe
    if [ "$now" \> "${before:-}" ] && cr_walkthrough "$R" "$PR" | grep -qi 'review limit reached'; then
      minutes=$(cr_stated_wait "$R" "$PR")
      echo "  the walkthrough says the limit was reached; holding ${minutes:-60}m and asking again"
      cr_hold $(( ${minutes:-60} * 60 + 30 )) "waiting out the limit the walkthrough named"
      continue 2
    fi
    # its own words, not a timer: "Currently processing new changes in this PR" means the
    # pass is alive, so the budget is extended instead of spent
    if [ "$(date +%s)" -ge $(( landing - 60 )) ] && [ "$(date +%s)" -lt "$ceiling" ] \
      && cr_walkthrough "$R" "$PR" | grep -qiE 'currently processing|review in progress'; then
      landing=$(( $(date +%s) + 300 ))
      echo "  still processing by its own account; five more minutes at $(date -u +%H:%M:%SZ)"
      continue
    fi
    # every slice, so the log moves while it waits: silence here is what four hours of
    # idling looked like, and a line with a clock in it is what tells the two apart
    echo "  waiting for the walkthrough, $(( (landing - $(date +%s) + 59) / 60 ))m left at $(date -u +%H:%M:%SZ)"
    sleep 30
  done
  echo "the review was accepted, the walkthrough claims no pass in progress, and the head is" >&2
  echo "still uncovered. Read the walkthrough before believing anything: this is also what a" >&2
  echo "pass that died quietly looks like." >&2
  exit 1
done
echo "gave up: rate limited on every attempt" >&2
exit 1
