#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

# 1) 正常轉換狀態（依 to.name 找 transition id）
out="$(bash "$SCRIPTS_DIR/jira-transition.sh" TEST-1 IMPLEMENT 2>&1)"
assert_contains "$out" "TEST-1 status 已轉換為 IMPLEMENT" "成功轉換狀態"
post_body="$(cat "$MOCK_LOG_DIR/last-post.json")"
assert_contains "$post_body" '"id": "21"' "POST payload 帶正確 transition id"

# 2) 目標狀態不在可用 transition 中 → 明確錯誤並列出可用狀態
out="$(bash "$SCRIPTS_DIR/jira-transition.sh" TEST-1 NOPE 2>&1 || true)"
assert_contains "$out" "無法轉換到" "無對應 transition 時報錯"
assert_contains "$out" "IMPLEMENT, Closed" "錯誤訊息列出可用目標狀態"

# 3) 參數不足 → 顯示用法
out="$(bash "$SCRIPTS_DIR/jira-transition.sh" TEST-1 2>&1 || true)"
assert_contains "$out" "用法" "參數不足時顯示用法"
