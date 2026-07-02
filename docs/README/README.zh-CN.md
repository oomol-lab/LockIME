<div align="center">

<img src="../images/appicon.png" alt="LockIME" width="128">

# LockIME

[English](../../README.md) · **简体中文** · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md)

[![最新版本](https://img.shields.io/github/v/release/oomol-lab/LockIME?sort=semver&color=3A5BD9)](https://github.com/oomol-lab/LockIME/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/LockIME/ci.yml?branch=main&label=CI)](https://github.com/oomol-lab/LockIME/actions/workflows/ci.yml)
[![许可证: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-3A5BD9)](../../LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)

</div>

一款 macOS 菜单栏应用，用于**锁定你的键盘输入源**。每当你（或其他应用）切换输入法时，LockIME 会立即切回被锁定的那个——可以是全局的、按前台应用区分的，或者（在可选的增强模式下）按浏览器 URL 区分的。

> macOS 14+ · 支持 Apple silicon 与 Intel——两个独立的应用，请下载与你的 Mac
> 匹配的 `-arm64` 或 `-x86_64` 文件 · 基于 SwiftUI 构建，macOS 26 (Tahoe) 上
> 呈现 Liquid Glass。

## Screenshots

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-general-zh-CN-dark.png">
    <img alt="常规设置" src="../images/settings-general-zh-CN-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-app-rules-zh-CN-dark.png">
    <img alt="按应用规则" src="../images/settings-app-rules-zh-CN-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-url-rules-zh-CN-dark.png">
    <img alt="按 URL 规则" src="../images/settings-url-rules-zh-CN-light.png" width="32%">
  </picture>
</p>

## Install

使用 [Homebrew](https://brew.sh) 安装（cask 会自动选择与你的 Mac
架构匹配的构建）：

```sh
brew install --cask oomol-lab/tap/lockime
```

或者从[最新发布版](https://github.com/oomol-lab/LockIME/releases/latest)下载与你的
Mac 匹配的 `.dmg`（Apple silicon 选 `-arm64`，Intel 选 `-x86_64`）。
无论哪种方式，应用都会通过 Sparkle 自动保持最新。

## Features

- **即时重新锁定**——每当你（或其他应用）切换输入源时，立即切回被锁定的那个，可全局或按应用生效。
- **锁定或切换**——按应用和按 URL 的规则既可以*锁定*某个输入源（一旦偏离就重新切回），也可以在你切到该应用或页面时只*切换*一次，之后任你自由更改。
- **全局锁定，或仅切换**——把全局默认设为某个输入源，就能在所有地方固定它；或把它设为**无**，将 LockIME 当作纯粹的按应用 / 按站点切换器来用——它会在你进入时为你切换，随后便放手让你自由，不固定任何东西。
- **灵活的 URL 匹配**——按 URL 规则（增强模式）可以按某个域名及其子域名、某个精确域名、某个域名关键词，或针对完整 URL 的正则表达式来匹配，并按你拖动排列出的优先级顺序生效——第一个命中者胜出。
- **菜单栏控制**——在菜单栏激活/停用、切换被锁定的输入源、查看当前输入源、追踪激活次数。
- **键盘快捷键**——可配置的全局快捷键用于开关 LockIME、切换被锁定的输入源（上一个 / 下一个），以及针对当前最前台应用的快捷键，用于切换或移除该应用的规则。
- **登录时启动**——登录后自动启动（默认关闭）。
- **浅色 / 深色模式**——统一的、系统原生的设计语言，自动适配浅色与深色外观，并配有定制应用图标。参见 [docs/DESIGN.md](../DESIGN.md)。
- **实时语言切换**——在 9 种语言间即时切换，无需重启：English、简体中文、繁體中文、日本語、Français、Deutsch、Español、Português、Русский。
- **24 小时激活日志**——回顾切换了什么、为什么、持续了多久。
- **配置备份**——把按应用和按 URL 的规则导出为 `.lockime` 文件，再导入回来；导入前会有一个预览步骤，先列出新增、冲突与移除项，确认后再应用。
- **通过 Sparkle 自动更新**——stable 与 beta 两个通道，配有自定义更新窗口。
- **超小体积**——整个应用打包成不到 3 MB 的 `.dmg`。
- **核心锁定无需系统权限**——可选的、受 Accessibility 把关的增强模式可解锁更细粒度的按 URL / 聚焦字段规则。
- **自动化**——通过 `lockime://` URL scheme，其他应用、脚本和 Shortcuts 都能驱动 LockIME（详见下文）。

## Comparison

LockIME 最被广泛使用的两个替代品是
**[Input Source Pro](https://github.com/runjuu/InputSourcePro)** 和
**[KeyboardHolder](https://github.com/leaves615/KeyboardHolder)**，此外还有一长串规模更小的开源和
CLI 工具。它们都会在你于应用或站点之间移动时*切换*输入源；而 LockIME
围绕持续**锁定**构建——一旦输入源偏离就立即重新应用，同时任何规则仍可回退为一次性*切换*。

| | LockIME | Input Source Pro | KeyboardHolder |
|---|---|---|---|
| 价格 | 免费 | 免费 | 免费（捐赠） |
| 开源 | GPL-3.0 | GPL-3.0 | ✗（闭源） |
| 最低 macOS | 14 | 11 | 10.15 |
| 下载体积 | < 3 MB | ≈ 7.6 MB | ≈ 4.5 MB |
| 按应用规则 | ✓ | ✓ | ✓ |
| 按网站 / URL 规则 | ✓ | ✓ | ✓ |
| URL 匹配类型 | 子域名 · 精确 · 关键词 · 正则 | 子域名 · 精确 · 正则 | 域名（通配符） |
| 地址栏（URL 字段）规则 | ✓（锁定/切换/优先级） | ✓（默认输入源） | — |
| 持续重新锁定 | ✓ | ✗ | ✗ |
| 每条规则可锁定*或*一次性切换 | ✓ | ✗ | ✗ |
| 全局键盘快捷键 | ✓ | ✓ | ✗ |
| 菜单栏控制 | ✓ | ✓ | ✓ |
| 屏幕输入提示 | ✗ | ✓ | ✓（可选） |
| 24 小时激活日志 | ✓ | ✗ | ✗ |
| 配置备份 / 导入 | ✓（`.lockime`，带审阅） | ✓（导出/导入 + CLI） | — |
| URL scheme 自动化 | ✓（`lockime://`，x-callback-url） | 部分（`inputsourcepro://` 导入） | ✗ |
| 界面语言 | 9（实时切换） | 6 | zh · en · ja |
| 系统权限 | 核心无需 · 按 URL 需 Accessibility | 核心无需 · 按 URL 需 Accessibility | Accessibility¹ |
| 自动更新 | Sparkle（stable + beta） | ✓ | ✓ |
| 持续维护中（2026） | ✓ | ✓ | ✓ |

¹ KeyboardHolder 没有说明其权限要求；其按网站规则要读取浏览器地址栏，实际上需要
Accessibility 访问权限。“—” 表示未记录的能力，而非确认缺失。

**如何选择：** Input Source Pro 拥有最大的社区和最丰富的屏幕输入提示；KeyboardHolder
则是一个精致、零配置的按应用记忆。当你想把一个输入源*钉住*——按应用、按 URL
或在地址栏，每当有东西改动它就立即重新应用——而不仅仅是在你到达时才切换它，就该用 LockIME。

**其他工具：** [SwitchKey](https://github.com/itsuhane/SwitchKey)（仅按应用，已不再维护）、
[Kawa](https://github.com/hatashiro/kawa)（手动、快捷键驱动）、InputSwitcher（免费增值，仅按应用），以及
[macism](https://github.com/laishulu/macism)（一个命令行构建块，而非图形界面切换器）。

> 对比基于 Input Source Pro 2.11.0 与 KeyboardHolder 1.14.10，采集于 2026 年中——细节会变化，欢迎指正。

## Automation

LockIME 提供了 `lockime://` URL scheme，让其他应用、脚本、Shortcuts 和启动器都能驱动它——开启或关闭它、重新指定输入源、管理规则，并通过 [x-callback-url](https://x-callback-url.com) 回调读回状态。它默认关闭——请在**设置 ▸ 通用 ▸ 自动化**中开启它。

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
```

完整参考：**[URL Scheme API](../URL-Scheme-API/README.zh-CN.md)**。

## Design

LockIME 遵循单一的设计系统（`Sources/LockIME/UI/DesignSystem.swift`）：语义化颜色、系统材质和 SF Symbols 驱动浅色/深色适配；Liquid Glass 仅保留给浮层/导航层使用。品牌强调色 "Lock Indigo" 以 `AccentColor` 资源的形式提供。完整规范见 [docs/DESIGN.md](../DESIGN.md)。

应用图标以编程方式生成（不使用任何设计工具）——用以下命令重新生成：

```sh
./scripts/make-appicon.sh   # renders the master via SwiftUI and rebuilds the appiconset
```

## Development

需要 Xcode 26+（应用本身以 macOS 14+ 为目标），以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen) + [xcbeautify](https://github.com/cpisciotta/xcbeautify)（`brew install xcodegen xcbeautify`）。

```sh
make gen     # generate LockIME.xcodeproj from project.yml
make build   # build (Debug)
make run     # build & launch
make test    # run unit tests
make archive # Release archive (Developer ID)
```

Xcode 项目由 `project.yml` 生成，不纳入版本控制。

涉及硬件的集成测试（真实的 TIS 切换）已从 `make test` 中排除；用 `make test-hw` 运行它们（会短暂改变输入源）。

## Releasing

由 dispatch 驱动、经过公证的 Developer ID 发布，通过 Sparkle 在 **stable** 和 **beta** 两个通道自动更新：运行 Release 工作流（Actions → Release），它会从 git 标签计算版本号、构建，并自动创建标签和 GitHub Release——切勿手动推送标签。beta 通道即每夜构建。每个版本都分别提供 Apple silicon 与 Intel 两个独立应用，各自走自己的更新 feed（不提供 universal 二进制，也不支持跨架构更新）。参见 [docs/RELEASING.md](../RELEASING.md)。

## Architecture

- **LockIMEKit**（静态库）——纯粹的、经过完整单元测试的逻辑，仅使用系统框架：锁定引擎、应用监视器、规则、增强（Accessibility）观察器、日志模型、本地化。
- **LockIME**（应用）——`@main`、SwiftUI UI、设计系统，以及面向 Sparkle、KeyboardShortcuts 和 PermissionFlow 的轻量集成适配层。

## License

Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
