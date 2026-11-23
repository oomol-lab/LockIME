<div align="center">

<img src="../images/appicon.png" alt="LockIME" width="128">

# LockIME

[English](../../README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · **Русский**

[![Последний выпуск](https://img.shields.io/github/v/release/oomol-lab/LockIME?sort=semver&color=3A5BD9)](https://github.com/oomol-lab/LockIME/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/LockIME/ci.yml?branch=main&label=CI)](https://github.com/oomol-lab/LockIME/actions/workflows/ci.yml)
[![Лицензия: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-3A5BD9)](../../LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Greptile: The War on Bugs](https://www.greptile.com/badge.svg)](https://www.greptile.com/?utm_source=oss_badge&utm_medium=readme&utm_campaign=greptile_for_open_source)

</div>

Приложение LockIME для строки меню macOS блокирует источник ввода клавиатуры. Когда вы или другое приложение меняете метод ввода, оно сразу возвращает заблокированный: глобально, для отдельного приложения или для URL в браузере.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-general-en-dark.png">
    <img alt="Основные настройки" src="../images/settings-general-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-app-rules-en-dark.png">
    <img alt="Правила для приложений" src="../images/settings-app-rules-en-light.png" width="32%">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../images/settings-url-rules-en-dark.png">
    <img alt="Правила для URL" src="../images/settings-url-rules-en-light.png" width="32%">
  </picture>
</p>

## Install

```sh
brew install --cask oomol-lab/tap/lockime
```

Или скачайте `.dmg` из [последнего релиза](https://github.com/oomol-lab/LockIME/releases/latest): `-arm64` для Apple silicon, `-x86_64` для Intel. Требуется macOS 14 или новее. LockIME обновляется через Sparkle, по каналу stable или beta.

## Features

- **Блокировка или переключение.** Правило для приложения или URL либо блокирует источник ввода и возвращает его при любом изменении, либо один раз переключает на него при открытии приложения или страницы, а дальше не мешает вам его менять.
- **Глобальный источник по умолчанию.** Заблокируйте один источник ввода везде, переключайтесь на него один раз в каждом приложении, которое опирается на источник по умолчанию, или выберите *Нет* и оставьте всю работу правилам.
- **Правила для URL и адресной строки.** Базовой блокировке не нужны системные разрешения. Необязательный расширенный режим запрашивает разрешение Accessibility и добавляет правила для URL и для адресной строки браузера. Правила для URL сопоставляют домен и его поддомены, точный домен, ключевое слово или регулярное выражение по всему URL; перетаскивайте их, чтобы задать приоритет, побеждает первое совпадение.
- **Программы без пакета.** Программы без пакета `.app`, например `java` игры Minecraft, отображаются в окне выбора приложений как `process:java`, пока они запущены.
- **Обработка конфликтов.** Когда другая программа снова и снова навязывает свой источник ввода, LockIME отступает вместо борьбы и записывает конфликт в журнал. Задайте такому приложению правило *Игнорировать* или *Переключить на*, чтобы решить проблему надолго.
- **Строка меню и сочетания клавиш.** Включайте и выключайте LockIME и меняйте заблокированный источник ввода из строки меню или глобальными сочетаниями клавиш. Сочетания также могут переключать или удалять правило активного приложения.
- **Журнал срабатываний.** Последние 24 часа: что переключалось, почему и на какое время.
- **Резервная копия.** Экспортируйте правила в файл `.lockime`. При импорте предпросмотр покажет добавления, конфликты и удаления до применения.
- **А также:** запуск при входе в систему, 9 языков интерфейса с переключением без перезапуска и загрузка меньше 3 MB.

## Comparison

[Input Source Pro](https://github.com/runjuu/InputSourcePro) и [KeyboardHolder](https://github.com/leaves615/KeyboardHolder) переключают источник ввода, когда вы переходите между приложениями или сайтами. LockIME ещё и удерживает его: заблокированный источник ввода применяется заново при любом изменении.

| | LockIME | Input Source Pro | KeyboardHolder |
|---|---|---|---|
| Открытый код | GPL-3.0 | GPL-3.0 | ✗ |
| Минимальная macOS | 14 | 11 | 10.15 |
| Размер загрузки | < 3 MB | ≈ 7.6 MB | ≈ 4.5 MB |
| Непрерывная повторная блокировка | ✓ | ✗ | ✗ |
| Блокировка или однократное переключение, для каждого правила | ✓ | ✗ | ✗ |
| Типы сопоставления URL | поддомен, точный, ключевое слово, регулярное выражение | поддомен, точный, регулярное выражение | домен (с подстановкой) |
| Правило для адресной строки | ✓ (блокировка/переключение/приоритет) | ✓ (источник по умолчанию) | — |
| Глобальные сочетания клавиш | ✓ | ✓ | ✗ |
| Экранные подсказки ввода | ✗ | ✓ | ✓ (опционально) |
| Журнал срабатываний за 24 часа | ✓ | ✗ | ✗ |
| Резервная копия / импорт конфигурации | ✓ (`.lockime`, с предпросмотром) | ✓ (экспорт/импорт + CLI) | — |
| Автоматизация через URL-схему | ✓ (`lockime://`, x-callback-url) | частично (импорт `inputsourcepro://`) | ✗ |
| Языки интерфейса | 9 | 6 | 3 |

> Сравнение с Input Source Pro 2.11.0 и KeyboardHolder 1.14.10, середина 2026 года. «—» означает недокументированную возможность, а не подтверждённое отсутствие. Поправки приветствуются.

## Automation

URL-схема `lockime://` позволяет скриптам, Shortcuts и другим приложениям включать и выключать LockIME, менять заблокированный источник ввода, управлять правилами и считывать состояние через [x-callback-url](https://x-callback-url.com). По умолчанию она выключена; включите её в **Настройки ▸ Основные ▸ Автоматизация**.

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
```

Полная справка: [URL Scheme API](../URL-Scheme-API/README.ru.md).

## Development

Требуются Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) и [xcbeautify](https://github.com/cpisciotta/xcbeautify) (`brew install xcodegen xcbeautify`). Проект Xcode генерируется из `project.yml` и не хранится в репозитории.

```sh
make gen      # generate LockIME.xcodeproj from project.yml
make build    # build (Debug)
make run      # build & launch
make test     # run unit tests
make test-hw  # integration tests; briefly changes the input source
```

Логика находится в `LockIMEKit`, статической библиотеке с модульными тестами, которая использует только системные фреймворки. Таргет приложения `LockIME` содержит интерфейс на SwiftUI и интеграции со Sparkle, KeyboardShortcuts и PermissionFlow. Значок приложения генерируется скриптом `./scripts/make-appicon.sh`.

Система дизайна описана в [docs/DESIGN.md](../DESIGN.md), процесс выпуска в [docs/RELEASING.md](../RELEASING.md).

## License

[GPL-3.0](../../LICENSE). Copyright © 2026 Hangzhou Wumou Software Co., Ltd.
