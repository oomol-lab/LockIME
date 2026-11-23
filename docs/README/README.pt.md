<div align="center">

<img src="../images/appicon.png" alt="LockIME" width="128">

# LockIME

[English](../../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · **Português** · [Русский](README.ru.md)

[![Última versão](https://img.shields.io/github/v/release/oomol-lab/LockIME?sort=semver&color=3A5BD9)](https://github.com/oomol-lab/LockIME/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/LockIME/ci.yml?branch=main&label=CI)](https://github.com/oomol-lab/LockIME/actions/workflows/ci.yml)
[![Licença: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-3A5BD9)](../../LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Greptile: The War on Bugs](https://www.greptile.com/badge.svg)](https://www.greptile.com/?utm_source=oss_badge&utm_medium=readme&utm_campaign=greptile_for_open_source)

</div>

O LockIME é um app de barra de menus para macOS que bloqueia a sua fonte de entrada do teclado. Quando você ou outro app troca o método de entrada, ele volta na hora para a bloqueada: globalmente, por app ou por URL do navegador.

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

```sh
brew install --cask oomol-lab/tap/lockime
```

Ou baixe o `.dmg` na [versão mais recente](https://github.com/oomol-lab/LockIME/releases/latest): `-arm64` para Apple silicon, `-x86_64` para Intel. Requer macOS 14 ou posterior. O LockIME se atualiza pelo Sparkle, em um canal stable ou beta.

## Features

- **Bloquear ou alternar.** Uma regra para um app ou URL bloqueia uma fonte de entrada, voltando a ela sempre que muda, ou alterna para ela uma única vez quando você foca o app ou a página e depois deixa você livre.
- **Padrão global.** Bloqueie uma fonte de entrada em todo lugar, alterne para ela uma vez em cada app que recorre ao padrão, ou escolha *Nenhuma* e deixe suas regras fazerem todo o trabalho.
- **Regras de URL e da barra de endereços.** O bloqueio básico não precisa de permissões do sistema. Um modo aprimorado opcional pede a permissão de Accessibility e adiciona regras por URL e para a barra de endereços do navegador. As regras de URL correspondem por um domínio e seus subdomínios, um domínio exato, uma palavra-chave ou uma expressão regular sobre a URL inteira; arraste-as para definir a prioridade, e a primeira correspondência vence.
- **Executáveis avulsos.** Programas sem bundle `.app`, como o `java` do Minecraft, aparecem no seletor de apps como `process:java` enquanto estão em execução.
- **Tratamento de conflitos.** Quando outro programa insiste em impor a própria fonte de entrada, o LockIME recua em vez de brigar e anota o conflito no registro. Dê a esse app uma regra *Ignorar* ou *Alternar para* para uma solução duradoura.
- **Barra de menus e atalhos.** Ative ou desative o LockIME e troque a fonte de entrada bloqueada pela barra de menus ou com atalhos globais. Os atalhos também podem percorrer ou remover a regra do app em primeiro plano.
- **Registro de ativações.** As últimas 24 horas: o que foi alternado, por quê e por quanto tempo.
- **Backup.** Exporte as regras para um arquivo `.lockime`. A importação mostra uma prévia de adições, conflitos e remoções antes de aplicar qualquer coisa.
- **E também:** abrir ao iniciar sessão, 9 idiomas de interface que mudam sem reiniciar e um download de menos de 3 MB.

## Comparison

O [Input Source Pro](https://github.com/runjuu/InputSourcePro) e o [KeyboardHolder](https://github.com/leaves615/KeyboardHolder) alternam a fonte de entrada conforme você passa de um app ou site para outro. O LockIME também a mantém: uma fonte de entrada bloqueada é reaplicada sempre que muda.

| | LockIME | Input Source Pro | KeyboardHolder |
|---|---|---|---|
| Código aberto | GPL-3.0 | GPL-3.0 | ✗ |
| macOS mínimo | 14 | 11 | 10.15 |
| Tamanho do download | < 3 MB | ≈ 7.6 MB | ≈ 4.5 MB |
| Rebloqueio contínuo | ✓ | ✗ | ✗ |
| Bloquear ou alternar uma vez, por regra | ✓ | ✗ | ✗ |
| Tipos de correspondência de URL | subdomínio, exato, palavra-chave, regex | subdomínio, exato, regex | domínio (curinga) |
| Regra da barra de endereços | ✓ (bloqueio/alternância/prioridade) | ✓ (fonte padrão) | — |
| Atalhos de teclado globais | ✓ | ✓ | ✗ |
| Dicas de entrada na tela | ✗ | ✓ | ✓ (opcional) |
| Registro de ativações de 24 horas | ✓ | ✗ | ✗ |
| Backup / importação da configuração | ✓ (`.lockime`, com prévia) | ✓ (exportar/importar + CLI) | — |
| Automação por esquema de URL | ✓ (`lockime://`, x-callback-url) | parcial (importação `inputsourcepro://`) | ✗ |
| Idiomas da interface | 9 | 6 | 3 |

> Comparado com o Input Source Pro 2.11.0 e o KeyboardHolder 1.14.10, em meados de 2026. "—" indica um recurso não documentado, não uma ausência confirmada. Correções são bem-vindas.

## Automation

Um esquema de URL `lockime://` permite que scripts, o Shortcuts e outros apps ativem ou desativem o LockIME, troquem a fonte de entrada bloqueada, gerenciem regras e leiam o estado via [x-callback-url](https://x-callback-url.com). Ele vem desativado por padrão; ative-o em **Ajustes ▸ Geral ▸ Automação**.

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
```

Referência completa: [URL Scheme API](../URL-Scheme-API/README.pt.md).

## Development

Requer Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) e [xcbeautify](https://github.com/cpisciotta/xcbeautify) (`brew install xcodegen xcbeautify`). O projeto do Xcode é gerado a partir de `project.yml` e não é versionado.

```sh
make gen      # generate LockIME.xcodeproj from project.yml
make build    # build (Debug)
make run      # build & launch
make test     # run unit tests
make test-hw  # integration tests; briefly changes the input source
```

A lógica fica no `LockIMEKit`, uma biblioteca estática com testes unitários que usa apenas frameworks do sistema. O target de app `LockIME` contém a interface SwiftUI e as integrações com Sparkle, KeyboardShortcuts e PermissionFlow. O ícone do app é gerado por `./scripts/make-appicon.sh`.

Veja [docs/DESIGN.md](../DESIGN.md) para o sistema de design e [docs/RELEASING.md](../RELEASING.md) para o processo de lançamento.

## License

[GPL-3.0](../../LICENSE). Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
