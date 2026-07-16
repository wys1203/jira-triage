#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

mkdraft() { # <檔案> <內容>
  printf '%s\n' "$2" > "$1"
}

good_draft="$(mktemp)"
cat > "$good_draft" <<'EOF'
h4. 👋 我們看過您回報的問題了
測試內容：CrashLoopBackOff 已定位。
----
🤖 由 AI triage 產生，經工程師審核後發布
PC-001
EOF

# 1) 合法草稿 → 完整發布（comment + label + priority + assign + transition）
out="$(bash "$SCRIPTS_DIR/jira-publish.sh" TEST-1 "$good_draft" \
  --priority Highest --assign sshong --transition IMPLEMENT 2>&1)"
assert_contains "$out" "comment 已發布" "發布 comment"
assert_contains "$out" 'TEST-1 已加上 label "triaged"' "加 label"
assert_contains "$out" 'priority 已更新為 "Highest"' "更新 priority"
assert_contains "$out" "assignee 已指派給 sshong" "指派 assignee"
assert_contains "$out" "status 已轉換為 IMPLEMENT" "轉換 status"
assert_contains "$out" "發布完成: TEST-1" "回報發布完成"

# 2) 缺 footer → 拒發且不打任何 API
rm -f "$MOCK_LOG_DIR/last-post.json"
bad1="$(mktemp)"
printf 'h4. 報告\n內容\n' > "$bad1"
out="$(bash "$SCRIPTS_DIR/jira-publish.sh" TEST-1 "$bad1" 2>&1 || true)"
assert_contains "$out" "缺少 footer" "缺 footer 攔下"
assert_contains "$out" "拒絕發布" "lint 失敗拒絕發布"
if [[ ! -f "$MOCK_LOG_DIR/last-post.json" ]]; then
  echo "PASS: 拒發時未送出 comment"
else
  echo "FAIL: 拒發時未送出 comment"
  FAILURES=$((FAILURES + 1))
fi

# 3) 殘留填空位 → 攔下
bad2="$(mktemp)"
cat > "$bad2" <<'EOF'
h4. 報告
分流: → <團隊名>
----
🤖 由 AI triage 產生，經工程師審核後發布
EOF
out="$(bash "$SCRIPTS_DIR/jira-publish.sh" TEST-1 "$bad2" 2>&1 || true)"
assert_contains "$out" "填空位" "殘留填空位攔下"

# 4) 規則編號列格式錯誤 → 攔下
bad3="$(mktemp)"
cat > "$bad3" <<'EOF'
h4. 報告
內容
----
🤖 由 AI triage 產生，經工程師審核後發布
PC-01
EOF
out="$(bash "$SCRIPTS_DIR/jira-publish.sh" TEST-1 "$bad3" 2>&1 || true)"
assert_contains "$out" "規則編號列格式錯誤" "編號格式錯誤攔下"

# 5) 編號不存在於規則庫 → 攔下
bad4="$(mktemp)"
cat > "$bad4" <<'EOF'
h4. 報告
內容
----
🤖 由 AI triage 產生，經工程師審核後發布
PC-099
EOF
out="$(bash "$SCRIPTS_DIR/jira-publish.sh" TEST-1 "$bad4" 2>&1 || true)"
assert_contains "$out" "不存在於規則庫" "幻覺編號攔下"

# 6) 參數不足 → 用法
out="$(bash "$SCRIPTS_DIR/jira-publish.sh" TEST-1 2>&1 || true)"
assert_contains "$out" "用法" "參數不足時顯示用法"
