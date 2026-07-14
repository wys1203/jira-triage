#!/usr/bin/env bash
# 用法: jira-comment.sh <ISSUE-KEY> < comment.txt
# comment 內容（Jira 7.10 wiki markup）由 stdin 讀入
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 1 ]] || die "用法: jira-comment.sh <ISSUE-KEY> < comment.txt"
KEY="$1"

content="$(cat)"
[[ -n "$content" ]] || die "comment 內容為空（請由 stdin 提供 wiki markup 文字）"

# jira_curl 的 stdin 被 curl config（-K -）占用，payload 走 temp file
payload="$(mktemp)"
jq -n --arg b "$content" '{body: $b}' > "$payload"
resp="$(jira_curl -X POST -H 'Content-Type: application/json' \
  -d @"$payload" "$JIRA_BASE_URL/rest/api/2/issue/$KEY/comment")"
rm -f "$payload"

printf 'comment 已發布（id: %s）\n' "$(jq -r '.id' <<<"$resp")"
