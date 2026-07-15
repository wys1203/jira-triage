---
name: jira-k8s-triage
description: Use when triaging K8s platform Jira issues (Jira Server 7.10) - single issue or queue mode, runs Triage Loop (classify severity, route to team, mitigation advice), analyzes screenshot attachments, reviews GitLab/Azure DevOps PRs via browser, follows up on user replies to triage comments, posts comment after human approval
---

# Jira K8s Issues Triage

對 Jira Server 7.10 的 K8s 報案單執行標準 Triage Loop 分診。
口吻：冷靜、專業、條理分明，不說廢話，高資訊密度。

## 設定區（安裝後請修改）

- PROJECT_KEY: `CHANGEME`
- 待分診狀態: `Open, "To Do"`
- 佇列 JQL（labels IS EMPTY 不可省略，否則會漏掉沒有任何 label 的新單）:
  `project = <PROJECT_KEY> AND (labels IS EMPTY OR labels != triaged) AND status in (<待分診狀態>) ORDER BY created ASC`
- Follow-up JQL（複診掃描；`updated` 會被任何欄位異動觸發，命中後仍須用水位線二次確認）:
  `project = <PROJECT_KEY> AND labels = triaged AND updated >= -7d ORDER BY updated DESC`

## Scripts

全部位於本 skill 的 `scripts/` 目錄（以下以 `$SCRIPTS` 代稱），認證讀自 `~/.jira-triage.env`：

| Script | 用途 |
|--------|------|
| `$SCRIPTS/jira-view.sh <KEY>` | 抓單，輸出含 Type、Description、Comments、附件清單 |
| `$SCRIPTS/jira-search.sh '<JQL>'` | 查詢，輸出精簡列表 |
| `$SCRIPTS/jira-attach.sh <附件ID> [目錄]` | 下載附件，印出存檔路徑 |
| `$SCRIPTS/jira-comment.sh <KEY> < file` | 發 comment（stdin 餵 wiki markup） |
| `$SCRIPTS/jira-label.sh <KEY>` | 加 triaged label；已有時 exit 2 |
| `$SCRIPTS/jira-priority.sh <KEY> <值>` | 更新 Priority（Highest/High/Low/Lowest） |
| `$SCRIPTS/jira-assign.sh <KEY> <username>` | 指派 assignee（Jira Server 帳號名） |

script 失敗時把 stderr 的中文錯誤訊息如實回報使用者，不要瞎猜原因。

## 啟動模式

**單一單號**（有參數，如 `PROJ-123`）：直接對該單執行下方「單張處理流程」。

**佇列模式**（無參數）：
1. 用設定區的佇列 JQL 跑 `jira-search.sh`
2. 先向使用者展示佇列總覽（單號、type、標題、建立時間）
3. 依序對每張單執行「單張處理流程」
4. 新單處理完後，用設定區的 Follow-up JQL 掃描複診佇列；`updated` 會被任何
   欄位異動觸發，須逐張以第 0 步的水位線判斷是否真有新回覆，有才進路徑 4
5. 全部處理完輸出統計：處理幾張、各分級數量、複診幾張、跳過幾張

## 單張處理流程

### 第 0 步：讀單與分派

1. `jira-view.sh <KEY>` 讀單
2. 分診狀態三態判斷。水位線 = comments 中**最後一則**含 footer（🤖 由 triage skill 產生）的 comment：
   - 無 footer 且 Labels 無 `triaged` → 未分診，繼續往下
   - 有 footer，且水位線之後有**其他人**的 comment → 已分診且有新回覆，
     直接進入路徑 4（複診），跳過步驟 4 的類型分派；若缺 triaged label 順便建議補上
   - 其他（已分診且無新回覆，含「有 label 無 footer」的手動標記情況）→
     告知使用者並跳過此單；有 footer 但缺 label 時建議補上 triaged label
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
2. **先天條件檢查**：對照 `references/preconditions.md` 逐條比對提取出的證據
   （node name、namespace、資源設定等）。命中時以該條「標準回覆」為診斷主體：
   分流改為「回報案者自行調整」（不轉專門團隊）、分級照實際影響評（通常 S3，
   屬 user 端設定錯誤）、止血措施段以標準回覆為主體並註明「調整後問題仍存在，
   表示非先天條件問題，請回覆本 comment 重新分診」，報告理由需引用規則編號
   （如 PC-001）；命中後跳過步驟 5 的止血措施庫
3. **Classify**：依 `references/routing.md` 的「Severity 分級」「Urgency 分級」評 S×U，
   再用「Priority 交叉矩陣」得出 P1-P4；證據不足時標「暫定」
4. **Route**：先比對 `references/routing.md` 的「特例分流規則」，命中直接採用
   該條分流對象並引用編號（如 SR-001）；未命中才對照「K8s 領域分流表」，
   依症狀關鍵字判定領域與分流對象；證據同時指向多個領域時，選最上游的
   （例：節點 NotReady 引發 Pod 崩潰 → Node/OS）
5. **Mitigate**：從「止血措施庫」對應領域挑 1-3 條立即可執行、可逆的動作；
   調查類指引以 kube-dashboard 操作路徑為主（多數報案者沒有 kubectl 執行權限），
   kubectl 指令僅供有權限者替代；可附建議的 YAML 修正片段（tolerations、
   resources、affinity 等，發布時用 {code} 區塊包覆）；絕不給根治方案，
   那是接手團隊的事

報告不含「升級觸發條件」段落——升級判斷由複診（路徑 4）依報案者回報的止血結果處理。

證據不足時（分級或分流下不了結論）：依 `references/questioning.md` 的「選題規則」
從 LQQOPQRST 映射與 Golden Signals 檢查中挑 2-3 題，填入報告的「需要補充的資訊」，
每題附一句為何需要這個資訊。

### 路徑 2：Ask Platform（諮詢輕量流程）

1. 理解問題本質（必要時看附件）
2. 對照 `references/preconditions.md` 檢查：若問題觸及先天條件（例如詢問為何
   無法排程到某類 node），直接以該條「標準回覆」作答並引用規則編號
3. 比對 `references/routing.md` 的「特例分流規則」：命中（如 SR-001 edge
   firewall 開通申請）直接分流給該條指定對象並引用編號
4. 直接給答案；答不了的指出正確文件或負責團隊
5. 常見問題註明「建議沉澱為 FAQ」
6. 用「Ask Platform 範本」產草稿；分級一律 S4

### 路徑 3：Pull Request Review（瀏覽器判讀）

1. 從單的描述與 comments 提取 PR 連結；找不到連結時，走「需要補充的資訊」
   請報案者補 PR 連結，不硬猜
2. 依 URL 判別平台：
   - 含 `gitlab` 或路徑帶 `/-/merge_requests/` → GitLab，diff 在 MR 的 **Changes** 頁
   - 含 `dev.azure.com` 或 `visualstudio.com` → Azure DevOps，diff 在 PR 的 **Files** 頁
3. 用 Claude in Chrome 開啟 PR 頁面（沿用使用者已登入的 Chrome session；
   瀏覽器工具未載入時先用 ToolSearch 一次載入 tabs_context_mcp、navigate、
   computer、read_page、tabs_create_mcp）
4. **Diff 證據閘門**：判讀前必須確認已在正確頁面（GitLab 的 **Changes** 頁 /
   Azure DevOps 的 **Files** 頁），並實際取得變更檔案清單（含每檔 +/- 行數）、
   至少引用一段真實 diff 內容。頁籤沒切對、lazy-load 未展開、權限不足時先重試
   切換頁籤/展開 2-3 次；仍拿不到證據 → **本次診斷無效：不產草稿、不發 comment、
   不加 label**，向使用者回報原因後跳過此單（留在佇列，下輪再處理）
5. 判讀：改動範圍、diff 內容、影響面；特別留意 K8s 資源異動、權限變更、破壞性變更
6. 依 `references/routing.md` 的「PR Review 分流」判定轉診對象：diff 涉及
   resource quota 相關（ResourceQuota / LimitRange、resources.requests/limits
   調整、namespace quota 變更）→ 轉診 engineer A；其他一律 → engineer B
7. 用「Pull Request Review 範本」產草稿；「Diff 證據」與「轉診」欄位必填，
   Diff 證據填不出具體檔名與行數 = 草稿無效，禁止進入收尾
8. **絕不碰 approve 按鈕**——approve 永遠由人工在 PR 平台執行
9. 瀏覽器連續失敗 2-3 次就停下回報，不要無限重試

### 路徑 4：複診（Follow-up）

處理已分診單上、水位線之後的他人新 comment：

1. 讀取水位線後的所有新 comment，連同原分診報告一起理解脈絡
2. 判斷回覆類型並對應處理（可能複合，逐項回應）：
   - **補充資訊**（回答了引導式提問）→ 新證據併入原診斷，重跑先天條件檢查與
     Classify/Route；結論有變時在報告中明確標註（例：分級 S3 → S2、分流改向）
   - **追問／質疑** → 直接回答；若確實誤判，修正結論並致謝
   - **回報止血結果** → 有效：建議觀察期後結案；無效或惡化：視同升級事件，
     提高分級並改分流，必要時建議立即通知對應團隊
   - **表示已解決** → 回覆確認並建議報案者結案（不操作 Jira 狀態）
3. 用「Follow-up 範本」產草稿（footer 必須保留，水位線機制依賴它），進入收尾流程

### 收尾（四條路徑共用）

1. 報告草稿以原單語言撰寫（技術名詞保留英文），完整展示給使用者
2. 用 AskUserQuestion 問：**核可發布** / **修改後發** / **跳過此單**
   - 核可發布 → 草稿寫入暫存檔，`jira-comment.sh <KEY> < 暫存檔`，
     成功後 `jira-label.sh <KEY>`；label script exit 2 表示該單已有 label——
     首次分診時代表別的 session 已分診（如實回報），複診時屬預期行為（忽略即可）。
     有分級結論的路徑（1、2；複診時分級有變動也算）再依 routing.md 的
     「Jira Priority 映射」跑 `jira-priority.sh <KEY> <值>`；
     路徑 3（PR Review）無分級，不更新 priority。
     分流/轉診對象為具體個人（routing.md 中 `[~username]` 格式）時，
     再跑 `jira-assign.sh <KEY> <username>` 把單指派過去；
     分流對象為團隊名稱、或先天條件命中（回報案者自行調整）→ 不動 assignee
   - 修改後發 → 依使用者指示改草稿，回到步驟 1 重新確認
   - 跳過此單 → 不留任何痕跡（不 comment、不加 label），下輪佇列仍會出現
3. 佇列模式 → 繼續下一張單

## 鐵則

- 未經使用者核可，絕不寫入 Jira（comment、label 都是）
- 範本的 `<填空位>` 發布前必須全部替換，不可殘留
- 報告只寫證據支持的結論；證據不足就標「暫定」並追問，不腦補
- PR 判讀未通過 Diff 證據閘門前，禁止產出報告草稿或進入收尾——
  沒讀到 diff 的診斷無效，寧可跳過留佇列，不可腦補發布
