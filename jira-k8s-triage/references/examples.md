# 分級範例庫（Few-shot Examples）

> Classify 步驟的判斷輔助：每個 Severity 等級的真實/典型案例與判定理由。
> 與討論模式連動：case review 的結論沉澱到這裡，範例庫隨案例成長。
> 格式固定三行：症狀／判定／理由。

## S1 範例（生產中斷或資料遺失）

- 症狀：生產 cluster 的 ingress controller 全數 CrashLoop，所有外部流量 5xx
  判定：S1 × U1 → P1
  理由：全站入口中斷、持續惡化中，影響所有服務

- 症狀：StatefulSet 的 PV 底層儲存故障，資料寫入 IO error
  判定：S1 × U1 → P1
  理由：有資料遺失風險——資料安全永遠從嚴評

## S2 範例（生產降級，有 workaround）

- 症狀：ES StatefulSet 擴容失敗，ArgoCD sync failed 顯示 quota exceeded；
  現有副本仍在服務（真實案例，PC-002 誕生的那張單）
  判定：S2 × U2 → P3
  理由：生產受影響但未中斷（現有副本健康）；穩定不惡化。
  注意：命中 PC-002 → 分流回報案者申請 quota，分級照實際影響評

- 症狀：生產 API 間歇性 5xx（錯誤率 ~3%），重試可成功
  判定：S2 × U1 → P2
  理由：生產降級且原因未明（可能惡化）→ 緊急度從嚴

- 症狀：worker node NotReady，Pod 已自動 failover 到其他節點
  判定：S2 × U2 → P3
  理由：容量損失但服務無感；失去更多節點前處理即可

## S3 範例（非生產或單一使用者）

- 症狀：staging 部署失敗，ImagePullBackOff
  判定：S3 × U2 → P3
  理由：非生產環境，但阻擋團隊測試流程

- 症狀：workload 被排程到 master node 起不來（PC-001 典型案例）
  判定：S3 × U3 → P4
  理由：user 端設定錯誤、影響僅自身 workload；先天條件命中類多半落 S3

- 症狀：單一開發者 kubectl 權限被拒
  判定：S3 × U3 → P4
  理由：單人受影響，有平台入口可替代查詢

## S4 範例（諮詢、申請、優化）

- 症狀：詢問 HPA 要怎麼設定才會依 memory 觸發
  判定：S4 × U3 → P4
  理由：純諮詢，無故障

- 症狀：申請開通 edge firewall（SR-001 典型案例）
  判定：S4 × U3 → P4
  理由：申請單非故障單；有明確 deadline 時 U 可上調

## 從嚴評級的通則

- 資料安全疑慮 → S 直接上調一級
- 原因未明且可能擴散 → U 從嚴（U2 視為 U1）
- 「生產」認定以實際流量為準，不看環境命名
