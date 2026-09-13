#!/usr/bin/env bash
# Reply inside a finding's thread, which is where an answer belongs.
#
#   cr-reply.sh <pr> <comment-id> "text"
#   cr-reply.sh <pr> <comment-id> -   # read the body from stdin
#
# CodeRabbit resolves the thread itself once it accepts the answer, so a
# still-unresolved thread is a reliable "not addressed yet".
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
PR=${1:?usage: cr-reply.sh <pr> <comment-id> <text|->}
ID=${2:?missing comment id}
BODY=${3:?missing body}
[ "$BODY" = - ] && BODY=$(cat)
R=$(cr_repo)
cr_ensure_account "$R"

cr_gh api "repos/$R/pulls/$PR/comments/$ID/replies" -f body="$BODY" --jq .html_url
