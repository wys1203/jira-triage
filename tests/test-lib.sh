#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

# 1) env 檔不存在 → 明確錯誤
out="$(JIRA_TRIAGE_ENV=/nonexistent/path bash -c "source '$SCRIPTS_DIR/lib.sh'" 2>&1 || true)"
assert_contains "$out" "找不到認證檔" "缺 env 檔時給出明確錯誤"

# 2) env 檔缺少變數 → 明確錯誤
bad_env="$(mktemp)"
printf 'JIRA_BASE_URL=%s\n' "$MOCK_URL" > "$bad_env"
out="$(JIRA_TRIAGE_ENV=$bad_env bash -c "source '$SCRIPTS_DIR/lib.sh'" 2>&1 || true)"
assert_contains "$out" "缺少 JIRA_USER" "env 檔缺變數時指出缺哪個"

# 3) 401 → 提示檢查認證
out="$(bash -c "source '$SCRIPTS_DIR/lib.sh'; jira_curl \"\$JIRA_BASE_URL/rest/api/2/issue/AUTH-401\"" 2>&1 || true)"
assert_contains "$out" "401 認證失敗" "401 時提示檢查認證"

# 4) 404 → 提示資源不存在
out="$(bash -c "source '$SCRIPTS_DIR/lib.sh'; jira_curl \"\$JIRA_BASE_URL/rest/api/2/nothing\"" 2>&1 || true)"
assert_contains "$out" "404 找不到資源" "404 時提示資源不存在"

# 5) 2xx → 印出 body
out="$(bash -c "source '$SCRIPTS_DIR/lib.sh'; jira_curl \"\$JIRA_BASE_URL/rest/api/2/myself\"" 2>&1)"
assert_contains "$out" '"name": "tester"' "2xx 時輸出 response body"

# 6) 連不上 → 網路錯誤訊息
dead_env="$(mktemp)"
printf 'JIRA_BASE_URL=http://127.0.0.1:1\nJIRA_USER=x\nJIRA_PASS=y\n' > "$dead_env"
out="$(JIRA_TRIAGE_ENV=$dead_env bash -c "source '$SCRIPTS_DIR/lib.sh'; jira_curl \"\$JIRA_BASE_URL/rest/api/2/myself\"" 2>&1 || true)"
assert_contains "$out" "無法連線 Jira" "連線失敗時給網路錯誤訊息"
