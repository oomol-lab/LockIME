<div align="center">

<img src="../images/appicon.png" alt="LockIME" width="128">

# LockIME

[English](../../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · **日本語** · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md)

[![最新リリース](https://img.shields.io/github/v/release/oomol-lab/LockIME?sort=semver&color=3A5BD9)](https://github.com/oomol-lab/LockIME/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/LockIME/ci.yml?branch=main&label=CI)](https://github.com/oomol-lab/LockIME/actions/workflows/ci.yml)
[![ライセンス: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-3A5BD9)](../../LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)

</div>

**キーボードの入力ソースをロックする** macOS メニューバーアプリ。あなた（または他のアプリ）が入力メソッドを切り替えるたびに、LockIME はロック中の入力ソースへ即座に切り戻します——グローバルに、最前面のアプリごとに、あるいは（オプションの拡張モードでは）ブラウザの URL ごとに。

> macOS 14+ · Apple silicon と Intel に対応——2 つの独立したアプリです。
> お使いの Mac に合った `-arm64` または `-x86_64` ファイルをダウンロード
> してください · SwiftUI 製、macOS 26 (Tahoe) では Liquid Glass を採用。

## Screenshots

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-general-en-dark.png">
    <img alt="一般設定" src="../images/settings-general-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-app-rules-en-dark.png">
    <img alt="アプリごとのルール" src="../images/settings-app-rules-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-url-rules-en-dark.png">
    <img alt="URL ごとのルール" src="../images/settings-url-rules-en-light.png" width="32%">
  </picture>
</p>

## Install

[Homebrew](https://brew.sh) でインストールできます（cask がお使いの Mac のアーキテクチャに合ったビルドを自動的に選択します）：

```sh
brew install --cask oomol-lab/tap/lockime
```

または、[最新リリース](https://github.com/oomol-lab/LockIME/releases/latest)からお使いの Mac に合った `.dmg`（Apple silicon は `-arm64`、Intel は `-x86_64`）をダウンロードしてください。いずれの方法でも、アプリは Sparkle により自動的に最新の状態に保たれます。

## Features

- **即時再ロック**——あなた（または他のアプリ）が入力ソースを切り替えた瞬間に、ロック中のものへ切り戻します。グローバルにも、アプリごとにも。
- **ロックまたは切り替え**——アプリごと・URL ごとのルールは、入力ソースを*ロック*（ずれるたびに切り戻す）することも、アプリやページをアクティブにしたときに一度だけ*切り替え*て、その後は自由に変更できるようにすることもできます。
- **メニューバーからの操作**——メニューバーから有効化/無効化、ロック中の入力ソースの切り替え、現在の入力ソースの確認、作動回数の追跡。
- **キーボードショートカット**——設定可能なグローバルショートカットでロックのオン/オフやロック中の入力ソースの切り替え（前 / 次）ができ、さらに最前面のアプリのルールを切り替えたり解除したりするアプリごとのショートカットも利用できます。
- **ログイン時に起動**——ログイン時に自動的に起動（デフォルトはオフ）。
- **ライト & ダークモード**——ライト/ダーク外観に適応する、統一されたシステムネイティブなデザイン言語と、専用のアプリアイコン。[docs/DESIGN.md](../DESIGN.md) を参照。
- **ライブ言語切り替え**——9 言語を再起動なしで即座に切り替え：English、简体中文、繁體中文、日本語、Français、Deutsch、Español、Português、Русский。
- **24 時間の作動ログ**——何が、なぜ、どれだけの時間切り替えられたかを確認できます。
- **設定のバックアップ**——アプリごと・URL ごとのルールを `.lockime` ファイルに書き出し、また読み込めます。読み込み前にはプレビュー画面で、追加・競合・削除を確認してから適用します。
- **自動アップデート**——Sparkle による stable / beta の 2 チャンネルと、カスタムアップデートウィンドウ。
- **小さなダウンロード**——アプリ全体が 3 MB 未満の `.dmg` に収まります。
- **コアのロックにシステム権限は不要**——オプションの Accessibility 権限付き拡張モードで、より細かい URL ごと / フォーカス中フィールドごとのルールが使えます。

## Design

LockIME は単一のデザインシステム（`Sources/LockIME/UI/DesignSystem.swift`）に従います：セマンティックカラー、システムマテリアル、SF Symbols がライト/ダーク適応を担い、Liquid Glass はフローティング/ナビゲーション層だけに使用します。ブランドのアクセントカラー "Lock Indigo" は `AccentColor` アセットとして同梱されています。完全な仕様は [docs/DESIGN.md](../DESIGN.md) を参照してください。

アプリアイコンはプログラムで生成されます（デザインツール不使用）——次のコマンドで再生成できます：

```sh
./scripts/make-appicon.sh   # renders the master via SwiftUI and rebuilds the appiconset
```

## Development

Xcode 26+（アプリ自体のターゲットは macOS 14+）と、[XcodeGen](https://github.com/yonaskolb/XcodeGen) + [xcbeautify](https://github.com/cpisciotta/xcbeautify)（`brew install xcodegen xcbeautify`）が必要です。

```sh
make gen     # generate LockIME.xcodeproj from project.yml
make build   # build (Debug)
make run     # build & launch
make test    # run unit tests
make archive # Release archive (Developer ID)
```

Xcode プロジェクトは `project.yml` から生成され、リポジトリには含まれません。

ハードウェアに触れる統合テスト（実際の TIS 切り替え）は `make test` から除外されています。`make test-hw` で実行してください（入力ソースが一時的に変わります）。

## Releasing

dispatch 駆動の、公証済み Developer ID リリース。Sparkle による **stable** と **beta** の 2 チャンネルで自動アップデートします：Release ワークフロー（Actions → Release）を実行すると、git タグからバージョンを計算してビルドし、タグと GitHub Release を自動的に作成します——タグを手動でプッシュしないでください。beta チャンネルはナイトリービルドです。各リリースは Apple silicon と Intel の独立したアプリをそれぞれ提供し、各々が独自のアップデートフィードを持ちます（universal バイナリなし、アーキテクチャをまたぐアップデートなし）。[docs/RELEASING.md](../RELEASING.md) を参照してください。

## Architecture

- **LockIMEKit**（静的ライブラリ）——システムフレームワークのみを使う、純粋で完全に単体テストされたロジック：ロックエンジン、アプリモニター、ルール、拡張（Accessibility）オブザーバー、ログモデル、ローカリゼーション。
- **LockIME**（アプリ）——`@main`、SwiftUI の UI、デザインシステム、そして Sparkle・KeyboardShortcuts・PermissionFlow 向けの薄い統合シム。

## License

Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
