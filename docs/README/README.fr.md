<div align="center">

<img src="../images/appicon.png" alt="LockIME" width="128">

# LockIME

[English](../../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · **Français** · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md)

[![Dernière version](https://img.shields.io/github/v/release/oomol-lab/LockIME?sort=semver&color=3A5BD9)](https://github.com/oomol-lab/LockIME/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/LockIME/ci.yml?branch=main&label=CI)](https://github.com/oomol-lab/LockIME/actions/workflows/ci.yml)
[![Licence : GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-3A5BD9)](../../LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Greptile: The War on Bugs](https://www.greptile.com/badge.svg)](https://www.greptile.com/?utm_source=oss_badge&utm_medium=readme&utm_campaign=greptile_for_open_source)

</div>

LockIME est une application macOS de barre de menus qui verrouille votre source de saisie clavier. Lorsque vous ou une autre application changez de méthode de saisie, elle rebascule aussitôt : globalement, par application ou par URL de navigateur.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-general-en-dark.png">
    <img alt="Réglages généraux" src="../images/settings-general-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-app-rules-en-dark.png">
    <img alt="Règles par application" src="../images/settings-app-rules-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-url-rules-en-dark.png">
    <img alt="Règles par URL" src="../images/settings-url-rules-en-light.png" width="32%">
  </picture>
</p>

## Install

```sh
brew install --cask oomol-lab/tap/lockime
```

Ou téléchargez le `.dmg` depuis la [dernière version](https://github.com/oomol-lab/LockIME/releases/latest) : `-arm64` pour Apple silicon, `-x86_64` pour Intel. Nécessite macOS 14 ou ultérieur. LockIME se met à jour via Sparkle, sur un canal stable ou beta.

## Features

- **Verrouiller ou basculer.** Une règle pour une application ou une URL verrouille une source de saisie, en y revenant dès qu'elle change, ou y bascule une seule fois lorsque vous activez l'application ou la page, puis vous laisse libre.
- **Valeur par défaut globale.** Verrouillez une source de saisie partout, basculez-y une fois dans chaque application qui se rabat sur la valeur par défaut, ou choisissez *Aucune* et laissez vos règles tout faire.
- **Règles d'URL et de barre d'adresse.** Le verrouillage de base ne demande aucune permission système. Un mode renforcé optionnel requiert l'autorisation Accessibility et ajoute des règles par URL et pour la barre d'adresse du navigateur. Les règles d'URL font correspondre un domaine et ses sous-domaines, un domaine exact, un mot-clé ou une expression régulière sur l'URL entière ; faites-les glisser pour fixer la priorité, la première correspondance l'emporte.
- **Exécutables sans bundle.** Les programmes sans bundle `.app`, comme le `java` de Minecraft, apparaissent dans le sélecteur d'applications sous `process:java` pendant leur exécution.
- **Gestion des conflits.** Lorsqu'un autre programme réimpose sans cesse sa propre source de saisie, LockIME s'efface au lieu de lutter et consigne le conflit dans le journal. Donnez à cette application une règle *Ignorer* ou *Basculer vers* pour une solution durable.
- **Barre de menus et raccourcis.** Activez ou désactivez LockIME et changez la source de saisie verrouillée depuis la barre de menus ou avec des raccourcis globaux. Des raccourcis permettent aussi de faire défiler ou de supprimer la règle de l'application au premier plan.
- **Journal d'activation.** Les 24 dernières heures : ce qui a été basculé, pourquoi et pendant combien de temps.
- **Sauvegarde.** Exportez les règles dans un fichier `.lockime`. L'import prévisualise les ajouts, les conflits et les suppressions avant toute application.
- **Et aussi :** lancement à l'ouverture de session, 9 langues d'interface modifiables sans redémarrage et un téléchargement de moins de 3 MB.

## Comparison

[Input Source Pro](https://github.com/runjuu/InputSourcePro) et [KeyboardHolder](https://github.com/leaves615/KeyboardHolder) basculent la source de saisie lorsque vous passez d'une application ou d'un site à l'autre. LockIME la maintient en plus : une source de saisie verrouillée est réappliquée dès qu'elle change.

| | LockIME | Input Source Pro | KeyboardHolder |
|---|---|---|---|
| Open source | GPL-3.0 | GPL-3.0 | ✗ |
| macOS minimum | 14 | 11 | 10.15 |
| Taille de téléchargement | < 3 MB | ≈ 7.6 MB | ≈ 4.5 MB |
| Reverrouillage continu | ✓ | ✗ | ✗ |
| Verrouiller ou basculer une fois, par règle | ✓ | ✗ | ✗ |
| Types de correspondance d'URL | sous-domaine, exact, mot-clé, regex | sous-domaine, exact, regex | domaine (joker) |
| Règle de barre d'adresse | ✓ (verrouillage/bascule/priorité) | ✓ (source par défaut) | — |
| Raccourcis clavier globaux | ✓ | ✓ | ✗ |
| Indications de saisie à l'écran | ✗ | ✓ | ✓ (optionnel) |
| Journal d'activation sur 24 heures | ✓ | ✗ | ✗ |
| Sauvegarde / import de la configuration | ✓ (`.lockime`, avec prévisualisation) | ✓ (export/import + CLI) | — |
| Automatisation par schéma d'URL | ✓ (`lockime://`, x-callback-url) | partiel (import `inputsourcepro://`) | ✗ |
| Langues de l'interface | 9 | 6 | 3 |

> Comparaison effectuée avec Input Source Pro 2.11.0 et KeyboardHolder 1.14.10, à la mi-2026. « — » signale une capacité non documentée, et non une absence confirmée. Les corrections sont les bienvenues.

## Automation

Un schéma d'URL `lockime://` permet aux scripts, à Shortcuts et aux autres applications d'activer ou de désactiver LockIME, de changer la source de saisie verrouillée, de gérer les règles et de relire l'état via [x-callback-url](https://x-callback-url.com). Il est désactivé par défaut ; activez-le dans **Réglages ▸ Général ▸ Automatisation**.

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
```

Référence complète : [URL Scheme API](../URL-Scheme-API/README.fr.md).

## Development

Nécessite Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) et [xcbeautify](https://github.com/cpisciotta/xcbeautify) (`brew install xcodegen xcbeautify`). Le projet Xcode est généré à partir de `project.yml` et n'est pas versionné.

```sh
make gen      # generate LockIME.xcodeproj from project.yml
make build    # build (Debug)
make run      # build & launch
make test     # run unit tests
make test-hw  # integration tests; briefly changes the input source
```

La logique se trouve dans `LockIMEKit`, une bibliothèque statique couverte par des tests unitaires qui n'utilise que les frameworks système. La cible d'application `LockIME` contient l'interface SwiftUI et les intégrations Sparkle, KeyboardShortcuts et PermissionFlow. L'icône de l'application est générée par `./scripts/make-appicon.sh`.

Voir [docs/DESIGN.md](../DESIGN.md) pour le système de design et [docs/RELEASING.md](../RELEASING.md) pour le processus de publication.

## License

[GPL-3.0](../../LICENSE). Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
