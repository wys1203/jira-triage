# Backlog

> 尚未實作的改進項目。完成後移到 spec 增補節並在此劃掉。

## 弱模型相容性強化（2026-07-16 規劃）

**背景**：若執行分診的模型不是 Claude 而是較弱模型（如 Qwen3，context ~256k），
現行 skill 依賴大量 LLM 判斷力的設計會失效。核心原則：**弱模型執行的每一步，
要嘛呼叫 script（deterministic），要嘛照 checklist 填空（可驗證），
盡量不留自由發揮空間。**

### 第一批：防呆（必做，純 script 工程，TDD 可覆蓋）

- [ ] **B-1 `jira-state.sh <KEY>`** — 把第 0 步的水位線三態判斷寫成 script，
  deterministic 輸出 `UNTRIAGED` / `TRIAGED_NO_REPLY` / `FOLLOWUP_PENDING`。
  弱模型最容易錯的邏輯推理直接消滅。**投報率最高。**
- [ ] **B-2 `jira-publish.sh <KEY> <草稿檔> [--priority X] [--assign Y]`** —
  把「comment → label → priority → assignee」四連發合併為一次原子呼叫，
  內建冪等檢查。四個決策點變一個。
- [ ] **B-3 草稿 lint（併入 B-2）** — 發布前機械檢查：無殘留 `<填空位>`、
  footer 存在（水位線機制依賴）、必填欄位齊全（PR 的 Diff 證據/轉診）、
  priority 白名單、草稿中引用的 PC/SR/PL 編號真實存在於 references/。
  不過就拒發並列出原因。
- [ ] **B-4 `jira-view.sh` 輸出上限** — comments 預設只出最後 N 則
  （加 `--all` 開關）、超長描述截斷加標記，防 context 稀釋
  （弱模型 30-50k 後注意力衰減，lost in the middle）。

### 第二批：提質（視情況）

- [ ] **B-5 SKILL.md 拆檔（progressive disclosure）** — 主檔只留設定區 +
  模式分派 + 鐵則（~30 行），四條路徑細節拆到 `references/flows/*.md`
  按需載入；處理 Something Broken 不載 PR 流程。
- [ ] **B-6 `pr-diff.sh`（API 版 PR 判讀）** — GitLab API / Azure DevOps API
  直接拉 diff 純文字，瀏覽器降為 fallback。視覺導航是弱模型死穴。
  ⚠️ 需要使用者決策：提供 GitLab / ADO 的 API token 與存放方式。
- [ ] **B-7 分級範例庫（few-shot）** — 每個 severity 等級 3-5 個真實案例
  與判定理由，補弱模型的 K8s 領域直覺。與**討論模式**連動：
  每次 case review 結論沉澱成範例，範例庫隨討論成長。
- [ ] **B-8 引用前逐字引述規則** — SKILL.md 要求引用 PC/SR/PL 前先逐字
  引述該條內文，防幻覺編號（與 B-3 的編號驗證互補）。
- [ ] **B-9 佇列模式逐單棄置細節** — 明確規定一張單處理完摘要一行後
  拋棄細節再讀下一張，控制長佇列的 context 成長。

### 附註

- 這些改動對 Claude 執行也全部有益（防呆閘門對強模型同樣是保險），
  沒有互斥取捨。
- B-1、B-2/B-3 完成後，SKILL.md 對應段落要同步改寫成「呼叫 script + branch」
  的形式，並更新 spec。
