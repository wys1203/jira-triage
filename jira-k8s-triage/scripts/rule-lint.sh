#!/usr/bin/env bash
# 用法: rule-lint.sh
# 驗證規則庫結構不變量（規則庫維護閘門，修改 references/ 後必跑）：
#   1. PC/SR/PL 編號連續且不重複
#   2. 每條規則必要欄位齊全
#   3. SKILL.md 引用的節標題契約未被破壞
#   4. footer 水位線字串未被改動
# 全部通過 exit 0；否則列出 LINT: 問題並 exit 1。不需 Jira 認證。
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="$DIR/references"
ERRORS=0

err() {
  printf 'LINT: %s\n' "$*" >&2
  ERRORS=$((ERRORS + 1))
}

# check_numbering <前綴> <檔案> <標題正則（含前綴，不含數字）>
check_numbering() {
  local prefix="$1" file="$2" pat="$3"
  local nums sorted expect n want total_count uniq_count
  nums="$(grep -oE "${pat}[0-9]{3}" "$file" | grep -oE '[0-9]{3}$' || true)"
  if [[ -z "$nums" ]]; then
    err "$(basename "$file"): 找不到任何 $prefix 規則"
    return
  fi
  total_count="$(printf '%s\n' "$nums" | wc -l | tr -d ' ')"
  uniq_count="$(printf '%s\n' "$nums" | sort -u | wc -l | tr -d ' ')"
  [[ "$total_count" == "$uniq_count" ]] || err "$prefix: 編號重複"
  sorted="$(printf '%s\n' "$nums" | sort -u)"
  expect=1
  while IFS= read -r n; do
    printf -v want '%03d' "$expect"
    if [[ "$n" != "$want" ]]; then
      err "$prefix: 編號不連續（預期 $prefix-$want，實得 $prefix-$n）"
      break
    fi
    expect=$((expect + 1))
  done <<<"$sorted"
}

# check_fields <檔案> <標題正則> <欄位名>...
check_fields() {
  local file="$1" hpat="$2" nrules label nl
  shift 2
  nrules="$(grep -cE "$hpat" "$file" || true)"
  for label in "$@"; do
    nl="$(grep -cF "**${label}**:" "$file" || true)"
    [[ "$nl" == "$nrules" ]] || err "$(printf '%s: 「%s」欄位數（%s）與規則數（%s）不符' "$(basename "$file")" "$label" "$nl" "$nrules")"
  done
}

# check_heading <檔案> <標題字串>
check_heading() {
  local file="$1" h="$2"
  grep -qF "$h" "$file" || err "$(printf '%s: 缺少節標題「%s」' "$(basename "$file")" "$h")"
}

# 1) 編號
check_numbering PC "$REF/preconditions.md" '^## PC-'
check_numbering SR "$REF/routing.md" '^### SR-'
check_numbering PL "$REF/policies.md" '^## PL-'

# 2) 必要欄位
check_fields "$REF/preconditions.md" '^## PC-' 偵測條件 先天條件 標準回覆
check_fields "$REF/routing.md" '^### SR-' 語意特徵 分流對象
check_fields "$REF/policies.md" '^## PL-' 適用範圍 檢核條件 違規原因 重新提交指引

# 3) SKILL.md 引用的節標題契約
check_heading "$REF/routing.md" '## Severity 分級'
check_heading "$REF/routing.md" '## Urgency 分級'
check_heading "$REF/routing.md" '## Priority 交叉矩陣'
check_heading "$REF/routing.md" '### Jira Priority 映射'
check_heading "$REF/routing.md" '## 特例分流規則'
check_heading "$REF/routing.md" '## PR Review 分流'
check_heading "$REF/routing.md" '## K8s 領域分流表'
check_heading "$REF/routing.md" '## 止血措施庫'
check_heading "$REF/report-template.md" '## 語氣與對外原則'
check_heading "$REF/report-template.md" '## Something Broken 範本'
check_heading "$REF/report-template.md" '## Ask Platform 範本'
check_heading "$REF/report-template.md" '## Pull Request Review 範本'
check_heading "$REF/report-template.md" '## 請調整後重新提交範本'
check_heading "$REF/report-template.md" '## Follow-up 範本'
check_heading "$REF/questioning.md" '## LQQOPQRST 映射'
check_heading "$REF/questioning.md" '## Golden Signals 檢查'
check_heading "$REF/questioning.md" '## 選題規則'
check_heading "$REF/analysis.md" '## 圖片判讀準則'
check_heading "$REF/analysis.md" '## ArgoCD 頁面判讀準則'
check_heading "$REF/analysis.md" '## 外部連結判讀閘門'

# 4) 流程檔存在（SKILL.md 分派依賴）
for flow in broken ask pr-review followup closing discuss; do
  [[ -f "$REF/flows/$flow.md" ]] || err "flows/$flow.md 不存在（SKILL.md 分派依賴）"
done

# 5) footer 水位線字串（範本與 jira-state.sh 必須一致）
FOOTER_FULL='🤖 由 AI triage 產生，經工程師審核後發布'
grep -qF "$FOOTER_FULL" "$REF/report-template.md" \
  || err "report-template.md: footer 字串被改動（水位線機制依賴逐字一致）"
grep -qF "FOOTER='由 AI triage 產生'" "$DIR/scripts/jira-state.sh" \
  || err "jira-state.sh: footer 偵測字串與範本不一致"

if [[ $ERRORS -eq 0 ]]; then
  echo "RULE LINT PASSED"
else
  printf 'RULE LINT FAILED（%d 個問題）\n' "$ERRORS"
  exit 1
fi
