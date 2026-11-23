<div align="center">

<img src="../images/appicon.png" alt="LockIME" width="128">

# LockIME

[English](../../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Français](README.fr.md) · **Deutsch** · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md)

[![Neueste Version](https://img.shields.io/github/v/release/oomol-lab/LockIME?sort=semver&color=3A5BD9)](https://github.com/oomol-lab/LockIME/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/LockIME/ci.yml?branch=main&label=CI)](https://github.com/oomol-lab/LockIME/actions/workflows/ci.yml)
[![Lizenz: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-3A5BD9)](../../LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Greptile: The War on Bugs](https://www.greptile.com/badge.svg)](https://www.greptile.com/?utm_source=oss_badge&utm_medium=readme&utm_campaign=greptile_for_open_source)

</div>

LockIME ist eine macOS-Menüleisten-App, die deine Tastatur-Eingabequelle sperrt. Wenn du oder eine andere App die Eingabemethode wechselt, schaltet sie sofort zurück: global, pro App oder pro Browser-URL.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-general-en-dark.png">
    <img alt="Allgemeine Einstellungen" src="../images/settings-general-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-app-rules-en-dark.png">
    <img alt="Regeln pro App" src="../images/settings-app-rules-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-url-rules-en-dark.png">
    <img alt="Regeln pro URL" src="../images/settings-url-rules-en-light.png" width="32%">
  </picture>
</p>

## Install

```sh
brew install --cask oomol-lab/tap/lockime
```

Oder lade die `.dmg` aus dem [neuesten Release](https://github.com/oomol-lab/LockIME/releases/latest): `-arm64` für Apple silicon, `-x86_64` für Intel. Erfordert macOS 14 oder neuer. LockIME aktualisiert sich über Sparkle, auf einem Stable- oder Beta-Kanal.

## Features

- **Sperren oder wechseln.** Eine Regel für eine App oder URL sperrt eine Eingabequelle und schaltet bei jeder Änderung zurück, oder sie wechselt einmalig dorthin, sobald du die App oder Seite aktivierst, und lässt dir danach freie Wahl.
- **Globaler Standard.** Sperre eine Eingabequelle überall, wechsle einmalig zu ihr in jeder App, die auf den Standard zurückgreift, oder stelle *Keine* ein und überlasse alles deinen Regeln.
- **URL- und Adressleisten-Regeln.** Das Kern-Sperren braucht keine Systemberechtigungen. Ein optionaler erweiterter Modus verlangt die Accessibility-Berechtigung und ergänzt Regeln pro URL und für die Adressleiste des Browsers. URL-Regeln gleichen eine Domain und ihre Subdomains, eine exakte Domain, ein Schlüsselwort oder einen regulären Ausdruck über die vollständige URL ab; ziehe sie, um die Priorität festzulegen, der erste Treffer gewinnt.
- **Programme ohne Bundle.** Programme ohne `.app`-Bundle, etwa Minecrafts `java`, erscheinen in der App-Auswahl als `process:java`, solange sie laufen.
- **Konfliktbehandlung.** Wenn ein anderes Programm immer wieder seine eigene Eingabequelle durchsetzt, tritt LockIME zurück, statt dagegen anzukämpfen, und vermerkt den Konflikt im Protokoll. Gib dieser App eine *Ignorieren*- oder *Wechseln zu*-Regel für eine dauerhafte Lösung.
- **Menüleiste und Kurzbefehle.** Schalte LockIME ein oder aus und ändere die gesperrte Eingabequelle über die Menüleiste oder mit globalen Kurzbefehlen. Kurzbefehle können auch die Regel der vordersten App durchschalten oder entfernen.
- **Aktivitätsprotokoll.** Die letzten 24 Stunden: was gewechselt wurde, warum und wie lange.
- **Backup.** Exportiere Regeln in eine `.lockime`-Datei. Beim Import siehst du Ergänzungen, Konflikte und Entfernungen in einer Vorschau, bevor etwas angewendet wird.
- **Außerdem:** Start bei der Anmeldung, 9 Oberflächensprachen, die sich ohne Neustart wechseln lassen, und ein Download unter 3 MB.

## Comparison

[Input Source Pro](https://github.com/runjuu/InputSourcePro) und [KeyboardHolder](https://github.com/leaves615/KeyboardHolder) wechseln die Eingabequelle, während du dich zwischen Apps oder Seiten bewegst. LockIME hält sie zusätzlich fest: Eine gesperrte Eingabequelle wird bei jeder Änderung erneut angewendet.

| | LockIME | Input Source Pro | KeyboardHolder |
|---|---|---|---|
| Open Source | GPL-3.0 | GPL-3.0 | ✗ |
| Mindest-macOS | 14 | 11 | 10.15 |
| Download-Größe | < 3 MB | ≈ 7.6 MB | ≈ 4.5 MB |
| Kontinuierliches Wieder-Sperren | ✓ | ✗ | ✗ |
| Sperren oder einmaliger Wechsel, pro Regel | ✓ | ✗ | ✗ |
| URL-Abgleichstypen | Subdomain, exakt, Schlüsselwort, Regex | Subdomain, exakt, Regex | Domain (Platzhalter) |
| Adressleisten-Regel | ✓ (Sperren/Wechseln/Priorität) | ✓ (Standardquelle) | — |
| Globale Tastatur-Kurzbefehle | ✓ | ✓ | ✗ |
| Eingabe-Hinweise auf dem Bildschirm | ✗ | ✓ | ✓ (optional) |
| 24-Stunden-Aktivitätsprotokoll | ✓ | ✗ | ✗ |
| Konfigurations-Backup / -Import | ✓ (`.lockime`, mit Vorschau) | ✓ (Export/Import + CLI) | — |
| URL-Schema-Automatisierung | ✓ (`lockime://`, x-callback-url) | teilweise (`inputsourcepro://`-Import) | ✗ |
| UI-Sprachen | 9 | 6 | 3 |

> Verglichen mit Input Source Pro 2.11.0 und KeyboardHolder 1.14.10, Mitte 2026. „—“ bedeutet nicht dokumentiert, nicht nachweislich fehlend. Korrekturen willkommen.

## Automation

Über ein `lockime://`-URL-Schema können Skripte, Kurzbefehle und andere Apps LockIME ein- oder ausschalten, die gesperrte Eingabequelle ändern, Regeln verwalten und den Zustand per [x-callback-url](https://x-callback-url.com) auslesen. Es ist standardmäßig aus; schalte es unter **Einstellungen ▸ Allgemein ▸ Automatisierung** ein.

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
```

Vollständige Referenz: [URL Scheme API](../URL-Scheme-API/README.de.md).

## Development

Erfordert Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) und [xcbeautify](https://github.com/cpisciotta/xcbeautify) (`brew install xcodegen xcbeautify`). Das Xcode-Projekt wird aus `project.yml` generiert und ist nicht eingecheckt.

```sh
make gen      # generate LockIME.xcodeproj from project.yml
make build    # build (Debug)
make run      # build & launch
make test     # run unit tests
make test-hw  # integration tests; briefly changes the input source
```

Die Logik liegt in `LockIMEKit`, einer unit-getesteten statischen Bibliothek, die nur Systemframeworks nutzt. Das App-Target `LockIME` enthält die SwiftUI-Oberfläche und die Integrationen für Sparkle, KeyboardShortcuts und PermissionFlow. Das App-Icon wird von `./scripts/make-appicon.sh` erzeugt.

Siehe [docs/DESIGN.md](../DESIGN.md) für das Designsystem und [docs/RELEASING.md](../RELEASING.md) für den Release-Prozess.

## License

[GPL-3.0](../../LICENSE). Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
