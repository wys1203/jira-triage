#!/usr/bin/env bash
# 用法: jira-label.sh <ISSUE-KEY> [LABEL]
# 預設 label 為 triaged；若該單已有此 label 則 exit 2（冪等保護，防重複分診）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 ]] || die "用法: jira-label.sh <ISSUE-KEY> [LABEL]"
KEY="$1"
LABEL="${2:-triaged}"

existing="$(jira_curl -G "$JIRA_BASE_URL/rest/api/2/issue/$KEY" \
  --data-urlencode 'fields=labels' | jq -r '.fields.labels[]?')"
if grep -qxF -- "$LABEL" <<<"$existing"; then
  printf '%s 已有 label "%s"（可能已分診過），不重複加上\n' "$KEY" "$LABEL" >&2
  exit 2
fi

payload="$(mktemp)"
jq -n --arg l "$LABEL" '{update: {labels: [{add: $l}]}}' > "$payload"
jira_curl -X PUT -H 'Content-Type: application/json' \
  -d @"$payload" "$JIRA_BASE_URL/rest/api/2/issue/$KEY" > /dev/null
rm -f "$payload"

printf '%s 已加上 label "%s"\n' "$KEY" "$LABEL"
