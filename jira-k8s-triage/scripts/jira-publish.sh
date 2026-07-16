#!/usr/bin/env bash
# 用法: jira-publish.sh <ISSUE-KEY> <草稿檔> [--priority <值>] [--assign <username>] [--transition <狀態>]
# 原子化發布：lint 草稿 → comment → label → priority → assignee → transition
# 把「核可發布」的多個決策點收斂成一次呼叫；lint 不過就拒發，什麼都不碰
set -euo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS/lib.sh"

FOOTER='🤖 由 AI triage 產生，經工程師審核後發布'
USAGE='用法: jira-publish.sh <ISSUE-KEY> <草稿檔> [--priority <值>] [--assign <username>] [--transition <狀態>]'

[[ $# -ge 2 ]] || die "$USAGE"
KEY="$1"
DRAFT="$2"
shift 2

PRIORITY=""
ASSIGN=""
TRANSITION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --priority)   PRIORITY="$2";   shift 2 ;;
    --assign)     ASSIGN="$2";     shift 2 ;;
    --transition) TRANSITION="$2"; shift 2 ;;
    *) die "$(printf '未知參數 %s（%s）' "$1" "$USAGE")" ;;
  esac
done

[[ -s "$DRAFT" ]] || die "草稿檔不存在或為空: $DRAFT"

# ---------- 草稿 lint ----------
LINT_ERRORS=0
lint_err() {
  printf 'LINT: %s\n' "$*" >&2
  LINT_ERRORS=$((LINT_ERRORS + 1))
}

# footer 必須逐字存在（水位線機制依賴）
grep -qF "$FOOTER" "$DRAFT" || lint_err "缺少 footer（水位線機制依賴逐字一致）"

# 殘留 <填空位>：角括號內含非 ASCII（範本填空位皆為中文）
ph_pat="$(printf '<[^<>]*[\x80-\xff][^<>]*>')"
if LC_ALL=C grep -qE "$ph_pat" "$DRAFT"; then
  lint_err "殘留未替換的 <填空位>: $(LC_ALL=C grep -oE "$ph_pat" "$DRAFT" | head -3 | tr '\n' ' ')"
fi

# 規則編號列：以 PC-/SR-/PL- 開頭的行必須完全符合逗號串格式，且編號真實存在
code_lines="$(grep -E '^(PC|SR|PL)-' "$DRAFT" || true)"
if [[ -n "$code_lines" ]]; then
  while IFS= read -r line; do
    if ! [[ "$line" =~ ^(PC|SR|PL)-[0-9]{3}(,(PC|SR|PL)-[0-9]{3})*$ ]]; then
      lint_err "規則編號列格式錯誤: $line"
      continue
    fi
    for code in $(tr ',' ' ' <<<"$line"); do
      grep -rqE "^##+ $code:" "$SCRIPTS/../references" \
        || lint_err "編號 $code 不存在於規則庫（疑似幻覺引用）"
    done
  done <<<"$code_lines"
fi

if [[ $LINT_ERRORS -ne 0 ]]; then
  die "$(printf '草稿未通過 lint（%d 個問題），拒絕發布' "$LINT_ERRORS")"
fi

# ---------- 發布 ----------
bash "$SCRIPTS/jira-comment.sh" "$KEY" < "$DRAFT"

set +e
bash "$SCRIPTS/jira-label.sh" "$KEY"
label_rc=$?
set -e
if [[ $label_rc -eq 2 ]]; then
  echo "label 已存在（複診情境屬預期），略過"
elif [[ $label_rc -ne 0 ]]; then
  die "加 label 失敗（comment 已發出，請手動確認單的狀態）"
fi

[[ -z "$PRIORITY" ]] || bash "$SCRIPTS/jira-priority.sh" "$KEY" "$PRIORITY"
[[ -z "$ASSIGN" ]]   || bash "$SCRIPTS/jira-assign.sh" "$KEY" "$ASSIGN"

if [[ -n "$TRANSITION" ]]; then
  if ! bash "$SCRIPTS/jira-transition.sh" "$KEY" "$TRANSITION"; then
    echo "WARN: status 轉換失敗（workflow 限制），其餘步驟已完成" >&2
  fi
fi

printf '發布完成: %s\n' "$KEY"
