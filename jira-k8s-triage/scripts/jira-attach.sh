#!/usr/bin/env bash
# 用法: jira-attach.sh <ATTACHMENT-ID> [輸出目錄]
# 下載 Jira 附件，stdout 印出存檔完整路徑
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 ]] || die "用法: jira-attach.sh <ATTACHMENT-ID> [輸出目錄]"
ATT_ID="$1"
OUT_DIR="${2:-$(mktemp -d)}"
mkdir -p "$OUT_DIR"

meta="$(jira_curl "$JIRA_BASE_URL/rest/api/2/attachment/$ATT_ID")"
filename="$(jq -r '.filename' <<<"$meta")"
content_url="$(jq -r '.content' <<<"$meta")"

out_file="$OUT_DIR/$filename"
jira_curl "$content_url" > "$out_file"
printf '%s\n' "$out_file"
