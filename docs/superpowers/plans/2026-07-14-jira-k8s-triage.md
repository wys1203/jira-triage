# jira-k8s-triage Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立一個 Claude Code skill，對 Jira Server 7.10 的 K8s 報案單執行標準 Triage Loop 分診（含截圖分析與 GitLab/Azure DevOps PR 判讀），經人工確認後回寫 comment 與 label。

**Architecture:** 「Skill + 輔助 scripts」兩層：SKILL.md 承載 Triage Loop 方法論與 issue type 分派邏輯（references/ 三份設定檔），scripts/ 五支 bash script 封裝 Jira REST API v2 呼叫並把肥大 JSON 壓成精簡文字。測試用 python3 mock Jira server 離線驗證每支 script。

**Tech Stack:** bash 3.2（macOS 內建）、curl、jq 1.8、python3（僅測試用 mock server）、Jira Server 7.10 REST API v2。

**設計文件:** `docs/superpowers/specs/2026-07-14-jira-k8s-triage-design.md`

## Global Constraints

- 目標 Jira 版本：**Jira Server v7.10**，REST API 路徑一律 `/rest/api/2/...`，comment 使用 **wiki markup**（非 ADF）
- 認證：Basic Auth，credentials 讀自 `~/.jira-triage.env`（可用環境變數 `JIRA_TRIAGE_ENV` 覆蓋路徑，測試靠這個）；env 檔內含 `JIRA_BASE_URL`、`JIRA_USER`、`JIRA_PASS`
- **密碼絕不出現在指令列參數**（避免進 shell history 與 `ps`）：curl 認證一律用 `printf 'user = "%s:%s"' ... | curl -K -` 由 stdin 傳入
- scripts 必須相容 **bash 3.2**：禁用關聯陣列、`${var,,}`、`mapfile` 等 bash 4+ 語法
- 所有 script 錯誤訊息用繁體中文、以 `ERROR:` 開頭、寫到 stderr、非零 exit code
- 測試 mock server 固定使用 port **18080**（fixtures 內的 URL 寫死此 port）
- repo 佈局：skill 本體在 `jira-k8s-triage/` 子目錄（安裝時 symlink 進 `~/.claude/skills/`），測試在 `tests/`
- commit message 前綴依內容用 `feat:` / `test:` / `docs:`

## File Structure

```
jira-triage/                          # repo root（已存在，含 docs/）
├── jira-k8s-triage/                  # skill 本體（symlink 安裝目標）
│   ├── SKILL.md                      # 入口：設定區、兩種模式、issue type 分派、確認流程
│   ├── references/
│   │   ├── routing.md                # 分級矩陣、K8s 領域分流表、止血措施庫
│   │   ├── report-template.md        # 三種 issue type 的分診報告範本（wiki markup）
│   │   └── questioning.md            # LQQOPQRST 映射 + Golden Signals 提問庫
│   └── scripts/
│       ├── lib.sh                    # 共用：載入認證、jira_curl 封裝、錯誤處理
│       ├── jira-view.sh              # 抓單 → 精簡純文字
│       ├── jira-search.sh            # JQL 查詢 → 精簡列表
│       ├── jira-attach.sh            # 下載附件
│       ├── jira-comment.sh           # 發 comment
│       └── jira-label.sh             # 加 label（冪等保護）
└── tests/
    ├── mock-jira.py                  # 離線 mock Jira server
    ├── helper.sh                     # 測試共用：起停 mock、assert
    ├── run-all.sh                    # 跑所有 test-*.sh
    ├── fixtures/                     # canned JSON responses
    │   ├── issue-TEST-1.json
    │   ├── issue-TEST-2.json
    │   ├── search.json
    │   └── attachment-10001.json
    └── test-*.sh                     # 每支 script 一份測試
```

---

### Task 1: 測試基礎設施 + lib.sh（認證載入與 jira_curl 封裝）

**Files:**
- Create: `tests/mock-jira.py`
- Create: `tests/helper.sh`
- Create: `tests/run-all.sh`
- Create: `jira-k8s-triage/scripts/lib.sh`
- Test: `tests/test-lib.sh`

**Interfaces:**
- Produces: `lib.sh` 供後續所有 script `source`，提供：
  - 已驗證的環境變數 `JIRA_BASE_URL`、`JIRA_USER`、`JIRA_PASS`
  - `die <訊息>` — 印 `ERROR: <訊息>` 到 stderr 並 exit 1
  - `jira_curl <curl 參數...>` — 帶認證呼叫，2xx 印 body 到 stdout；401/404/逾時給明確中文錯誤並 exit 1
- Produces: `helper.sh` 供所有測試 `source`，提供 `start_mock`、`make_env`、`stop_mock`、`assert_contains <實際輸出> <預期子字串> <測項名>`、`finish`（trap EXIT 用）
- Produces: mock server 路由（本 task 只需 `/rest/api/2/myself` 與 `/rest/api/2/issue/AUTH-401`，其餘路由在後續 task 已一次寫齊）

- [ ] **Step 1: 寫 mock Jira server**

```python
#!/usr/bin/env python3
"""離線 mock Jira Server 7.10，供 script 測試使用。
用法: mock-jira.py <port> <fixtures_dir> <log_dir>
POST/PUT 的 request body 會寫入 log_dir 供測試斷言。"""
import sys
import http.server
import pathlib

PORT = int(sys.argv[1])
FIX = pathlib.Path(sys.argv[2])
LOG = pathlib.Path(sys.argv[3])


class Handler(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body=b"", ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/rest/api/2/myself":
            self._send(200, b'{"name": "tester"}')
        elif path == "/rest/api/2/issue/AUTH-401":
            self._send(401, b"{}")
        elif path == "/rest/api/2/issue/TEST-1":
            self._send(200, (FIX / "issue-TEST-1.json").read_bytes())
        elif path == "/rest/api/2/issue/TEST-2":
            self._send(200, (FIX / "issue-TEST-2.json").read_bytes())
        elif path == "/rest/api/2/search":
            self._send(200, (FIX / "search.json").read_bytes())
        elif path == "/rest/api/2/attachment/10001":
            self._send(200, (FIX / "attachment-10001.json").read_bytes())
        elif path == "/secure/attachment/10001/pods.png":
            self._send(200, b"PNGDATA", "image/png")
        else:
            self._send(404, b"{}")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        (LOG / "last-post.json").write_bytes(self.rfile.read(length))
        if self.path == "/rest/api/2/issue/TEST-1/comment":
            self._send(201, b'{"id": "20001"}')
        else:
            self._send(404, b"{}")

    def do_PUT(self):
        length = int(self.headers.get("Content-Length", 0))
        (LOG / "last-put.json").write_bytes(self.rfile.read(length))
        if self.path == "/rest/api/2/issue/TEST-1":
            self._send(204)
        else:
            self._send(404, b"{}")

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
```

寫入 `tests/mock-jira.py`。

- [ ] **Step 2: 寫測試 helper**

```bash
#!/usr/bin/env bash
# 測試共用：起停 mock server、產生測試用 env 檔、斷言
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$TESTS_DIR/../jira-k8s-triage/scripts"
MOCK_PORT="${MOCK_PORT:-18080}"
MOCK_URL="http://127.0.0.1:$MOCK_PORT"
FAILURES=0

start_mock() {
  MOCK_LOG_DIR="$(mktemp -d)"
  python3 "$TESTS_DIR/mock-jira.py" "$MOCK_PORT" "$TESTS_DIR/fixtures" "$MOCK_LOG_DIR" &
  MOCK_PID=$!
  local i
  for i in $(seq 1 30); do
    if curl -s -o /dev/null "$MOCK_URL/rest/api/2/myself"; then
      return 0
    fi
    sleep 0.1
  done
  echo "ERROR: mock server 啟動失敗（port $MOCK_PORT 可能被占用）" >&2
  exit 1
}

make_env() {
  TEST_ENV="$(mktemp)"
  printf 'JIRA_BASE_URL=%s\nJIRA_USER=tester\nJIRA_PASS=secret\n' "$MOCK_URL" > "$TEST_ENV"
  export JIRA_TRIAGE_ENV="$TEST_ENV"
}

stop_mock() {
  kill "${MOCK_PID:-0}" 2>/dev/null || true
}

assert_contains() { # <實際輸出> <預期子字串> <測項名>
  if grep -qF -- "$2" <<<"$1"; then
    echo "PASS: $3"
  else
    echo "FAIL: $3"
    echo "  預期包含: $2"
    echo "  實際輸出: $1"
    FAILURES=$((FAILURES + 1))
  fi
}

finish() {
  stop_mock
  if [[ $FAILURES -ne 0 ]]; then
    echo "$FAILURES 個測項失敗"
    exit 1
  fi
}
```

寫入 `tests/helper.sh`。同時建立空的 fixtures 目錄：`mkdir -p tests/fixtures`（fixture 檔在後續 task 加入；本 task 的路由只用到 hardcoded response）。

- [ ] **Step 3: 寫 run-all.sh**

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
overall=0
for t in test-*.sh; do
  echo "== $t =="
  bash "$t" || overall=1
done
if [[ $overall -eq 0 ]]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
  exit 1
fi
```

寫入 `tests/run-all.sh`，`chmod +x tests/run-all.sh tests/mock-jira.py`。

- [ ] **Step 4: 寫 lib.sh 的失敗測試**

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

# 1) env 檔不存在 → 明確錯誤
out="$(JIRA_TRIAGE_ENV=/nonexistent/path bash -c "source '$SCRIPTS_DIR/lib.sh'" 2>&1 || true)"
assert_contains "$out" "找不到認證檔" "缺 env 檔時給出明確錯誤"

# 2) env 檔缺少變數 → 明確錯誤
bad_env="$(mktemp)"
printf 'JIRA_BASE_URL=%s\n' "$MOCK_URL" > "$bad_env"
out="$(JIRA_TRIAGE_ENV=$bad_env bash -c "source '$SCRIPTS_DIR/lib.sh'" 2>&1 || true)"
assert_contains "$out" "缺少 JIRA_USER" "env 檔缺變數時指出缺哪個"

# 3) 401 → 提示檢查認證
out="$(bash -c "source '$SCRIPTS_DIR/lib.sh'; jira_curl \"\$JIRA_BASE_URL/rest/api/2/issue/AUTH-401\"" 2>&1 || true)"
assert_contains "$out" "401 認證失敗" "401 時提示檢查認證"

# 4) 404 → 提示資源不存在
out="$(bash -c "source '$SCRIPTS_DIR/lib.sh'; jira_curl \"\$JIRA_BASE_URL/rest/api/2/nothing\"" 2>&1 || true)"
assert_contains "$out" "404 找不到資源" "404 時提示資源不存在"

# 5) 2xx → 印出 body
out="$(bash -c "source '$SCRIPTS_DIR/lib.sh'; jira_curl \"\$JIRA_BASE_URL/rest/api/2/myself\"" 2>&1)"
assert_contains "$out" '"name": "tester"' "2xx 時輸出 response body"

# 6) 連不上 → 網路錯誤訊息
dead_env="$(mktemp)"
printf 'JIRA_BASE_URL=http://127.0.0.1:1\nJIRA_USER=x\nJIRA_PASS=y\n' > "$dead_env"
out="$(JIRA_TRIAGE_ENV=$dead_env bash -c "source '$SCRIPTS_DIR/lib.sh'; jira_curl \"\$JIRA_BASE_URL/rest/api/2/myself\"" 2>&1 || true)"
assert_contains "$out" "無法連線 Jira" "連線失敗時給網路錯誤訊息"
```

寫入 `tests/test-lib.sh`。

- [ ] **Step 5: 跑測試確認失敗**

Run: `bash tests/test-lib.sh`
Expected: 全部 FAIL（lib.sh 不存在，`source` 失敗）

- [ ] **Step 6: 實作 lib.sh**

```bash
#!/usr/bin/env bash
# 共用函式：載入認證、封裝 curl、統一錯誤處理
# 由各 jira-*.sh script source，不直接執行
set -euo pipefail

JIRA_TRIAGE_ENV="${JIRA_TRIAGE_ENV:-$HOME/.jira-triage.env}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ -f "$JIRA_TRIAGE_ENV" ]] || die "找不到認證檔 $JIRA_TRIAGE_ENV。請建立該檔（chmod 600），內容三行：JIRA_BASE_URL=...、JIRA_USER=...、JIRA_PASS=..."
# shellcheck source=/dev/null
source "$JIRA_TRIAGE_ENV"
[[ -n "${JIRA_BASE_URL:-}" ]] || die "$JIRA_TRIAGE_ENV 缺少 JIRA_BASE_URL"
[[ -n "${JIRA_USER:-}" ]] || die "$JIRA_TRIAGE_ENV 缺少 JIRA_USER"
[[ -n "${JIRA_PASS:-}" ]] || die "$JIRA_TRIAGE_ENV 缺少 JIRA_PASS"

# jira_curl <curl 參數...>
# 認證由 stdin 以 curl config 傳入（-K -），密碼不出現在指令列/ps。
# 2xx: 印 response body 到 stdout；401/404/其他/逾時: 明確錯誤並 exit 1。
jira_curl() {
  local body_file http_code
  body_file="$(mktemp)"
  if ! http_code="$(printf 'user = "%s:%s"\n' "$JIRA_USER" "$JIRA_PASS" \
      | curl -sS -K - --max-time 30 -o "$body_file" -w '%{http_code}' "$@" 2>/dev/null)"; then
    rm -f "$body_file"
    die "無法連線 Jira（網路錯誤或逾時 30 秒）：請確認 $JIRA_BASE_URL 可達"
  fi
  case "$http_code" in
    2*)
      cat "$body_file"
      rm -f "$body_file"
      ;;
    401)
      rm -f "$body_file"
      die "401 認證失敗：請檢查 $JIRA_TRIAGE_ENV 的 JIRA_USER / JIRA_PASS"
      ;;
    404)
      rm -f "$body_file"
      die "404 找不到資源：請確認單號或附件 ID 是否存在"
      ;;
    *)
      rm -f "$body_file"
      die "Jira 回應 HTTP $http_code"
      ;;
  esac
}
```

寫入 `jira-k8s-triage/scripts/lib.sh`。

- [ ] **Step 7: 跑測試確認通過**

Run: `bash tests/test-lib.sh`
Expected: 6 個 PASS，exit 0

- [ ] **Step 8: Commit**

```bash
git add tests/ jira-k8s-triage/scripts/lib.sh
git commit -m "feat: add lib.sh auth/curl wrapper with offline mock jira test harness"
```

---

### Task 2: jira-view.sh（抓單 → 精簡純文字）

**Files:**
- Create: `jira-k8s-triage/scripts/jira-view.sh`
- Create: `tests/fixtures/issue-TEST-1.json`
- Test: `tests/test-view.sh`

**Interfaces:**
- Consumes: `lib.sh` 的 `die`、`jira_curl`
- Produces: `jira-view.sh <ISSUE-KEY>` — stdout 輸出精簡文字，固定含 `KEY:`、`Type:`、`Status:`、`Reporter:`、`Created:`、`Labels:`、`Summary:` 行，以及 `--- Description ---`、`--- Comments (N) ---`、`--- Attachments (N) ---` 三個區段；附件行格式 `[<附件ID>] <檔名> (<mime>, <size> bytes)`（SKILL.md 依此判斷 issue type 與附件）

- [ ] **Step 1: 寫 fixture**

```json
{
  "key": "TEST-1",
  "fields": {
    "summary": "payment namespace 的 pod 一直重啟",
    "description": "早上開始 checkout-api 一直掛，附截圖。",
    "status": {"name": "Open"},
    "issuetype": {"name": "Something Broken"},
    "reporter": {"displayName": "Alice Chen"},
    "created": "2026-07-14T09:12:00.000+0800",
    "labels": [],
    "comment": {
      "total": 1,
      "comments": [
        {
          "author": {"displayName": "Bob Wu"},
          "created": "2026-07-14T09:30:00.000+0800",
          "body": "我也遇到，錯誤是 CrashLoopBackOff"
        }
      ]
    },
    "attachment": [
      {
        "id": "10001",
        "filename": "pods.png",
        "mimeType": "image/png",
        "size": 7,
        "content": "http://127.0.0.1:18080/secure/attachment/10001/pods.png"
      }
    ]
  }
}
```

寫入 `tests/fixtures/issue-TEST-1.json`（注意 `content` URL 寫死 mock port 18080）。

- [ ] **Step 2: 寫失敗測試**

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

out="$(bash "$SCRIPTS_DIR/jira-view.sh" TEST-1 2>&1)"
assert_contains "$out" "KEY: TEST-1" "輸出單號"
assert_contains "$out" "Type: Something Broken" "輸出 issue type"
assert_contains "$out" "Status: Open" "輸出狀態"
assert_contains "$out" "Reporter: Alice Chen" "輸出 reporter"
assert_contains "$out" "Summary: payment namespace 的 pod 一直重啟" "輸出 summary"
assert_contains "$out" "早上開始 checkout-api 一直掛" "輸出 description"
assert_contains "$out" "--- Comments (1) ---" "輸出 comment 區段與數量"
assert_contains "$out" "CrashLoopBackOff" "輸出 comment 內容"
assert_contains "$out" "--- Attachments (1) ---" "輸出附件區段與數量"
assert_contains "$out" "[10001] pods.png (image/png, 7 bytes)" "附件行含 ID/檔名/類型/大小"

out="$(bash "$SCRIPTS_DIR/jira-view.sh" 2>&1 || true)"
assert_contains "$out" "用法" "無參數時顯示用法"
```

寫入 `tests/test-view.sh`。

- [ ] **Step 3: 跑測試確認失敗**

Run: `bash tests/test-view.sh`
Expected: 全部 FAIL（jira-view.sh 不存在）

- [ ] **Step 4: 實作 jira-view.sh**

```bash
#!/usr/bin/env bash
# 用法: jira-view.sh <ISSUE-KEY>
# 抓取 Jira 單並輸出精簡純文字（含 issue type、comments、附件清單）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 1 ]] || die "用法: jira-view.sh <ISSUE-KEY>"
KEY="$1"

jira_curl -G "$JIRA_BASE_URL/rest/api/2/issue/$KEY" \
  --data-urlencode 'fields=summary,description,status,issuetype,reporter,created,labels,comment,attachment' \
| jq -r '
  "KEY: \(.key)",
  "Type: \(.fields.issuetype.name)",
  "Status: \(.fields.status.name)",
  "Reporter: \(.fields.reporter.displayName // "unknown")",
  "Created: \(.fields.created)",
  "Labels: \(.fields.labels | join(", "))",
  "Summary: \(.fields.summary)",
  "",
  "--- Description ---",
  (.fields.description // "(空白)"),
  "",
  "--- Comments (\(.fields.comment.total)) ---",
  (.fields.comment.comments[]? | "[\(.author.displayName) @ \(.created)]\n\(.body)\n"),
  "--- Attachments (\(.fields.attachment | length)) ---",
  (.fields.attachment[]? | "[\(.id)] \(.filename) (\(.mimeType), \(.size) bytes)")
'
```

寫入 `jira-k8s-triage/scripts/jira-view.sh`，`chmod +x`。

- [ ] **Step 5: 跑測試確認通過**

Run: `bash tests/test-view.sh`
Expected: 11 個 PASS，exit 0

- [ ] **Step 6: Commit**

```bash
git add jira-k8s-triage/scripts/jira-view.sh tests/fixtures/issue-TEST-1.json tests/test-view.sh
git commit -m "feat: add jira-view.sh issue fetcher with condensed text output"
```

---

### Task 3: jira-search.sh（JQL 查詢 → 精簡列表）

**Files:**
- Create: `jira-k8s-triage/scripts/jira-search.sh`
- Create: `tests/fixtures/search.json`
- Test: `tests/test-search.sh`

**Interfaces:**
- Consumes: `lib.sh` 的 `die`、`jira_curl`
- Produces: `jira-search.sh '<JQL>'` — 首行 `共 N 張（顯示前 M 張）`，之後每單一行：`<KEY> | <type> | <status> | <created日期> | <reporter> | <summary>`（SKILL.md 佇列模式依此列總覽）

- [ ] **Step 1: 寫 fixture**

```json
{
  "total": 2,
  "issues": [
    {
      "key": "TEST-1",
      "fields": {
        "summary": "payment namespace 的 pod 一直重啟",
        "issuetype": {"name": "Something Broken"},
        "status": {"name": "Open"},
        "created": "2026-07-14T09:12:00.000+0800",
        "reporter": {"displayName": "Alice Chen"}
      }
    },
    {
      "key": "TEST-3",
      "fields": {
        "summary": "請問 HPA 要怎麼設定",
        "issuetype": {"name": "Ask Platform"},
        "status": {"name": "Open"},
        "created": "2026-07-13T15:00:00.000+0800",
        "reporter": {"displayName": "Carol Lin"}
      }
    }
  ]
}
```

寫入 `tests/fixtures/search.json`。

- [ ] **Step 2: 寫失敗測試**

```bash
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
```

寫入 `tests/test-search.sh`。

- [ ] **Step 3: 跑測試確認失敗**

Run: `bash tests/test-search.sh`
Expected: 全部 FAIL（jira-search.sh 不存在）

- [ ] **Step 4: 實作 jira-search.sh**

```bash
#!/usr/bin/env bash
# 用法: jira-search.sh '<JQL>'
# JQL 查詢並輸出精簡列表（單號 | type | 狀態 | 建立日期 | reporter | 標題）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 1 ]] || die "用法: jira-search.sh '<JQL>'"

jira_curl -G "$JIRA_BASE_URL/rest/api/2/search" \
  --data-urlencode "jql=$1" \
  --data-urlencode 'fields=summary,issuetype,status,created,reporter' \
  --data-urlencode 'maxResults=50' \
| jq -r '
  "共 \(.total) 張（顯示前 \(.issues | length) 張）",
  (.issues[] | "\(.key) | \(.fields.issuetype.name) | \(.fields.status.name) | \(.fields.created[0:10]) | \(.fields.reporter.displayName // "unknown") | \(.fields.summary)")
'
```

寫入 `jira-k8s-triage/scripts/jira-search.sh`，`chmod +x`。

- [ ] **Step 5: 跑測試確認通過**

Run: `bash tests/test-search.sh`
Expected: 4 個 PASS，exit 0

- [ ] **Step 6: Commit**

```bash
git add jira-k8s-triage/scripts/jira-search.sh tests/fixtures/search.json tests/test-search.sh
git commit -m "feat: add jira-search.sh JQL query with condensed list output"
```

---

### Task 4: jira-attach.sh（下載附件）

**Files:**
- Create: `jira-k8s-triage/scripts/jira-attach.sh`
- Create: `tests/fixtures/attachment-10001.json`
- Test: `tests/test-attach.sh`

**Interfaces:**
- Consumes: `lib.sh` 的 `die`、`jira_curl`
- Produces: `jira-attach.sh <ATTACHMENT-ID> [輸出目錄]` — 下載附件（附件 ID 來自 jira-view.sh 輸出的 `[10001]`），存檔為 `<輸出目錄>/<原始檔名>`，stdout 只印存檔完整路徑一行（SKILL.md 拿此路徑餵給 Read tool）。省略輸出目錄時用 `mktemp -d`

設計說明：spec 原寫 `jira-attach.sh <issue-key> <attachment-id>`，但 Jira 7.10 的 `/rest/api/2/attachment/{id}` 單靠附件 ID 即可取得 metadata 與下載 URL，issue key 冗餘，故簡化為單一參數。

- [ ] **Step 1: 寫 fixture**

```json
{
  "id": "10001",
  "filename": "pods.png",
  "mimeType": "image/png",
  "size": 7,
  "content": "http://127.0.0.1:18080/secure/attachment/10001/pods.png"
}
```

寫入 `tests/fixtures/attachment-10001.json`。

- [ ] **Step 2: 寫失敗測試**

```bash
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
```

寫入 `tests/test-attach.sh`。

- [ ] **Step 3: 跑測試確認失敗**

Run: `bash tests/test-attach.sh`
Expected: 全部 FAIL（jira-attach.sh 不存在）

- [ ] **Step 4: 實作 jira-attach.sh**

```bash
#!/usr/bin/env bash
# 用法: jira-attach.sh <ATTACHMENT-ID> [輸出目錄]
# 下載 Jira 附件，stdout 印出存檔完整路徑
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 ]] || die "用法: jira-attach.sh <ATTACHMENT-ID> [輸出目錄]"
ATT_ID="$1"
OUT_DIR="${2:-$(mktemp -d)}"
mkdir -p "$OUT_DIR"

meta="$(jira_curl "$JIRA_BASE_URL/rest/api/2/attachment/$ATT_ID")"
filename="$(jq -r '.filename' <<<"$meta")"
content_url="$(jq -r '.content' <<<"$meta")"

out_file="$OUT_DIR/$filename"
jira_curl "$content_url" > "$out_file"
printf '%s\n' "$out_file"
```

寫入 `jira-k8s-triage/scripts/jira-attach.sh`，`chmod +x`。

- [ ] **Step 5: 跑測試確認通過**

Run: `bash tests/test-attach.sh`
Expected: 4 個 PASS，exit 0

- [ ] **Step 6: Commit**

```bash
git add jira-k8s-triage/scripts/jira-attach.sh tests/fixtures/attachment-10001.json tests/test-attach.sh
git commit -m "feat: add jira-attach.sh attachment downloader"
```

---

### Task 5: jira-comment.sh（發 comment）

**Files:**
- Create: `jira-k8s-triage/scripts/jira-comment.sh`
- Test: `tests/test-comment.sh`

**Interfaces:**
- Consumes: `lib.sh` 的 `die`、`jira_curl`
- Produces: `jira-comment.sh <ISSUE-KEY> < comment.txt` — comment 內容（wiki markup 純文字）由 stdin 讀入，成功時 stdout 印 `comment 已發布（id: <id>）`。注意：因 `jira_curl` 的 stdin 已被 curl config 占用（`-K -`），JSON payload 必須經 temp file 以 `-d @file` 傳遞，不可用 `-d @-`

- [ ] **Step 1: 寫失敗測試**

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

out="$(printf 'h4. 分診報告\n症狀: CrashLoopBackOff\n' | bash "$SCRIPTS_DIR/jira-comment.sh" TEST-1 2>&1)"
assert_contains "$out" "comment 已發布（id: 20001）" "成功時印出 comment id"

posted="$(cat "$MOCK_LOG_DIR/last-post.json")"
assert_contains "$posted" '"body"' "POST payload 含 body 欄位"
assert_contains "$posted" '分診報告' "POST payload 含 comment 內容"
assert_contains "$posted" 'CrashLoopBackOff' "多行內容完整送出"

out="$(printf '' | bash "$SCRIPTS_DIR/jira-comment.sh" TEST-1 2>&1 || true)"
assert_contains "$out" "comment 內容為空" "空內容時拒絕發布"

out="$(bash "$SCRIPTS_DIR/jira-comment.sh" 2>&1 || true)"
assert_contains "$out" "用法" "無參數時顯示用法"
```

寫入 `tests/test-comment.sh`。

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash tests/test-comment.sh`
Expected: 全部 FAIL（jira-comment.sh 不存在）

- [ ] **Step 3: 實作 jira-comment.sh**

```bash
#!/usr/bin/env bash
# 用法: jira-comment.sh <ISSUE-KEY> < comment.txt
# comment 內容（Jira 7.10 wiki markup）由 stdin 讀入
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 1 ]] || die "用法: jira-comment.sh <ISSUE-KEY> < comment.txt"
KEY="$1"

content="$(cat)"
[[ -n "$content" ]] || die "comment 內容為空（請由 stdin 提供 wiki markup 文字）"

# jira_curl 的 stdin 被 curl config（-K -）占用，payload 走 temp file
payload="$(mktemp)"
jq -n --arg b "$content" '{body: $b}' > "$payload"
resp="$(jira_curl -X POST -H 'Content-Type: application/json' \
  -d @"$payload" "$JIRA_BASE_URL/rest/api/2/issue/$KEY/comment")"
rm -f "$payload"

printf 'comment 已發布（id: %s）\n' "$(jq -r '.id' <<<"$resp")"
```

寫入 `jira-k8s-triage/scripts/jira-comment.sh`，`chmod +x`。

- [ ] **Step 4: 跑測試確認通過**

Run: `bash tests/test-comment.sh`
Expected: 6 個 PASS，exit 0

- [ ] **Step 5: Commit**

```bash
git add jira-k8s-triage/scripts/jira-comment.sh tests/test-comment.sh
git commit -m "feat: add jira-comment.sh comment poster with stdin body"
```

---

### Task 6: jira-label.sh（加 label，冪等保護）

**Files:**
- Create: `jira-k8s-triage/scripts/jira-label.sh`
- Create: `tests/fixtures/issue-TEST-2.json`
- Test: `tests/test-label.sh`

**Interfaces:**
- Consumes: `lib.sh` 的 `die`、`jira_curl`
- Produces: `jira-label.sh <ISSUE-KEY> [LABEL]` — LABEL 預設 `triaged`。加 label 前先查該單現有 labels：**已存在則印警告到 stderr 並 exit 2（不重複加）**；成功加上則 stdout 印 `<KEY> 已加上 label "<LABEL>"`，exit 0。SKILL.md 靠 exit 2 辨識「已分診過」並中止該單流程

- [ ] **Step 1: 寫 fixture（已有 triaged label 的單）**

```json
{
  "key": "TEST-2",
  "fields": {
    "labels": ["triaged"]
  }
}
```

寫入 `tests/fixtures/issue-TEST-2.json`。

- [ ] **Step 2: 寫失敗測試**

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
start_mock
make_env
trap finish EXIT

# 1) 正常加 label
out="$(bash "$SCRIPTS_DIR/jira-label.sh" TEST-1 2>&1)"
assert_contains "$out" 'TEST-1 已加上 label "triaged"' "成功加 label"
put_body="$(cat "$MOCK_LOG_DIR/last-put.json")"
assert_contains "$put_body" '"add": "triaged"' "PUT payload 用 update.labels add"

# 2) 已有 label → exit 2 且不打 PUT
rm -f "$MOCK_LOG_DIR/last-put.json"
set +e
out="$(bash "$SCRIPTS_DIR/jira-label.sh" TEST-2 2>&1)"
code=$?
set -e
if [[ $code -eq 2 ]]; then
  echo "PASS: 已有 label 時 exit 2"
else
  echo "FAIL: 已有 label 時 exit 2（實際 exit $code）"
  FAILURES=$((FAILURES + 1))
fi
assert_contains "$out" '已有 label "triaged"' "已有 label 時給出警告"
if [[ ! -f "$MOCK_LOG_DIR/last-put.json" ]]; then
  echo "PASS: 已有 label 時不送 PUT"
else
  echo "FAIL: 已有 label 時不送 PUT"
  FAILURES=$((FAILURES + 1))
fi

out="$(bash "$SCRIPTS_DIR/jira-label.sh" 2>&1 || true)"
assert_contains "$out" "用法" "無參數時顯示用法"
```

寫入 `tests/test-label.sh`。

- [ ] **Step 3: 跑測試確認失敗**

Run: `bash tests/test-label.sh`
Expected: 全部 FAIL（jira-label.sh 不存在）

- [ ] **Step 4: 實作 jira-label.sh**

```bash
#!/usr/bin/env bash
# 用法: jira-label.sh <ISSUE-KEY> [LABEL]
# 預設 label 為 triaged；若該單已有此 label 則 exit 2（冪等保護，防重複分診）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 ]] || die "用法: jira-label.sh <ISSUE-KEY> [LABEL]"
KEY="$1"
LABEL="${2:-triaged}"

existing="$(jira_curl -G "$JIRA_BASE_URL/rest/api/2/issue/$KEY" \
  --data-urlencode 'fields=labels' | jq -r '.fields.labels[]?')"
if grep -qx -- "$LABEL" <<<"$existing"; then
  printf '%s 已有 label "%s"（可能已分診過），不重複加上\n' "$KEY" "$LABEL" >&2
  exit 2
fi

payload="$(mktemp)"
jq -n --arg l "$LABEL" '{update: {labels: [{add: $l}]}}' > "$payload"
jira_curl -X PUT -H 'Content-Type: application/json' \
  -d @"$payload" "$JIRA_BASE_URL/rest/api/2/issue/$KEY" > /dev/null
rm -f "$payload"

printf '%s 已加上 label "%s"\n' "$KEY" "$LABEL"
```

寫入 `jira-k8s-triage/scripts/jira-label.sh`，`chmod +x`。

- [ ] **Step 5: 跑測試確認通過**

Run: `bash tests/test-label.sh`
Expected: 6 個 PASS，exit 0

- [ ] **Step 6: 跑全部測試**

Run: `bash tests/run-all.sh`
Expected: 末行 `ALL TESTS PASSED`

- [ ] **Step 7: Commit**

```bash
git add jira-k8s-triage/scripts/jira-label.sh tests/fixtures/issue-TEST-2.json tests/test-label.sh
git commit -m "feat: add jira-label.sh with idempotency guard (exit 2 when already labeled)"
```

---

### Task 7: references/routing.md（分級矩陣、分流表、止血措施庫）

**Files:**
- Create: `jira-k8s-triage/references/routing.md`

**Interfaces:**
- Produces: SKILL.md 的 Classify 步驟引用「Severity 分級」「Urgency 分級」「Priority 交叉矩陣」三節；Route 步驟引用「K8s 領域分流表」；Mitigate 步驟引用「止血措施庫」。節標題（`## Severity 分級` 等五個 `##` 標題）為介面，SKILL.md 以標題指名引用，不可改名

- [ ] **Step 1: 寫 routing.md**

````markdown
# Routing 設定檔

> 這是你日後最常維護的檔案：團隊改組、調整 SLA、新增止血 runbook 都只改這一份。
> 「分流對象」欄目前是 placeholder，請改成實際團隊/人名。

## Severity 分級

| 等級 | 定義 | K8s 範例 |
|------|------|----------|
| S1 | 生產服務中斷或資料遺失 | 整個 namespace Pod CrashLoop、PV 資料毀損、API server 不可用 |
| S2 | 生產服務降級，有 workaround | 部分副本異常、間歇性 5xx、節點 NotReady 但已 failover |
| S3 | 非生產環境或單一使用者受影響 | dev/staging 部署失敗、單人 kubectl 權限問題 |
| S4 | 諮詢、文件、優化建議 | HPA 設定諮詢、資源配額調整請求 |

## Urgency 分級

| 等級 | 定義 |
|------|------|
| U1 | 正在惡化或有明確 deadline |
| U2 | 穩定但持續影響 |
| U3 | 可排程處理 |

## Priority 交叉矩陣

|        | U1 | U2 | U3 |
|--------|----|----|----|
| **S1** | P1（立即升級 on-call） | P2 | P2 |
| **S2** | P2（當日處理） | P3 | P3 |
| **S3** | P3 | P3 | P4 |
| **S4** | P3 | P4 | P4 |

## K8s 領域分流表

| 領域 | 典型症狀/關鍵字 | 分流對象 |
|------|----------------|----------|
| Compute/Workload | CrashLoopBackOff、OOMKilled、ImagePullBackOff、FailedScheduling | Platform 團隊 |
| Network | CNI 錯誤、Service/Ingress 不通、DNS 解析失敗、NetworkPolicy | Network 團隊 |
| Storage | PVC Pending、mount failed、IO error、StorageClass | Storage 團隊 |
| Control Plane | API server 慢、etcd、controller/scheduler 異常 | SRE/Infra 團隊 |
| Node/OS | NotReady、kubelet、資源壓力、kernel | Infra 團隊 |
| App 層 | 應用邏輯錯誤、config 錯誤、image 內容問題 | 回歸應用團隊（附證據） |
| Security/RBAC | 權限拒絕、certificate、secret | Security 團隊 |

## 止血措施庫

Mitigate 步驟從對應領域挑選，只給「立即可執行、可逆」的動作，不給根治方案。

### Compute/Workload
- rollback 到上一個可用版本：`kubectl rollout undo deployment/<name> -n <ns>`
- 暫時調高 memory limit（OOMKilled 時）
- cordon 問題節點讓 Pod 重新排程：`kubectl cordon <node>`

### Network
- 確認是否可用 Pod IP 直連繞過 Service（判斷 kube-proxy/CNI 層問題）
- 暫時放寬疑似誤擋的 NetworkPolicy（記錄原狀以便還原）
- DNS 問題時改用 FQDN 或暫時寫入 hostAliases

### Storage
- PVC Pending：確認 StorageClass 與配額，暫時改用其他 StorageClass
- mount failed：將 Pod 排程到其他節點驗證是否節點層問題
- 唯讀降級：先確保資料不再寫壞，再處理修復

### Control Plane
- 立即通知 SRE/Infra，不建議報案者自行操作
- 提供替代查詢路徑（如唯讀 kubeconfig 指向備援 API endpoint）

### Node/OS
- cordon + drain 問題節點：`kubectl drain <node> --ignore-daemonsets`
- 資源壓力：先確認是否單一工作負載造成，暫時 evict 該負載

### App 層
- rollback 應用版本或 config
- 附上平台側證據（events、Pod 狀態）後轉回應用團隊

### Security/RBAC
- 權限問題不做臨時放權，一律轉 Security 團隊確認
- certificate 過期：確認影響範圍，安排輪替
````

寫入 `jira-k8s-triage/references/routing.md`。

- [ ] **Step 2: 驗證必要節標題齊全**

Run: `grep -c '^## ' jira-k8s-triage/references/routing.md`
Expected: `5`

Run: `grep '^## ' jira-k8s-triage/references/routing.md`
Expected: 依序列出 `## Severity 分級`、`## Urgency 分級`、`## Priority 交叉矩陣`、`## K8s 領域分流表`、`## 止血措施庫`

- [ ] **Step 3: Commit**

```bash
git add jira-k8s-triage/references/routing.md
git commit -m "docs: add routing.md severity matrix, domain routing table, mitigation library"
```

---

### Task 8: references/report-template.md（三種分診報告範本）

**Files:**
- Create: `jira-k8s-triage/references/report-template.md`

**Interfaces:**
- Produces: SKILL.md 產報告草稿時依 issue type 取用三個 `##` 節之一：`## Something Broken 範本`、`## Ask Platform 範本`、`## Pull Request Review 範本`。範本本體為 Jira 7.10 wiki markup（`h4.`、`*粗體*`、`# 編號清單`）

- [ ] **Step 1: 寫 report-template.md**

````markdown
# 分診報告範本

> 發到 Jira comment 的格式。語言跟隨原單語言（技術名詞保留英文），以下以中文示意。
> 範本使用 Jira 7.10 wiki markup：`h4.` 標題、`*粗體*`、`#` 編號清單。
> `<角括號>` 為填空位，發布前必須全部替換，不可殘留。

## Something Broken 範本

```
h4. 🏥 分診報告 (Triage Report)
*症狀摘要*
時間: <發生時間/持續時間>　地點: <cluster/namespace/資源>
關鍵症狀:
# <錯誤碼或現象，一行一條>

*分級*: <P2> (Severity: <S2> × Urgency: <U1>)
理由: <一句話>

*分流*: → <團隊名>
理由: <證據指向哪個領域>

*立即止血措施（非根治）*
# <可立即執行的動作>

*升級觸發條件*
若 <條件：錯誤率超過 X%、擴散到其他 namespace、止血無效超過 30 分鐘>，請立即回報並升級至 <對象>。

*需要補充的資訊*（如適用）
# <引導式提問，最多 3 題>

----
🤖 由 triage skill 產生，經工程師審核後發布
```

規則：
- 證據不足時「分級」標註 `暫定`，且「需要補充的資訊」為必填段落
- 「需要補充的資訊」的題目從 questioning.md 選出，只挑最能改變分級或分流結論的 2-3 題

## Ask Platform 範本

```
h4. 💬 平台諮詢回覆
*問題理解*: <一句話重述問題>

*解答 / 指引*
<直接給答案；或指出正確文件連結/負責團隊>

*FAQ 建議*: <若屬常見問題，註明「建議沉澱為 FAQ」；否則刪除此行>

----
🤖 由 triage skill 產生，經工程師審核後發布
```

規則：分級一律 S4，不含止血與升級條件段落。

## Pull Request Review 範本

```
h4. 🔍 PR 判讀報告
*PR*: <PR 連結>（<GitLab / Azure DevOps>）

*改動摘要*
<兩三句話：改了什麼、範圍多大>

*風險點*
# <K8s 資源異動、權限變更、破壞性變更等，一行一條；無則寫「未發現明顯風險」>

*建議關注的檔案*
# <檔名：一句話說明為何要看>

*Review 建議*: <傾向可 approve / 需要討論>
理由: <一句話>

----
🤖 由 triage skill 產生，經工程師審核後發布；approve 由人工在 PR 平台執行
```
````

寫入 `jira-k8s-triage/references/report-template.md`。

- [ ] **Step 2: 驗證三個範本節齊全**

Run: `grep '^## ' jira-k8s-triage/references/report-template.md`
Expected: 依序 `## Something Broken 範本`、`## Ask Platform 範本`、`## Pull Request Review 範本`

- [ ] **Step 3: Commit**

```bash
git add jira-k8s-triage/references/report-template.md
git commit -m "docs: add report templates for three issue types (jira wiki markup)"
```

---

### Task 9: references/questioning.md（引導式提問庫）

**Files:**
- Create: `jira-k8s-triage/references/questioning.md`

**Interfaces:**
- Produces: SKILL.md 在證據不足時引用本檔的「LQQOPQRST 映射」與「Golden Signals 檢查」選題，並遵守「選題規則」節

- [ ] **Step 1: 寫 questioning.md**

````markdown
# 引導式提問庫

> 證據不足時，從下表挑「最能改變分級或分流結論」的 2-3 題追問報案者。
> 參考醫學問診框架，映射到 K8s 情境。

## LQQOPQRST 映射

| 問診項 | K8s 追問 |
|--------|----------|
| Location | 哪個 cluster / namespace / pod？ |
| Quality | 錯誤長什麼樣？確切錯誤碼/訊息是什麼？ |
| Quantity | 影響幾個 Pod / 幾 % 的請求？ |
| Onset | 何時開始？之前改了什麼（deploy、config、升級）？ |
| Palliative/Provocative | 做什麼會好轉/惡化（重啟、擴容）？ |
| Region | 有無擴散到其他 namespace / cluster？ |
| Severity | 對業務的實際影響是什麼？ |
| Timing | 持續性或間歇性？有無週期？ |

## Golden Signals 檢查

| Signal | 追問 |
|--------|------|
| Latency | 回應時間有變慢嗎？P95/P99 大約多少？ |
| Traffic | 流量有異常增減嗎？ |
| Errors | 錯誤率多少？哪種錯誤碼最多？ |
| Saturation | CPU/memory/disk/連線數有打滿嗎？ |

## 選題規則

- 只挑 2-3 題，不全問——追問越多，報案者越不會回
- 挑選標準：答案「最能改變分級或分流結論」的優先
  - 例：已知錯誤碼但不知影響範圍 → 問 Quantity 與 Region（影響分級）
  - 例：症狀明確但不知何時開始 → 問 Onset（影響分流：最近 deploy 指向 App 層）
- 已能從單內容或附件推得答案的題目不問
````

寫入 `jira-k8s-triage/references/questioning.md`。

- [ ] **Step 2: 驗證節標題齊全**

Run: `grep '^## ' jira-k8s-triage/references/questioning.md`
Expected: 依序 `## LQQOPQRST 映射`、`## Golden Signals 檢查`、`## 選題規則`

- [ ] **Step 3: Commit**

```bash
git add jira-k8s-triage/references/questioning.md
git commit -m "docs: add guided questioning library (LQQOPQRST + golden signals)"
```

---

### Task 10: SKILL.md（入口：分派邏輯與工作流程）

**Files:**
- Create: `jira-k8s-triage/SKILL.md`

**Interfaces:**
- Consumes: Task 1-6 的五支 script（呼叫介面如各 task Produces 所述）、Task 7-9 的三份 references（以節標題指名引用）
- Produces: 完整可觸發的 skill。使用者以 `/jira-k8s-triage [ISSUE-KEY]` 呼叫

- [ ] **Step 1: 寫 SKILL.md**

````markdown
---
name: jira-k8s-triage
description: Use when triaging K8s platform Jira issues (Jira Server 7.10) - single issue or queue mode, runs Triage Loop (classify severity, route to team, mitigation advice), analyzes screenshot attachments, reviews GitLab/Azure DevOps PRs via browser, posts comment after human approval
---

# Jira K8s Issues Triage

對 Jira Server 7.10 的 K8s 報案單執行標準 Triage Loop 分診。
口吻：冷靜、專業、條理分明，不說廢話，高資訊密度。

## 設定區（安裝後請修改）

- PROJECT_KEY: `CHANGEME`
- 待分診狀態: `Open, "To Do"`
- 佇列 JQL（labels IS EMPTY 不可省略，否則會漏掉沒有任何 label 的新單）:
  `project = <PROJECT_KEY> AND (labels IS EMPTY OR labels != triaged) AND status in (<待分診狀態>) ORDER BY created ASC`

## Scripts

全部位於本 skill 的 `scripts/` 目錄（以下以 `$SCRIPTS` 代稱），認證讀自 `~/.jira-triage.env`：

| Script | 用途 |
|--------|------|
| `$SCRIPTS/jira-view.sh <KEY>` | 抓單，輸出含 Type、Description、Comments、附件清單 |
| `$SCRIPTS/jira-search.sh '<JQL>'` | 查詢，輸出精簡列表 |
| `$SCRIPTS/jira-attach.sh <附件ID> [目錄]` | 下載附件，印出存檔路徑 |
| `$SCRIPTS/jira-comment.sh <KEY> < file` | 發 comment（stdin 餵 wiki markup） |
| `$SCRIPTS/jira-label.sh <KEY>` | 加 triaged label；已有時 exit 2 |

script 失敗時把 stderr 的中文錯誤訊息如實回報使用者，不要瞎猜原因。

## 啟動模式

**單一單號**（有參數，如 `PROJ-123`）：直接對該單執行下方「單張處理流程」。

**佇列模式**（無參數）：
1. 用設定區的佇列 JQL 跑 `jira-search.sh`
2. 先向使用者展示佇列總覽（單號、type、標題、建立時間）
3. 依序對每張單執行「單張處理流程」
4. 全部處理完輸出統計：處理幾張、各分級數量、跳過幾張

## 單張處理流程

### 第 0 步：讀單與分派

1. `jira-view.sh <KEY>` 讀單
2. 若 Labels 已含 `triaged`：告知使用者並跳過此單
3. 有附件時：
   - 圖片（png/jpg/gif/jpeg）：`jira-attach.sh <附件ID>` 下載後用 Read tool 視覺分析，
     讀出截圖中的錯誤訊息、Pod 狀態、dashboard 數值，納入證據
   - 文字（log/yaml/txt）：下載後閱讀；檔案超過 5MB 先用 grep 抽錯誤關鍵字段落（error、fail、warn、exception），不整檔載入
4. 依 `Type:` 分派：
   - `Something Broken` → 路徑 1
   - `Ask Platform` → 路徑 2
   - `Pull Request Review` → 路徑 3
   - 其他 type → 詢問使用者要走哪條路徑

### 路徑 1：Something Broken（完整 Triage Loop）

依序執行五步驟，結論寫進 `references/report-template.md` 的「Something Broken 範本」：

1. **Ingest & Observe**：從描述、comments、附件提取——時間（何時開始/持續多久）、
   地點（cluster/namespace/node/資源名）、關鍵症狀與錯誤碼
2. **Classify**：依 `references/routing.md` 的「Severity 分級」「Urgency 分級」評 S×U，
   再用「Priority 交叉矩陣」得出 P1-P4；證據不足時標「暫定」
3. **Route**：對照「K8s 領域分流表」，依症狀關鍵字判定領域與分流對象；
   證據同時指向多個領域時，選最上游的（例：節點 NotReady 引發 Pod 崩潰 → Node/OS）
4. **Mitigate**：從「止血措施庫」對應領域挑 1-3 條立即可執行、可逆的動作；
   絕不給根治方案，那是接手團隊的事
5. **Re-evaluate**：設定具體、可觀察的升級觸發條件（錯誤率門檻、擴散範圍、止血時限）

證據不足時（分級或分流下不了結論）：依 `references/questioning.md` 的「選題規則」
從 LQQOPQRST 映射與 Golden Signals 檢查中挑 2-3 題，填入報告的「需要補充的資訊」。

### 路徑 2：Ask Platform（諮詢輕量流程）

1. 理解問題本質（必要時看附件）
2. 直接給答案；答不了的指出正確文件或負責團隊
3. 常見問題註明「建議沉澱為 FAQ」
4. 用「Ask Platform 範本」產草稿；分級一律 S4

### 路徑 3：Pull Request Review（瀏覽器判讀）

1. 從單的描述與 comments 提取 PR 連結；找不到連結時，走「需要補充的資訊」
   請報案者補 PR 連結，不硬猜
2. 依 URL 判別平台：
   - 含 `gitlab` 或路徑帶 `/-/merge_requests/` → GitLab，diff 在 MR 的 **Changes** 頁
   - 含 `dev.azure.com` 或 `visualstudio.com` → Azure DevOps，diff 在 PR 的 **Files** 頁
3. 用 Claude in Chrome 開啟 PR 頁面（沿用使用者已登入的 Chrome session；
   瀏覽器工具未載入時先用 ToolSearch 一次載入 tabs_context_mcp、navigate、
   computer、read_page、tabs_create_mcp）
4. 判讀：改動範圍、diff 內容、影響面；特別留意 K8s 資源異動、權限變更、破壞性變更
5. 用「Pull Request Review 範本」產草稿
6. **絕不碰 approve 按鈕**——approve 永遠由人工在 PR 平台執行
7. 瀏覽器連續失敗 2-3 次就停下回報，不要無限重試

### 收尾（三條路徑共用）

1. 報告草稿以原單語言撰寫（技術名詞保留英文），完整展示給使用者
2. 用 AskUserQuestion 問：**核可發布** / **修改後發** / **跳過此單**
   - 核可發布 → 草稿寫入暫存檔，`jira-comment.sh <KEY> < 暫存檔`，
     成功後 `jira-label.sh <KEY>`；label script exit 2 表示別的 session 已分診，
     如實回報
   - 修改後發 → 依使用者指示改草稿，回到步驟 1 重新確認
   - 跳過此單 → 不留任何痕跡（不 comment、不加 label），下輪佇列仍會出現
3. 佇列模式 → 繼續下一張單

## 鐵則

- 未經使用者核可，絕不寫入 Jira（comment、label 都是）
- 範本的 `<填空位>` 發布前必須全部替換，不可殘留
- 報告只寫證據支持的結論；證據不足就標「暫定」並追問，不腦補
````

寫入 `jira-k8s-triage/SKILL.md`。

- [ ] **Step 2: 一致性驗證**

Run: `grep -o 'jira-[a-z]*\.sh' jira-k8s-triage/SKILL.md | sort -u`
Expected: 恰好五支 `jira-attach.sh jira-comment.sh jira-label.sh jira-search.sh jira-view.sh`

Run: `ls jira-k8s-triage/references/`
Expected: `questioning.md report-template.md routing.md`（SKILL.md 引用的三份都存在）

- [ ] **Step 3: Commit**

```bash
git add jira-k8s-triage/SKILL.md
git commit -m "feat: add SKILL.md entry with issue-type dispatch and triage loop workflow"
```

---

### Task 11: 安裝與端到端手動驗證

**Files:**
- Create: `~/.jira-triage.env`（不進 repo）
- Create: symlink `~/.claude/skills/jira-k8s-triage`

**Interfaces:**
- Consumes: 全部前置 task 的產出
- Produces: 已安裝、經真實 Jira 驗證的可用 skill

- [ ] **Step 1: 跑全部離線測試**

Run: `bash tests/run-all.sh`
Expected: 末行 `ALL TESTS PASSED`

- [ ] **Step 2: 建立認證檔（需使用者提供帳密）**

請使用者在終端機自行執行（避免密碼進入對話）：

```bash
cat > ~/.jira-triage.env <<'EOF'
JIRA_BASE_URL=https://<你的-jira-主機>
JIRA_USER=<username>
JIRA_PASS=<password>
EOF
chmod 600 ~/.jira-triage.env
```

- [ ] **Step 3: 驗證真實 Jira 連線**

Run: `bash -c 'source jira-k8s-triage/scripts/lib.sh; jira_curl "$JIRA_BASE_URL/rest/api/2/myself" | jq -r .name'`
Expected: 印出使用者的 Jira username（401 時檢查帳密；連線失敗時檢查 JIRA_BASE_URL）

- [ ] **Step 4: 修改 SKILL.md 設定區**

把 `PROJECT_KEY: CHANGEME` 改成實際專案 KEY；與使用者確認待分診狀態清單是否符合他們的 workflow。

```bash
git add jira-k8s-triage/SKILL.md
git commit -m "docs: set real project key in skill config"
```

- [ ] **Step 5: 安裝 symlink**

```bash
ln -s "$PWD/jira-k8s-triage" ~/.claude/skills/jira-k8s-triage
ls -l ~/.claude/skills/jira-k8s-triage
```

Expected: symlink 指向 repo 內的 `jira-k8s-triage/`

- [ ] **Step 6: 端到端手動驗證（真實測試單）**

請使用者在 Jira 建立（或指定）測試單後，逐項驗證並記錄結果：

1. `jira-view.sh <測試單>` — 輸出完整且正確
2. `jira-search.sh` 用設定區 JQL — 測試單出現在佇列
3. 對含截圖的 Something Broken 測試單跑完整流程 — 附件視覺分析納入報告、
   確認畫面出現、核可後 comment 與 label 都成功
4. 到 Jira 網頁檢查 comment 的 wiki markup 渲染正確（h4. 標題、粗體、編號清單）
5. 對同一張單再跑一次 — jira-label 的冪等保護觸發（exit 2、跳過）
6. Ask Platform 測試單 — 輕量格式正確
7. Pull Request Review 測試單（GitLab 與 Azure DevOps 各一）— 瀏覽器判讀成功、
   報告含改動摘要與風險點
8. 新 session 輸入 `/jira-k8s-triage <測試單>` — skill 能被觸發

- [ ] **Step 7: 最終 commit**

```bash
git add -A
git commit -m "docs: mark plan complete after end-to-end verification"
```

（若驗證中發現問題，先修復、補測試、commit 修復，再做此步。）
