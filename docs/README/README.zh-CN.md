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
- **菜单栏控制**——在菜单栏激活/停用、切换被锁定的输入源、查看当前输入源、追踪激活次数。
- **键盘快捷键**——可配置的全局快捷键用于开关锁定、切换被锁定的输入源（上一个 / 下一个），以及针对当前最前台应用的快捷键，用于切换或移除该应用的规则。
- **登录时启动**——登录后自动启动（默认关闭）。
- **浅色 / 深色模式**——统一的、系统原生的设计语言，自动适配浅色与深色外观，并配有定制应用图标。参见 [docs/DESIGN.md](../DESIGN.md)。
- **实时语言切换**——在 9 种语言间即时切换，无需重启：English、简体中文、繁體中文、日本語、Français、Deutsch、Español、Português、Русский。
- **24 小时激活日志**——回顾切换了什么、为什么、持续了多久。
- **通过 Sparkle 自动更新**——stable 与 beta 两个通道，配有自定义更新窗口。
- **核心锁定无需系统权限**——可选的、受 Accessibility 把关的增强模式可解锁更细粒度的按 URL / 聚焦字段规则。

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
- **LockIME**（应用）——`@main`、SwiftUI UI、设计系统，以及面向 Sparkle、KeyboardShortcuts、PermissionFlow 和 MarkdownUI 的轻量集成适配层。

## License

Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
