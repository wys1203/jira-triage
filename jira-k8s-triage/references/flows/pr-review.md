# 路徑 3：Pull Request Review（瀏覽器判讀）

1. 從單的描述與 comments 提取 PR 連結；找不到連結時，走「需要補充的資訊」
   請報案者補 PR 連結，不硬猜
2. 依 URL 判別平台：
   - 含 `gitlab` 或路徑帶 `/-/merge_requests/` → GitLab，diff 在 MR 的 **Changes** 頁
   - 含 `dev.azure.com` 或 `visualstudio.com` → Azure DevOps，diff 在 PR 的 **Files** 頁
3. 以執行環境提供的瀏覽器自動化工具開啟 PR 頁面（工具名稱依 agent 環境
   而異，用當下可用的即可；優先沿用使用者已登入的瀏覽器 session，
   避免重新處理 code review 平台的登入）
4. **Diff 證據閘門**：判讀前必須確認已在正確頁面（GitLab 的 **Changes** 頁 /
   Azure DevOps 的 **Files** 頁），並實際取得變更檔案清單（含每檔 +/- 行數）、
   至少引用一段真實 diff 內容。頁籤沒切對、lazy-load 未展開、權限不足時先重試
   切換頁籤/展開 2-3 次；仍拿不到證據 → **本次診斷無效：不產草稿、不發 comment、
   不加 label**，向使用者回報原因後跳過此單（留在佇列，下輪再處理）
5. 判讀：改動範圍、diff 內容、影響面；特別留意 K8s 資源異動、權限變更、破壞性變更
6. **Policy 檢核**：對照 `references/policies.md` 適用於 PR 的政策
   （如 PL-001：diff 混合 resource quota 與其他變更）。違規 → 不轉診、
   不做後續判讀結論，改用「請調整後重新提交範本」產草稿（具體證據寫入
   正文，編號記入規則編號列），直接進收尾（不動 priority，assignee 改指回
   Reporter）；報案者拆單重提後由複診接手
7. 依 `references/routing.md` 的「PR Review 分流」判定轉診對象：diff 涉及
   resource quota 相關（ResourceQuota / LimitRange 物件、namespace quota
   申請或變更；不含 workload 自身的 resources.requests/limits）
   → 轉診 engineer A；其他一律 → engineer B
8. 用「Pull Request Review 範本」產草稿；「Diff 證據」與「轉診」欄位必填，
   Diff 證據填不出具體檔名與行數 = 草稿無效，禁止進入收尾
9. **絕不碰 approve 按鈕**——approve 永遠由人工在 PR 平台執行
10. 瀏覽器連續失敗 2-3 次就停下回報，不要無限重試

完成後依 `references/flows/closing.md` 收尾。
