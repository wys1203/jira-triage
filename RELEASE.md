# 發版與釘選流程

生產環境 = 各 engineer 的 local clone + symlink 進 `~/.config/opencode/skills/`。
**clone 當下 checkout 的內容就是生產行為**，因此：

## 鐵則

- 生產機的 clone **嚴禁直接 `git pull`（跟 main）**——一律停在 release tag 上
- main 是開發線，任何 commit 未經發版流程不得進入生產

## 發版流程（維護者）

1. main 上開發完成，離線測試全綠：`bash tests/run-all.sh`
2. E2E 回歸：以測試單走完三條路徑（Something Broken 含截圖、Ask Platform、
   PR Review）+ 複診一輪，comment 渲染正確
3. 打 tag 並推送：
   ```
   git tag vX.Y
   git push origin vX.Y
   ```

## 升級流程（每台生產機）

```
cd <clone 路徑>
git fetch --tags
git checkout vX.Y
```

symlink 不用動——換 checkout 即換版本。

## 回滾

```
git checkout v<上一版>
```

一分鐘完成，無其他步驟。

## 版本紀錄

| 版本 | 日期 | 內容 |
|------|------|------|
| v1.0 | 2026-07-16 | 首個釘選版：完整分診/複診/討論模式、三規則庫、語氣改造、opencode 環境中立化 |
