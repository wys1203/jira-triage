# 平台先天條件（Platform Preconditions）

> 平台的既定規範清單。分診時逐條比對證據，命中即以該條「標準回覆」為診斷主體，
> 分流回報案者自行調整，並在報告理由中引用規則編號。
> 持續補充：新規則直接 append，編號遞增（PC-002、PC-003…）。
> 每條固定三欄：偵測條件（如何從證據判斷命中）、先天條件（平台規範本身）、
> 標準回覆（填入報告的建議文字，發布時依原單語言轉寫）。

## PC-001: Master node 不提供 user app 進駐

**偵測條件**: 症狀涉及的 node name 包含 `-ms-`（master node 命名規則）——
workload 被排程到該類 node，或 user 詢問為何無法使用該類 node

**先天條件**: master node 保留給 control plane，不提供 user application 進駐

**標準回覆**:
此問題源於 workload 被排程（或嘗試排程）到 master node（node name 含 `-ms-`）。
平台規範 master node 不提供 user app 進駐，請調整 Deployment/Pod 的
tolerations（移除容忍 master taint 的設定），必要時搭配 nodeSelector/affinity
確保 workload 排程到 worker node。

## PC-002: Namespace resource quota 用罄

**偵測條件**: 錯誤訊息含 quota exceeded / exceeded quota /
forbidden: exceeded quota 等字樣——常見於 ArgoCD 的 Last Sync Result
failure message、kubectl apply 錯誤、namespace events

**先天條件**: namespace 資源受 ResourceQuota 管制，用罄時新資源會被拒絕建立

**標準回覆**:
此問題源於 namespace 的 resource quota 已用罄（錯誤原文：<逐字引用>）。
請先檢視 namespace 內資源用量，清理不需要的資源或調降 requests；
若確認為業務成長所需，請**開單申請調高 quota**，由平台審核處理。

## PC-003: Bound PVC 的 storageClassName 不可變

**偵測條件**: 錯誤訊息含 spec is immutable，且變更涉及已 Bound PVC 的
storageClassName（例：dc1 → dc2）——常見於 ArgoCD App Diff、apply 錯誤

**先天條件**: Kubernetes 不允許修改已 Bound PVC 的 storageClassName
（PVC spec 絕大部分欄位建立後不可變）

**標準回覆**:
此問題源於嘗試直接修改已 Bound PVC 的 storageClassName（<原值> → <新值>），
K8s 規範此欄位不可變，直接改 yaml 無法生效。正確做法是規劃資料遷移：
建立使用新 storageClass 的新 PVC → 遷移資料 → 切換 workload 掛載 →
回收舊 PVC。如需平台協助，請於單中說明資料量與可停機窗口。
