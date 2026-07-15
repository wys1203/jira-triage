#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

out="$(bash "$SCRIPTS_DIR/jira-view.sh" TEST-1 2>&1)"
assert_contains "$out" "KEY: TEST-1" "輸出單號"
assert_contains "$out" "Type: Something Broken" "輸出 issue type"
assert_contains "$out" "Status: Open" "輸出狀態"
assert_contains "$out" "Reporter: Alice Chen (achen)" "輸出 reporter 顯示名與帳號"
assert_contains "$out" "Summary: payment namespace 的 pod 一直重啟" "輸出 summary"
assert_contains "$out" "早上開始 checkout-api 一直掛" "輸出 description"
assert_contains "$out" "--- Comments (1) ---" "輸出 comment 區段與數量"
assert_contains "$out" "CrashLoopBackOff" "輸出 comment 內容"
assert_contains "$out" "--- Attachments (1) ---" "輸出附件區段與數量"
assert_contains "$out" "[10001] pods.png (image/png, 7 bytes)" "附件行含 ID/檔名/類型/大小"

out="$(bash "$SCRIPTS_DIR/jira-view.sh" 2>&1 || true)"
assert_contains "$out" "用法" "無參數時顯示用法"
