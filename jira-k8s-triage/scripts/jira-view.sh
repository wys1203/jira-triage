#!/usr/bin/env bash
# 用法: jira-view.sh <ISSUE-KEY>
# 抓取 Jira 單並輸出精簡純文字（含 issue type、comments、附件清單）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 1 ]] || die "用法: jira-view.sh <ISSUE-KEY>"
KEY="$1"

jira_curl -G "$JIRA_BASE_URL/rest/api/2/issue/$KEY" \
  --data-urlencode 'fields=summary,description,status,issuetype,reporter,created,labels,comment,attachment' \
| jq -r '
  "KEY: \(.key)",
  "Type: \(.fields.issuetype.name)",
  "Status: \(.fields.status.name)",
  "Reporter: \(.fields.reporter.displayName // "unknown") (\(.fields.reporter.name // "unknown"))",
  "Created: \(.fields.created)",
  "Labels: \(.fields.labels | join(", "))",
  "Summary: \(.fields.summary)",
  "",
  "--- Description ---",
  (.fields.description // "(空白)"),
  "",
  "--- Comments (\(.fields.comment.total)) ---",
  (.fields.comment.comments[]? | "[\(.author.displayName) @ \(.created)]\n\(.body)\n"),
  "--- Attachments (\(.fields.attachment | length)) ---",
  (.fields.attachment[]? | "[\(.id)] \(.filename) (\(.mimeType), \(.size) bytes)")
'
