<div align="center">

<img src="../images/appicon.png" alt="LockIME" width="128">

# LockIME

[English](../../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · **Português** · [Русский](README.ru.md)

[![Última versão](https://img.shields.io/github/v/release/oomol-lab/LockIME?sort=semver&color=3A5BD9)](https://github.com/oomol-lab/LockIME/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/LockIME/ci.yml?branch=main&label=CI)](https://github.com/oomol-lab/LockIME/actions/workflows/ci.yml)
[![Licença: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-3A5BD9)](../../LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)

</div>

Um app de barra de menus para macOS que **bloqueia a sua fonte de entrada do teclado**. Sempre que você (ou outro app) troca o método de entrada, o LockIME volta imediatamente para o que está bloqueado — globalmente, por app em primeiro plano, ou (com o modo aprimorado opcional) por URL do navegador.

> macOS 14+ · Apple silicon e Intel — apps separados, baixe o arquivo
> `-arm64` ou `-x86_64` correspondente ao seu Mac · construído com SwiftUI,
> Liquid Glass no macOS 26 (Tahoe).

## Screenshots

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-general-en-dark.png">
    <img alt="Ajustes gerais" src="../images/settings-general-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-app-rules-en-dark.png">
    <img alt="Regras por app" src="../images/settings-app-rules-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-url-rules-en-dark.png">
    <img alt="Regras por URL" src="../images/settings-url-rules-en-light.png" width="32%">
  </picture>
</p>

## Install

Instale com o [Homebrew](https://brew.sh) (o cask escolhe a build
correspondente à arquitetura do seu Mac):

```sh
brew install --cask oomol-lab/tap/lockime
```

Ou baixe o `.dmg` correspondente ao seu Mac (`-arm64` para Apple silicon,
`-x86_64` para Intel) na
[última versão](https://github.com/oomol-lab/LockIME/releases/latest).
De qualquer forma, o app se mantém atualizado sozinho via Sparkle.

## Features

- **Rebloqueio instantâneo** — devolve a fonte de entrada ativa para a bloqueada no momento em que você (ou outro app) a troca, globalmente ou por app.
- **Controle pela barra de menus** — ative/desative, troque a fonte de entrada bloqueada, veja a fonte atual e acompanhe o contador de ativações pela barra de menus.
- **Atalho global de alternância** — ligue ou desligue o bloqueio com um atalho de teclado configurável.
- **Iniciar no login** — inicia automaticamente quando você faz login (desativado por padrão).
- **Modo claro e escuro** — uma linguagem de design unificada e nativa do sistema, que se adapta às aparências clara e escura, além de um ícone de app sob medida. Veja [docs/DESIGN.md](../DESIGN.md).
- **Troca de idioma ao vivo** — alterne instantaneamente entre 9 idiomas, sem reiniciar: English, 简体中文, 繁體中文, 日本語, Français, Deutsch, Español, Português, Русский.
- **Registro de ativações de 24 horas** — veja o que foi trocado, por quê e por quanto tempo.
- **Atualização automática** — canais stable e beta via Sparkle, com uma janela de atualização personalizada.
- **Sem permissões do sistema para o bloqueio básico** — um modo aprimorado opcional, condicionado à permissão de Accessibility, libera regras mais finas por URL e por campo em foco.

## Design

O LockIME segue um único sistema de design (`Sources/LockIME/UI/DesignSystem.swift`): cores semânticas, materiais do sistema e SF Symbols conduzem a adaptação claro/escuro; o Liquid Glass fica reservado apenas à camada flutuante/de navegação. A cor de destaque da marca, "Lock Indigo", é distribuída como asset `AccentColor`. A especificação completa está em [docs/DESIGN.md](../DESIGN.md).

O ícone do app é gerado programaticamente (sem ferramenta de design) — regenere-o com:

```sh
./scripts/make-appicon.sh   # renders the master via SwiftUI and rebuilds the appiconset
```

## Development

Requer Xcode 26+ (o app em si tem como alvo o macOS 14+), além de [XcodeGen](https://github.com/yonaskolb/XcodeGen) + [xcbeautify](https://github.com/cpisciotta/xcbeautify) (`brew install xcodegen xcbeautify`).

```sh
make gen     # generate LockIME.xcodeproj from project.yml
make build   # build (Debug)
make run     # build & launch
make test    # run unit tests
make archive # Release archive (Developer ID)
```

O projeto do Xcode é gerado a partir de `project.yml` e não é versionado.

Os testes de integração que tocam o hardware (troca real de TIS) estão excluídos do `make test`; execute-os com `make test-hw` (muda brevemente a fonte de entrada).

## Releasing

Lançamentos Developer ID notarizados e acionados por dispatch, com atualização automática via Sparkle nos canais **stable** e **beta**: execute o workflow Release (Actions → Release) — ele calcula a versão a partir das tags do git, compila e cria a tag e a GitHub Release automaticamente — nunca envie uma tag manualmente. O canal beta é a build nightly. Cada lançamento traz apps separados para Apple silicon e Intel, cada um com seu próprio feed de atualização (sem binário universal, sem atualizações entre arquiteturas). Veja [docs/RELEASING.md](../RELEASING.md).

## Architecture

- **LockIMEKit** (biblioteca estática) — lógica pura, totalmente coberta por testes unitários, usando apenas frameworks do sistema: motor de bloqueio, monitor de apps, regras, observador aprimorado (Accessibility), modelo de registro, localização.
- **LockIME** (app) — `@main`, a interface SwiftUI, o sistema de design e as finas camadas de integração para Sparkle, KeyboardShortcuts, PermissionFlow e MarkdownUI.

## License

Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
