#!/usr/bin/env bash
# Whether a pull request is genuinely reviewed, and what is still open.
#
#   cr-status.sh <pr>
#
# Exit 0 when the review covers the head and nothing is unresolved; 1 otherwise,
# so it can gate a merge.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
PR=${1:?usage: cr-status.sh <pr>}
R=$(cr_repo)
cr_ensure_account "$R"

head=$(cr_head "$R" "$PR")
seen=$(cr_reviewed_sha "$R" "$PR")
open=$(cr_unresolved "$R" "$PR")
premerge=$(cr_failed_premerge "$R" "$PR")
nits=$(cr_nit_sections "$R" "$PR")
# NOT through cr_gh: `gh pr checks` exits 8 whenever anything is pending or failing --
# exactly the state this line exists to report -- and the wrapper discards the stdout of a
# non-zero call, retries it five more times, and returns empty. That printed
# "0 failing, 0 pending" and "ready to merge" on a pull request with a leg still running.
# So this call goes direct and its exit status is ignored rather than trusted
checks=$(gh pr checks "$PR" --repo "$R" 2>/dev/null || true)
rows=$(printf '%s' "$checks" | grep -c . || true)
failing=$(printf '%s' "$checks" | grep -c $'\tfail' || true)
pending=$(printf '%s' "$checks" | grep -c $'\tpending' || true)

covered=no
[ -n "$seen" ] && [ "${head:0:${#seen}}" = "$seen" ] && covered=yes

echo "repo:        $R#$PR"
echo "head:        ${head:0:12}"
echo "reviewed:    ${seen:-never}   (covers head: $covered)"
echo "threads:     $open unresolved"
# printed whether or not they gate: nothing else surfaces these, and a merge made
# on "0 threads, all green" has not seen them
echo "pre-merge:   ${premerge:-0} failed   (cr-nits.sh for the table)"
echo "nitpicks:    ${nits:-0} sections     (cr-nits.sh to read them)"
if [ "$rows" = 0 ]; then
  # a pull request with CI configured never has zero rows, so this is a failed read and
  # not a quiet pass. Said out loud, because the whole point of this script is to be the
  # thing that does not report agreement it cannot see
  echo "checks:      UNREADABLE - no rows came back; do not merge on this"
else
  echo "checks:      $failing failing, $pending pending  (of $rows)"
fi
# `premerge` is in this condition, not merely printed above it. It was printed and ignored,
# so this said `ready to merge` on a pull request with a failed pre-merge check — the same
# shape as every other guard here whose only effect was output. A pre-merge failure is a
# warning rather than a red check, which is exactly why the verdict has to carry it.
[ "$covered" = yes ] && [ "$open" = 0 ] && [ "$rows" != 0 ] && [ "$failing" = 0 ] && [ "$pending" = 0 ] \
  && [ "${premerge:-0}" = 0 ] \
  && { echo "verdict:     ready to merge"; exit 0; }
echo "verdict:     not ready"
exit 1
