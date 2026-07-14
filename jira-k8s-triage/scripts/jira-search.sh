#!/usr/bin/env bash
# 用法: jira-search.sh '<JQL>'
# JQL 查詢並輸出精簡列表（單號 | type | 狀態 | 建立日期 | reporter | 標題）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 1 ]] || die "用法: jira-search.sh '<JQL>'"

jira_curl -G "$JIRA_BASE_URL/rest/api/2/search" \
  --data-urlencode "jql=$1" \
  --data-urlencode 'fields=summary,issuetype,status,created,reporter' \
  --data-urlencode 'maxResults=50' \
| jq -r '
  "共 \(.total) 張（顯示前 \(.issues | length) 張）",
  (.issues[] | "\(.key) | \(.fields.issuetype.name) | \(.fields.status.name) | \(.fields.created[0:10]) | \(.fields.reporter.displayName // "unknown") | \(.fields.summary)")
'
