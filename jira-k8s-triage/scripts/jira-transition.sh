#!/usr/bin/env bash
# 用法: jira-transition.sh <ISSUE-KEY> <目標狀態名>
# 依目標狀態查詢可用 transition 並觸發（Jira 改 status 必須走 workflow transition）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 2 ]] || die "用法: jira-transition.sh <ISSUE-KEY> <目標狀態名>"
KEY="$1"
TARGET="$2"

trans="$(jira_curl "$JIRA_BASE_URL/rest/api/2/issue/$KEY/transitions")"
tid="$(jq -r --arg t "$TARGET" \
  '[.transitions[] | select(.to.name == $t or .name == $t)][0].id // empty' <<<"$trans")"

if [[ -z "$tid" ]]; then
  avail="$(jq -r '[.transitions[].to.name] | join(", ")' <<<"$trans")"
  die "$(printf '無法轉換到「%s」：此單目前可用的目標狀態為 %s（受 workflow 限制）' "$TARGET" "$avail")"
fi

payload="$(mktemp)"
jq -n --arg id "$tid" '{transition: {id: $id}}' > "$payload"
jira_curl -X POST -H 'Content-Type: application/json' \
  -d @"$payload" "$JIRA_BASE_URL/rest/api/2/issue/$KEY/transitions" > /dev/null
rm -f "$payload"

printf '%s status 已轉換為 %s\n' "$KEY" "$TARGET"
