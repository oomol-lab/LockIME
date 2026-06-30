<div align="center">

<img src="../images/appicon.png" alt="LockIME" width="128">

# LockIME

[English](../../README.md) · [简体中文](README.zh-CN.md) · **繁體中文** · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md)

[![最新版本](https://img.shields.io/github/v/release/oomol-lab/LockIME?sort=semver&color=3A5BD9)](https://github.com/oomol-lab/LockIME/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/LockIME/ci.yml?branch=main&label=CI)](https://github.com/oomol-lab/LockIME/actions/workflows/ci.yml)
[![授權條款: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-3A5BD9)](../../LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)

</div>

一款 macOS 選單列應用程式，用於**鎖定你的鍵盤輸入法**。每當你（或其他應用程式）切換輸入法時，LockIME 會立即切回被鎖定的那個——可以是全域的、依最前方應用程式區分的，或者（在可選的增強模式下）依瀏覽器 URL 區分的。

> macOS 14+ · 支援 Apple silicon 與 Intel——兩個獨立的應用程式，請下載與你的
> Mac 相符的 `-arm64` 或 `-x86_64` 檔案 · 以 SwiftUI 打造，macOS 26 (Tahoe)
> 上呈現 Liquid Glass。

## Screenshots

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

使用 [Homebrew](https://brew.sh) 安裝（cask 會自動選取與你的 Mac 架構相符的建置版本）：

```sh
brew install --cask oomol-lab/tap/lockime
```

或者從[最新版本](https://github.com/oomol-lab/LockIME/releases/latest)下載與你的 Mac 相符的 `.dmg`（Apple silicon 用 `-arm64`，Intel 用 `-x86_64`）。無論哪種方式，應用程式都會透過 Sparkle 自動保持最新。

## Features

- **即時重新鎖定**——每當你（或其他應用程式）切換輸入法時，立即切回被鎖定的那個，可全域或依應用程式生效。
- **鎖定或切換**——各應用程式與各 URL 的規則既可*鎖定*某個輸入法（一旦偏離就重新切回），也可以在你切到該應用程式或頁面時只*切換*一次，之後任你自由變更。
- **全域鎖定，或僅切換**——只要一個 **啟用 LockIME** 開關就能驅動一切；其下從屬的 **啟用鎖定** 切換則只控制持續鎖定。把鎖定關掉，就能把 LockIME 當作純粹的依應用程式／依站台切換器使用——它會在你切入時幫你切好，之後便放手讓你自由，什麼也不固定。
- **彈性的 URL 比對**——依 URL 規則（增強模式）可依一個網域及其子網域、一個確切網域、一個網域關鍵字，或一個涵蓋整個 URL 的正規表示式來比對，並依你拖曳排列的優先序套用——第一個比對到的勝出。
- **選單列控制**——在選單列啟用/停用、切換被鎖定的輸入法、檢視目前輸入法、追蹤觸發次數。
- **鍵盤快速鍵**——可自訂的全域快速鍵用於開關 LockIME、切換被鎖定的輸入法（上一個 / 下一個），以及針對目前最前台應用程式的快速鍵，用於切換或移除該應用程式的規則。
- **登入時啟動**——登入後自動啟動（預設關閉）。
- **淺色 / 深色模式**——統一的、系統原生的設計語言，自動適應淺色與深色外觀，並配有專屬應用程式圖示。參見 [docs/DESIGN.md](../DESIGN.md)。
- **即時語言切換**——在 9 種語言間即時切換，無需重新啟動：English、简体中文、繁體中文、日本語、Français、Deutsch、Español、Português、Русский。
- **24 小時觸發記錄**——回顧切換了什麼、為什麼、持續了多久。
- **設定備份**——把依應用程式與依 URL 的規則匯出為 `.lockime` 檔案，再匯入回來；匯入前會有一個預覽步驟，先列出新增、衝突與移除項，確認後再套用。
- **透過 Sparkle 自動更新**——stable 與 beta 兩個頻道，配有自訂更新視窗。
- **超小體積**——整個應用程式打包成不到 3 MB 的 `.dmg`。
- **核心鎖定無需系統權限**——可選的、由 Accessibility 把關的增強模式可解鎖更細緻的依 URL / 聚焦欄位規則。
- **自動化**——`lockime://` URL scheme 讓其他應用程式、指令稿與「捷徑」（Shortcuts）能驅動 LockIME（見下文）。

## Comparison

macOS 輸入法生態中有兩個被廣泛使用、可替代 LockIME 的選擇——
**[Input Source Pro](https://github.com/runjuu/InputSourcePro)**（≈3.3k★，最受
歡迎的那個）與 **[KeyboardHolder](https://github.com/leaves615/KeyboardHolder)**
（≈1.6k★）——再加上一長串較小型的開源與 CLI 工具。它們全都會在你於應用程式或
站台之間移動時*切換*輸入法；LockIME 則是圍繞著持續**鎖定**打造的那一個，一旦
輸入法偏離就立刻重新套用，同時仍允許任一條規則在你只需要這樣時退回到一次性的
*切換*。

| | LockIME | Input Source Pro | KeyboardHolder |
|---|---|---|---|
| 價格 | 免費 | 免費 | 免費（捐款） |
| 開源 | GPL-3.0 | GPL-3.0 | ✗（閉源） |
| 最低 macOS | 14 | 11 | 10.15 |
| 下載體積 | < 3 MB | ≈ 7.6 MB | ≈ 4.5 MB |
| 依應用程式規則 | ✓ | ✓ | ✓ |
| 依站台 / URL 規則 | ✓ | ✓ | ✓ |
| URL 比對類型 | 子網域 · 確切 · 關鍵字 · 正規表示式 | 子網域 · 確切 · 正規表示式 | 網域（萬用字元） |
| 網址列（URL 欄位）規則 | ✓（鎖定 / 切換 / 優先序） | ✓（預設輸入法） | — |
| 持續重新鎖定 | ✓ | ✗ | ✗ |
| 逐規則鎖定*或*一次性切換 | ✓ | ✗ | ✗ |
| 全域鍵盤快速鍵 | ✓ | ✓ | ✗ |
| 選單列控制 | ✓ | ✓ | ✓ |
| 畫面上輸入法提示 | ✗ | ✓ | ✓（可選） |
| 24 小時觸發記錄 | ✓ | ✗ | ✗ |
| 設定備份 / 匯入 | ✓（`.lockime`，含審查） | ✓（匯出/匯入 + CLI） | — |
| URL scheme 自動化 | ✓（`lockime://`、x-callback-url） | 部分（`inputsourcepro://` 匯入） | ✗ |
| 介面語言 | 9（即時切換） | 6 | zh · en · ja |
| 系統權限 | 核心免權限 · 依 URL 需 Accessibility | 核心免權限 · 依 URL 需 Accessibility | Accessibility¹ |
| 自動更新 | Sparkle（stable + beta） | ✓ | ✓ |
| 持續維護中（2026） | ✓ | ✓ | ✓ |

¹ KeyboardHolder 未說明它的權限需求；在實務上，要為其依站台規則讀取瀏覽器
網址列需要 Accessibility 存取權。

**其他值得了解的工具：**
[SwitchKey](https://github.com/itsuhane/SwitchKey)（≈959★、GPL-3.0、僅自動依
應用程式、自 2021 年起未再維護）、
[Kawa](https://github.com/hatashiro/kawa)（≈1.5k★、MIT、*手動*以快速鍵驅動
切換、自 2017 年起未再維護）、InputSwitcher（freemium、僅依應用程式），以及
[macism](https://github.com/laishulu/macism)（供編輯器整合的 CLI 構件，並非
GUI 切換器）。

**LockIME 的定位：**若想要最大的社群與最豐富的畫面上輸入法提示——一個跟隨你
游標的浮動指示器，並具備色彩配置與位置控制——請選 **Input Source Pro**；若想
要精緻、零設定、開箱即用的依應用程式記憶，請選 **KeyboardHolder**。當你想要把
輸入法*固定*住、而不只是切換它時，就選 **LockIME**：一種硬性的依應用程式、依
URL 或網址列**鎖定**，只要有任何東西改變它就立刻重新套用——並具備逐規則的一次
性*切換*模式、`keyword` 這種 URL 比對類型、豐富的 `lockime://` 自動化
（x-callback-url、完整狀態控制）、24 小時觸發記錄、這一群裡最廣的在地化
（9 種語言），以及最小的下載體積（不到 3 MB）。

> 數字為約略值，蒐集於 2026 年中（Input Source Pro 2.11.0、
> KeyboardHolder 1.14.10）；「—」標示的是未記載的能力，而非已確認的缺漏。
> 星數、體積與能力都會隨時間變動——歡迎指正。

## Automation

LockIME 提供 `lockime://` URL scheme，讓其他應用程式、指令稿、「捷徑」（Shortcuts）與啟動器都能驅動它——切換鎖定、重新指定輸入法、管理規則，並透過 [x-callback-url](https://x-callback-url.com) 回呼讀回狀態。它預設為關閉——請到 **設定 ▸ 一般 ▸ 自動化** 把它開啟。

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
```

完整參考：**[URL Scheme API](../URL-Scheme-API/README.zh-TW.md)**。

## Design

LockIME 遵循單一的設計系統（`Sources/LockIME/UI/DesignSystem.swift`）：語意化顏色、系統材質和 SF Symbols 驅動淺色/深色適應；Liquid Glass 僅保留給浮動/導覽層使用。品牌強調色 "Lock Indigo" 以 `AccentColor` 資源的形式提供。完整規格見 [docs/DESIGN.md](../DESIGN.md)。

應用程式圖示以程式化方式產生（不使用任何設計工具）——用以下指令重新產生：

```sh
./scripts/make-appicon.sh   # renders the master via SwiftUI and rebuilds the appiconset
```

## Development

需要 Xcode 26+（應用程式本身以 macOS 14+ 為目標），以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen) + [xcbeautify](https://github.com/cpisciotta/xcbeautify)（`brew install xcodegen xcbeautify`）。

```sh
make gen     # generate LockIME.xcodeproj from project.yml
make build   # build (Debug)
make run     # build & launch
make test    # run unit tests
make archive # Release archive (Developer ID)
```

Xcode 專案由 `project.yml` 產生，不納入版本控制。

涉及硬體的整合測試（真實的 TIS 切換）已從 `make test` 中排除；用 `make test-hw` 執行它們（會短暫改變輸入法）。

## Releasing

由 dispatch 驅動、經過公證的 Developer ID 發佈，透過 Sparkle 在 **stable** 和 **beta** 兩個頻道自動更新：執行 Release 工作流程（Actions → Release），它會從 git 標籤計算版本號、建置，並自動建立標籤和 GitHub Release——切勿手動推送標籤。beta 頻道即每夜建置。每個版本都分別提供 Apple silicon 與 Intel 兩個獨立應用程式，各自走自己的更新 feed（不提供 universal 二進位檔，也不支援跨架構更新）。參見 [docs/RELEASING.md](../RELEASING.md)。

## Architecture

- **LockIMEKit**（靜態程式庫）——純粹的、經過完整單元測試的邏輯，僅使用系統框架：鎖定引擎、應用程式監視器、規則、增強（Accessibility）觀察器、記錄模型、在地化。
- **LockIME**（應用程式）——`@main`、SwiftUI UI、設計系統，以及面向 Sparkle、KeyboardShortcuts 和 PermissionFlow 的輕量整合介面層。

## License

Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
