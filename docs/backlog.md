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
- [ ] **B-6 `pr-diff.sh`（純 API 版 PR 判讀，2026-07-16 討論定案）** —
  取代瀏覽器成為主路徑，瀏覽器降為 fallback（無 token/API 失敗時），
  Diff 證據閘門兩路徑一體適用。
  - **GitLab**: `GET /api/v4/projects/{id}/merge_requests/{iid}/diffs`
    （分頁）直接取得各檔 diff 文字
  - **Azure DevOps**: 無直接 diff API——`iterations/changes` 拿變更檔清單，
    逐檔抓 base/target 兩版內容（items API）後本地 `diff -u`；
    temp file 用完即刪；變更檔數設上限（如 50 檔，超過列檔名不展開）
  - **認證**: 各 engineer 在自己的 `~/.jira-triage.env` 加
    `GITLAB_TOKEN`（read_api）與 `ADO_PAT`（Code Read）——與現行
    onboarding 同一步驟；token 一律唯讀 scope，API 物理上無法 approve
    （鐵則從 prose 升級為能力邊界）；日後與 B-10 一起搬進 jira-cred 保護
  - **已否決的替代案**: git clone/fetch 本地 diff——skill 供多位
    support engineer 使用（SSH key 各自申請成本高），且部分 repo 超肥、
    開發機磁碟有限，完整 clone 不可行；partial clone 仍有 tree 下載成本
  - 效益: 零磁碟、零視覺導航（弱模型死穴消除）、可 headless/cron、
    diff --stat 等級的精確證據天然滿足閘門
- [ ] **B-7 分級範例庫（few-shot）** — 每個 severity 等級 3-5 個真實案例
  與判定理由，補弱模型的 K8s 領域直覺。與**討論模式**連動：
  每次 case review 結論沉澱成範例，範例庫隨討論成長。
- [ ] **B-8 引用前逐字引述規則** — SKILL.md 要求引用 PC/SR/PL 前先逐字
  引述該條內文，防幻覺編號（與 B-3 的編號驗證互補）。
- [ ] **B-9 佇列模式逐單棄置細節** — 明確規定一張單處理完摘要一行後
  拋棄細節再讀下一張，控制長佇列的 context 成長。

## 帳密安全強化（2026-07-16 規劃，目標環境 Ubuntu 24）

**威脅模型**：現行 `~/.jira-triage.env`（chmod 600 明文）與執行 skill 的
LLM agent 同一個 uid，agent `cat` 即讀走；且 JIRA_PASS 很可能是 AD/LDAP
帳密，洩漏影響遠大於 Jira 權限本身。同 uid 之內沒有秘密：
OS keyring（secret-tool）也擋不住 agent 跑同一條 lookup 指令。

- [ ] **B-10 使用者邊界隔離（主防線，Tier 3）** —
  把「能力」給 LLM、把「秘密」留在另一個 uid：
  1. 專用系統帳號 `jira-cred`（`useradd -r -s /usr/sbin/nologin`）
  2. 帳密檔 `/etc/jira-triage/env`（owner jira-cred, mode 600）——
     agent 的 uid 物理上讀不到
  3. 受限 wrapper `/usr/local/lib/jira-triage/authcurl`（root 擁有）：
     以 jira-cred 身分 source env、stdin 注入認證、執行 curl；
     **必須強制 URL 前綴 = JIRA_BASE_URL**，否則淪為帶認證的萬用 curl，
     可被誘導把 Authorization header 打到外部主機
  4. sudoers 白名單：`agent-user ALL=(jira-cred) NOPASSWD: .../authcurl`
  5. `lib.sh` 加 sudo 模式（env 檔模式保留給離線測試，測試不受影響）
  6. 交付物：安裝腳本（建帳號/裝 wrapper/設 sudoers，需使用者 sudo 執行）
  - 殘餘風險：agent 仍持有「操作 Jira」能力（skill 運作必要條件），
    由人工確認閘門管控；密碼本體不再可能進入 context/history/ps/log
- [ ] **B-11 Harness deny 規則（縱深，Tier 1）** — Claude Code settings
  加 deny：`Read(~/.jira-triage.env)` 與相關 Bash pattern。
  成本低但可繞（base64、python open），只當輔助不當主防線。

### 附註

- 這些改動對 Claude 執行也全部有益（防呆閘門對強模型同樣是保險），
  沒有互斥取捨。
- B-1、B-2/B-3 完成後，SKILL.md 對應段落要同步改寫成「呼叫 script + branch」
  的形式，並更新 spec。
