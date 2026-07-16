# 規則庫維護指南（Authoring Guide）

> 給「要新增或修改規則」的模型與工程師。照本指南填表，不需要理解整個
> skill——完整性由分類決策樹、跨檔影響表與 rule-lint 共同保證。
> **鐵則：只能產出「規則變更提案」，經使用者核可且 `scripts/rule-lint.sh`
> 通過後才能 commit。**

## 第一步：分類決策樹（最容易錯的一步，先走完再動手）

依序問，命中就停：

1. **這是在教模型「怎麼看某類證據」嗎？**（如：看 Grafana 先看哪個 panel）
   → 判讀準則，加進 `analysis.md`（無編號，加一個 `##` 節）
2. **user 的提交方式不合規、要退件請他重新提交嗎？**（如：混單、缺必要資訊格式）
   → PL 政策，加進 `policies.md`
3. **user 撞到平台/K8s 的既定規範、該由 user 自己調整嗎？**（如：master node
   不能進駐、quota 用罄）
   → PC 先天條件，加進 `preconditions.md`
4. **某種語意的單固定轉診給特定人嗎？**（如：firewall 申請 → 某 engineer）
   → SR 特例分流，加進 `routing.md` 的「特例分流規則」
5. **是 PR 的轉診對象調整嗎？** → 改 `routing.md` 的「PR Review 分流」表
6. **是分級標準或團隊分流的調整嗎？** → 改 `routing.md` 對應表格
7. 都不是 → 停下來問使用者，不要硬塞

判斷提示：PC 和 PL 最容易混——**PC 是「user 的東西撞牆了」**（結果性），
**PL 是「user 提交的形式不對」**（程序性）。

## 第二步：照表填寫（欄位缺一不可，rule-lint 會驗）

### PC 先天條件（preconditions.md）

```markdown
## PC-0XX: <一句話規則名>

**偵測條件**: <如何從證據判斷命中——錯誤字樣、資源特徵；註明常見出處>

**先天條件**: <平台/K8s 規範本身，一句話>

**標準回覆**: <發給 user 的文字草稿——遵守 report-template.md
「語氣與對外原則」：白話、step-by-step、附小知識、不用內部術語>
```

### SR 特例分流（routing.md「特例分流規則」段內）

```markdown
### SR-0XX: <一句話規則名>

**語意特徵**: <哪些說法算命中——列同義表述，註明依語意判斷非字面比對>

**分流對象**: <[~username] 或團隊名>

**附註**: <分級建議、報告調整等，可省略>
```

### PL 政策（policies.md）

```markdown
## PL-0XX: <一句話規則名>

**適用範圍**: <哪條路徑、何時檢核>

**檢核條件**: <怎樣算違規——具體、可驗證>

**違規原因**: <為什麼有此規範，寫給 user 看得懂的理由>

**重新提交指引**: <user 該怎麼修正重提，step-by-step>
```

## 第三步：跨檔影響表（改完規則檔，檢查要不要動別的檔）

| 變更類型 | 必動 | 檢查是否要動 |
|----------|------|-------------|
| 新增 PC / SR / PL（照既有格式 append） | 該規則檔 + spec 變更紀錄 | 無（SKILL.md 的檢查點是通用的） |
| 修改規則的**偵測/檢核條件定義** | 該規則檔 + spec | **全 repo grep 該定義的舊描述**——定義可能被複述在 SKILL.md、其他規則、spec（前例：resource quota 定義改動時動了 4 個檔） |
| 改分級矩陣 / Priority 映射 | routing.md + spec | SKILL.md 收尾的 priority 說明、範本規則 |
| 改範本結構或 footer | report-template.md + spec | **footer 動到 = 水位線機制變更**，必須同步 jira-state.sh 的 FOOTER 與所有範本；非必要不改 |
| 新增判讀準則 | analysis.md + spec | SKILL.md 第 0 步是否需要點名引用 |

## 第四步：產出「規則變更提案」（固定格式，不得直接 commit）

```
【規則變更提案】
分類判定: <走決策樹的路徑與結論，如「程序性 → PL」>
規則編號: <下一個可用編號，rule-lint 會驗連續性>
完整條文: <照第二步的表格，全文>
影響檔案: <照第三步的表，列出全部要動的檔>
依據: <為什麼需要這條——來自哪個 case 或誰的要求>
```

## 第五步：核可後落地

1. 使用者核可提案
2. 修改列出的所有檔案
3. `bash <skill>/scripts/rule-lint.sh` → 必須 `RULE LINT PASSED`
4. spec 變更紀錄加一列
5. commit（不 push 到生產 tag——發版依 RELEASE.md 流程）

## Worked Example（完整走一遍）

需求：「user 常問為什麼 pod 刪不掉，其實是 PVC 還掛著」

1. 決策樹：是 user 撞到 K8s 既定行為、自己調整可解 → **PC**
2. 編號：現有 PC-001~003 → 新規則是 **PC-004**
3. 條文：

```markdown
## PC-004: Pod 因 PVC finalizer 卡在 Terminating

**偵測條件**: Pod 長時間卡 Terminating，且描述/events 涉及 PVC 或
volume 卸載——常見於 kubectl delete 後「刪不掉」的回報

**先天條件**: K8s 會等 volume 安全卸載後才移除 Pod，PVC 被佔用時
刪除會被暫緩，這是資料保護機制而非故障

**標準回覆**: （依語氣準則撰寫，此處略）
```

4. 影響檔案：preconditions.md、spec 變更紀錄（新增 PC 不需動 SKILL.md）
5. 提案送核 → 核可 → rule-lint → commit
