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

## 19. 特例分流規則（Special Routing）

存於 `routing.md` 的「特例分流規則」段，**優先於「K8s 領域分流表」比對**，
命中即直接分流給指定對象並引用規則編號，不再走領域判定。
適用於非 PR 類 issue（Something Broken 與 Ask Platform 路徑各掛一個檢查點）。
編號制 SR-001、SR-002… 持續 append 擴充，與先天條件（PC-xxx）並行。

**首條規則 SR-001**：語意為「申請開通 edge 的 firewall」（含防火牆開通、
firewall rule、開 port / whitelist 到 edge 等同義表述，依語意判斷非字面比對）
→ 直接分流給指定 engineer（設定檔中為 placeholder，由使用者填實際人名）。
此類屬申請單而非故障單，分級通常 S4/U3，止血措施段改為請報案者附上
來源/目的 IP、port、protocol 與申請事由。

## 20. 報告範本調整（取代第 9/11/16 節的部分原設計）

依實際使用回饋做四項調整：

1. **移除「升級觸發條件」段落**：分診 comment 不再包含此段；升級判斷改由
   複診（第 17 節路徑 4）依報案者回報的止血結果處理——止血無效或惡化即
   視同升級事件，提高分級並改分流。第 16 節原「升級條件改為…」的設計
   同步調整為寫入止血措施段（「調整後問題仍存在請回覆本 comment 重新分診」）。
2. **止血建議以 kube-dashboard 為主**：多數報案者沒有 kubectl 執行權限，
   調查類指引優先給 kube-dashboard 操作路徑，kubectl 指令僅供有權限者替代
   （routing.md 止血措施庫加註指引原則）。
3. **可附 YAML 修正建議**：止血措施可附建議的 YAML 修正片段（tolerations、
   resources、affinity 等），發布時用 wiki markup 的 {code} 區塊包覆，
   由報案者透過自己的部署管道套用。
4. **引導式提問必附原因**：「需要補充的資訊」每題附一句為何需要
   （格式：`# <提問>（原因: <一句話>）`）——報案者知道原因才更願意回覆。

## 21. PR Review 轉診分流

PR 判讀完成後（已通過第 18 節的 Diff 證據閘門）必須轉診，依 diff 內容二擇一：

- **resource quota 相關**（diff 涉及 ResourceQuota / LimitRange 物件、
  resources.requests/limits 調整、namespace quota 申請或變更）→ 轉診 engineer A
- **非 resource quota** 的所有 PR → 轉診 engineer B

分流表存於 routing.md 的「PR Review 分流」段（A/B 均為 placeholder，
由使用者填實際人名）；PR 範本新增必填「轉診」欄位。

## 22. 自動更新 Jira Priority（取代第 2 節「不更新 Priority 欄位」的原設計）

分診核可發布後，依分級結論同步更新 Jira Priority 欄位。

**新 script** `jira-priority.sh <ISSUE-KEY> <PRIORITY>`：
PUT `/rest/api/2/issue/<KEY>` 的 `fields.priority.name`；
輸入驗證白名單（Highest, High, Low, Lowest, Blocker, Minor），
非法值給中文錯誤。含離線測試（tests/test-priority.sh）。

**映射**（存於 routing.md「Jira Priority 映射」）：
P1 → Highest、P2 → High、P3 → Low、P4 → Lowest；
Blocker 與 Minor 不由 skill 使用。

**適用範圍**：有分級結論的路徑 1、2（複診時分級有變動也更新）；
路徑 3（PR Review）無分級，不更新。更新動作與 comment/label 同屬
「核可發布」這一步，仍受人工確認閘門保護。

**實作備註**：jira-priority.sh 再次踩到 bash 3.2 的 `$VAR` 後接全形字元
解析 bug（Task 1 已知問題），錯誤訊息以 printf 組字繞過。

## 23. 自動指派 Assignee

分流/轉診對象為具體個人時，核可發布後同步把單指派給該人。

**新 script** `jira-assign.sh <ISSUE-KEY> <USERNAME>`：
PUT `/rest/api/2/issue/<KEY>/assignee` 的 `{"name": "<username>"}`
（Jira Server 格式，非 Cloud 的 accountId）。含離線測試（tests/test-assign.sh）。

**觸發條件**：routing.md 的分流對象以 `[~username]` 格式填寫
（特例分流 SR-xxx、PR Review 分流 A/B 皆適用）——`[~username]` 在 comment
中渲染為提及並通知對方，assignee 取其中的 username 指派。

**不指派的情況**：分流對象為團隊名稱（Jira 無法指派團隊）；
先天條件命中（回報案者自行調整，單留在報案者手上）。

**慣例**：與 comment/label/priority 同屬「核可發布」動作，受人工確認閘門保護。

## 24. 提交政策（Submission Policies）

第三類規則庫 `references/policies.md`，與先天條件（PC-xxx，平台規範、
user 自行調整）、特例分流（SR-xxx，指定對象）並列。政策管的是
**提交規範本身**：違規時不分流、不轉診、不動 priority，
直接以「Policy 違規回覆範本」回覆 Reporter 違規原因（必須引用具體證據）
與重新提交指引，加 triaged label，並把 **assignee 改指回 Reporter**
（單退回報案者手上；Reporter username 由 jira-view.sh 輸出的
`Reporter: 顯示名 (帳號)` 括號內取得）；報案者修正後回覆由複診接手重新分診。

每條政策四欄：適用範圍（哪條路徑、何時檢核）、檢核條件、違規原因、
重新提交指引。編號 PL-001、PL-002… append 擴充。

**檢核點**：路徑 3 在 Diff 證據閘門通過、判讀完成後檢核（優先於轉診判定）；
路徑 1、2 併入先天條件檢查步驟（依各條適用範圍過濾）。

**首條政策 PL-001**：PR 不得混合 resource quota 與其他變更——
quota 變更須由專責 engineer 獨立審核，混單使審核責任無法切分；
違規回覆請 Reporter 將 quota 變更與其他變更拆成獨立 PR 並分別開單。

## 變更紀錄

| 日期 | 內容 |
|------|------|
| 2026-07-14 | v1 設計（第 1-15 節），Task 1-10 實作合入 main；Task 11（安裝/E2E）依使用者決定跳過 |
| 2026-07-15 | 增補第 16 節平台先天條件（PC-001 master node） |
| 2026-07-15 | 增補第 17 節複診 Follow-up（footer 水位線機制） |
| 2026-07-15 | 增補第 18 節 PR Diff 證據閘門（防止未讀 diff 的無效診斷發布） |
| 2026-07-15 | 增補第 19 節特例分流規則（SR-001 edge firewall 開通申請） |
| 2026-07-15 | 增補第 20 節報告範本調整（移除升級觸發條件、kube-dashboard 優先、YAML 建議、追問附原因） |
| 2026-07-15 | 增補第 21 節 PR Review 轉診分流（quota 相關 → engineer A、其他 → engineer B） |
| 2026-07-15 | 增補第 22 節自動更新 Jira Priority（P1→Highest、P2→High、P3→Low、P4→Lowest） |
| 2026-07-15 | 增補第 23 節自動指派 Assignee（分流對象為 [~username] 時同步指派） |
| 2026-07-15 | 增補第 24 節提交政策（PL-001 PR 不得混合 quota 與其他變更） |
| 2026-07-15 | 第 24 節補充：違規單 assignee 改指回 Reporter；jira-view.sh 輸出 Reporter 帳號 |
