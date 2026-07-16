# 發版與釘選流程

生產環境 = 各 engineer 下載 repo 的 **ZIP**（生產環境無法 clone GitHub），
解壓後 symlink skill 資料夾進 `~/.config/opencode/skills/`。

## 鐵則

- **一律下載 release tag 的 ZIP，絕不下載 main 的 ZIP**——main 是未經
  E2E 驗證的開發線，tag 才是驗證過的版本：
  ```
  https://github.com/wys1203/jira-triage/archive/refs/tags/vX.Y.zip
  ```
- main 上的任何 commit 未經發版流程不得進入生產

## 發版流程（維護者）

1. main 上開發完成，離線測試全綠：`bash tests/run-all.sh`
2. E2E 回歸：以測試單走完三條路徑（Something Broken 含截圖、Ask Platform、
   PR Review）+ 複診一輪，comment 渲染正確
3. 打 tag 並推送：
   ```
   git tag vX.Y
   git push origin vX.Y
   ```
4. 通知團隊新版 ZIP 連結

## 安裝/升級流程（每台生產機，無 git 環境）

1. 下載 tag ZIP 並解壓成**版本化目錄**（不要覆蓋舊版）：
   ```
   ~/skill-releases/jira-triage-vX.Y/
   ```
2. 重指 symlink（`-n` 必要，否則會解參考舊 symlink）：
   ```
   ln -sfn ~/skill-releases/jira-triage-vX.Y/jira-k8s-triage \
     ~/.config/opencode/skills/jira-k8s-triage
   ```
3. **保留上一版目錄**，這是回滾的依靠

## 回滾

```
ln -sfn ~/skill-releases/jira-triage-v<上一版>/jira-k8s-triage \
  ~/.config/opencode/skills/jira-k8s-triage
```

一分鐘完成，無其他步驟。

## 版本紀錄

| 版本 | 日期 | 內容 |
|------|------|------|
| v1.0 | 2026-07-16 | 首個釘選版：完整分診/複診/討論模式、三規則庫、語氣改造、opencode 環境中立化 |
