# 路徑 1：Something Broken（完整 Triage Loop）

依序執行五步驟，結論寫進 `references/report-template.md` 的「Something Broken 範本」：

1. **Ingest & Observe**：從描述、comments、附件提取——時間（何時開始/持續多久）、
   地點（cluster/namespace/node/資源名）、關鍵症狀與錯誤碼
2. **先天條件與政策檢查**：對照 `references/preconditions.md` 與
   `references/policies.md`（依各條適用範圍）逐條比對提取出的證據
   （node name、namespace、資源設定等）。政策違規時改用「請調整後重新
   提交範本」產草稿（不分流、不動 priority，assignee 改指回 Reporter），
   直接進收尾（`references/flows/closing.md`）。
   先天條件命中時以該條「標準回覆」為診斷主體：
   分流改為「回報案者自行調整」（不轉專門團隊）、分級照實際影響評（通常 S3，
   屬 user 端設定錯誤）、止血措施段以標準回覆為主體並註明「調整後問題仍存在，
   表示非先天條件問題，請回覆本 comment 重新分診」；命中編號記入
   內部判定摘要與 footer 下方的規則編號列，**正文不出現代號**；
   命中後跳過步驟 5 的止血措施庫
3. **Classify**：依 `references/routing.md` 的「Severity 分級」「Urgency 分級」評 S×U，
   再用「Priority 交叉矩陣」得出 P1-P4；拿不準時對照 `references/examples.md`
   的同級範例與從嚴通則；證據不足時標「暫定」
4. **Route**：先比對 `references/routing.md` 的「特例分流規則」，命中直接採用
   該條分流對象，編號記入內部判定摘要與規則編號列（正文不出現）；
   未命中才對照「K8s 領域分流表」，依症狀關鍵字判定領域與分流對象；
   證據同時指向多個領域時，選最上游的
   （例：節點 NotReady 引發 Pod 崩潰 → Node/OS）
5. **Mitigate**：從「止血措施庫」對應領域挑 1-3 條立即可執行、可逆的動作；
   調查類指引以 kube-dashboard 操作路徑為主（多數報案者沒有 kubectl 執行權限），
   kubectl 指令僅供有權限者替代；可附建議的 YAML 修正片段（tolerations、
   resources、affinity 等，發布時用 {code} 區塊包覆）；絕不給根治方案，
   那是接手團隊的事

報告不含「升級觸發條件」段落——升級判斷由複診（`references/flows/followup.md`）
依報案者回報的止血結果處理。

證據不足時（分級或分流下不了結論）：依 `references/questioning.md` 的「選題規則」
從 LQQOPQRST 映射與 Golden Signals 檢查中挑 2-3 題，填入報告的「需要補充的資訊」，
每題附一句為何需要這個資訊。

完成後依 `references/flows/closing.md` 收尾。
