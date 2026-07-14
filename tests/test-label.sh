#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

# 1) 正常加 label
out="$(bash "$SCRIPTS_DIR/jira-label.sh" TEST-1 2>&1)"
assert_contains "$out" 'TEST-1 已加上 label "triaged"' "成功加 label"
put_body="$(cat "$MOCK_LOG_DIR/last-put.json")"
assert_contains "$put_body" '"add": "triaged"' "PUT payload 用 update.labels add"

# 2) 已有 label → exit 2 且不打 PUT
rm -f "$MOCK_LOG_DIR/last-put.json"
set +e
out="$(bash "$SCRIPTS_DIR/jira-label.sh" TEST-2 2>&1)"
code=$?
set -e
if [[ $code -eq 2 ]]; then
  echo "PASS: 已有 label 時 exit 2"
else
  echo "FAIL: 已有 label 時 exit 2（實際 exit $code）"
  FAILURES=$((FAILURES + 1))
fi
assert_contains "$out" '已有 label "triaged"' "已有 label 時給出警告"
if [[ ! -f "$MOCK_LOG_DIR/last-put.json" ]]; then
  echo "PASS: 已有 label 時不送 PUT"
else
  echo "FAIL: 已有 label 時不送 PUT"
  FAILURES=$((FAILURES + 1))
fi

out="$(bash "$SCRIPTS_DIR/jira-label.sh" 2>&1 || true)"
assert_contains "$out" "用法" "無參數時顯示用法"
