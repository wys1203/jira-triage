#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_git_mock
make_env
trap finish EXIT

# 帶 token 的完整 env（token 與 Jira 帳密同檔）
FULL_ENV="$(mktemp)"
cat "$TEST_ENV" > "$FULL_ENV"
printf 'GITLAB_TOKEN=glpat-test\nADO_PAT=adopat-test\n' >> "$FULL_ENV"

GL_URL="$GIT_MOCK_URL/group/app/-/merge_requests/123"
GL_BIG_URL="$GIT_MOCK_URL/big/repo/-/merge_requests/9"
ADO_URL="$GIT_MOCK_URL/org/proj/_git/repo/pullrequest/7"

# --- 參數與 URL 判別 ---
out="$(bash "$SCRIPTS_DIR/pr-diff.sh" 2>&1 || true)"
assert_contains "$out" "用法" "無參數時顯示用法"

out="$(JIRA_TRIAGE_ENV="$FULL_ENV" bash "$SCRIPTS_DIR/pr-diff.sh" "http://example.com/not/a/pr" 2>&1 || true)"
assert_contains "$out" "無法辨識" "無法辨識的 URL 明確報錯"

# --- token 缺失（fallback 提示） ---
out="$(bash "$SCRIPTS_DIR/pr-diff.sh" "$GL_URL" 2>&1 || true)"
assert_contains "$out" "GITLAB_TOKEN" "GitLab 缺 token 時點名 GITLAB_TOKEN"
assert_contains "$out" "瀏覽器" "GitLab 缺 token 時提示瀏覽器 fallback"

out="$(bash "$SCRIPTS_DIR/pr-diff.sh" "$ADO_URL" 2>&1 || true)"
assert_contains "$out" "ADO_PAT" "ADO 缺 PAT 時點名 ADO_PAT"

# --- GitLab happy path（含分頁合併） ---
out="$(JIRA_TRIAGE_ENV="$FULL_ENV" bash "$SCRIPTS_DIR/pr-diff.sh" "$GL_URL" 2>&1)"
assert_contains "$out" "GitLab" "輸出標明平台"
assert_contains "$out" "charts/app/values.yaml (+2 -1)" "檔案清單含 +/- 行數"
assert_contains "$out" "quota/ns-quota.yaml" "第一頁第二檔在清單中"
assert_contains "$out" "docs/README.md" "第二頁檔案有被合併（分頁）"
assert_contains "$out" "=== charts/app/values.yaml ===" "逐檔 diff 區段標頭"
assert_contains "$out" "+cpu: 200m" "diff 內容完整輸出"
assert_contains "$out" "+# App" "第二頁 diff 內容也輸出"

# --- GitLab 錯誤 token ---
BAD_ENV="$(mktemp)"
cat "$TEST_ENV" > "$BAD_ENV"
printf 'GITLAB_TOKEN=wrong\nADO_PAT=adopat-test\n' >> "$BAD_ENV"
out="$(JIRA_TRIAGE_ENV="$BAD_ENV" bash "$SCRIPTS_DIR/pr-diff.sh" "$GL_URL" 2>&1 || true)"
assert_contains "$out" "401" "token 無效時回報 401 認證失敗"

# --- 檔案數上限：超過 50 檔僅列檔名不展開 diff ---
out="$(JIRA_TRIAGE_ENV="$FULL_ENV" bash "$SCRIPTS_DIR/pr-diff.sh" "$GL_BIG_URL" 2>&1)"
assert_contains "$out" "60" "超限時回報總檔數"
assert_contains "$out" "50" "超限時回報上限值"
assert_contains "$out" "file-59.yaml" "超限檔案仍列出檔名"
if grep -qF -- "=== file-59.yaml ===" <<<"$out"; then
  echo "FAIL: 超限檔案不展開 diff"
  FAILURES=$((FAILURES + 1))
else
  echo "PASS: 超限檔案不展開 diff"
fi

# --- Azure DevOps happy path（iterations/changes + 本地 diff） ---
out="$(JIRA_TRIAGE_ENV="$FULL_ENV" bash "$SCRIPTS_DIR/pr-diff.sh" "$ADO_URL" 2>&1)"
assert_contains "$out" "Azure DevOps" "輸出標明平台"
assert_contains "$out" "/app/deploy.yaml" "變更檔案清單含路徑"
assert_contains "$out" "-replicas: 2" "本地 diff 含 base 行"
assert_contains "$out" "+replicas: 4" "本地 diff 含 PR 行"
