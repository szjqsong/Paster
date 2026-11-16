# Paster

macOS 剪貼簿管理工具，操作方式參考 Paste：按快捷鍵從螢幕底部叫出一排卡片，選一張就直接貼到目前使用中的 App。

## 安裝

1. 打開 `dist/Paster-<版本>.dmg`，把 **Paster** 拖到「應用程式」資料夾。
2. 第一次打開：這個 App 是 ad-hoc 簽名，沒有 Apple 開發者憑證，請在「應用程式」資料夾對 Paster **按右鍵 → 打開**。若仍被擋，執行：
   ```sh
   xattr -dr com.apple.quarantine /Applications/Paster.app
   ```
3. 依提示到「系統設定 → 隱私權與安全性 → 輔助使用」打開 Paster，才能直接貼上。沒開的話，選擇項目只會拷貝到剪貼簿。

## 快捷鍵

| 按鍵 | 動作 |
|---|---|
| ⇧⌘V | 打開／關閉面板（可在偏好設定修改） |
| ← → | 選擇卡片（⌘← ⌘→ 跳到頭尾） |
| ↩ | 貼上 |
| ⇧↩ | 以純文字貼上 |
| ⌘1–9 | 快速貼上第 1–9 個（⇧⌘1–9 為純文字） |
| 空白鍵 | 預覽 |
| ⌘C | 只拷貝不貼上 |
| ⌘⌫ | 刪除 |
| ⇥ ／ ⇧⇥ | 切換釘選板 |
| ⌘N | 新增釘選板 |
| ⌘F 或直接打字 | 搜尋 |
| ⌘, | 偏好設定 |
| Esc | 關閉預覽 → 清除搜尋 → 關閉面板 |

## 功能

- 記錄文字、格式文字（RTF/HTML）、連結、圖片、檔案與顏色碼；重複內容會合併並移到最前面。
- 卡片頂部顏色取自來源 App 圖示，顯示 App 圖示、類型、時間、字數或尺寸。
- 搜尋內容、來源 App、檔名，以及圖片中的文字（Vision 裝置上 OCR）。
- 釘選板：在卡片上按右鍵 →「釘選到」。釘選的項目不受歷史上限與清除影響。
- 隱私：
  - 遵守 `org.nspasteboard` 的機密／暫時性標記。
  - 預設忽略 1Password、Bitwarden、Dashlane、LastPass、Keeper、Apple 密碼、鑰匙圈存取。
  - 可暫停記錄。
  - 螢幕分享和錄影時不顯示面板。
- 選單列圖示：最近 10 個項目、暫停、偏好設定。
- 偏好設定：快捷鍵、登入時啟動、直接貼上、預設純文字、歷史上限、忽略的 App。

資料存放在 `~/Library/Application Support/Paster/`（`history.json` 與 `blobs/`）。

## 從原始碼建置

需要 Xcode 或 Command Line Tools（Swift 5.9 以上）。

```sh
./scripts/build_dmg.sh            # 產生 build/Paster.app 與 dist/Paster-1.0.0.dmg
VERSION=1.1.0 ./scripts/build_dmg.sh
```

開發用：

```sh
swift build
PASTER_DATA_DIR=/tmp/paster-test .build/debug/Paster --self-test
PASTER_DATA_DIR=/tmp/paster-test .build/debug/Paster --snapshot /tmp/strip.png
```

## 尚未實作

- iCloud 同步、Paste Stack（依序貼上）、拖曳卡片到其他 App、釘選板內拖曳排序、AI 分類。
