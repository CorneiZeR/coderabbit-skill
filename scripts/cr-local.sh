#!/usr/bin/env bash
# A local review: the CodeRabbit CLI reads this working tree directly, and no
# pull request is involved. It spends the CLI column of the hourly allowance,
# which is not the column pull request reviews come out of — see SKILL.md,
# "Local reviews: the coderabbit CLI".
#
# Usage:
#   cr-local.sh [--committed|--uncommitted|--all] [--light] [--base <ref>] [-- <cr args>]
#
#   --committed     only what is committed on this branch
#   --uncommitted   only staged and unstaged edits to tracked files
#   --all           every tracked change, plus untracked files
#   (default)       every tracked change
#   --light         the faster policy, for a pass during development
#   --base <ref>    what to diff against; defaults to the pull request's base
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=_common.sh
. "$here/_common.sh"

scope=""; light=""; base=""; extra=()
while [ $# -gt 0 ]; do
  case "$1" in
    --committed | --uncommitted) scope="$1"; shift ;;
    --all) scope="--include-untracked"; shift ;;
    --light) light="--light"; shift ;;
    --base) base="${2:-}"; shift 2 ;;
    --) shift; extra=("$@"); break ;;
    -h | --help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "cr-local: unknown argument '$1' — pass CLI flags after --" >&2; exit 2 ;;
  esac
done

# `cr` is too common an alias to trust; only the full name is looked up.
if command -v coderabbit >/dev/null 2>&1; then
  BIN=coderabbit
elif [ -x "$HOME/.local/bin/coderabbit" ]; then
  BIN="$HOME/.local/bin/coderabbit"
else
  cat >&2 <<'EOF'
cr-local: the CodeRabbit CLI is not installed.

  brew install coderabbit      # or: curl -fsSL https://cli.coderabbit.ai/install.sh | sh
  coderabbit auth login        # once per machine; --api-key "cr-…" for headless

EOF
  exit 127
fi

# `auth status` exits 0 while signed out — verified on CLI 0.7.5, which prints
# "Status : signed out" and returns success. Reading the exit code alone would
# send an unauthenticated review off to fail several seconds later.
if "$BIN" auth status 2>&1 | grep -qi 'signed out'; then
  echo "cr-local: signed out — run '$BIN auth login' (and '$BIN auth org' if the account has several)" >&2
  exit 3
fi

# Same reason as "One waiter, ever": a second concurrent review is a second
# review out of the same hourly column, and neither of them is faster for it.
# `pgrep -x`, matching the executable's name, never `pgrep -f` against the whole command line:
# any shell whose command text merely mentions a review -- another session's, a heredoc, this
# very check written into a wrapper -- matches `-f` and refuses a run for no reason. Measured:
# a shell in an unrelated directory held this guard closed with nothing running.
if pgrep -x coderabbit >/dev/null 2>&1; then
  echo "cr-local: a local review is already running (pgrep -x coderabbit); not starting a second" >&2
  exit 4
fi

# ...unless the caller passed `--base-commit` through: the CLI prefers `--base` and ignores it,
# so injecting a default here silently reviewed the whole branch against master instead of the
# commits asked for -- and answered in 16 seconds with "no new findings", which reads like a
# clean per-commit pass and is a deduplication of the branch pass before it. A slot for nothing.
case " ${extra[@]+${extra[*]}} " in
  *' --base-commit '*) base_commit_given=1 ;;
  *) base_commit_given=0 ;;
esac

# The base a pull request would use is the right base for a local pass too. A
# wrong active gh account answers with silence rather than an error (see
# cr_ensure_account), so pin it first and fall through to origin/HEAD.
if [ "$base_commit_given" = 1 ] && [ -n "$base" ]; then
  echo "cr-local: --base and --base-commit together; the CLI ignores the second. Drop one." >&2
  exit 2
fi
if [ "$base_commit_given" = 0 ] && [ -z "$base" ] && command -v gh >/dev/null 2>&1; then
  R=$(cr_repo 2>/dev/null || true)
  if [ -n "$R" ] && cr_ensure_account "$R" 2>/dev/null; then
    base=$(cr_gh pr view --repo "$R" --json baseRefName --jq .baseRefName 2>/dev/null || true)
  fi
fi
if [ "$base_commit_given" = 0 ] && [ -z "$base" ]; then
  base=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
fi

# Under .git so the log is invisible to git status and to the review itself.
log_dir="$(git rev-parse --git-dir)/coderabbit-local"
mkdir -p "$log_dir"
out="$log_dir/$(git rev-parse --abbrev-ref HEAD | tr '/' '-')-$(date +%Y%m%dT%H%M%S).log"

echo "cr-local: ${scope:-all tracked changes} against ${base:-the CLI default base}${light:+, light policy}" >&2
echo "cr-local: 7 to 30+ minutes is normal — scope it down rather than starting another" >&2
echo "cr-local: transcript → $out" >&2

case " ${extra[@]+${extra[*]}} " in
  *" --use-credits "*)
    echo "cr-local: --use-credits bills this review beyond the included allowance — real money, per file" >&2 ;;
esac

# Not retried, deliberately: a retried review is a second review, exactly as a
# retried `full review` comment was (see cr_gh). If it fails, read why first.
set +e
"$BIN" review ${scope:+$scope} ${light:+$light} ${base:+--base "$base"} ${extra[@]+"${extra[@]}"} 2>&1 | tee "$out"
status=${PIPESTATUS[0]}
set -e

if [ "$status" != 0 ]; then
  echo "cr-local: the CLI exited $status — read $out before re-running; a re-run costs another review" >&2
  exit "$status"
fi

cat >&2 <<EOF

cr-local: transcript kept at $out
          replay it with '$BIN review findings' — that costs nothing
          local findings are not on the pull request: no threads, no walkthrough,
          no evidence for the merge gate. They change what you push, not what you claim.
EOF
