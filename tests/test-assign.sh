#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

# 1) 正常指派 assignee
out="$(bash "$SCRIPTS_DIR/jira-assign.sh" TEST-1 sshong 2>&1)"
assert_contains "$out" "TEST-1 assignee 已指派給 sshong" "成功指派 assignee"
put_body="$(cat "$MOCK_LOG_DIR/last-put.json")"
assert_contains "$put_body" '"name": "sshong"' "PUT payload 用 name 欄位（Jira Server 格式）"

# 2) 單號不存在 → 明確錯誤
out="$(bash "$SCRIPTS_DIR/jira-assign.sh" NOPE-1 sshong 2>&1 || true)"
assert_contains "$out" "404 找不到資源" "單號不存在時明確報錯"

# 3) 參數不足 → 顯示用法
out="$(bash "$SCRIPTS_DIR/jira-assign.sh" TEST-1 2>&1 || true)"
assert_contains "$out" "用法" "參數不足時顯示用法"
