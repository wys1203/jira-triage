# Routing 設定檔

> 這是你日後最常維護的檔案：團隊改組、調整 SLA、新增止血 runbook 都只改這一份。
> 「分流對象」欄目前是 placeholder，請改成實際團隊/人名。
> 指定個人時請用 `[~username]` 格式（Jira Server 帳號名）——comment 中會
> 渲染成提及並通知對方，且核可發布後 assignee 會同步指派給該人；
> 填團隊名稱則僅在報告中顯示，不動 assignee。

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

### Jira Priority 映射

分診核可後同步更新 Jira Priority 欄位（`jira-priority.sh`）：

| 分級 | Jira Priority |
|------|---------------|
| P1 | Highest |
| P2 | High |
| P3 | Low |
| P4 | Lowest |

（本 Jira 另有 Blocker、Minor 兩值，不由 skill 使用）

## 特例分流規則

> 優先於「K8s 領域分流表」比對；命中即直接分流給指定對象，不再走領域判定，
> 報告理由引用規則編號。適用於非 PR 類 issue（Something Broken 與 Ask Platform）。
> 持續補充：新規則直接 append，編號遞增（SR-002、SR-003…）。

### SR-001: Edge firewall 開通申請

**語意特徵**: 申請開通 edge 的 firewall——包含防火牆開通、firewall rule、
開 port / whitelist 到 edge 環境等同義表述（依語意判斷，不只比對字面關鍵字）

**分流對象**: <指定 engineer，請填實際人名>

**附註**: 此類為申請單而非故障單，分級通常 S4/U3；報告的止血措施段改為
「請附上來源/目的 IP、port、protocol 與申請事由，加速 engineer 處理」

### SR-002: Vault / Secret 元件問題

**語意特徵**: 提及 Secret 長不出來、Secret 找不到、Vault 連不上、
Vault 似乎不 work、ExternalSecret / SecretStore 同步失敗等 Vault 與
Secret 注入相關症狀（依語意判斷，不只比對字面關鍵字）

**分流對象**: <指定 engineer，請填實際人名，格式 [~username]>

**附註**: 判定為疑似 Vault / Secret 元件（含 Secret 同步鏈路）問題，
不走領域分流表；分級依實際影響評（生產環境 Secret 無法注入通常 S2 起跳）

## PR Review 分流

> PR 判讀完成後（已通過 Diff 證據閘門）依 diff 內容判定轉診對象，二擇一：

| 判定 | 依據 | 轉診對象 |
|------|------|----------|
| resource quota 相關 | diff 涉及 ResourceQuota / LimitRange 物件、resources.requests/limits 調整、namespace quota 申請或變更 | <engineer A，請填實際人名> |
| 非 resource quota | 上述以外的所有 PR | <engineer B，請填實際人名> |

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

給報案者的指引原則：
- 調查步驟以 kube-dashboard 操作路徑為主（多數報案者沒有 kubectl 執行權限）；
  下方的 kubectl 指令僅供有權限者作為替代
- 可附上建議的 YAML 修正片段（tolerations、resources、affinity 等），
  發布時用 {code} 區塊包覆，由報案者透過自己的部署管道套用

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
