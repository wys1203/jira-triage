---
name: jira-k8s-triage
description: Use when triaging K8s platform Jira issues (Jira Server 7.10) - single issue or queue mode, runs Triage Loop (classify severity, route to team, mitigation advice), analyzes screenshot attachments, reviews GitLab/Azure DevOps PRs via browser, follows up on user replies to triage comments, posts comment after human approval; also discuss mode (read-only case review to improve the rule library)
---

# Jira K8s Issues Triage

對 Jira Server 7.10 的 K8s 報案單執行標準 Triage Loop 分診。
口吻：冷靜、專業、條理分明，不說廢話，高資訊密度。
各模式的細節流程放在 `references/flows/`，**進入該模式時才讀取對應檔案**，
不要一次全部載入。

## 設定區（安裝後請修改）

- PROJECT_KEY: `CHANGEME`
- 待分診狀態: `Open, "To Do"`
- 分流後狀態: `IMPLEMENT`（分流/轉診成立時自動轉換到此狀態）
- 佇列 JQL（labels IS EMPTY 不可省略，否則會漏掉沒有任何 label 的新單）:
  `project = <PROJECT_KEY> AND (labels IS EMPTY OR labels != triaged) AND status in (<待分診狀態>) ORDER BY created ASC`
- Follow-up JQL（複診掃描；`updated` 會被任何欄位異動觸發，命中後仍須用 jira-state.sh 二次確認）:
  `project = <PROJECT_KEY> AND labels = triaged AND updated >= -7d ORDER BY updated DESC`

## Scripts

全部位於本 skill 的 `scripts/` 目錄（以下以 `$SCRIPTS` 代稱），認證讀自 `~/.jira-triage.env`：

| Script | 用途 |
|--------|------|
| `$SCRIPTS/jira-state.sh <KEY>` | 分診狀態三態判斷（UNTRIAGED / TRIAGED_NO_REPLY / FOLLOWUP_PENDING） |
| `$SCRIPTS/jira-view.sh <KEY> [--all]` | 抓單（comments 預設最後 10 則） |
| `$SCRIPTS/jira-search.sh '<JQL>'` | 查詢，輸出精簡列表 |
| `$SCRIPTS/jira-attach.sh <附件ID> [目錄]` | 下載附件，印出存檔路徑 |
| `$SCRIPTS/jira-publish.sh <KEY> <草稿檔> [選項]` | **發布首選**：lint + comment + label + priority + assign + transition 一次完成 |
| `$SCRIPTS/rule-lint.sh` | 規則庫結構驗證（維護規則時必跑） |

（單步 script：jira-comment / jira-label / jira-priority / jira-assign /
jira-transition 仍在 scripts/，僅除錯時單獨使用；正常發布一律走 jira-publish。）

script 失敗時把 stderr 的中文錯誤訊息如實回報使用者，不要瞎猜原因。

## 啟動模式

**單一單號**（有參數，如 `PROJ-123`）：直接對該單執行下方「第 0 步」。

**佇列模式**（無參數）：
1. 用設定區的佇列 JQL 跑 `jira-search.sh`
2. 先向使用者展示佇列總覽（單號、type、標題、建立時間）
3. 依序對每張單執行「第 0 步」起的流程；**每張處理完，輸出一行摘要
   （單號／結論／是否發布）後即拋棄該單細節再讀下一張**——長佇列
   不得把每張單的完整內容都留在腦中
4. 新單處理完後，用設定區的 Follow-up JQL 掃描複診佇列；逐張以
   `jira-state.sh` 確認是否真為 FOLLOWUP_PENDING，是才進複診
5. 全部處理完輸出統計：處理幾張、各分級數量、複診幾張、跳過幾張

**討論模式**（參數為 `discuss <單號>`，或語意是「討論/review 這個 case」
而非要求分診）：讀取並執行 `references/flows/discuss.md`（絕對唯讀）。

## 第 0 步：讀單與分派（各路徑共用的入口）

1. `jira-view.sh <KEY>` 讀單
2. `jira-state.sh <KEY>` 判斷分診狀態，依輸出直接分流（邏輯已封裝在
   script 內，不需自行推理）：
   - `UNTRIAGED` → 未分診，繼續往下
   - `FOLLOWUP_PENDING` → 已分診且有新回覆，讀取並執行
     `references/flows/followup.md`（複診），跳過步驟 5
   - `TRIAGED_NO_REPLY` → 已分診且無新回覆，告知使用者並跳過此單
3. **證據清點**：列出這張單的完整證據清單——描述與 comments 中的每個連結
   （ArgoCD、dashboard、PR…）、每個附件、每段貼上的 yaml/config。
   逐項消化；產出報告前每項標注「已分析」或「無法存取（原因）」。
   **存在未消化的證據時不得下確定診斷**——只能標「暫定」並說明缺哪塊
4. 逐項處理證據：
   - 圖片（png/jpg/gif/jpeg）：`jira-attach.sh <附件ID>` 下載後以檔案讀取
     工具直接視覺判讀，依 `references/analysis.md` 的「圖片判讀準則」抄錄關鍵錯誤
   - 文字（log/yaml/txt）：下載後閱讀；檔案超過 5MB 先用 grep 抽錯誤關鍵字段落（error、fail、warn、exception），不整檔載入
   - 連結：以瀏覽器開啟時適用 analysis.md 的「外部連結判讀閘門」——
     頁面須有效（非登入頁/載入中/錯誤頁）；**需要登入時停下請使用者授權，
     等明確回覆完成後才繼續**；ArgoCD 頁面依「ArgoCD 頁面判讀準則」
     逐層看到 Last Sync Result 的 failure message 與 App Diff
5. 依 `Type:` 分派，**讀取對應流程檔並照章執行**（各流程檔結尾都會導向
   `references/flows/closing.md` 收尾）：
   - `Something Broken` → `references/flows/broken.md`
   - `Ask Platform` → `references/flows/ask.md`
   - `Pull Request Review` → `references/flows/pr-review.md`
   - 其他 type → 詢問使用者要走哪條流程

## 規則庫維護（新增/修改 PC、SR、PL、判讀準則時）

嚴格依 `references/authoring.md` 執行：分類決策樹 → 照表填欄位 →
跨檔影響表 → 產出「規則變更提案」→ **使用者核可 + `scripts/rule-lint.sh`
通過後才能 commit**。未經核可不改規則庫——與「未經核可不寫 Jira」同級鐵則。

## 鐵則

- 未經使用者核可，絕不寫入 Jira（comment、label 都是）
- 討論模式絕對唯讀：任何情況下都不寫入 Jira
- 範本的 `<填空位>` 發布前必須全部替換，不可殘留
- 報告只寫證據支持的結論；證據不足就標「暫定」並追問，不腦補
- PR 判讀未通過 Diff 證據閘門前，禁止產出報告草稿或進入收尾——
  沒讀到 diff 的診斷無效，寧可跳過留佇列，不可腦補發布
- 未經驗證的頁面內容（登入頁、載入中、未授權）不得作為證據；
  需要登入時等使用者明確確認完成後才繼續判讀
- 證據清單有未消化項目時，不得下確定診斷（只能標「暫定」並說明缺口）
- comment 正文不得出現規則編號與內部術語——編號只出現在 footer 下方的
  規則編號列；分級代號反映在 Priority 欄位而非正文
- 引用任何 PC/SR/PL 規則前，先開啟對應 reference 檔**逐字引述該條內文**，
  不得憑記憶引用（防幻覺編號；jira-publish 的 lint 會再驗一次真實性）
