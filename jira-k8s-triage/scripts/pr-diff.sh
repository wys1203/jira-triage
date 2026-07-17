#!/usr/bin/env bash
# 用法: pr-diff.sh <PR/MR 連結>
# 純 API 取得 PR diff（PR 判讀主路徑；無 token 或失敗時改走瀏覽器 fallback）。
#   GitLab:       GET /api/v4/projects/{id}/merge_requests/{iid}/diffs（分頁合併）
#   Azure DevOps: iterations/changes 取變更清單，逐檔抓 base/PR 兩版後本地 diff -u
# token 讀自認證檔（與 Jira 帳密同檔）：GITLAB_TOKEN（read_api 唯讀）、
# ADO_PAT（Code Read 唯讀）——唯讀 scope 使 approve 在 API 層物理上不可能。
# 認證一律經 stdin curl-config 傳入，不出現在指令列/ps。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FILE_CAP=50        # 超過此檔數僅列檔名，不展開 diff
DIFF_LINE_CAP=300  # 單檔 diff 輸出行數上限

[[ $# -eq 1 ]] || die '用法: pr-diff.sh <PR/MR 連結>'
URL="$1"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# git_curl <平台名> <token變數名> <curl-config行> <url>
git_curl() {
  local plat="$1" tvar="$2" cfg="$3" body_file http_code
  shift 3
  body_file="$(mktemp "$WORK/body.XXXXXX")"
  if ! http_code="$(printf '%s\n' "$cfg" \
      | curl -sS -K - --max-time 30 -o "$body_file" -w '%{http_code}' "$@" 2>/dev/null)"; then
    rm -f "$body_file"
    die "$(printf '%s%s' "$plat" ' API 連線失敗（網路錯誤或逾時 30 秒）')"
  fi
  case "$http_code" in
    2*)
      cat "$body_file"
      rm -f "$body_file"
      ;;
    401|403)
      rm -f "$body_file"
      die "$(printf '%s%s%s%s%s%s' "$plat" ' 回應 HTTP ' "$http_code" '：請檢查 ' "$tvar" ' 是否有效、未過期')"
      ;;
    404)
      rm -f "$body_file"
      die "$(printf '%s%s' "$plat" ' 回應 404：請確認 PR 連結正確，且 token 有權限讀取該 repo')"
      ;;
    *)
      rm -f "$body_file"
      die "$(printf '%s%s%s' "$plat" ' 回應 HTTP ' "$http_code")"
      ;;
  esac
}

# 單檔 diff 行數截斷
cap_lines() {
  awk -v cap="$DIFF_LINE_CAP" 'NR<=cap {print} NR==cap+1 {print "…（diff 過長，已截斷）"}'
}

# ---------- Azure DevOps ----------
re_ado='^(.+)/([^/]+)/_git/([^/]+)/pullrequest/([0-9]+)'
# ---------- GitLab ----------
re_gl='^(https?://[^/]+)/(.+)/-/merge_requests/([0-9]+)'
re_gl_old='^(https?://[^/]+)/(.+)/merge_requests/([0-9]+)'

if [[ "$URL" =~ $re_ado ]]; then
  base="${BASH_REMATCH[1]}"
  project="${BASH_REMATCH[2]}"
  repo="${BASH_REMATCH[3]}"
  prid="${BASH_REMATCH[4]}"
  [[ -n "${ADO_PAT:-}" ]] || die "$(printf '%s%s%s' '未設定 ADO_PAT：請在 ' "$JIRA_TRIAGE_ENV" ' 加入 ADO_PAT=<Code Read 唯讀 PAT>；設定前此單請改走瀏覽器判讀 fallback')"
  cfg="$(printf 'user = ":%s"' "$ADO_PAT")"
  api="$base/$project/_apis/git/repositories/$repo"

  pr_json="$(git_curl 'Azure DevOps' ADO_PAT "$cfg" "$api/pullrequests/$prid?api-version=6.0")"
  src="$(jq -r '.lastMergeSourceCommit.commitId // empty' <<<"$pr_json")"
  tgt="$(jq -r '.lastMergeTargetCommit.commitId // empty' <<<"$pr_json")"
  [[ -n "$src" && -n "$tgt" ]] || die 'Azure DevOps: PR 回應缺少 source/target commit（PR 可能尚未產生 merge 預覽）'

  iters="$(git_curl 'Azure DevOps' ADO_PAT "$cfg" "$api/pullrequests/$prid/iterations?api-version=6.0")"
  iter="$(jq -r '.value | max_by(.id) | .id' <<<"$iters")"
  changes="$(git_curl 'Azure DevOps' ADO_PAT "$cfg" "$api/pullrequests/$prid/iterations/$iter/changes?api-version=6.0")"
  files="$(jq '[.changeEntries[] | select((.item.isFolder // false) | not)]' <<<"$changes")"
  total="$(jq 'length' <<<"$files")"

  printf 'Platform: Azure DevOps\nPR: %s/%s #%s（共 %s 檔）\n' "$project" "$repo" "$prid" "$total"
  echo '--- 變更檔案清單 ---'
  jq -r '.[] | .item.path + " (" + .changeType + ")"' <<<"$files"
  if [[ "$total" -gt "$FILE_CAP" ]]; then
    printf '注意：變更共 %s 檔，超過展開上限 %s 檔，僅前 %s 檔展開 diff，其餘只列於清單\n' "$total" "$FILE_CAP" "$FILE_CAP"
  fi
  echo '--- Diff ---'
  jq -r '.[] | [.item.path, .changeType] | @tsv' <<<"$files" \
    | head -n "$FILE_CAP" \
    | while IFS="$(printf '\t')" read -r path ctype; do
        enc_path="$(jq -rn --arg p "$path" '$p|@uri')"
        base_f="$WORK/base"
        head_f="$WORK/head"
        : > "$base_f"
        : > "$head_f"
        if [[ "$ctype" != "add" ]]; then
          if ! git_curl 'Azure DevOps' ADO_PAT "$cfg" \
              "$api/items?path=$enc_path&versionDescriptor.versionType=commit&versionDescriptor.version=$tgt&api-version=6.0&\$format=text" \
              > "$base_f" 2>/dev/null; then
            printf '=== %s ===\n（無法取得 target 分支版本內容，略過 diff——可能為二進位檔或權限不足）\n' "$path"
            continue
          fi
        fi
        if [[ "$ctype" != "delete" ]]; then
          if ! git_curl 'Azure DevOps' ADO_PAT "$cfg" \
              "$api/items?path=$enc_path&versionDescriptor.versionType=commit&versionDescriptor.version=$src&api-version=6.0&\$format=text" \
              > "$head_f" 2>/dev/null; then
            printf '=== %s ===\n（無法取得 PR 版本內容，略過 diff——可能為二進位檔或權限不足）\n' "$path"
            continue
          fi
        fi
        printf '=== %s ===\n' "$path"
        diff -u -L "$(printf 'a%s (target)' "$path")" -L "$(printf 'b%s (PR)' "$path")" \
          "$base_f" "$head_f" | cap_lines
      done

elif [[ "$URL" =~ $re_gl ]] || [[ "$URL" =~ $re_gl_old ]]; then
  base="${BASH_REMATCH[1]}"
  proj="${BASH_REMATCH[2]}"
  iid="${BASH_REMATCH[3]}"
  [[ -n "${GITLAB_TOKEN:-}" ]] || die "$(printf '%s%s%s' '未設定 GITLAB_TOKEN：請在 ' "$JIRA_TRIAGE_ENV" ' 加入 GITLAB_TOKEN=<read_api 唯讀 token>；設定前此單請改走瀏覽器判讀 fallback')"
  cfg="$(printf 'header = "PRIVATE-TOKEN: %s"' "$GITLAB_TOKEN")"
  enc="$(jq -rn --arg p "$proj" '$p|@uri')"

  all='[]'
  page=1
  while :; do
    resp="$(git_curl GitLab GITLAB_TOKEN "$cfg" "$base/api/v4/projects/$enc/merge_requests/$iid/diffs?per_page=100&page=$page")"
    n="$(jq 'length' <<<"$resp")"
    if [[ "$n" -eq 0 ]]; then
      break
    fi
    all="$(printf '%s\n%s' "$all" "$resp" | jq -s '.[0] + .[1]')"
    page=$((page + 1))
    if [[ "$page" -gt 20 ]]; then
      # 安全上限 20 頁（2000 檔）——超過必然大於 FILE_CAP，清單已足夠
      break
    fi
  done
  total="$(jq 'length' <<<"$all")"

  printf 'Platform: GitLab\nMR: %s !%s（共 %s 檔）\n' "$proj" "$iid" "$total"
  echo '--- 變更檔案清單 ---'
  jq -r '.[] | .new_path
    + " (+" + ((.diff // "" | split("\n") | map(select(startswith("+") and (startswith("+++") | not))) | length | tostring))
    + " -"  + ((.diff // "" | split("\n") | map(select(startswith("-") and (startswith("---") | not))) | length | tostring))
    + ")"' <<<"$all"
  if [[ "$total" -gt "$FILE_CAP" ]]; then
    printf '注意：變更共 %s 檔，超過展開上限 %s 檔，僅前 %s 檔展開 diff，其餘只列於清單\n' "$total" "$FILE_CAP" "$FILE_CAP"
  fi
  echo '--- Diff ---'
  jq -r --argjson cap "$FILE_CAP" --argjson lcap "$DIFF_LINE_CAP" '
    .[:$cap][]
    | "=== \(.new_path) ===",
      ((.diff // "") | split("\n")
        | if length > $lcap then (.[:$lcap] | join("\n")) + "\n…（diff 過長，已截斷）" else join("\n") end)
  ' <<<"$all"

else
  die '無法辨識平台：僅支援 GitLab MR（.../merge_requests/<iid>）與 Azure DevOps PR（.../_git/<repo>/pullrequest/<id>）連結'
fi
