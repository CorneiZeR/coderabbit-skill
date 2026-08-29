#!/usr/bin/env bash
# Everything CodeRabbit says outside a review thread.
#
#   cr-nits.sh <pr>
#
# `cr-threads.sh` shows the findings that opened a thread. It cannot show these,
# and they are the ones that get missed:
#
#   * **Pre-merge checks** — a table in the walkthrough. A failed one is a
#     WARNING, not a check-run failure, so it turns nothing red anywhere.
#   * **Nitpick comments** — collapsed per file. Individually small, and the
#     place where "the docs still say the old thing" tends to land.
#   * **Outside diff range** — findings about code this pull request did not
#     touch but its change affects.
#
# None of them appear in `gh pr checks`, none of them block a merge, and none of
# them are in the unresolved-thread count. Read this before merging.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
PR=${1:?usage: cr-nits.sh <pr>}
R=$(cr_repo)
cr_ensure_account "$R"

body=$(cr_walkthrough "$R" "$PR")
if [ -z "$body" ]; then
  echo "no walkthrough yet — nothing has been reviewed" >&2
  exit 1
fi

strip() { sed 's/<[^>]*>//g' | grep -vE '^\s*$'; }

echo "=== pre-merge checks ==="
printf '%s\n' "$body" | sed -n '/Pre-merge checks/,/Walkthrough/p' \
  | sed -n '/Failed checks/,/Passed checks/p' | strip || true
printf '%s\n' "$body" | grep -oE 'Pre-merge checks[^|]*\| ✅ [0-9]+ \| ❌ [0-9]+' | tail -1 || true

echo
echo "=== nitpicks and outside-diff findings ==="
# These sections live in the *review* body (pulls/{pr}/reviews), not the walkthrough
# issue comment -- scan both, or a nitpick/outside-diff finding posted only in the
# review is silently reported as "none". See cr_latest_review_body in _common.sh.
review_body=$(cr_latest_review_body "$R" "$PR")
found=0
for marker in 'Nitpick comments' 'Outside diff range' 'Additional comments'; do
  for source_name in walkthrough review; do
    if [ "$source_name" = walkthrough ]; then src=$body; else src=$review_body; fi
    # `|| true`: strip()'s trailing `grep -v` exits 1 when a marker genuinely has no
    # match in this source (the overwhelmingly common case — most markers match in
    # only one of the two sources, if either). Under `set -euo pipefail` an unguarded
    # `var=$(... | grep ...)` assignment then kills the whole script right here,
    # silently, before the `found=0` fallback ever gets to say so. Measured on a real
    # pull request: the very first marker checked ('Nitpick comments' against
    # the walkthrough, which never carries nitpicks) exited the script on line 1 of
    # the loop, so a Major outside-diff finding and a nitpick sat unread with the
    # script reporting nothing at all past this header.
    section=$(printf '%s\n' "$src" | sed -n "/$marker/,/<\/details>/p" | strip) || true
    if [ -n "$section" ]; then
      found=1
      printf -- '--- %s (%s) ---\n%s\n\n' "$marker" "$source_name" "$section"
    fi
  done
done
[ "$found" = 1 ] || echo "  none in the walkthrough or the latest review"

echo "=== review comments that opened no thread ==="
# a file-level comment has no diff position, so it is not a thread and
# cr-threads.sh cannot see it
# `// []` for the reason cr_comments carries: `add` over an empty stream is null, and the
# `.[]` below dies on it — taking this script with it under `set -euo pipefail`
cr_gh api --paginate "repos/$R/pulls/$PR/comments?per_page=100" 2>/dev/null | jq -s 'add // []' \
  | jq -r '[.[] | select(.user.login=="coderabbitai[bot]") | select(.line == null and .original_line == null)]
           | if length == 0 then "  none" else .[] | "  \(.path): \(.body | gsub("<[^>]*>";"") | .[0:120])" end'
