#!/usr/bin/env bash
# 測試共用：起停 mock server、產生測試用 env 檔、斷言
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$TESTS_DIR/../jira-k8s-triage/scripts"
MOCK_PORT="${MOCK_PORT:-18080}"
MOCK_URL="http://127.0.0.1:$MOCK_PORT"
FAILURES=0

start_mock() {
  MOCK_LOG_DIR="$(mktemp -d)"
  python3 "$TESTS_DIR/mock-jira.py" "$MOCK_PORT" "$TESTS_DIR/fixtures" "$MOCK_LOG_DIR" &
  MOCK_PID=$!
  local i
  for i in $(seq 1 30); do
    if curl -s -o /dev/null "$MOCK_URL/rest/api/2/myself"; then
      return 0
    fi
    sleep 0.1
  done
  echo "ERROR: mock server 啟動失敗（port $MOCK_PORT 可能被占用）" >&2
  exit 1
}

make_env() {
  TEST_ENV="$(mktemp)"
  printf 'JIRA_BASE_URL=%s\nJIRA_USER=tester\nJIRA_PASS=secret\n' "$MOCK_URL" > "$TEST_ENV"
  export JIRA_TRIAGE_ENV="$TEST_ENV"
}

stop_mock() {
  # MOCK_PID 未設時不可 kill（kill 0 會殺掉整個 process group）
  if [[ -n "${MOCK_PID:-}" ]]; then
    kill "$MOCK_PID" 2>/dev/null || true
  fi
}

assert_contains() { # <實際輸出> <預期子字串> <測項名>
  if grep -qF -- "$2" <<<"$1"; then
    echo "PASS: $3"
  else
    echo "FAIL: $3"
    echo "  預期包含: $2"
    echo "  實際輸出: $1"
    FAILURES=$((FAILURES + 1))
  fi
}

finish() {
  stop_mock
  if [[ $FAILURES -ne 0 ]]; then
    echo "$FAILURES 個測項失敗"
    exit 1
  fi
}
