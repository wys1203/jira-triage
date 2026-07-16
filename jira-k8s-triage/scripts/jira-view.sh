#!/usr/bin/env bash
# 用法: jira-view.sh <ISSUE-KEY> [--all]
# 抓取 Jira 單並輸出精簡純文字（含 issue type、comments、附件清單）
# comments 預設只輸出最後 10 則（防 context 稀釋），--all 輸出全部；
# 描述超過 3000 字元截斷並標注
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 ]] || die "用法: jira-view.sh <ISSUE-KEY> [--all]"
KEY="$1"
ALL="${2:-}"

jira_curl -G "$JIRA_BASE_URL/rest/api/2/issue/$KEY" \
  --data-urlencode 'fields=summary,description,status,issuetype,reporter,created,labels,comment,attachment' \
| jq -r --arg all "$ALL" '
  (.fields.comment.comments // []) as $c
  | (if $all == "--all" or ($c | length) <= 10 then $c else $c[-10:] end) as $shown
  | "KEY: \(.key)",
  "Type: \(.fields.issuetype.name)",
  "Status: \(.fields.status.name)",
  "Reporter: \(.fields.reporter.displayName // "unknown") (\(.fields.reporter.name // "unknown"))",
  "Created: \(.fields.created)",
  "Labels: \(.fields.labels | join(", "))",
  "Summary: \(.fields.summary)",
  "",
  "--- Description ---",
  ((.fields.description // "(空白)")
    | if length > 3000 then .[0:3000] + "\n…（描述過長已截斷，原文共 \(length) 字元）" else . end),
  "",
  (if ($shown | length) < ($c | length)
   then "--- Comments (\($c | length)，顯示最後 10 則，--all 顯示全部) ---"
   else "--- Comments (\(.fields.comment.total)) ---" end),
  ($shown[]? | "[\(.author.displayName) @ \(.created)]\n\(.body)\n"),
  "--- Attachments (\(.fields.attachment | length)) ---",
  (.fields.attachment[]? | "[\(.id)] \(.filename) (\(.mimeType), \(.size) bytes)")
'
