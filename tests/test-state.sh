#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

# 1) 無 footer 無 label → UNTRIAGED
out="$(bash "$SCRIPTS_DIR/jira-state.sh" TEST-1 2>&1)"
assert_contains "$out" "UNTRIAGED" "無 footer 無 label 判為未分診"

# 2) 有 triaged label 但無 footer（手動標記）→ TRIAGED_NO_REPLY
out="$(bash "$SCRIPTS_DIR/jira-state.sh" TEST-2 2>&1)"
assert_contains "$out" "TRIAGED_NO_REPLY" "有 label 無 footer 判為已分診無回覆"

# 3) footer 是最後一則 comment → TRIAGED_NO_REPLY
out="$(bash "$SCRIPTS_DIR/jira-state.sh" TEST-3 2>&1)"
assert_contains "$out" "TRIAGED_NO_REPLY" "footer 為最後一則時判為已分診無回覆"

# 4) footer 之後有他人 comment → FOLLOWUP_PENDING
out="$(bash "$SCRIPTS_DIR/jira-state.sh" TEST-4 2>&1)"
assert_contains "$out" "FOLLOWUP_PENDING" "水位線後有新回覆判為待複診"

# 5) 無參數 → 用法
out="$(bash "$SCRIPTS_DIR/jira-state.sh" 2>&1 || true)"
assert_contains "$out" "用法" "無參數時顯示用法"
