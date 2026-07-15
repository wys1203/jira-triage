# Jira K8s Issues Triage Skill — 設計文件

日期：2026-07-14（v1）；2026-07-15 增補第 16-18 節
狀態：設計已與使用者逐段確認；增補功能已實作合入 main

## 1. 背景與目標

K8s Platform Support Engineer 每天需處理大量來自 user 的 Jira 報案（Jira Server v7.10），
分診（triage）是可 loop 且有秩序的流程，但耗費大量人力時間。

本 skill 的核心任務：接收模糊、混亂的初始回報，透過標準 Triage Loop 進行結構化分類、
阻斷擴大、精準分流，並將分診結果以 comment 回寫 Jira。

### 成功標準

- 一個指令即可對單一單號或整個待分診佇列跑完 Triage Loop
- 分診報告格式嚴格一致、高資訊密度
- 所有寫入 Jira 的動作（comment、label）皆經工程師確認後才執行
- 已分診的單不會被重複處理（loop 冪等）

## 2. 範圍

### 本版包含

- Jira Server v7.10 REST API v2 存取（Basic Auth，username/password）
- 三種 issue type 的分派處理：`Something Broken`、`Ask Platform`、`Pull Request Review`
- 附件下載與分析（截圖視覺判讀、log/yaml 文字分析）
- PR 判讀（GitLab 與 Azure DevOps 雙平台，經 Claude in Chrome 瀏覽器判讀）
- 分診報告產出、人工確認、發布 comment、加 `triaged` label

### 本版不包含（預留擴充）

- 主動查詢 K8s cluster 收集證據（第一版純粹依 Jira 單內容分診；
  未來可加唯讀 kubectl 查證，設計上 Ingest 步驟預留此擴充點）
- 自動 approve PR（approve 永遠由人工在 PR 平台執行）
- 更新 Jira Priority 欄位（僅加 label，不動其他欄位）

## 3. 架構總覽

採「Skill + 輔助 scripts」架構：

- **SKILL.md（智慧層）**：Triage Loop 方法論、issue type 分派、確認流程
- **scripts/（機械層）**：封裝 Jira REST API 呼叫，把肥大 JSON 壓成精簡文字，
  集中認證與錯誤處理

被否決的替代方案：純 SKILL.md 臨場組 curl（token 消耗高、行為不穩定）、
完整 CLI/MCP server（過度設計，分診核心價值在 LLM 判斷力而非工具）。

## 4. 檔案結構

skill 於本 repo 開發，安裝時 symlink 至 `~/.claude/skills/jira-k8s-triage`
（沿用使用者現有 skills 的 symlink 慣例）。

```
jira-k8s-triage/
├── SKILL.md                  # 入口：觸發條件、預設 JQL 設定區、兩種模式、分派邏輯
├── references/
│   ├── report-template.md    # 分診報告範本（三種 issue type 各一份格式）
│   ├── routing.md            # 分流設定檔：團隊名單、K8s 領域分類、severity 矩陣、止血措施庫
│   └── questioning.md        # 引導式提問庫（LQQOPQRST 映射 + Golden Signals）
└── scripts/
    ├── jira-view.sh          # 抓單 → 精簡純文字（含 issue type、附件清單）
    ├── jira-search.sh        # JQL 查詢 → 精簡列表（單號、標題、type、建立時間、reporter）
    ├── jira-attach.sh        # 下載指定附件到 session 暫存目錄
    ├── jira-comment.sh       # post comment（Jira 7.10 wiki markup 格式）
    └── jira-label.sh         # 加 label（triaged），內建已有 label 時的冪等檢查
```

`routing.md` 是使用者日後最常維護的檔案：團隊改組、新增 runbook 只改這一份。

## 5. 認證

- Credentials 存於 `~/.jira-triage.env`（`chmod 600`），內容：
  `JIRA_BASE_URL`、`JIRA_USER`、`JIRA_PASS`
- 所有 script 啟動時 source 此檔，以 curl Basic Auth 呼叫 `/rest/api/2/...`
- 密碼不出現在對話、不出現在指令列參數（避免進 shell history 與 ps）、不被 commit
- PR 平台（GitLab、Azure DevOps）不需額外認證：瀏覽器判讀沿用使用者 Chrome
  已登入的 session

## 6. 執行模式

### 單一單號模式

`/jira-k8s-triage PROJ-123` → 對該單跑一輪對應 issue type 的流程。

### 佇列模式

`/jira-k8s-triage`（不帶參數）→ 以預設 JQL 拉出待分診佇列，逐一處理：

```
project = <專案KEY> AND (labels IS EMPTY OR labels != triaged)
AND status in (Open, "To Do") ORDER BY created ASC
```

（注意：Jira JQL 的 `labels != triaged` 不匹配無 label 的單，
必須加 `labels IS EMPTY` 才涵蓋從未分診過的新單。）

專案 KEY、status 清單、JQL 皆定義於 SKILL.md 開頭設定區，安裝時填入、可隨時修改。佇列模式先顯示總覽
（單號、標題、type、建立時間），再逐張處理，全部完成後輸出本輪統計摘要
（處理幾張、各分級數量、跳過幾張）。

## 7. Issue Type 分派

`jira-view.sh` 輸出含 issue type，SKILL.md 依 type 分派三條路徑。
三條路徑共用尾端流程：報告草稿 → 人工確認 → 發 comment → 加 `triaged` label。

### 路徑 1：Something Broken → 完整 Triage Loop

```
1. Ingest & Observe   讀單＋附件 → 提取時間、地點(cluster/namespace/node)、關鍵症狀/錯誤碼
2. Classify           依 severity × urgency 矩陣評級
3. Route              對照 routing.md 分流表決定團隊
4. Mitigate           給出止血臨時措施（引用 routing.md 止血措施庫，非根治方案）
5. Re-evaluate        設定升級觸發條件
6. 資訊不足時          附引導式提問（最關鍵的 2-3 個遺漏線索）
```

### 路徑 2：Ask Platform → 諮詢輕量流程

理解問題 → 直接給答案或指出正確文件/團隊 → 常見問題註明可沉澱為 FAQ。
分級一律 S4，不含止血與升級條件段落。

### 路徑 3：Pull Request Review → 瀏覽器 PR 判讀

```
1. 從單內容提取 PR 連結，依 URL 判別平台：
   - GitLab（含 self-hosted）→ Merge Request 的 Changes 頁
   - Azure DevOps → Pull Request 的 Files 頁
2. 以 Claude in Chrome 開啟 PR 頁面（沿用已登入 session）
3. 判讀：改動範圍、diff 內容、影響面
4. 產出分析報告：改動摘要、風險點（K8s 資源異動、權限變更、破壞性變更）、
   建議關注的檔案、review 建議（傾向可 approve / 需要討論）
5. approve 動作永遠由人工在 PR 平台執行，skill 不碰 approve 按鈕
```

## 8. 附件處理

1. `jira-view.sh` 列出附件清單（附件 ID、檔名、MIME 類型、大小），
   下載 URL 來自 issue JSON 的 `fields.attachment[].content`
2. 圖片附件（png/jpg/gif）：`jira-attach.sh` 下載至 session 暫存目錄，
   以 Read tool 視覺分析（讀出截圖中的錯誤訊息、Pod 狀態、dashboard 畫面），
   納入 Ingest & Observe
3. 文字附件（log、yaml）：同一支 script 下載後閱讀；
   過大檔案（>5MB）先以 grep 抽關鍵段落，不整檔載入 context

## 9. 分級矩陣（routing.md 內容）

### Severity（嚴重度）

| 等級 | 定義 | K8s 範例 |
|------|------|----------|
| S1 | 生產服務中斷或資料遺失 | 整個 namespace Pod CrashLoop、PV 資料毀損、API server 不可用 |
| S2 | 生產服務降級，有 workaround | 部分副本異常、間歇性 5xx、節點 NotReady 但已 failover |
| S3 | 非生產環境或單一使用者受影響 | dev/staging 部署失敗、單人 kubectl 權限問題 |
| S4 | 諮詢、文件、優化建議 | HPA 設定諮詢、資源配額調整請求 |

### Urgency（緊急度）

| 等級 | 定義 |
|------|------|
| U1 | 正在惡化或有明確 deadline |
| U2 | 穩定但持續影響 |
| U3 | 可排程處理 |

### Priority 交叉矩陣

|        | U1 | U2 | U3 |
|--------|----|----|----|
| **S1** | P1（立即升級 on-call） | P2 | P2 |
| **S2** | P2（當日處理） | P3 | P3 |
| **S3** | P3 | P3 | P4 |
| **S4** | P3 | P4 | P4 |

矩陣可依團隊 SLA 調整，調整只改 routing.md。

## 10. K8s 領域分類與分流表（預設值）

分流對象為 placeholder，使用者依實際團隊編制修改 routing.md。

| 領域 | 典型症狀/關鍵字 | 分流對象 |
|------|----------------|----------|
| Compute/Workload | CrashLoopBackOff、OOMKilled、ImagePullBackOff、FailedScheduling | Platform 團隊 |
| Network | CNI 錯誤、Service/Ingress 不通、DNS 解析失敗、NetworkPolicy | Network 團隊 |
| Storage | PVC Pending、mount failed、IO error、StorageClass | Storage 團隊 |
| Control Plane | API server 慢、etcd、controller/scheduler 異常 | SRE/Infra 團隊 |
| Node/OS | NotReady、kubelet、資源壓力、kernel | Infra 團隊 |
| App 層 | 應用邏輯錯誤、config 錯誤、image 內容問題 | 回歸應用團隊（附證據） |
| Security/RBAC | 權限拒絕、certificate、secret | Security 團隊 |

每個領域附常見止血措施清單供 Mitigate 步驟引用
（例：Compute → rollback 上一版、暫時調高 memory limit、cordon 問題節點）。

## 11. 分診報告範本（report-template.md 內容）

Comment 語言跟隨原單語言（技術名詞保留英文）。
Something Broken 的完整格式（中文示意）：

```
🏥 分診報告 (Triage Report)
━━━━━━━━━━━━━━━━━━━━
■ 症狀摘要
  時間: <發生時間/持續時間>　地點: <cluster/namespace/資源>
  關鍵症狀: <錯誤碼、現象，一行一條>

■ 分級: P2 (Severity: S2 × Urgency: U1)
  理由: <一句話>

■ 分流: → <團隊名>
  理由: <證據指向哪個領域>

■ 立即止血措施（非根治）
  1. <可立即執行的動作>

■ 升級觸發條件
  若 <條件：錯誤率超過 X%、擴散到其他 namespace、止血無效超過 30 分鐘>，
  請立即回報並升級至 <對象>。

■ 需要補充的資訊（如適用）
  1. <引導式提問，最多 3 題>
━━━━━━━━━━━━━━━━━━━━
🤖 由 triage skill 產生，經工程師審核後發布
```

- 證據不足時：「分級」標註 `暫定`，「需要補充的資訊」為必填段落
- Ask Platform 精簡格式：問題理解、解答/指引、FAQ 建議
- PR Review 格式：改動摘要、風險點、建議關注檔案、review 建議
- 實際輸出使用 Jira 7.10 wiki markup（非 ADF）

## 12. 引導式提問庫（questioning.md 內容）

### LQQOPQRST → K8s 映射

| 問診項 | K8s 追問 |
|--------|----------|
| Location | 哪個 cluster / namespace / pod？ |
| Quality | 錯誤長什麼樣？確切錯誤碼/訊息？ |
| Quantity | 影響幾個 Pod / 幾 % 請求？ |
| Onset | 何時開始？之前改了什麼（deploy、config、升級）？ |
| Palliative/Provocative | 做什麼會好轉/惡化（重啟、擴容）？ |
| Region | 有無擴散到其他 namespace/cluster？ |
| Severity | 對業務的實際影響？ |
| Timing | 持續性或間歇性？有無週期？ |

### Golden Signals 檢查

Latency / Traffic / Errors / Saturation 各對應一個追問句。

### 選題規則

只挑「最能改變分級或分流結論」的 2-3 題，不全問。
例：已知錯誤碼但不知範圍 → 問 Quantity 與 Region。

## 13. 人工確認流程

每張單產出報告草稿後，以選項方式詢問：

- **核可發布** → `jira-comment.sh` 發 comment + `jira-label.sh` 加 label
- **修改後發** → 使用者指出修改處，改完重新確認
- **跳過此單** → 不留任何痕跡（不加 label），下輪佇列仍會出現，避免跳過變漏掉

## 14. 冪等與錯誤處理

- 發 comment 前 `jira-label.sh` 先檢查該單是否已有 `triaged` label，
  有則中止並回報（防兩個 session 同時分診同一張單）
- scripts 對常見錯誤給出明確錯誤訊息與下一步指示：
  401（認證失效 → 檢查 `~/.jira-triage.env`）、404（單號不存在）、網路逾時
- PR 連結缺失或瀏覽器無法開啟 → 回報並改走「需要補充資訊」路徑，不硬猜

## 15. 測試策略

- 每支 script 可獨立手動測試（view/search/attach/comment/label 各自驗證）
- 實作完成後以真實測試單分別走完三條路徑的端到端流程：
  1. Something Broken 含截圖附件 → 驗證附件視覺分析
  2. Ask Platform → 驗證輕量格式
  3. Pull Request Review（GitLab 與 Azure DevOps 各一）→ 驗證雙平台判讀
- comment 先發到測試單驗證 wiki markup 渲染正確，再用於正式佇列

---

以下為 v1 合入後的增補設計（2026-07-15，均已與使用者確認並實作）。

## 16. 平台先天條件（Platform Preconditions）

平台既定規範清單，存於 `references/preconditions.md`，由使用者持續補充
（append 即可，編號遞增）。每條規則固定三欄：

- **偵測條件**：如何從證據判斷命中（node name、namespace、資源設定等）
- **先天條件**：平台規範本身
- **標準回覆**：填入報告的建議文字（發布時依原單語言轉寫）

**掛載點**：路徑 1 在 Ingest 與 Classify 之間插入「先天條件檢查」步驟；
路徑 2（Ask Platform）也做同樣比對。

**命中時的行為**：以該條標準回覆為診斷主體；分流改為「回報案者自行調整」
（不轉專門團隊）；分級照實際影響評（通常 S3，屬 user 端設定錯誤）；
升級條件改為「調整後問題仍存在，表示非先天條件問題，請重開流程」；
報告理由引用規則編號（如 PC-001）以利追溯。

**首條規則 PC-001**：node name 含 `-ms-` 為 master node，保留給 control plane，
不提供 user application 進駐；標準回覆引導 user 調整 tolerations
（移除容忍 master taint 的設定），必要時搭配 nodeSelector/affinity。

## 17. 複診（Follow-up）

處理報案者對分診 comment 的回覆（補充資訊、追問、止血結果回報、確認解決）。

**偵測原理——footer 水位線**：skill 發的每則 comment 都帶
`🤖 由 triage skill 產生` footer。水位線 = comments 中最後一則含 footer 的
comment；水位線之後若有其他人的 comment 即為待處理 follow-up。
每次複診回覆帶同樣 footer，水位線自動前移，天然支援多輪往返，
不需新 script 或額外欄位。

**第 0 步三態判斷**（取代原「已 triaged 即跳過」）：

1. 無 footer 且無 `triaged` label → 未分診，照原流程分派
2. 有 footer 且水位線後有他人 comment → 進入路徑 4（複診），跳過類型分派
3. 其他（已分診無新回覆，含「有 label 無 footer」的手動標記）→ 跳過

**路徑 4（複診）**依回覆類型處理（可複合）：

- 補充資訊 → 新證據併入原診斷，重跑先天條件檢查與 Classify/Route，
  結論有變時明確標註（例：分級 S3 → S2）
- 追問／質疑 → 直接回答；確實誤判則修正結論並致謝
- 回報止血結果 → 有效：建議觀察期後結案；無效或惡化：依原報告升級條件
  升級、提高分級並改分流
- 表示已解決 → 回覆確認並建議報案者結案（不操作 Jira 狀態）

**佇列模式**加第二輪掃描，Follow-up JQL：
`project = <KEY> AND labels = triaged AND updated >= -7d ORDER BY updated DESC`
（`updated` 會被任何欄位異動觸發，須逐張以水位線二次確認）。

**範本**：report-template.md 新增「Follow-up 範本」——回應摘要、
更新後結論（僅列有變動者）、下一步建議；footer 必須保留以維持水位線機制。

**收尾**：複診時單已有 `triaged` label，`jira-label.sh` exit 2 屬預期行為。

## 18. PR Diff 證據閘門

**問題背景**：實際使用中發生 LLM 經瀏覽器判讀 PR 時，第一時間未切到正確的
diff 頁面就產出診斷草稿並通過人工確認發布；之後才找到 diff 頁籤取得正確
內容，但 comment 已發出。沒讀到 diff 的診斷是無效診斷，且草稿表面上
無法分辨真偽。

**設計——讓無效草稿在結構上不可能通過**：

1. **硬性閘門**（路徑 3 判讀前）：必須確認已在正確頁面（GitLab 的 Changes 頁 /
   Azure DevOps 的 Files 頁），並實際取得變更檔案清單（含每檔 +/- 行數）、
   至少引用一段真實 diff 內容。頁籤沒切對、lazy-load 未展開、權限不足時
   重試 2-3 次；仍失敗 → 本次診斷無效：不產草稿、不發 comment、不加 label，
   回報使用者後跳過，單留在佇列下輪再處理
2. **範本必填欄位**：PR 範本新增「Diff 證據」欄
   （`共 N 檔變更（file1 +a/-b、…）`）——具體檔名與行數只有真正讀取 diff 頁
   才能取得；缺失或填不出具體數字 = 草稿無效，禁止進入收尾。
   工程師在確認關卡可據此一眼驗證真偽
3. **鐵則**：PR 判讀未通過 Diff 證據閘門前，禁止產出報告草稿或進入收尾

**「找不到 PR 連結」維持原設計**：發追問 comment + 加 label——報案者補連結
後由複診（第 17 節）接手重跑路徑 3，同樣受證據閘門約束。

## 變更紀錄

| 日期 | 內容 |
|------|------|
| 2026-07-14 | v1 設計（第 1-15 節），Task 1-10 實作合入 main；Task 11（安裝/E2E）依使用者決定跳過 |
| 2026-07-15 | 增補第 16 節平台先天條件（PC-001 master node） |
| 2026-07-15 | 增補第 17 節複診 Follow-up（footer 水位線機制） |
| 2026-07-15 | 增補第 18 節 PR Diff 證據閘門（防止未讀 diff 的無效診斷發布） |
