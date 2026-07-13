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
- **Bloquear o cambiar** — las reglas por aplicación y por URL pueden *bloquear* una fuente de entrada (se vuelve a aplicar cada vez que se desvía) o solo *cambiar* a ella una vez cuando activas la aplicación o la página, y luego dejarte cambiarla libremente.
- **Bloquear de forma global, o solo cambiar** — asigna a la fuente de entrada predeterminada global uno de tres comportamientos: *bloquear* para fijarla en todas partes; *cambiar* para cambiarte a ella una vez cada vez que una aplicación recurre a la predeterminada global (no tiene regla propia, o su regla es *Usar predeterminada*) y luego dejarte libre; o **Ninguna** para no tener ningún comportamiento global en absoluto — entonces LockIME actúa solo a través de tus reglas por aplicación y por URL. *Cambiar* te cambia activamente cada vez que se aplica la predeterminada; **Ninguna** no hace nada de forma global.
- **Coincidencia de URL flexible** — las reglas por URL (modo mejorado) coinciden por un dominio y sus subdominios, por un dominio exacto, por una palabra clave de dominio o por una expresión regular sobre la URL completa, y se aplican en el orden de prioridad que tú arrastras para organizar — la primera coincidencia gana.
- **Control desde la barra de menús** — activa/desactiva, cambia la fuente de entrada bloqueada, consulta la fuente actual y sigue el contador de activaciones desde la barra de menús.
- **Atajos de teclado** — atajos globales configurables para activar/desactivar LockIME y recorrer la fuente de entrada bloqueada, además de atajos por aplicación para recorrer o eliminar la regla de la aplicación en primer plano.
- **Arranque al iniciar sesión** — se inicia automáticamente al iniciar sesión (desactivado por defecto).
- **Modo claro y oscuro** — un lenguaje de diseño unificado y nativo del sistema que se adapta a la apariencia clara y oscura, además de un icono de aplicación a medida. Ver [docs/DESIGN.md](../DESIGN.md).
- **Cambio de idioma en vivo** — cambia al instante entre 9 idiomas, sin reiniciar: English, 简体中文, 繁體中文, 日本語, Français, Deutsch, Español, Português, Русский.
- **Registro de activaciones de 24 horas** — revisa qué se cambió, por qué y durante cuánto tiempo.
- **Copia de seguridad de la configuración** — exporta tus reglas por aplicación y por URL a un archivo `.lockime` e impórtalas de vuelta, con un paso de previsualización que muestra las adiciones, los conflictos y las eliminaciones antes de aplicar nada.
- **Actualización automática** — canales stable y beta mediante Sparkle, con una ventana de actualización personalizada.
- **Descarga diminuta** — toda la aplicación cabe en un `.dmg` de menos de 3 MB.
- **Sin permisos del sistema para el bloqueo básico** — un modo mejorado opcional, protegido por Accessibility, desbloquea reglas más finas por URL y por campo con el foco.
- **Automatización** — un esquema de URL `lockime://` permite que otras aplicaciones, scripts y Shortcuts controlen LockIME (ver más abajo).

## Comparison

Las dos alternativas a LockIME más utilizadas son
**[Input Source Pro](https://github.com/runjuu/InputSourcePro)** y
**[KeyboardHolder](https://github.com/leaves615/KeyboardHolder)**, junto con una
larga cola de herramientas de código abierto y de CLI más pequeñas. Todas ellas
*cambian* la fuente de entrada a medida que te mueves entre aplicaciones o
sitios; LockIME está construida en torno a un **bloqueo** continuo que la vuelve
a aplicar en el momento en que se desvía — sin dejar de permitir que cualquier
regla recurra a un *cambio* único.

| | LockIME | Input Source Pro | KeyboardHolder |
|---|---|---|---|
| Precio | Gratis | Gratis | Gratis (donación) |
| Código abierto | GPL-3.0 | GPL-3.0 | ✗ (cerrado) |
| macOS mínimo | 14 | 11 | 10.15 |
| Tamaño de descarga | < 3 MB | ≈ 7.6 MB | ≈ 4.5 MB |
| Reglas por aplicación | ✓ | ✓ | ✓ |
| Reglas por sitio web / URL | ✓ | ✓ | ✓ |
| Tipos de coincidencia de URL | subdominio · exacto · palabra clave · regex | subdominio · exacto · regex | dominio (comodín) |
| Regla de barra de direcciones (campo de URL) | ✓ (bloqueo/cambio/prioridad) | ✓ (fuente predeterminada) | — |
| Rebloqueo continuo | ✓ | ✗ | ✗ |
| Bloqueo *o* cambio único, por regla | ✓ | ✗ | ✗ |
| Atajos de teclado globales | ✓ | ✓ | ✗ |
| Control desde la barra de menús | ✓ | ✓ | ✓ |
| Indicaciones de entrada en pantalla | ✗ | ✓ | ✓ (opcional) |
| Registro de activaciones de 24 horas | ✓ | ✗ | ✗ |
| Copia de seguridad / importación de la configuración | ✓ (`.lockime`, con revisión) | ✓ (exportación/importación + CLI) | — |
| Automatización con esquema de URL | ✓ (`lockime://`, x-callback-url) | parcial (importación `inputsourcepro://`) | ✗ |
| Idiomas de la interfaz | 9 (cambio en vivo) | 6 | zh · en · ja |
| Permisos del sistema | ninguno para el núcleo · Accessibility para reglas por URL | ninguno para el núcleo · Accessibility para reglas por URL | Accessibility¹ |
| Actualización automática | Sparkle (stable + beta) | ✓ | ✓ |
| Mantenido activamente (2026) | ✓ | ✓ | ✓ |

¹ KeyboardHolder no documenta sus requisitos de permisos; leer la barra de
direcciones del navegador para sus reglas por sitio web requiere acceso a
Accessibility en la práctica. Un «—» marca una capacidad no documentada, no una
ausencia confirmada.

**Cómo elegir entre ellas:** Input Source Pro tiene la comunidad más grande y
las indicaciones de entrada en pantalla más completas; KeyboardHolder es una
memoria por aplicación pulida y sin configuración. Recurre a LockIME cuando
quieras *fijar* una fuente de entrada — por aplicación, por URL o en la barra de
direcciones, vuelta a aplicar en el instante en que algo la cambia — en lugar de
solo cambiarla al llegar.

**Otras herramientas:** [SwitchKey](https://github.com/itsuhane/SwitchKey) (solo
por aplicación, sin mantenimiento), [Kawa](https://github.com/hatashiro/kawa)
(manual, dirigido por atajos), InputSwitcher (freemium, solo por aplicación) y
[macism](https://github.com/laishulu/macism) (un componente de línea de
comandos, no un cambiador con interfaz gráfica).

> Comparado con Input Source Pro 2.11.0 y KeyboardHolder 1.14.10, a mediados de 2026 — los detalles cambian; se agradecen las correcciones.

## Automation

LockIME expone un esquema de URL `lockime://` para que otras aplicaciones, scripts, Shortcuts y lanzadores puedan controlarlo: activarlo o desactivarlo, recambiar la fuente de entrada, gestionar reglas y leer el estado de vuelta con callbacks de [x-callback-url](https://x-callback-url.com). Está desactivada por defecto — actívala en **Ajustes ▸ General ▸ Automatización**.

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
```

Referencia completa: **[URL Scheme API](../URL-Scheme-API/README.es.md)**.

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
- **LockIME** (aplicación) — `@main`, la interfaz SwiftUI, el sistema de diseño y las finas capas de integración para Sparkle, KeyboardShortcuts y PermissionFlow.

## License

Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
