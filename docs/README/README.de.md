<div align="center">

<img src="../images/appicon.png" alt="LockIME" width="128">

# LockIME

[English](../../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Français](README.fr.md) · **Deutsch** · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md)

[![Neueste Version](https://img.shields.io/github/v/release/oomol-lab/LockIME?sort=semver&color=3A5BD9)](https://github.com/oomol-lab/LockIME/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/LockIME/ci.yml?branch=main&label=CI)](https://github.com/oomol-lab/LockIME/actions/workflows/ci.yml)
[![Lizenz: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-3A5BD9)](../../LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)

</div>

Eine macOS-Menüleisten-App, die **deine Tastatur-Eingabequelle sperrt**. Wann immer du (oder eine andere App) die Eingabemethode wechselst, schaltet LockIME sofort auf die gesperrte zurück — global, pro Vordergrund-App oder (mit dem optionalen erweiterten Modus) pro Browser-URL.

> macOS 14+ · Apple silicon & Intel — separate Apps, lade die zu deinem Mac
> passende `-arm64`- oder `-x86_64`-Datei herunter · gebaut mit SwiftUI,
> Liquid Glass unter macOS 26 (Tahoe).

## Screenshots

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

Installiere mit [Homebrew](https://brew.sh) (der Cask wählt den zur Architektur deines Macs passenden Build):

```sh
brew install --cask oomol-lab/tap/lockime
```

Oder lade die zu deinem Mac passende `.dmg`-Datei (`-arm64` für Apple silicon, `-x86_64` für Intel) aus dem [neuesten Release](https://github.com/oomol-lab/LockIME/releases/latest) herunter. So oder so hält sich die App via Sparkle automatisch aktuell.

## Features

- **Sofortiges Wieder-Sperren** — schaltet die aktive Eingabequelle in dem Moment zurück, in dem du (oder eine andere App) sie wechselst, global oder pro App.
- **Sperren oder wechseln** — Regeln pro App und pro URL können eine Eingabequelle *sperren* (bei jeder Abweichung erneut angewendet) oder einmalig dorthin *wechseln*, sobald du die App oder Seite aktivierst, und dich danach frei wählen lassen.
- **Steuerung über die Menüleiste** — aktivieren/deaktivieren, die gesperrte Eingabequelle wechseln, die aktuelle Eingabequelle einsehen und die Auslösungen direkt in der Menüleiste verfolgen.
- **Tastatur-Kurzbefehle** — konfigurierbare globale Kurzbefehle zum Ein- und Ausschalten der Sperre und zum Durchschalten der gesperrten Eingabequelle sowie App-spezifische Kurzbefehle, um die Regel der vordersten App durchzuschalten oder zu entfernen.
- **Start bei Anmeldung** — startet automatisch beim Anmelden (standardmäßig aus).
- **Heller & dunkler Modus** — eine einheitliche, systemnative Designsprache, die sich an helles und dunkles Erscheinungsbild anpasst, plus ein maßgeschneidertes App-Symbol. Siehe [docs/DESIGN.md](../DESIGN.md).
- **Sprachwechsel zur Laufzeit** — wechsle sofort zwischen 9 Sprachen, ohne Neustart: English, 简体中文, 繁體中文, 日本語, Français, Deutsch, Español, Português, Русский.
- **24-Stunden-Aktivitätsprotokoll** — sieh nach, was warum und wie lange zurückgeschaltet wurde.
- **Konfigurations-Backup** — exportiere deine Regeln pro App und pro URL in eine `.lockime`-Datei und importiere sie wieder, mit einem Vorschau-Schritt, der Ergänzungen, Konflikte und Entfernungen auflistet, bevor etwas angewendet wird.
- **Automatische Updates** — Stable- und Beta-Kanal via Sparkle, mit einem eigenen Update-Fenster.
- **Winziger Download** — die gesamte App steckt in einer `.dmg` unter 3 MB.
- **Keine Systemberechtigungen für das Kern-Sperren** — ein optionaler, über Accessibility freigeschalteter erweiterter Modus ermöglicht feinere Regeln pro URL und pro fokussiertem Feld.
- **Automatisierung** — ein `lockime://`-URL-Schema lässt andere Apps, Skripte und Kurzbefehle LockIME steuern (siehe unten).

## Automation

LockIME stellt ein `lockime://`-URL-Schema bereit, damit andere Apps, Skripte, Kurzbefehle und Launcher es steuern können — das Sperren umschalten, die Eingabequelle neu festlegen, Regeln verwalten und mit [x-callback-url](https://x-callback-url.com)-Rückrufen den Zustand auslesen. Sie ist standardmäßig aus — schalte sie unter **Einstellungen ▸ Allgemein ▸ Automatisierung** ein.

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
```

Vollständige Referenz: **[URL Scheme API](../URL-Scheme-API/README.de.md)**.

## Design

LockIME folgt einem einzigen Designsystem (`Sources/LockIME/UI/DesignSystem.swift`): semantische Farben, Systemmaterialien und SF Symbols steuern die Hell/Dunkel-Anpassung; Liquid Glass ist ausschließlich der schwebenden/Navigations-Ebene vorbehalten. Die Marken-Akzentfarbe „Lock Indigo" wird als `AccentColor`-Asset ausgeliefert. Die vollständige Spezifikation steht in [docs/DESIGN.md](../DESIGN.md).

Das App-Symbol wird programmatisch erzeugt (ohne Design-Tool) — regeneriere es mit:

```sh
./scripts/make-appicon.sh   # renders the master via SwiftUI and rebuilds the appiconset
```

## Development

Erfordert Xcode 26+ (die App selbst zielt auf macOS 14+) sowie [XcodeGen](https://github.com/yonaskolb/XcodeGen) + [xcbeautify](https://github.com/cpisciotta/xcbeautify) (`brew install xcodegen xcbeautify`).

```sh
make gen     # generate LockIME.xcodeproj from project.yml
make build   # build (Debug)
make run     # build & launch
make test    # run unit tests
make archive # Release archive (Developer ID)
```

Das Xcode-Projekt wird aus `project.yml` generiert und ist nicht eingecheckt.

Hardware-berührende Integrationstests (echtes TIS-Umschalten) sind von `make test` ausgenommen; führe sie mit `make test-hw` aus (ändert kurzzeitig die Eingabequelle).

## Releasing

Dispatch-gesteuerte, notarisierte Developer-ID-Releases mit Sparkle-Auto-Update über die Kanäle **stable** und **beta**: Starte den Release-Workflow (Actions → Release) — er berechnet die Version aus den Git-Tags, baut und erstellt Tag und GitHub-Release automatisch — niemals einen Tag von Hand pushen. Der Beta-Kanal ist der Nightly-Build. Jedes Release liefert separate Apps für Apple silicon und Intel, jede mit eigenem Update-Feed (kein Universal-Binary, keine architekturübergreifenden Updates). Siehe [docs/RELEASING.md](../RELEASING.md).

## Architecture

- **LockIMEKit** (statische Bibliothek) — reine, vollständig unit-getestete Logik, die nur Systemframeworks nutzt: Sperr-Engine, App-Monitor, Regeln, erweiterter (Accessibility-)Beobachter, Protokollmodell, Lokalisierung.
- **LockIME** (App) — `@main`, die SwiftUI-Oberfläche, das Designsystem und die dünnen Integrationsschichten für Sparkle, KeyboardShortcuts und PermissionFlow.

## License

Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
