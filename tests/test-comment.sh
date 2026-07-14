#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

out="$(printf 'h4. 分診報告\n症狀: CrashLoopBackOff\n' | bash "$SCRIPTS_DIR/jira-comment.sh" TEST-1 2>&1)"
assert_contains "$out" "comment 已發布（id: 20001）" "成功時印出 comment id"

posted="$(cat "$MOCK_LOG_DIR/last-post.json")"
assert_contains "$posted" '"body"' "POST payload 含 body 欄位"
assert_contains "$posted" '分診報告' "POST payload 含 comment 內容"
assert_contains "$posted" 'CrashLoopBackOff' "多行內容完整送出"

out="$(printf '' | bash "$SCRIPTS_DIR/jira-comment.sh" TEST-1 2>&1 || true)"
assert_contains "$out" "comment 內容為空" "空內容時拒絕發布"

out="$(bash "$SCRIPTS_DIR/jira-comment.sh" 2>&1 || true)"
assert_contains "$out" "用法" "無參數時顯示用法"
