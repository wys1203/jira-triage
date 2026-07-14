#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

out="$(bash "$SCRIPTS_DIR/jira-search.sh" 'project = TEST' 2>&1)"
assert_contains "$out" "共 2 張（顯示前 2 張）" "輸出總數"
assert_contains "$out" "TEST-1 | Something Broken | Open | 2026-07-14 | Alice Chen | payment namespace 的 pod 一直重啟" "每單一行含六欄"
assert_contains "$out" "TEST-3 | Ask Platform | Open | 2026-07-13 | Carol Lin | 請問 HPA 要怎麼設定" "第二單也正確"

out="$(bash "$SCRIPTS_DIR/jira-search.sh" 2>&1 || true)"
assert_contains "$out" "用法" "無參數時顯示用法"
