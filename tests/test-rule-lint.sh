#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
trap finish EXIT
SKILL_DIR="$TESTS_DIR/../jira-k8s-triage"

# 1) 對現行規則庫執行 → 通過
out="$(bash "$SKILL_DIR/scripts/rule-lint.sh" 2>&1)"
assert_contains "$out" "RULE LINT PASSED" "現行規則庫通過 lint"

# 2) 編號重複 → 攔下
tmp="$(mktemp -d)"
cp -R "$SKILL_DIR" "$tmp/skill"
sed -i.bak 's/^## PC-002:/## PC-001:/' "$tmp/skill/references/preconditions.md"
out="$(bash "$tmp/skill/scripts/rule-lint.sh" 2>&1 || true)"
assert_contains "$out" "編號" "編號重複/不連續時攔下"

# 3) 必要欄位缺失 → 攔下
tmp2="$(mktemp -d)"
cp -R "$SKILL_DIR" "$tmp2/skill"
sed -i.bak 's/\*\*偵測條件\*\*:/偵測條件:/' "$tmp2/skill/references/preconditions.md"
out="$(bash "$tmp2/skill/scripts/rule-lint.sh" 2>&1 || true)"
assert_contains "$out" "偵測條件" "必要欄位缺失時攔下"

# 4) 介面節標題被改壞 → 攔下
tmp3="$(mktemp -d)"
cp -R "$SKILL_DIR" "$tmp3/skill"
sed -i.bak 's/^## 止血措施庫/## 止血手段庫/' "$tmp3/skill/references/routing.md"
out="$(bash "$tmp3/skill/scripts/rule-lint.sh" 2>&1 || true)"
assert_contains "$out" "止血措施庫" "節標題契約破壞時攔下"

# 5) footer 字串被改動 → 攔下
tmp4="$(mktemp -d)"
cp -R "$SKILL_DIR" "$tmp4/skill"
sed -i.bak 's/由 AI triage 產生/由 AI 產生/' "$tmp4/skill/references/report-template.md"
out="$(bash "$tmp4/skill/scripts/rule-lint.sh" 2>&1 || true)"
assert_contains "$out" "footer" "footer 字串變動時攔下"

rm -rf "$tmp" "$tmp2" "$tmp3" "$tmp4"
