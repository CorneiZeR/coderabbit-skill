#!/usr/bin/env bash
# Unresolved findings, with the comment id to reply to.
#
#   cr-threads.sh <pr> [--full]
#
# Bodies are truncated unless --full: CodeRabbit embeds its whole analysis
# transcript in a <details> block, which is rarely what you need to read.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
PR=${1:?usage: cr-threads.sh <pr> [--full]}
R=$(cr_repo)
cr_ensure_account "$R"
LIMIT=$([ "${2:-}" = --full ] && echo 100000 || echo 700)

cr_gh api "repos/$R/pulls/$PR/comments" --jq "
  .[] | select(.user.login==\"coderabbitai[bot]\") | select(.in_reply_to_id == null)
  | \"=== \(.path):\(.line // .original_line)  id=\(.id)\n\(.body | sub(\"(?s)<details>.*\";\"\") | .[0:$LIMIT])\n\"
"
echo "--- $(cr_unresolved "$R" "$PR") thread(s) still unresolved"
