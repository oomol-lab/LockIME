<div align="center">

<img src="../images/appicon.png" alt="LockIME" width="128">

# LockIME

[English](../../README.md) · [简体中文](README.zh-CN.md) · **繁體中文** · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md)

[![最新版本](https://img.shields.io/github/v/release/oomol-lab/LockIME?sort=semver&color=3A5BD9)](https://github.com/oomol-lab/LockIME/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/LockIME/ci.yml?branch=main&label=CI)](https://github.com/oomol-lab/LockIME/actions/workflows/ci.yml)
[![授權條款: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-3A5BD9)](../../LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Greptile: The War on Bugs](https://www.greptile.com/badge.svg)](https://www.greptile.com/?utm_source=oss_badge&utm_medium=readme&utm_campaign=greptile_for_open_source)

</div>

LockIME 是一款 macOS 選單列應用程式，用來鎖定鍵盤輸入法。當你或其他應用程式切換了輸入法，它會立刻切回去：可以全域生效，也可以依應用程式或依瀏覽器 URL 生效。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-general-en-dark.png">
    <img alt="一般設定" src="../images/settings-general-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-app-rules-en-dark.png">
    <img alt="依應用程式規則" src="../images/settings-app-rules-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-url-rules-en-dark.png">
    <img alt="依 URL 規則" src="../images/settings-url-rules-en-light.png" width="32%">
  </picture>
</p>

## Install

```sh
brew install --cask oomol-lab/tap/lockime
```

或者從[最新版本](https://github.com/oomol-lab/LockIME/releases/latest)下載 `.dmg`：Apple silicon 用 `-arm64`，Intel 用 `-x86_64`。需要 macOS 14 或更新版本。LockIME 透過 Sparkle 自動更新，提供 stable 與 beta 兩個頻道。

## Features

- **鎖定或切換。** 應用程式或 URL 的規則可以鎖定某個輸入法，一旦被改動就切回；也可以只在你切到該應用程式或頁面時切換一次，之後任你變更。
- **全域預設。** 可以在所有地方鎖定同一個輸入法，也可以只在退回到預設的應用程式裡切換一次，或者設為*無*，完全交給規則。
- **URL 與網址列規則。** 核心鎖定不需要任何系統權限。可選的增強模式需要 Accessibility 權限，可依 URL 和瀏覽器網址列設定規則。URL 規則可依網域及其子網域、確切網域、關鍵字，或涵蓋整個 URL 的正規表示式比對；拖曳調整優先序，第一個比對到的生效。
- **裸可執行檔。** 沒有 `.app` bundle 的程式，例如 Minecraft 的 `java`，執行期間會以 `process:java` 出現在應用程式挑選器裡。
- **衝突處理。** 當另一個程式不斷強制改回它自己的輸入法時，LockIME 會停手而不是與它來回拉鋸，並把這次衝突寫入記錄。為該應用程式設定一條*忽略*或*切換為*規則即可徹底解決。
- **選單列與快速鍵。** 在選單列或透過全域快速鍵開關 LockIME、更換被鎖定的輸入法。快速鍵還可以切換或移除目前最前方應用程式的規則。
- **觸發記錄。** 最近 24 小時內切換了什麼、為什麼、持續了多久。
- **備份。** 把規則匯出為 `.lockime` 檔案。匯入時會先預覽新增、衝突與移除項，確認後才套用。
- **此外：** 登入時啟動，9 種介面語言無需重新啟動即可切換，下載體積不到 3 MB。

## Comparison

[Input Source Pro](https://github.com/runjuu/InputSourcePro) 與 [KeyboardHolder](https://github.com/leaves615/KeyboardHolder) 會在你切換應用程式或網站時切換輸入法。LockIME 還會讓它保持不變：被鎖定的輸入法一旦被改動就會重新套用。

| | LockIME | Input Source Pro | KeyboardHolder |
|---|---|---|---|
| 開源 | GPL-3.0 | GPL-3.0 | ✗ |
| 最低 macOS | 14 | 11 | 10.15 |
| 下載體積 | < 3 MB | ≈ 7.6 MB | ≈ 4.5 MB |
| 持續重新鎖定 | ✓ | ✗ | ✗ |
| 逐規則鎖定或一次性切換 | ✓ | ✗ | ✗ |
| URL 比對類型 | 子網域、確切、關鍵字、正規表示式 | 子網域、確切、正規表示式 | 網域 (萬用字元) |
| 網址列規則 | ✓ (鎖定/切換/優先序) | ✓ (預設輸入法) | — |
| 全域鍵盤快速鍵 | ✓ | ✓ | ✗ |
| 畫面上輸入法提示 | ✗ | ✓ | ✓ (可選) |
| 24 小時觸發記錄 | ✓ | ✗ | ✗ |
| 設定備份 / 匯入 | ✓ (`.lockime`，含審查) | ✓ (匯出/匯入 + CLI) | — |
| URL scheme 自動化 | ✓ (`lockime://`、x-callback-url) | 部分 (`inputsourcepro://` 匯入) | ✗ |
| 介面語言 | 9 | 6 | 3 |

> 對比基準為 Input Source Pro 2.11.0 與 KeyboardHolder 1.14.10，2026 年中。「—」表示未記載，而非確認不支援。歡迎指正。

## Automation

透過 `lockime://` URL scheme，指令稿、Shortcuts 和其他應用程式可以開關 LockIME、更換被鎖定的輸入法、管理規則，並透過 [x-callback-url](https://x-callback-url.com) 讀回狀態。它預設為關閉，請到**設定 ▸ 一般 ▸ 自動化**開啟。

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
```

完整參考：[URL Scheme API](../URL-Scheme-API/README.zh-TW.md)。

## Development

需要 Xcode 26+、[XcodeGen](https://github.com/yonaskolb/XcodeGen) 和 [xcbeautify](https://github.com/cpisciotta/xcbeautify) (`brew install xcodegen xcbeautify`)。Xcode 專案由 `project.yml` 產生，不納入版本控制。

```sh
make gen      # generate LockIME.xcodeproj from project.yml
make build    # build (Debug)
make run      # build & launch
make test     # run unit tests
make test-hw  # integration tests; briefly changes the input source
```

邏輯位於 `LockIMEKit`，這是一個帶有單元測試、只使用系統框架的靜態程式庫。`LockIME` 應用程式 target 包含 SwiftUI 介面，以及 Sparkle、KeyboardShortcuts 和 PermissionFlow 的整合。應用程式圖示由 `./scripts/make-appicon.sh` 產生。

設計系統見 [docs/DESIGN.md](../DESIGN.md)，發布流程見 [docs/RELEASING.md](../RELEASING.md)。

## License

[GPL-3.0](../../LICENSE)。Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
