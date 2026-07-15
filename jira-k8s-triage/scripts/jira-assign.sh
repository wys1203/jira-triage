#!/usr/bin/env bash
# 用法: jira-assign.sh <ISSUE-KEY> <USERNAME>
# 指派 assignee；USERNAME 為 Jira Server 帳號名（[~username] 中的 username）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 2 ]] || die "用法: jira-assign.sh <ISSUE-KEY> <USERNAME>"
KEY="$1"
ASSIGNEE="$2"

payload="$(mktemp)"
jq -n --arg n "$ASSIGNEE" '{name: $n}' > "$payload"
jira_curl -X PUT -H 'Content-Type: application/json' \
  -d @"$payload" "$JIRA_BASE_URL/rest/api/2/issue/$KEY/assignee" > /dev/null
rm -f "$payload"

printf '%s assignee 已指派給 %s\n' "$KEY" "$ASSIGNEE"
