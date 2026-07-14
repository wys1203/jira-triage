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
