#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

out_dir="$(mktemp -d)"
out="$(bash "$SCRIPTS_DIR/jira-attach.sh" 10001 "$out_dir" 2>&1)"
assert_contains "$out" "$out_dir/pods.png" "stdout 印出存檔路徑"
if [[ "$(cat "$out_dir/pods.png")" == "PNGDATA" ]]; then
  echo "PASS: 下載內容正確"
else
  echo "FAIL: 下載內容正確"
  FAILURES=$((FAILURES + 1))
fi

out="$(bash "$SCRIPTS_DIR/jira-attach.sh" 2>&1 || true)"
assert_contains "$out" "用法" "無參數時顯示用法"

out="$(bash "$SCRIPTS_DIR/jira-attach.sh" 99999 2>&1 || true)"
assert_contains "$out" "404 找不到資源" "附件不存在時明確報錯"
