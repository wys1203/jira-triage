# 判讀準則庫（Analysis Guidelines）

> 指導「怎麼看證據」的準則——與 PC/SR/PL 規則庫不同（那些決定「判什麼」）。
> 持續補充：新的證據類型判讀準則直接 append。

## 圖片判讀準則

依優先序：

1. **紅色文字優先**——UI 慣例上紅字是錯誤/警示，必須逐字抄錄，
   不可略過或改寫
2. **錯誤語意詞所在行完整抄錄**——Error、Failed、Failure、Missing、
   Denied、Timeout、NotFound、CrashLoop、Refused、Unable、Invalid
   等字樣出現的整行內容
3. 抄錄一律保留原文（錯誤碼、資源名、路徑原樣），這些是分級與分流的
   直接證據；圖中資訊模糊不清時明說「無法辨識」，不腦補

## ArgoCD 頁面判讀準則

依序檢視，缺一不可：

1. **App Health**（Healthy / Degraded / Progressing）
2. **Sync Status**（Synced / OutOfSync）——OutOfSync 只是現象，不是病因，
   看到它不代表找到答案
3. **Last Sync Result 的 failure message**——同步失敗的關鍵錯誤幾乎都在
   這裡（例：quota exceeded、admission webhook 拒絕、immutable 欄位），
   必須點開並逐字抄錄
4. **App Diff**——resource 層級的期望/實際差異（例：Bound PVC 的
   storageClassName 被改動）

只看到 OutOfSync 就下結論 = 無效診斷。

## 外部連結判讀閘門（通用，所有瀏覽器判讀適用）

瀏覽器開啟任何連結後，判讀前必須確認頁面有效：

- 不是登入頁、不是載入中、不是錯誤頁
- **需要登入時：停下，請使用者完成授權，等使用者明確回覆完成後才繼續**
  ——絕不在授權完成前判讀
- 未經驗證的頁面內容不得作為證據（PR Diff 證據閘門的一般化）
