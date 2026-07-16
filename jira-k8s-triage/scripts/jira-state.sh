#!/usr/bin/env bash
# 用法: jira-state.sh <ISSUE-KEY>
# 輸出分診狀態三態之一（deterministic，取代 prompt 層的水位線推理）：
#   UNTRIAGED         未分診
#   TRIAGED_NO_REPLY  已分診（含 footer 或 triaged label）且水位線後無新回覆
#   FOLLOWUP_PENDING  已分診且水位線後有他人 comment，待複診
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FOOTER='由 AI triage 產生'

[[ $# -eq 1 ]] || die "用法: jira-state.sh <ISSUE-KEY>"
KEY="$1"

jira_curl -G "$JIRA_BASE_URL/rest/api/2/issue/$KEY" \
  --data-urlencode 'fields=labels,comment' \
| jq -r --arg f "$FOOTER" '
  (.fields.comment.comments // []) as $c
  | ([$c | to_entries[] | select(.value.body | contains($f)) | .key]
     | if length > 0 then max else null end) as $wm
  | if $wm == null then
      (if ((.fields.labels // []) | index("triaged")) != null
       then "TRIAGED_NO_REPLY" else "UNTRIAGED" end)
    elif (($c | length) - 1) > $wm then "FOLLOWUP_PENDING"
    else "TRIAGED_NO_REPLY"
    end
'
