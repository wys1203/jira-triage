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
3. 若 comments 中已含分診報告 footer（🤖 由 triage skill 產生），視同已分診：告知使用者並建議補上 triaged label，不重複發 comment
4. 有附件時：
   - 圖片（png/jpg/gif/jpeg）：`jira-attach.sh <附件ID>` 下載後用 Read tool 視覺分析，
     讀出截圖中的錯誤訊息、Pod 狀態、dashboard 數值，納入證據
   - 文字（log/yaml/txt）：下載後閱讀；檔案超過 5MB 先用 grep 抽錯誤關鍵字段落（error、fail、warn、exception），不整檔載入
5. 依 `Type:` 分派：
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
