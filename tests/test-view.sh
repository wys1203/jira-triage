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

# 截斷行為：12 則 comments + 超長描述（fixture 由此處生成）
python3 - "$TESTS_DIR/fixtures/issue-TEST-5.json" <<'EOF'
import json, sys
comments = [{"author": {"displayName": "U"}, "created": "2026-07-15T10:00:00.000+0800",
             "body": "comment-number-%02d" % i} for i in range(1, 13)]
issue = {"key": "TEST-5", "fields": {
    "summary": "long thread", "description": "x" * 3500,
    "status": {"name": "Open"}, "issuetype": {"name": "Something Broken"},
    "reporter": {"displayName": "Alice Chen", "name": "achen"},
    "created": "2026-07-15T09:00:00.000+0800", "labels": [],
    "comment": {"total": 12, "comments": comments}, "attachment": []}}
open(sys.argv[1], "w").write(json.dumps(issue))
EOF

out="$(bash "$SCRIPTS_DIR/jira-view.sh" TEST-5 2>&1)"
assert_contains "$out" "顯示最後 10 則" "超過 10 則 comments 時標注截斷"
assert_contains "$out" "comment-number-12" "保留最新 comment"
assert_contains "$out" "comment-number-03" "保留倒數第 10 則"
if grep -qF "comment-number-02" <<<"$out"; then
  echo "FAIL: 預設不輸出第 11 舊的 comment"
  FAILURES=$((FAILURES + 1))
else
  echo "PASS: 預設不輸出第 11 舊的 comment"
fi
assert_contains "$out" "描述過長已截斷" "超長描述截斷加標記"

out="$(bash "$SCRIPTS_DIR/jira-view.sh" TEST-5 --all 2>&1)"
assert_contains "$out" "comment-number-01" "--all 輸出全部 comments"
