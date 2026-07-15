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
