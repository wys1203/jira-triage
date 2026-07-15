#!/usr/bin/env bash
# 用法: jira-priority.sh <ISSUE-KEY> <PRIORITY>
# 更新 Jira Priority 欄位；PRIORITY 必須是 Jira 專案已定義的名稱
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ALLOWED="Highest, High, Low, Lowest, Blocker, Minor"

[[ $# -eq 2 ]] || die "$(printf '用法: jira-priority.sh <ISSUE-KEY> <PRIORITY>（可用值: %s）' "$ALLOWED")"
KEY="$1"
PRIORITY="$2"

if ! grep -qxF -- "$PRIORITY" <<EOF
Highest
High
Low
Lowest
Blocker
Minor
EOF
then
  die "$(printf '不支援的 priority「%s」（可用值: %s）' "$PRIORITY" "$ALLOWED")"
fi

payload="$(mktemp)"
jq -n --arg p "$PRIORITY" '{fields: {priority: {name: $p}}}' > "$payload"
jira_curl -X PUT -H 'Content-Type: application/json' \
  -d @"$payload" "$JIRA_BASE_URL/rest/api/2/issue/$KEY" > /dev/null
rm -f "$payload"

printf '%s priority 已更新為 "%s"\n' "$KEY" "$PRIORITY"
