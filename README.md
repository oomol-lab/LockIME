<div align="center">

<img src="docs/images/appicon.png" alt="LockIME" width="128">

# LockIME

**English** · [简体中文](docs/README/README.zh-CN.md) · [繁體中文](docs/README/README.zh-TW.md) · [日本語](docs/README/README.ja.md) · [Français](docs/README/README.fr.md) · [Deutsch](docs/README/README.de.md) · [Español](docs/README/README.es.md) · [Português](docs/README/README.pt.md) · [Русский](docs/README/README.ru.md)

[![Latest release](https://img.shields.io/github/v/release/oomol-lab/LockIME?sort=semver&color=3A5BD9)](https://github.com/oomol-lab/LockIME/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/LockIME/ci.yml?branch=main&label=CI)](https://github.com/oomol-lab/LockIME/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-3A5BD9)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Greptile: The War on Bugs](https://www.greptile.com/badge.svg)](https://www.greptile.com/?utm_source=oss_badge&utm_medium=readme&utm_campaign=greptile_for_open_source)

</div>

LockIME is a macOS menu-bar app that locks your keyboard input source. When you
or another app switches input methods, it switches straight back: globally, per
app, or per browser URL.

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

```sh
brew install --cask oomol-lab/tap/lockime
```

Or download the `.dmg` from the
[latest release](https://github.com/oomol-lab/LockIME/releases/latest): `-arm64`
for Apple silicon, `-x86_64` for Intel. Requires macOS 14 or later. LockIME
updates itself through Sparkle, on a stable or beta channel.

## Features

- **Lock or switch.** A rule for an app or URL either locks an input source,
  switching back whenever it changes, or switches to it once when you focus the
  app or page and then leaves you free.
- **Global default.** Lock one input source everywhere, switch to it once in
  every app that falls back to the default, or set it to *None* and let your
  rules do all the work.
- **URL and address-bar rules.** Core locking needs no system permissions. An
  optional enhanced mode asks for Accessibility and adds rules per URL and for
  the browser address bar. URL rules match a domain and its subdomains, an
  exact domain, a keyword, or a regular expression over the full URL; drag them
  to set priority, and the first match wins.
- **Bare executables.** Programs without an `.app` bundle, such as Minecraft's
  `java`, appear in the app picker as `process:java` while they run.
- **Conflict handling.** When another program keeps forcing its own input
  source, LockIME stands down instead of fighting it and records the conflict
  in the log. Give that app an *Ignore* or *Switch to* rule for a lasting fix.
- **Menu bar and shortcuts.** Toggle LockIME and change the locked input source
  from the menu bar or with global shortcuts. Shortcuts can also cycle or
  unbind the rule for the frontmost app.
- **Activation log.** The last 24 hours of what was switched, why, and for how
  long.
- **Backup.** Export rules to a `.lockime` file. Importing previews additions,
  conflicts, and removals before anything is applied.
- **Also:** launch at login, 9 interface languages switchable without a
  restart, and a download under 3 MB.

## Comparison

[Input Source Pro](https://github.com/runjuu/InputSourcePro) and
[KeyboardHolder](https://github.com/leaves615/KeyboardHolder) switch the input
source as you move between apps or sites. LockIME also keeps it there: a locked
input source is re-applied whenever it changes.

| | LockIME | Input Source Pro | KeyboardHolder |
|---|---|---|---|
| Open source | GPL-3.0 | GPL-3.0 | ✗ |
| Minimum macOS | 14 | 11 | 10.15 |
| Download size | < 3 MB | ≈ 7.6 MB | ≈ 4.5 MB |
| Continuous re-lock | ✓ | ✗ | ✗ |
| Lock or one-time switch, per rule | ✓ | ✗ | ✗ |
| URL match types | subdomain, exact, keyword, regex | subdomain, exact, regex | domain (wildcard) |
| Address-bar rule | ✓ (lock/switch/priority) | ✓ (default source) | — |
| Global keyboard shortcuts | ✓ | ✓ | ✗ |
| On-screen input hints | ✗ | ✓ | ✓ (optional) |
| 24-hour activation log | ✓ | ✗ | ✗ |
| Config backup / import | ✓ (`.lockime`, with review) | ✓ (export/import + CLI) | — |
| URL-scheme automation | ✓ (`lockime://`, x-callback-url) | partial (`inputsourcepro://` import) | ✗ |
| UI languages | 9 | 6 | 3 |

> Compared against Input Source Pro 2.11.0 and KeyboardHolder 1.14.10 in
> mid-2026. "—" means undocumented, not confirmed absent. Corrections welcome.

## Automation

A `lockime://` URL scheme lets scripts, Shortcuts, and other apps toggle
LockIME, change the locked input source, manage rules, and read state back
through [x-callback-url](https://x-callback-url.com). It is off by default;
turn it on in **Settings ▸ General ▸ Automation**.

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
```

Full reference: [URL Scheme API](docs/URL-Scheme-API/README.md).

## Development

Requires Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and
[xcbeautify](https://github.com/cpisciotta/xcbeautify)
(`brew install xcodegen xcbeautify`). The Xcode project is generated from
`project.yml` and is not checked in.

```sh
make gen      # generate LockIME.xcodeproj from project.yml
make build    # build (Debug)
make run      # build & launch
make test     # run unit tests
make test-hw  # integration tests; briefly changes the input source
```

The logic lives in `LockIMEKit`, a unit-tested static library that uses only
system frameworks. The `LockIME` app target holds the SwiftUI UI and the
Sparkle, KeyboardShortcuts, and PermissionFlow integrations. The app icon is
generated by `./scripts/make-appicon.sh`.

See [docs/DESIGN.md](docs/DESIGN.md) for the design system and
[docs/RELEASING.md](docs/RELEASING.md) for the release process.

## License

[GPL-3.0](LICENSE). Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
