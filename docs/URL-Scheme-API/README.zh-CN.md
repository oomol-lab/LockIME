# URL Scheme API

[English](README.md) · **简体中文** · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md)

LockIME 提供了一个 `lockime://` URL scheme，让其他应用、脚本、Shortcuts、
Stream Deck、Alfred/Raycast、AppleScript——任何能打开 URL 的东西——都能驱动它：
开关锁定、重新指定输入源、管理规则，并读回状态。

每条命令都是一个 URL，默认是发出即不管（fire-and-forget），并可选地附带
[x-callback-url](https://x-callback-url.com) 回调来处理成功/失败，以及从查询命令
返回数据。

> **请先启用它。** URL Scheme API **默认关闭**。请在 **LockIME ▸ 设置 ▸ 通用 ▸
> 自动化 ▸ URL Scheme API** 中开启它。在它关闭期间，每条命令都会返回
> `api_disabled` 错误，且什么都不会发生。

> **安全提示。** 一旦启用，命令执行时**不会有逐条确认**——任何能打开
> `lockime://` 链接的进程（包括一个网页）都能驱动 LockIME。每条命令都是可逆的，
> 且都不会触及你的文件；一个恶意调用者最多只能开关你的输入源锁定或编辑规则。
> 不使用时请把这个 API 关闭。

---

## URL shape

接受两种等价的形式：

```
lockime://<command>?<param>=<value>&<param>=<value>
lockime://x-callback-url/<command>?<param>=<value>&…
```

- **命令 token**（`<command>`）不区分大小写。
- **参数名**不区分大小写；**参数值**则按原样照取（因此 bundle ID 和 source ID
  会保留其大小写）。
- 对于包含保留字符（`?`、`&`、`=`、`/`、空格……）的值，请始终进行
  **百分号编码**。一个像 `ABC – Extended` 这样的输入源显示名会变成
  `name=ABC%20%E2%80%93%20Extended`。

`x-callback-url/` 前缀只是为 x-callback-url 工具准备的可选语法糖；下面的回调参数
在裸形式上同样有效。

> **开发构建。** LockIME 的 Debug 构建注册的是 `lockime-dev://` 而非
> `lockime://`，因此本地构建绝不会劫持已安装正式版的 scheme。其余一切都完全相同。

---

## x-callback-url

任何命令都可以携带这些保留参数：

| Parameter | Meaning |
|---|---|
| `x-success` | 命令成功后打开的 URL。对于**查询**命令，JSON 结果会以 `result=<json>`（经过百分号编码）的形式追加在后面。 |
| `x-error`   | 命令失败时打开的 URL，并在后面追加 `errorCode=<code>&errorMessage=<text>`。 |
| `x-source`  | 调用方应用的显示名（仅供参考；LockIME 会记录它）。 |

动作命令触发 `x-success` 时不带 `result`。查询命令通过 `x-success` 返回其负载；
若没有 `x-success` URL，查询就根本没有地方发送其结果（它仍会运行，且无害）。

往返示例——请求状态并把它接收回你自己的应用：

```
lockime://status?x-success=myapp%3A%2F%2Fgot-status
```

成功时 LockIME 会打开：

```
myapp://got-status?result=%7B%22locked%22%3Atrue%2C…%7D
```

---

## Command reference

### Enable & locking

主开关（`lock` / `unlock` / `toggle-lock`）用于开启或关闭 **LockIME**——它掌控着一切（锁定与切换都包括在内）。从属于主开关的 `set-locking` 子开关只控制**持续锁定**：把它关掉，就会停止固定任何输入源，而一次性的切换规则照常触发——也就是“表现得像一个纯切换器”的模式。

| Command | Parameters | Effect |
|---|---|---|
| `lock` | — | 开启 **LockIME**（主开关）——应用你的规则。 |
| `unlock` | — | 关闭 **LockIME**（主开关）——完全闲置。 |
| `toggle-lock` *(alias `toggle`)* | — | 翻转主开关的开/关。 |
| `set-locking` *(alias `locking`)* | `enabled` = `true` \| `false` \| `toggle` | 开启/关闭**持续锁定**（或翻转它）。关闭后 ⇒ 不固定任何东西，但切换规则仍会触发。当主开关关闭时无即时运行效果。 |

### Global input source

一个**输入源**由 `id`（规范的 Text Input Source 标识符，例如
`com.apple.keylayout.ABC`，由 [`list-sources`](#queries) 返回）或 `name`
（其本地化显示名，不区分大小写）来指定。它必须指向一个当前已安装、可选用的
输入源，否则命令会返回 `unknown_source`。

| Command | Parameters | Effect |
|---|---|---|
| `lock-to-source` | `id` \| `name` | 设置全局默认输入源**并**开启锁定。 |
| `set-default-source` | `id` \| `name` *(omit both to clear)* | 设置（或清除）全局默认输入源，而不改变开/关状态。 |
| `cycle-source` | `direction` = `next` \| `previous` | 将全局目标切换到下一个/上一个已安装的输入源（循环），并开启锁定。 |
| `switch-source` | `id` \| `name` | 立即将当前输入源切换**一次**，仅此一次——它**不会**开启或修改持续锁定。若此时已有持续锁定在生效，它会胜出，并把输入源切回锁定目标。 |

`direction` 还接受别名 `prev`、`forward`、`back`、`up`、`down`。

### Per-app rules

| Command | Parameters | Effect |
|---|---|---|
| `set-app-rule` | `bundle` *(req)*, `mode` = `lock` \| `switch` \| `ignore` \| `default` *(default `lock`)*, `source` \| `source-name` *(req for `lock`/`switch`)* | 为某个应用创建或替换规则。`lock` 会持续强制锁定该输入源；`switch` 会在激活时切换一次然后放手；`ignore` 会为该应用禁用锁定；`default` 则回退到全局默认。 |
| `remove-app-rule` | `bundle` *(req)* | 删除 `bundle` 的规则。若不存在则返回 `rule_not_found`。 |
| `cycle-app-source` | `direction` *(req)*, `bundle` *(optional; default = frontmost app)* | 将该应用自己的规则切换到下一个/上一个输入源。若该应用没有规则则为空操作（`rule_not_found`）。 |
| `remove-frontmost-app-rule` | — | 删除当前最前台应用的规则。 |
| `clear-app-rules` | — | 移除**所有**按应用规则。 |

### General settings

| Command | Parameters | Effect |
|---|---|---|
| `set-launch-at-login` *(alias `launch-at-login`)* | `enabled` = `true` \| `false` \| `toggle` | 将 LockIME 注册/取消注册为登录项。 |
| `set-language` | `code` = `en` \| `zh-Hans` \| `zh-Hant` \| `ja` \| `fr` \| `de` \| `es` \| `pt` \| `ru` \| `system` | 设置应用内的语言覆盖；`system`（别名 `auto`）会清除它并跟随 macOS 的语言。宽松匹配：`zh-CN`→`zh-Hans`、`zh-TW`→`zh-Hant`、`fr-CA`→`fr`，…… |

### Enhanced mode & per-URL rules

按 URL 规则需要可选的、受 Accessibility 把关的**增强模式**。

| Command | Parameters | Effect |
|---|---|---|
| `set-enhanced-mode` | `enabled` = `true` \| `false` \| `toggle` | 开启/关闭增强模式（或翻转它）。 |
| `set-url-rule` | `host` *(alias `pattern`, req)*, `source` \| `source-name` *(req)*, `match-type` = `domain-suffix` \| `domain` \| `domain-keyword` \| `url-regex` *(default `domain-suffix`)*, `action` = `lock` \| `switch` *(default `lock`)*, `id` *(optional UUID)* | 创建或替换一条按 URL 规则。模式如何匹配取决于 `match-type`（参见[下文](#match-types)）。若不带 `id`，则更新同一模式的现有规则，而不是新建重复项。 |
| `remove-url-rule` | `id` *(UUID)* \| `host` | 通过 `id`（来自 `list-url-rules`）或 `host` 删除一条 URL 规则。 |
| `clear-url-rules` | — | 移除**所有**按 URL 规则。 |

#### Match types

`match-type` 决定一条规则的模式如何与浏览器当前的 URL 进行比较。规则**从上到下
逐条求值，第一个命中者胜出**，所以它们的顺序就是优先级（在 **Settings ▸ URL
Rules** 中拖动以重排）。

| `match-type` | Pattern is… | Matches |
|---|---|---|
| `domain-suffix` *(default)* | 一个 host，如 `github.com` | 匹配该 host **及其所有子域名**（`github.com`、`gist.github.com`）。开头的 `*.` 会被容许。 |
| `domain` | 一个 host，如 `github.com` | **仅匹配该精确 host**，绝不匹配子域名。 |
| `domain-keyword` | 一个子串，如 `google` | 匹配任何**包含**它的 host（`google.com`、`mail.google.com`、`googleapis.com`）。 |
| `url-regex` | 一个正则表达式 | 匹配**整个 URL**（scheme · host · path · query · fragment）——不区分大小写且不锚定。这是唯一能按 path 或 query 区分同一站点不同页面的类型。无法编译的模式会以 `invalid_parameter` 被拒绝。 |

`match-type` 还接受 `suffix`、`keyword`、`regex` 等别名。对于一条 `url-regex`
规则，模式通常会包含必须在 URL 中进行百分号编码的字符（`?`、`&`、`/`、`\`）。

### App

| Command | Parameters | Effect |
|---|---|---|
| `quit` | — | 退出 LockIME。 |

（另见 [`set-language`](#general-settings) 和 [`set-launch-at-login`](#general-settings)。）

LockIME 刻意**不提供任何打开其 UI 的命令**（设置、关于、更新窗口）：这套 API 是
为无界面自动化设计的，而不是用来驱动窗口。

### Queries

查询命令通过 `x-success` 回调返回一个 JSON 负载（参见
[x-callback-url](#x-callback-url)）。

| Command | Result |
|---|---|
| `status` | 整个状态——参见[下文](#status-payload)。 |
| `current-source` | 实时输入源的 `{ "id": "...", "name": "..." }`。 |
| `list-sources` *(alias `sources`)* | 已安装输入源的数组：`{ "id", "name", "isCJKV", "isEnabled", "isSelectCapable" }`。 |
| `list-app-rules` *(alias `app-rules`)* | `{ "bundleID", "mode", "source"? }` 的数组。 |
| `list-url-rules` *(alias `url-rules`)* | `{ "id", "host", "action", "matchType", "source" }` 的数组，按优先级排序（第一个命中者胜出）。 |
| `list-log` *(aliases `log`, `recent-activations`)* | 最近 24 小时的强制切换记录，最新的在前：`{ "timestamp", "inputSource", "inputSourceName", "reason", "durationMs", "fromSourceName"?, "app"?, "bundleID"?, "ruleSource"?, "matchedHost"? }`。 |
| `get-config` *(alias `config`)* | 完整的持久化配置对象。 |
| `version` | `{ "version": "x.y.z", "build": "n" }`。 |
| `ping` | `{ "ok": true, "app": "LockIME", "version": "x.y.z", "build": "n" }`——一个廉价的存在性/版本探测。 |

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

`enabled` 即主开关（“启用 LockIME”）；`lockingEnabled` 是持续锁定子开关；只有当两者都开启时（确实有锁定在生效）`locked` 才为 `true`。
`currentSource`、`defaultSource` 和 `frontmostApp` 仅在已知时才会出现。

---

## Errors

失败时（且存在 `x-error` 回调时），LockIME 会追加一个稳定的、供机器使用的
`errorCode` 和一个供人阅读的 `errorMessage`。错误文本在设计上是**英文且稳定**
的——它会跨入你的应用并进入日志，所以从不本地化。

| `errorCode` | When |
|---|---|
| `api_disabled` | API 已关闭——请在“设置 ▸ 通用 ▸ 自动化”中启用它。 |
| `malformed_url` | URL 无法被解析。 |
| `no_command` | 未提供命令 token。 |
| `unknown_command` | 命令 token 无法识别。 |
| `missing_parameter` | 缺少某个必需参数。 |
| `invalid_parameter` | 某个参数值超出范围（错误的 `mode`、`action`、`match-type`、`direction`、`code`，一个无法编译的 `url-regex` 模式，或一个格式错误的 UUID）。 |
| `unknown_source` | `id`/`name` 没有匹配到任何已安装的可选用输入源。 |
| `no_input_sources` | 没有安装任何可选用的输入源。 |
| `rule_not_found` | 目标的应用/URL 规则不存在。 |
| `not_supported` | 操作无法完成（例如配置序列化）。 |

---

## Examples

**Shell / `open(1)`**

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
open "lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&action=switch"
open "lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&match-type=domain"
# url-regex 匹配整个 URL——请对模式进行百分号编码（此处为：github\.com/.*/pull）
open "lockime://set-url-rule?pattern=github%5C.com%2F.%2A%2Fpull&source=com.apple.keylayout.ABC&match-type=url-regex"
open "lockime://set-launch-at-login?enabled=on"
```

**AppleScript**

```applescript
open location "lockime://toggle-lock"
```

**Shortcuts (macOS)**

添加一个 **Open URLs** 动作并填入 `lockime://lock`，或者用 **Get Contents of URL**
加上 x-callback-url 形式来读回状态。

**从脚本读取状态**（使用一个回调接收方应用/URL）：

```sh
open "lockime://status?x-success=myreceiver%3A%2F%2Fstatus"
```

---

## Notes & guarantees

- **幂等且可逆。** 重新发送一条命令是安全的；除了你主动要求的规则编辑之外，
  不会破坏任何东西。
- **从不抢占焦点。** 没有任何命令会把 LockIME 带到前台或打开它的任何窗口——这套
  API 在设计上就是无界面的。
- **锁定保持权威。** `switch-source` 是一次性的礼让式切换；一个持续生效的连续
  锁定会重新强制其输入源。
- **输入源的身份是 `id`。** 显示名只是为了方便，且依赖于系统语言环境；为了实现
  稳定的自动化，请优先使用 `id`（来自 `list-sources`）。
- **备份不包含 API。** 配置导出/导入（`.lockime` 文件）涵盖的是你的规则，而非
  任何与 API 相关的内容——没有单独的 API 状态需要携带。
