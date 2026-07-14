#!/usr/bin/env bash
# 共用函式：載入認證、封裝 curl、統一錯誤處理
# 由各 jira-*.sh script source，不直接執行
set -euo pipefail

JIRA_TRIAGE_ENV="${JIRA_TRIAGE_ENV:-$HOME/.jira-triage.env}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ -f "$JIRA_TRIAGE_ENV" ]] || die "$(printf '%s%s%s' '找不到認證檔 ' "$JIRA_TRIAGE_ENV" '。請建立該檔（chmod 600），內容三行：JIRA_BASE_URL=...、JIRA_USER=...、JIRA_PASS=...')"
# shellcheck source=/dev/null
source "$JIRA_TRIAGE_ENV"
[[ -n "${JIRA_BASE_URL:-}" ]] || die "$(printf '%s%s' "$JIRA_TRIAGE_ENV" ' 缺少 JIRA_BASE_URL')"
[[ -n "${JIRA_USER:-}" ]] || die "$(printf '%s%s' "$JIRA_TRIAGE_ENV" ' 缺少 JIRA_USER')"
[[ -n "${JIRA_PASS:-}" ]] || die "$(printf '%s%s' "$JIRA_TRIAGE_ENV" ' 缺少 JIRA_PASS')"

# jira_curl <curl 參數...>
# 認證由 stdin 以 curl config 傳入（-K -），密碼不出現在指令列/ps。
# 2xx: 印 response body 到 stdout；401/404/其他/逾時: 明確錯誤並 exit 1。
jira_curl() {
  local body_file http_code
  body_file="$(mktemp)"
  if ! http_code="$(printf 'user = "%s:%s"\n' "$JIRA_USER" "$JIRA_PASS" \
      | curl -sS -K - --max-time 30 -o "$body_file" -w '%{http_code}' "$@" 2>/dev/null)"; then
    rm -f "$body_file"
    die "$(printf '%s%s%s' '無法連線 Jira（網路錯誤或逾時 30 秒）：請確認 ' "$JIRA_BASE_URL" ' 可達')"
  fi
  case "$http_code" in
    2*)
      cat "$body_file"
      rm -f "$body_file"
      ;;
    401)
      rm -f "$body_file"
      die "$(printf '%s%s%s' '401 認證失敗：請檢查 ' "$JIRA_TRIAGE_ENV" ' 的 JIRA_USER / JIRA_PASS')"
      ;;
    404)
      rm -f "$body_file"
      die "404 找不到資源：請確認單號或附件 ID 是否存在"
      ;;
    *)
      rm -f "$body_file"
      die "Jira 回應 HTTP $http_code"
      ;;
  esac
}
