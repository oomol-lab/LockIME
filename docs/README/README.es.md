<div align="center">

<img src="../images/appicon.png" alt="LockIME" width="128">

# LockIME

[English](../../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · **Español** · [Português](README.pt.md) · [Русский](README.ru.md)

[![Última versión](https://img.shields.io/github/v/release/oomol-lab/LockIME?sort=semver&color=3A5BD9)](https://github.com/oomol-lab/LockIME/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/LockIME/ci.yml?branch=main&label=CI)](https://github.com/oomol-lab/LockIME/actions/workflows/ci.yml)
[![Licencia: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-3A5BD9)](../../LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)

</div>

Una aplicación de barra de menús para macOS que **bloquea tu fuente de entrada de teclado**. Cada vez que tú (u otra aplicación) cambias el método de entrada, LockIME vuelve inmediatamente al bloqueado — globalmente, por aplicación en primer plano, o (con el modo mejorado opcional) por URL del navegador.

> macOS 14+ · Apple silicon e Intel — aplicaciones separadas, descarga el
> archivo `-arm64` o `-x86_64` que corresponda a tu Mac · construida con
> SwiftUI, Liquid Glass en macOS 26 (Tahoe).

## Screenshots

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-general-en-dark.png">
    <img alt="Ajustes generales" src="../images/settings-general-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-app-rules-en-dark.png">
    <img alt="Reglas por aplicación" src="../images/settings-app-rules-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-url-rules-en-dark.png">
    <img alt="Reglas por URL" src="../images/settings-url-rules-en-light.png" width="32%">
  </picture>
</p>

## Install

Instala con [Homebrew](https://brew.sh) (el cask elige la compilación que
corresponde a la arquitectura de tu Mac):

```sh
brew install --cask oomol-lab/tap/lockime
```

O descarga el `.dmg` que corresponda a tu Mac (`-arm64` para Apple silicon,
`-x86_64` para Intel) desde la
[última versión](https://github.com/oomol-lab/LockIME/releases/latest).
En cualquier caso, la aplicación se mantiene actualizada mediante Sparkle.

## Features

- **Rebloqueo instantáneo** — devuelve la fuente de entrada activa a la bloqueada en el momento en que tú (u otra aplicación) la cambias, globalmente o por aplicación.
- **Control desde la barra de menús** — activa/desactiva, cambia la fuente de entrada bloqueada, consulta la fuente actual y sigue el contador de activaciones desde la barra de menús.
- **Atajos de teclado** — atajos globales configurables para activar/desactivar el bloqueo y recorrer la fuente de entrada bloqueada, además de atajos por aplicación para recorrer o eliminar la regla de la aplicación en primer plano.
- **Arranque al iniciar sesión** — se inicia automáticamente al iniciar sesión (desactivado por defecto).
- **Modo claro y oscuro** — un lenguaje de diseño unificado y nativo del sistema que se adapta a la apariencia clara y oscura, además de un icono de aplicación a medida. Ver [docs/DESIGN.md](../DESIGN.md).
- **Cambio de idioma en vivo** — cambia al instante entre 9 idiomas, sin reiniciar: English, 简体中文, 繁體中文, 日本語, Français, Deutsch, Español, Português, Русский.
- **Registro de activaciones de 24 horas** — revisa qué se cambió, por qué y durante cuánto tiempo.
- **Actualización automática** — canales stable y beta mediante Sparkle, con una ventana de actualización personalizada.
- **Sin permisos del sistema para el bloqueo básico** — un modo mejorado opcional, protegido por Accessibility, desbloquea reglas más finas por URL y por campo con el foco.

## Design

LockIME sigue un único sistema de diseño (`Sources/LockIME/UI/DesignSystem.swift`): los colores semánticos, los materiales del sistema y los SF Symbols dirigen la adaptación claro/oscuro; Liquid Glass se reserva únicamente para la capa flotante/de navegación. El color de acento de la marca, «Lock Indigo», se incluye como asset `AccentColor`. La especificación completa está en [docs/DESIGN.md](../DESIGN.md).

El icono de la aplicación se genera por programa (sin herramienta de diseño) — regenéralo con:

```sh
./scripts/make-appicon.sh   # renders the master via SwiftUI and rebuilds the appiconset
```

## Development

Requiere Xcode 26+ (la propia aplicación apunta a macOS 14+), además de [XcodeGen](https://github.com/yonaskolb/XcodeGen) + [xcbeautify](https://github.com/cpisciotta/xcbeautify) (`brew install xcodegen xcbeautify`).

```sh
make gen     # generate LockIME.xcodeproj from project.yml
make build   # build (Debug)
make run     # build & launch
make test    # run unit tests
make archive # Release archive (Developer ID)
```

El proyecto de Xcode se genera a partir de `project.yml` y no está versionado.

Las pruebas de integración que tocan hardware (cambio real de TIS) están excluidas de `make test`; ejecútalas con `make test-hw` (cambia brevemente la fuente de entrada).

## Releasing

Versiones Developer ID notarizadas y dirigidas por dispatch, con actualización automática de Sparkle en los canales **stable** y **beta**: ejecuta el workflow Release (Actions → Release) — calcula la versión a partir de las etiquetas de git, compila y crea la etiqueta y la GitHub Release automáticamente — nunca subas una etiqueta a mano. El canal beta es la compilación nightly. Cada versión incluye aplicaciones separadas para Apple silicon e Intel, cada una con su propio feed de actualización (sin binario universal, sin actualizaciones entre arquitecturas). Ver [docs/RELEASING.md](../RELEASING.md).

## Architecture

- **LockIMEKit** (biblioteca estática) — lógica pura, totalmente cubierta por pruebas unitarias, que solo usa frameworks del sistema: motor de bloqueo, monitor de aplicaciones, reglas, observador mejorado (Accessibility), modelo de registro, localización.
- **LockIME** (aplicación) — `@main`, la interfaz SwiftUI, el sistema de diseño y las finas capas de integración para Sparkle, KeyboardShortcuts, PermissionFlow y MarkdownUI.

## License

Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
