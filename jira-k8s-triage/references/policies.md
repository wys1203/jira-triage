# 提交政策（Submission Policies）

> 報案與 PR 的提交規範。違規時**不進行分流/轉診/priority/assignee**，
> 直接以「Policy 違規回覆範本」回覆 Reporter 違規原因與重新提交方式；
> 報案者修正後回覆，由複診（路徑 4）接手重新分診。
> 持續補充：新政策直接 append，編號遞增（PL-002、PL-003…）。
> 每條固定四欄：適用範圍（哪條路徑、何時檢核）、檢核條件、違規原因、重新提交指引。

## PL-001: PR 不得混合 resource quota 與其他變更

**適用範圍**: Pull Request Review（路徑 3，通過 Diff 證據閘門後檢核）

**檢核條件**: diff 同時包含 resource quota 相關變更（ResourceQuota / LimitRange、
resources.requests/limits 調整、namespace quota）**與**任何其他性質的變更

**違規原因**: resource quota 變更須由專責 engineer 獨立審核，
與其他變更混在同一 PR 會使審核責任無法切分，不符合 policy

**重新提交指引**: 請將 resource quota 變更與其他變更拆成獨立的 PR，
並分別開立對應的 Jira 單
