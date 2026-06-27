# URL Scheme API

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · **Русский**

LockIME предоставляет URL-схему `lockime://`, чтобы другие приложения, скрипты,
Shortcuts, Stream Deck, Alfred/Raycast, AppleScript — всё, что может открыть URL, —
могли управлять им: включать и выключать блокировку, менять источник ввода,
управлять правилами и считывать состояние обратно.

Каждая команда — это URL, по умолчанию работающий по принципу
«запустил и забыл», с опциональными колбэками
[x-callback-url](https://x-callback-url.com) для успеха/ошибки и для
возврата данных от команд-запросов.

> **Сначала включите её.** URL Scheme API **по умолчанию выключен**. Включите его в
> **LockIME ▸ Настройки ▸ Основные ▸ Автоматизация ▸ URL Scheme API**. Пока он выключен,
> каждая команда возвращает ошибку `api_disabled` и ничего не происходит.

> **Замечание о безопасности.** После включения команды выполняются **без
> подтверждения для каждой команды** — любой процесс, способный открыть URL `lockime://`
> (включая веб-страницу), может управлять LockIME. Каждая команда обратима и ни одна из них
> не трогает ваши файлы; самое худшее, что может сделать злонамеренный вызывающий, —
> переключить блокировку источника ввода или отредактировать правила.
> Оставляйте API выключенным, когда вы им не пользуетесь.

---

## URL shape

Принимаются две эквивалентные формы:

```
lockime://<command>?<param>=<value>&<param>=<value>
lockime://x-callback-url/<command>?<param>=<value>&…
```

- **Токен команды** (`<command>`) нечувствителен к регистру.
- **Имена параметров** нечувствительны к регистру; **значения параметров** берутся
  дословно (поэтому идентификаторы bundle и источника сохраняют свой регистр).
- Всегда **кодируйте процентами** значения, содержащие зарезервированные символы
  (`?`, `&`, `=`, `/`, пробелы, …). Отображаемое имя источника, например `ABC – Extended`,
  превращается в `name=ABC%20%E2%80%93%20Extended`.

Префикс `x-callback-url/` — это необязательный синтаксический сахар для инструментов
x-callback-url; параметры колбэков ниже работают и с краткой формой.

> **Development builds.** Debug-сборка LockIME регистрирует `lockime-dev://`
> вместо `lockime://`, поэтому локальная сборка никогда не перехватывает схему
> установленного релиза. Всё остальное идентично.

---

## x-callback-url

Любая команда может нести эти зарезервированные параметры:

| Parameter | Meaning |
|---|---|
| `x-success` | URL, открываемый после успешного выполнения команды. Для команд-**запросов** результат в формате JSON добавляется как `result=<json>` (закодированный процентами). |
| `x-error`   | URL, открываемый при сбое команды, с добавлением `errorCode=<code>&errorMessage=<text>`. |
| `x-source`  | Отображаемое имя вызывающего приложения (информационное; LockIME записывает его в журнал). |

Команды-действия запускают `x-success` без `result`. Команды-запросы возвращают свою
полезную нагрузку через `x-success`; без URL `x-success` запросу просто некуда
отправить свой результат (он всё равно выполняется, безвредно).

Пример полного цикла — запросить статус и получить его обратно в собственное приложение:

```
lockime://status?x-success=myapp%3A%2F%2Fgot-status
```

При успехе LockIME открывает:

```
myapp://got-status?result=%7B%22locked%22%3Atrue%2C…%7D
```

---

## Command reference

### Enable & locking

Главный переключатель (`lock` / `unlock` / `toggle-lock`) включает и выключает **LockIME** — он управляет всем (и блокировкой, и переключением). Подчинённый ему вспомогательный переключатель `set-locking` управляет только **непрерывной блокировкой**: выключите его, чтобы перестать закреплять какой-либо источник, пока продолжают срабатывать одноразовые правила переключения, — режим «вести себя как чистый переключатель».

| Command | Parameters | Effect |
|---|---|---|
| `lock` | — | **Включить** **LockIME** (главный переключатель) — применяются ваши правила. |
| `unlock` | — | **Выключить** **LockIME** (главный переключатель) — полностью бездействует. |
| `toggle-lock` *(alias `toggle`)* | — | Переключить главный переключатель (вкл/выкл). |
| `set-locking` *(alias `locking`)* | `enabled` = `true` \| `false` \| `toggle` | Включить/выключить **непрерывную блокировку** (или переключить её). Выкл ⇒ ничего не закрепляется, но правила переключения по-прежнему срабатывают. Не действует немедленно во время выполнения, пока главный переключатель выключен. |

### Global input source

**Источник** задаётся через `id` (канонический идентификатор Text Input Source, например
`com.apple.keylayout.ABC`, возвращаемый командой [`list-sources`](#queries)) или через
`name` (его локализованное отображаемое имя, нечувствительно к регистру). Он должен указывать
на установленный в данный момент, выбираемый источник, иначе команда возвращает `unknown_source`.

| Command | Parameters | Effect |
|---|---|---|
| `lock-to-source` | `id` \| `name` | Задать глобальный источник по умолчанию **и** включить блокировку. |
| `set-default-source` | `id` \| `name` *(omit both to clear)* | Задать (или сбросить) глобальный источник по умолчанию, не меняя состояние вкл/выкл. |
| `cycle-source` | `direction` = `next` \| `previous` | Перейти к следующему/предыдущему установленному источнику в глобальной цели (по кругу) и включить блокировку. |
| `switch-source` | `id` \| `name` | Переключает текущий источник ввода **один раз**, прямо сейчас — это **не** включает и не изменяет непрерывную блокировку. Если непрерывная блокировка уже активна, она берёт верх и возвращает источник к своей цели. |

`direction` также принимает псевдонимы `prev`, `forward`, `back`, `up`, `down`.

### Per-app rules

| Command | Parameters | Effect |
|---|---|---|
| `set-app-rule` | `bundle` *(req)*, `mode` = `lock` \| `switch` \| `ignore` \| `default` *(default `lock`)*, `source` \| `source-name` *(req for `lock`/`switch`)* | Создать или заменить правило для приложения. `lock` непрерывно применяет источник; `switch` переключает один раз при активации, затем отпускает; `ignore` отключает блокировку для этого приложения; `default` возвращается к глобальному значению по умолчанию. |
| `remove-app-rule` | `bundle` *(req)* | Удалить правило для `bundle`. `rule_not_found`, если его нет. |
| `cycle-app-source` | `direction` *(req)*, `bundle` *(optional; default = frontmost app)* | Перейти к следующему/предыдущему источнику в собственном правиле этого приложения. Ничего не делает (`rule_not_found`), если у приложения нет правила. |
| `remove-frontmost-app-rule` | — | Удалить правило для того приложения, которое сейчас на переднем плане. |
| `clear-app-rules` | — | Удалить **все** правила для приложений. |

### General settings

| Command | Parameters | Effect |
|---|---|---|
| `set-launch-at-login` *(alias `launch-at-login`)* | `enabled` = `true` \| `false` \| `toggle` | Зарегистрировать/снять регистрацию LockIME как объекта входа. |
| `set-language` | `code` = `en` \| `zh-Hans` \| `zh-Hant` \| `ja` \| `fr` \| `de` \| `es` \| `pt` \| `ru` \| `system` | Задать переопределение языка внутри приложения; `system` (псевдоним `auto`) сбрасывает его и следует за языком macOS. Снисходительно: `zh-CN`→`zh-Hans`, `zh-TW`→`zh-Hant`, `fr-CA`→`fr`, … |

### Enhanced mode & per-URL rules

Правила для URL требуют опционального **расширенного режима**, защищённого разрешением Accessibility.

| Command | Parameters | Effect |
|---|---|---|
| `set-enhanced-mode` | `enabled` = `true` \| `false` \| `toggle` | Включить/выключить расширенный режим (или переключить его). |
| `set-url-rule` | `host` *(alias `pattern`, req)*, `source` \| `source-name` *(req)*, `match-type` = `domain-suffix` \| `domain` \| `domain-keyword` \| `url-regex` *(default `domain-suffix`)*, `action` = `lock` \| `switch` *(default `lock`)*, `id` *(optional UUID)* | Создать или заменить правило для URL. Способ сопоставления шаблона зависит от `match-type` (см. [ниже](#match-types)). Без `id` существующее правило для того же шаблона обновляется, а не дублируется. |
| `remove-url-rule` | `id` *(UUID)* \| `host` | Удалить правило для URL по его `id` (из `list-url-rules`) или по `host`. |
| `clear-url-rules` | — | Удалить **все** правила для URL. |

#### Match types

`match-type` определяет, как шаблон правила сравнивается с текущим URL в
браузере. Правила обрабатываются **сверху вниз, и побеждает первое совпадение**,
поэтому их порядок задаёт их приоритет (перетаскивайте для изменения порядка в
**Настройки ▸ Правила для URL**).

| `match-type` | Pattern is… | Matches |
|---|---|---|
| `domain-suffix` *(default)* | хост, например `github.com` | этот хост **и все его поддомены** (`github.com`, `gist.github.com`). Ведущий `*.` допускается. |
| `domain` | хост, например `github.com` | **только этот точный хост**, без поддоменов. |
| `domain-keyword` | подстрока, например `google` | любой хост, который её **содержит** (`google.com`, `mail.google.com`, `googleapis.com`). |
| `url-regex` | регулярное выражение | **весь URL** (схема · хост · путь · запрос · фрагмент) — без учёта регистра и без привязки к началу/концу. Единственный тип, способный различать страницы одного сайта по пути или запросу. Шаблон, который не компилируется, отклоняется с ошибкой `invalid_parameter`. |

`match-type` также принимает псевдонимы вроде `suffix`, `keyword` и `regex`. В правиле
`url-regex` шаблон обычно содержит символы (`?`, `&`, `/`, `\`), которые нужно
кодировать процентами в URL.

### App

| Command | Parameters | Effect |
|---|---|---|
| `quit` | — | Завершить работу LockIME. |

(См. также [`set-language`](#general-settings) и [`set-launch-at-login`](#general-settings).)

LockIME намеренно не предоставляет **никаких команд, открывающих его интерфейс**
(Настройки, «О программе», окно обновлений): API предназначен для автоматизации
без участия интерфейса, а не для управления окнами.

### Queries

Команды-запросы возвращают полезную нагрузку в формате JSON через колбэк `x-success` (см.
[x-callback-url](#x-callback-url)).

| Command | Result |
|---|---|
| `status` | Всё состояние — см. [ниже](#status-payload). |
| `current-source` | `{ "id": "...", "name": "..." }` активного источника. |
| `list-sources` *(alias `sources`)* | Массив установленных источников: `{ "id", "name", "isCJKV", "isEnabled", "isSelectCapable" }`. |
| `list-app-rules` *(alias `app-rules`)* | Массив `{ "bundleID", "mode", "source"? }`. |
| `list-url-rules` *(alias `url-rules`)* | Массив `{ "id", "host", "action", "matchType", "source" }`, в порядке приоритета (побеждает первое совпадение). |
| `list-log` *(aliases `log`, `recent-activations`)* | Записи о принудительных переключениях за последние 24 ч, новейшие сначала: `{ "timestamp", "inputSource", "inputSourceName", "reason", "durationMs", "fromSourceName"?, "app"?, "bundleID"?, "ruleSource"?, "matchedHost"? }`. |
| `get-config` *(alias `config`)* | Полный сохранённый объект конфигурации. |
| `version` | `{ "version": "x.y.z", "build": "n" }`. |
| `ping` | `{ "ok": true, "app": "LockIME", "version": "x.y.z", "build": "n" }` — дешёвая проверка присутствия/версии. |

#### `status` payload

```json
{
  "enabled": true,
  "lockingEnabled": true,
  "locked": true,
  "enhancedMode": false,
  "launchAtLogin": true,
  "accessibilityGranted": true,
  "activationCount": 42,
  "language": "en",
  "version": "1.2.0",
  "build": "20260615",
  "currentSource": { "id": "com.apple.keylayout.ABC", "name": "ABC" },
  "defaultSource": { "id": "com.apple.keylayout.ABC", "name": "ABC" },
  "frontmostApp": "com.apple.Safari"
}
```

`enabled` — это главный переключатель («Включить LockIME»); `lockingEnabled` — вспомогательный переключатель непрерывной блокировки; `locked` равно `true`, только когда включены оба (блокировка действительно действует).
`currentSource`, `defaultSource` и `frontmostApp` присутствуют только когда известны.

---

## Errors

При сбое (и при наличии колбэка `x-error`) LockIME добавляет стабильный
машинный `errorCode` и человекочитаемое `errorMessage`. Текст ошибки **по замыслу
на английском и стабилен** — он переходит в ваше приложение и в журналы, поэтому никогда
не локализуется.

| `errorCode` | When |
|---|---|
| `api_disabled` | API выключен — включите его в «Настройки ▸ Основные ▸ Автоматизация». |
| `malformed_url` | URL не удалось разобрать. |
| `no_command` | Токен команды не был передан. |
| `unknown_command` | Токен команды не распознан. |
| `missing_parameter` | Обязательный параметр отсутствует. |
| `invalid_parameter` | Значение параметра вне допустимого диапазона (неверный `mode`, `action`, `match-type`, `direction`, `code`, не компилирующийся шаблон `url-regex` или некорректный UUID). |
| `unknown_source` | `id`/`name` не совпадает ни с одним установленным выбираемым источником. |
| `no_input_sources` | Не установлено ни одного выбираемого источника ввода. |
| `rule_not_found` | Указанное правило для приложения/URL не существует. |
| `not_supported` | Операцию не удалось завершить (например, сериализацию конфигурации). |

---

## Examples

**Shell / `open(1)`**

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
open "lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&action=switch"
open "lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&match-type=domain"
# url-regex сопоставляется со всем URL — закодируйте шаблон процентами (здесь: github\.com/.*/pull)
open "lockime://set-url-rule?pattern=github%5C.com%2F.%2A%2Fpull&source=com.apple.keylayout.ABC&match-type=url-regex"
open "lockime://set-launch-at-login?enabled=on"
```

**AppleScript**

```applescript
open location "lockime://toggle-lock"
```

**Shortcuts (macOS)**

Добавьте действие **Open URLs** с `lockime://lock` или **Get Contents of URL**
плюс форму x-callback-url, чтобы считать состояние обратно.

**Read status from a script** (с использованием приложения/URL-приёмника колбэка):

```sh
open "lockime://status?x-success=myreceiver%3A%2F%2Fstatus"
```

---

## Notes & guarantees

- **Идемпотентно и обратимо.** Повторная отправка команды безопасна; ничего не
  уничтожается, кроме тех изменений правил, о которых вы просите.
- **Никогда не перехватывает фокус.** Ни одна команда не выводит LockIME на
  передний план и не открывает ни одно из его окон — API по замыслу работает без
  участия интерфейса.
- **Блокировки остаются авторитетными.** `switch-source` — это разовое переключение
  из вежливости; действующая непрерывная блокировка вновь навяжет свой источник.
- **Идентичность источника — это `id`.** Отображаемые имена — это удобство и зависят от
  системной локали; для стабильной автоматизации предпочитайте `id` (из `list-sources`).
- **Резервные копии не включают API.** Экспорт/импорт конфигурации (файлы `.lockime`)
  охватывает ваши правила, а не что-либо специфичное для API, — отдельного состояния API
  для переноса не существует.
