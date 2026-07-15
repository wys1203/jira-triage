#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

# 1) 正常更新 priority
out="$(bash "$SCRIPTS_DIR/jira-priority.sh" TEST-1 Highest 2>&1)"
assert_contains "$out" 'TEST-1 priority 已更新為 "Highest"' "成功更新 priority"
put_body="$(cat "$MOCK_LOG_DIR/last-put.json")"
assert_contains "$put_body" '"name": "Highest"' "PUT payload 用 fields.priority.name"

# 2) 不在允許清單的 priority → 明確錯誤
out="$(bash "$SCRIPTS_DIR/jira-priority.sh" TEST-1 Critical 2>&1 || true)"
assert_contains "$out" "不支援的 priority" "非法 priority 名稱時報錯"
assert_contains "$out" "Highest, High, Low, Lowest, Blocker, Minor" "錯誤訊息列出允許清單"

# 3) 參數不足 → 顯示用法
out="$(bash "$SCRIPTS_DIR/jira-priority.sh" TEST-1 2>&1 || true)"
assert_contains "$out" "用法" "參數不足時顯示用法"
