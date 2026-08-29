#!/usr/bin/env bash
# Shared helpers. Sourced, not run.
#
# The repository comes from $CR_REPO, or from the current directory's origin
# remote — so every script works from inside a checkout with no arguments.
set -euo pipefail

# Run a gh call, retrying the transient failures GitHub hands out in bursts.
#
# github.com answers 5xx often enough that a single unlucky call is normal, and
# under `set -euo pipefail` an unretried one kills the caller outright — which is
# how a review wait died on its own first request, having posted nothing and
# waited for nothing. Retried with a growing pause; a 4xx is not retried, because
# a bad id or a missing permission will fail the same way for ever.
cr_gh() {
  # separate streams, not `2>&1`: merging gh's diagnostics into its stdout would
  # feed them to the jq on the other side of every pipe here
  local attempt errors out status=1 argument writes=0
  # A retried write is a second write. github.com answered 503 *after* accepting a
  # `@coderabbitai full review` comment, so the retry posted it again — two
  # requests, and the duplicate consumed the next rate-limit slot and was refused.
  # Reads are retried; writes fail once, loudly, and the caller checks what landed.
  for argument in "$@"; do
    case "$argument" in
      -f | --field | -F | --raw-field | POST | PATCH | PUT | DELETE) writes=1 ;;
      *) ;;
    esac
  done
  errors=$(mktemp)
  # shellcheck disable=SC2064 - expand the path now, while it exists
  trap "rm -f '$errors'" RETURN
  for attempt in 1 2 3 4 5 6; do
    if out=$(gh "$@" 2>"$errors"); then printf '%s' "$out"; return 0; fi
    status=$?
    [ "$writes" = 0 ] || { printf 'gh: a write failed and is NOT retried; check whether it landed\n' >&2; break; }
    grep -qE '(HTTP|status code:) 5[0-9][0-9]|Service Unavailable|timed out|connection reset' "$errors" || break
    printf 'gh: transient failure, retrying (%s/6)\n' "$attempt" >&2
    sleep $(( attempt * 5 ))
  done
  cat "$errors" >&2
  return "$status"
}

# Parsed from `origin`'s URL, not from `gh repo view` — resolving the repo has
# to work before we know which gh account (if any) can read it, and a `gh` API
# call needs exactly the account we have not resolved yet. Handles both the SSH
# and HTTPS github.com forms; anything else falls through to the gh call below.
cr_repo() {
  if [ -n "${CR_REPO:-}" ]; then printf '%s' "$CR_REPO"; return; fi
  local url=$(git remote get-url origin 2>/dev/null || true)
  case "$url" in
    git@github.com:*) printf '%s' "${url#git@github.com:}" | sed 's/\.git$//'; return ;;
    ssh://git@github.com/*) printf '%s' "${url#ssh://git@github.com/}" | sed 's/\.git$//'; return ;;
    https://github.com/*) printf '%s' "${url#https://github.com/}" | sed 's/\.git$//'; return ;;
  esac
  # Retried like the rest: a 503 here used to surface as "not in a GitHub checkout",
  # which is the one diagnosis that sends you looking in entirely the wrong place.
  cr_gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null \
    || { echo "cannot read the repository: not a GitHub checkout, or github.com is refusing. Set CR_REPO=owner/repo" >&2; exit 2; }
}

# Make sure every `gh` call for the rest of THIS process can actually read
# $1 (owner/repo), and pin it there — via GH_TOKEN, not `gh auth switch`.
#
# This machine (and plenty of others) has several `gh`-logged-in accounts, and
# gh's "active account" is one pointer on disk shared by every `gh` invocation
# system-wide, including ones this skill did not start. That pointer has been
# observed to flip to an account with no access to the target repo between two
# calls a few seconds apart, with nothing in this skill touching it. Concretely,
# on 2026-08-19: cr-status.sh reported "reviewed: never" and "0 failing,
# 0 pending" on a PR that in fact had a coderabbitai review with state APPROVED
# at head and a green "CodeRabbit — Review completed" check — every read had
# silently gone through an account that could not resolve the repository at
# all. Several call sites here swallow gh's stderr on purpose (a missing
# check-run is not an error), so a wrong-account failure never surfaces as
# anything louder than "everything came back empty".
#
# `GH_TOKEN`, once exported, overrides the active-account pointer for every gh
# call this process makes from here on (including ones inside loops in the
# same script), and is immune to whatever keeps flipping that pointer, because
# it is only ever read from this process's own environment.
cr_ensure_account() {
  local repo="$1" want active login token
  # its own statement, because `local a="$1" b="${a%%/*}"` does NOT work: bash declares every
  # name in a `local` first -- emptying it -- and assigns afterwards, so `b` was derived from an
  # empty `a`. That left the owner blank, which made the identity check below fall through to the
  # access-only path in silence. Found only because the fast path prints the login it is using
  local owner="${repo%%/*}"
  # WHICH account, not merely one that works. The check below used to be "can the active
  # account read this repository", and several accounts can: a review was requested on a
  # personal repository by a second account of the same person's, which is a write to a public
  # thread under a name nobody chose. Access is not identity.
  #
  # Who should be writing, in order: CR_LOGIN when set, else the repository's owner when that
  # owner is a person rather than an organisation. An organisation repository has no single
  # right author, so there the old access-only rule stands.
  want="${CR_LOGIN:-}"
  if [ -z "$want" ] && [ "$(gh api "users/$owner" -q .type 2>/dev/null || true)" = User ]; then
    want="$owner"
  fi
  active=$(gh api user -q .login 2>/dev/null || true)
  if [ -n "$want" ] && [ "$active" != "$want" ]; then
    token=$(gh auth token --hostname github.com --user "$want" 2>/dev/null) || {
      echo "cr: writes here must go out as '$want' and no gh login has it (see 'gh auth status')" >&2
      return 1
    }
    export GH_TOKEN="$token"
    echo "cr: active gh account is '${active:-none}' — pinning this run to '$want'" >&2
    gh api "repos/$repo" -q .full_name >/dev/null 2>&1 && return 0
    echo "cr: '$want' cannot read $repo" >&2
    return 1
  fi
  # Fast path: the right account is active and can read it — no extra calls.
  [ -n "$active" ] && echo "cr: acting as '$active'" >&2
  gh api "repos/$repo" -q .full_name >/dev/null 2>&1 && return 0
  while IFS= read -r login; do
    [ -n "$login" ] || continue
    token=$(gh auth token --hostname github.com --user "$login" 2>/dev/null) || continue
    if GH_TOKEN="$token" gh api "repos/$repo" -q .full_name >/dev/null 2>&1; then
      export GH_TOKEN="$token"
      echo "cr: active gh account cannot read $repo — using '$login' instead for this run" >&2
      return 0
    fi
  done < <(gh auth status --json hosts --jq '.hosts["github.com"][]?.login' 2>/dev/null)
  echo "cr: no logged-in gh account (see 'gh auth status') can read $repo" >&2
  return 1
}

cr_head() { cr_gh pr view "$2" --repo "$1" --json headRefOid --jq '.headRefOid'; }

# Every comment on the pull request, as one JSON array.
#
# `gh api .../comments` returns the FIRST PAGE ONLY — thirty of them, oldest
# first. On a pull request that has been through a few review rounds that page
# stops at yesterday's traffic, so a reader looking for the newest reply finds
# nothing and reports "no answer" while the answer sits on page two. Reviewing
# one pull request here passed thirty comments and the wait loop started asking
# for a review it had already been granted.
#
# --paginate emits one array per page; `jq -s add` concatenates them. Bodies are
# multiline, so anything line-oriented has to work from this array, not from raw
# --jq output.
#
# `// []`, because `add` over an empty stream is `null` — and every caller below writes
# `.[]`, which dies on null with "Cannot iterate over null". Under `set -euo pipefail` that
# ends the waiter, so a read that returned no pages once killed a loop five seconds after it
# had posted its ask: the request outstanding and nothing left watching for the answer.
cr_comments() {
  cr_gh api --paginate "repos/$1/issues/$2/comments?per_page=100" 2>/dev/null | jq -s 'add // []'
}

# The walkthrough is the one comment CodeRabbit edits in place on every review.
# Identify it by the "up to `<sha>`" marker, not by length: a "Review limit
# reached" notice runs past 3000 characters and would otherwise pass for a
# review that never happened.
# The walkthrough comment, whether or not it has finished being written.
#
# Selected by the marker CodeRabbit puts in every walkthrough rather than by the presence of
# `up to <sha>`, and that is the whole point: a pass still running says so *in this comment* --
# "Currently processing new changes in this PR" -- and has no SHA line yet. Selecting on the SHA
# therefore hid the liveness note behind the very condition it exists to explain, and a waiter
# looking for "currently processing" found nothing, extended nothing, and reported a live pass as
# one that had died quietly. Measured: sixteen minutes into a review that was processing and
# saying so.
#
# `cr_reviewed_sha` is unaffected -- it reads the SHA out of whatever this returns, and a
# walkthrough with no SHA yet means exactly what it says: nothing is covered.
cr_walkthrough() {
  cr_comments "$1" "$2" \
    | jq -r '[.[] | select(.user.login=="coderabbitai[bot]")]
             | map(select(.body | test("summarize by coderabbit.ai|up to `[0-9a-f]+`")))
             | last | .body // empty'
}

cr_last_comment() {
  cr_comments "$1" "$2" \
    | jq -r '[.[] | select(.user.login=="coderabbitai[bot]")] | last | .body // empty'
}

# Outside-diff-range comments and nitpick comments are NOT in the walkthrough issue
# comment -- they are posted in the *review* object (`pulls/{pr}/reviews`), a distinct
# API endpoint from `issues/{pr}/comments`. Measured on a real pull request: cr-nits.sh
# read only cr_walkthrough and reported "none" for both sections while a Major
# outside-diff finding and a nitpick sat unread in the review body the whole time --
# a script that only checks the issue-comment walkthrough is blind to this class of
# finding by construction, not by bad luck on that one PR.
cr_latest_review_body() {
  cr_gh api --paginate "repos/$1/pulls/$2/reviews?per_page=100" 2>/dev/null | jq -s 'add // []' \
    | jq -r '[.[] | select(.user.login=="coderabbitai[bot]") | select(.body | length > 0)] | last | .body // empty'
}

# How long it says to wait, in minutes, or empty. Searched across recent comments
# rather than only the last one: the limit notice carries the number, while the
# last comment is usually its short reply to a command and carries none.
# Every grep here ends in `|| true`. Under `set -o pipefail` a grep that matches
# nothing fails the whole pipeline, which fails the command substitution, which
# under `set -e` kills the caller before it prints anything — so "no review yet",
# the one state these scripts exist to report, came out as silence and exit 0.
cr_stated_wait() {
  cr_comments "$1" "$2" \
    | jq -r '[.[] | select(.user.login=="coderabbitai[bot]") | .body] | reverse | .[0:6] | .[]' \
    | { grep -oE 'available in:?\**[[:space:]]*\**[0-9]+ minutes?' || true; } \
    | { grep -oE '[0-9]+' || true; } | head -1
}

# How long a refusal says to wait, in seconds, or empty. It names seconds,
# minutes or hours depending on how close the next slot is — a parser that knows
# only minutes matches nothing when the answer is "33 seconds", and then the
# empty result takes the whole pipeline down with it.
cr_wait_seconds() {
  local amount unit
  amount=$(printf '%s' "$1" | { grep -oiE 'available in[^0-9]{0,12}[0-9]+' || true; } \
    | { grep -oE '[0-9]+' || true; } | head -1)
  [ -n "$amount" ] || return 0
  unit=$(printf '%s' "$1" \
    | { grep -oiE "available in[^0-9]{0,12}${amount}[^a-zA-Z]{0,4}(second|minute|hour)" || true; } \
    | { grep -oiE '(second|minute|hour)' || true; } | tail -1)
  case "$(printf '%s' "$unit" | tr 'A-Z' 'a-z')" in
    hour) echo $(( amount * 3600 )) ;;
    minute) echo $(( amount * 60 )) ;;
    second) echo "$amount" ;;
    *) echo $(( amount * 60 )) ;;  # unlabelled: minutes is what it used to say
  esac
}

# Wait out a stated window without trusting one long sleep, and say so while waiting.
#
# `sleep 2420` was observed still running after 4h20m elapsed. A sleep long enough to cover
# a rate-limit window is long enough for the machine to suspend inside it, and it comes back
# owing time it never counted — so the re-ask never happened and a pull request sat idle for
# four hours behind a process that `ps` called healthy. Two consequences, both handled here:
#
#   * the wait is a **wall-clock deadline**, re-read every slice, so suspending costs nothing
#   * it prints a line every couple of minutes, so a log whose last line is older than that
#     means a dead waiter rather than a sleeping one — which is the only cheap way to tell
#
# Slices of 120s: short enough that a suspend cannot swallow the wait, long enough that an
# hour of waiting is thirty lines rather than three thousand.
cr_hold() {
  local seconds=${1:-0} label=${2:-holding} deadline now slice
  deadline=$(( $(date +%s) + seconds ))
  while :; do
    now=$(date +%s)
    [ "$now" -ge "$deadline" ] && return 0
    printf '  %s: %sm left at %s\n' "$label" "$(( (deadline - now + 59) / 60 ))" "$(date -u +%H:%M:%SZ)" >&2
    slice=$(( deadline - now ))
    [ "$slice" -gt 120 ] && slice=120
    sleep "$slice"
  done
}

# What was actually reviewed. Never parse "between X and Y": that is the range
# CodeRabbit meant to read, not the one it finished.
cr_reviewed_sha() {
  cr_walkthrough "$1" "$2" | { grep -oE 'up to `[0-9a-f]+`' || true; } \
    | tail -1 | tr -d '`' | awk '{print $3}'
}

# When the walkthrough last changed. CodeRabbit edits that one comment in place
# on every review, so a newer stamp is the only evidence that a review ran —
# the SHA alone cannot say whether it was this review or an earlier one.
cr_walkthrough_stamp() {
  cr_comments "$1" "$2" \
    | jq -r '[.[] | select(.user.login=="coderabbitai[bot]")] | map(select(.body | test("up to `[0-9a-f]+`"))) | last | .updated_at // empty'
}

# CodeRabbit's own answer to a request posted at <iso>. This is the only thing
# that distinguishes "the review ran" from "the review was refused": the
# walkthrough, the check-run and the head SHA all look the same either way.
cr_reply_after() {
  cr_comments "$1" "$2" \
    | jq -r "[.[] | select(.user.login==\"coderabbitai[bot]\") | select(.created_at > \"$3\")] | first | .body // empty"
}

# How many pre-merge checks failed, per the walkthrough table. They are WARNINGs:
# nothing goes red, no thread opens, and `gh pr checks` never mentions them.
cr_failed_premerge() {
  cr_walkthrough "$1" "$2" \
    | { grep -oE 'Pre-merge checks[^|]*\| ✅ [0-9]+ \| ❌ [0-9]+' || true; } \
    | { grep -oE '❌ [0-9]+' || true; } | { grep -oE '[0-9]+' || true; } | tail -1
}

# Nitpicks and outside-diff findings live in collapsed walkthrough sections, not
# in review threads, so the unresolved count is blind to them.
cr_nit_sections() {
  cr_walkthrough "$1" "$2" \
    | { grep -coE 'Nitpick comments|Outside diff range' || true; } | tail -1
}

cr_unresolved() {
  cr_gh api graphql -f query='query($o:String!,$r:String!,$p:Int!){repository(owner:$o,name:$r){
    pullRequest(number:$p){reviewThreads(first:100){nodes{isResolved}}}}}' \
    -F o="${1%%/*}" -F r="${1##*/}" -F p="$2" \
    --jq '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved|not)]|length'
}
