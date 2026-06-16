<div align="center">

<img src="docs/images/appicon.png" alt="LockIME" width="128">

# LockIME

**English** · [简体中文](docs/README/README.zh-CN.md) · [繁體中文](docs/README/README.zh-TW.md) · [日本語](docs/README/README.ja.md) · [Français](docs/README/README.fr.md) · [Deutsch](docs/README/README.de.md) · [Español](docs/README/README.es.md) · [Português](docs/README/README.pt.md) · [Русский](docs/README/README.ru.md)

[![Latest release](https://img.shields.io/github/v/release/oomol-lab/LockIME?sort=semver&color=3A5BD9)](https://github.com/oomol-lab/LockIME/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/LockIME/ci.yml?branch=main&label=CI)](https://github.com/oomol-lab/LockIME/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-3A5BD9)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)

</div>

A macOS menu-bar app that **locks your keyboard input source**. Whenever you (or
another app) switch input methods, LockIME immediately switches back to the locked
one — globally, or per-frontmost-app, or (with the optional enhanced mode) per
browser URL.

> macOS 14+ · Apple silicon & Intel — separate apps, download the `-arm64` or
> `-x86_64` file matching your Mac · built with SwiftUI, Liquid Glass on
> macOS 26 (Tahoe).

## Screenshots

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-general-en-dark.png">
    <img alt="General settings" src="docs/images/settings-general-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-app-rules-en-dark.png">
    <img alt="Per-app rules" src="docs/images/settings-app-rules-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-url-rules-en-dark.png">
    <img alt="Per-URL rules" src="docs/images/settings-url-rules-en-light.png" width="32%">
  </picture>
</p>

## Install

Install with [Homebrew](https://brew.sh) (the cask picks the build matching
your Mac's architecture):

```sh
brew install --cask oomol-lab/tap/lockime
```

Or download the `.dmg` matching your Mac (`-arm64` for Apple silicon,
`-x86_64` for Intel) from the
[latest release](https://github.com/oomol-lab/LockIME/releases/latest).
Either way, the app keeps itself up to date via Sparkle.

## Features

- **Instant re-lock** — switches the active input source back the moment you (or
  another app) change it, globally or per-app.
- **Lock or switch** — per-app and per-URL rules can *lock* an input source
  (re-applied whenever it drifts) or just *switch* to it once when you focus the
  app or page, then step out of the way and let you change it freely.
- **Flexible URL matching** — per-URL rules (enhanced mode) match by a domain and
  its subdomains, an exact domain, a domain keyword, or a regular expression over
  the full URL, and apply in a priority order you drag to arrange — first match
  wins.
- **Menu-bar control** — activate/deactivate, switch the locked input source,
  view the current source, and track the activation count from the menu bar.
- **Keyboard shortcuts** — configurable global shortcuts to toggle locking and
  cycle the locked input source, plus per-app shortcuts to cycle or unbind the
  rule for whichever app is frontmost.
- **Launch at login** — starts automatically when you log in (off by default).
- **Light & dark mode** — a unified, system-native design language that adapts to
  light and dark appearance, plus a bespoke app icon. See
  [docs/DESIGN.md](docs/DESIGN.md).
- **Live language switching** — switch between 9 languages instantly, no
  restart: English, 简体中文, 繁體中文, 日本語, Français, Deutsch, Español,
  Português, Русский.
- **24-hour activation log** — review what was switched, why, and for how long.
- **Config backup** — export your per-app and per-URL rules to a `.lockime`
  file and import them back, with a review step that previews additions,
  conflicts, and removals before anything is applied.
- **Auto-update** — stable and beta channels via Sparkle, with a custom update
  window.
- **Tiny download** — the whole app ships in a `.dmg` under 3 MB.
- **No system permissions for core locking** — an optional Accessibility-gated
  enhanced mode unlocks finer-grained per-URL and focused-field rules.
- **Automation** — a `lockime://` URL scheme lets other apps, scripts, and
  Shortcuts drive LockIME (see below).

## Automation

LockIME exposes a `lockime://` URL scheme so other apps, scripts, Shortcuts, and
launchers can drive it — toggle locking, retarget the input source, manage
rules, and read state back with [x-callback-url](https://x-callback-url.com)
callbacks. It is off by default — turn it on in **Settings ▸ General ▸
Automation**.

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
```

Full reference: **[URL Scheme API](docs/URL-Scheme-API/README.md)**.

## Design

LockIME follows a single design system (`Sources/LockIME/UI/DesignSystem.swift`):
semantic colors, system materials, and SF Symbols drive light/dark adaptation;
Liquid Glass is reserved for the floating/navigation layer only. The brand
"Lock Indigo" accent ships as an `AccentColor` asset. The full spec lives in
[docs/DESIGN.md](docs/DESIGN.md).

The app icon is generated programmatically (no design tool) — regenerate it with:

```sh
./scripts/make-appicon.sh   # renders the master via SwiftUI and rebuilds the appiconset
```

## Development

Requires Xcode 26+ (the app itself targets macOS 14+), and
[XcodeGen](https://github.com/yonaskolb/XcodeGen)
+ [xcbeautify](https://github.com/cpisciotta/xcbeautify) (`brew install xcodegen xcbeautify`).

```sh
make gen     # generate LockIME.xcodeproj from project.yml
make build   # build (Debug)
make run     # build & launch
make test    # run unit tests
make archive # Release archive (Developer ID)
```

The Xcode project is generated from `project.yml` and is not checked in.

Hardware-touching integration tests (real TIS switching) are excluded from
`make test`; run them with `make test-hw` (briefly changes the input source).

## Releasing

Dispatch-driven, notarized Developer ID releases with Sparkle auto-update over
**stable** and **beta** channels: run the Release workflow (Actions → Release)
and it computes the version from git tags, builds, and creates the tag and
GitHub Release automatically — never push a tag by hand. The beta channel is
the nightly build. Every release ships separate Apple-silicon and Intel apps,
each on its own update feed (no universal binary, no cross-arch updates). See
[docs/RELEASING.md](docs/RELEASING.md).

## Architecture

- **LockIMEKit** (static library) — pure, fully unit-tested logic using only system
  frameworks: lock engine, app monitor, rules, enhanced (Accessibility) observer,
  logging model, localization.
- **LockIME** (app) — `@main`, SwiftUI UI, the design system, and the thin
  integration shims for Sparkle, KeyboardShortcuts, and PermissionFlow.

## License

Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
