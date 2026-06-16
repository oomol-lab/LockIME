# URL Scheme API

**English** · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md)

LockIME exposes a `lockime://` URL scheme so other apps, scripts, Shortcuts,
Stream Deck, Alfred/Raycast, AppleScript — anything that can open a URL — can
drive it: toggle locking, retarget the input source, manage rules, and read
state back.

Each command is a URL, fire-and-forget by default, with optional
[x-callback-url](https://x-callback-url.com) callbacks for success/error and for
returning data from query commands.

> **Enable it first.** The URL scheme API is **off by default**. Turn it on in
> **LockIME ▸ Settings ▸ General ▸ Automation ▸ URL Scheme API**. While it is off,
> every command returns the `api_disabled` error and nothing happens.

> **Security note.** Once enabled, commands run **without a per-command
> confirmation** — any process that can open a `lockime://` URL (including a web
> page) can drive LockIME. Every command is reversible and none touch your files;
> the worst a rogue caller can do is toggle your input-source lock or edit rules.
> Leave the API off when you are not using it.

---

## URL shape

Two equivalent forms are accepted:

```
lockime://<command>?<param>=<value>&<param>=<value>
lockime://x-callback-url/<command>?<param>=<value>&…
```

- The **command token** (`<command>`) is case-insensitive.
- **Parameter names** are case-insensitive; **parameter values** are taken
  verbatim (so bundle IDs and source IDs keep their case).
- Always **percent-encode** values that contain reserved characters
  (`?`, `&`, `=`, `/`, spaces, …). A source display name like `ABC – Extended`
  becomes `name=ABC%20%E2%80%93%20Extended`.

The `x-callback-url/` prefix is optional sugar for x-callback-url tooling; the
callback parameters below work on the bare form too.

> **Development builds.** A Debug build of LockIME registers `lockime-dev://`
> instead of `lockime://`, so a local build never hijacks the installed
> release's scheme. Everything else is identical.

---

## x-callback-url

Any command may carry these reserved parameters:

| Parameter | Meaning |
|---|---|
| `x-success` | URL opened after the command succeeds. For **query** commands the JSON result is appended as `result=<json>` (percent-encoded). |
| `x-error`   | URL opened if the command fails, with `errorCode=<code>&errorMessage=<text>` appended. |
| `x-source`  | A display name for the calling app (informational; LockIME logs it). |

Action commands fire `x-success` with no `result`. Query commands return their
payload through `x-success`; without an `x-success` URL a query simply has
nowhere to send its result (it still runs, harmlessly).

Example round-trip — ask for status and receive it back into your own app:

```
lockime://status?x-success=myapp%3A%2F%2Fgot-status
```

On success LockIME opens:

```
myapp://got-status?result=%7B%22locked%22%3Atrue%2C…%7D
```

---

## Command reference

### Master lock

| Command | Parameters | Effect |
|---|---|---|
| `lock` | — | Turn the master lock **on**. |
| `unlock` | — | Turn the master lock **off**. |
| `toggle-lock` *(alias `toggle`)* | — | Flip the master lock. |

### Global input source

A **source** is named by `id` (the canonical Text Input Source identifier, e.g.
`com.apple.keylayout.ABC`, as returned by [`list-sources`](#queries)) or by
`name` (its localized display name, case-insensitive). It must name a currently
installed, selectable source or the command returns `unknown_source`.

| Command | Parameters | Effect |
|---|---|---|
| `lock-to-source` | `id` \| `name` | Set the global default source **and** turn locking on. |
| `set-default-source` | `id` \| `name` *(omit both to clear)* | Set (or clear) the global default source without changing the on/off state. |
| `cycle-source` | `direction` = `next` \| `previous` | Step the global target to the next/previous installed source (wrapping) and turn locking on. |
| `switch-source` | `id` \| `name` | Switch the current input source **once**, right now — it does **not** turn on or change a continuous lock. If a continuous lock is already active, it wins and switches the source back to its target. |

`direction` also accepts the aliases `prev`, `forward`, `back`, `up`, `down`.

### Per-app rules

| Command | Parameters | Effect |
|---|---|---|
| `set-app-rule` | `bundle` *(req)*, `mode` = `lock` \| `switch` \| `ignore` \| `default` *(default `lock`)*, `source` \| `source-name` *(req for `lock`/`switch`)* | Create or replace the rule for an app. `lock` continuously enforces the source; `switch` switches once on activation then releases; `ignore` disables locking for that app; `default` falls back to the global default. |
| `remove-app-rule` | `bundle` *(req)* | Delete the rule for `bundle`. `rule_not_found` if there is none. |
| `cycle-app-source` | `direction` *(req)*, `bundle` *(optional; default = frontmost app)* | Step that app's own rule to the next/previous source. No-op (`rule_not_found`) if the app has no rule. |
| `remove-frontmost-app-rule` | — | Delete the rule for whichever app is frontmost. |
| `clear-app-rules` | — | Remove **all** per-app rules. |

### General settings

| Command | Parameters | Effect |
|---|---|---|
| `set-launch-at-login` *(alias `launch-at-login`)* | `enabled` = `true` \| `false` \| `toggle` | Register/unregister LockIME as a login item. |
| `set-language` | `code` = `en` \| `zh-Hans` \| `zh-Hant` \| `ja` \| `fr` \| `de` \| `es` \| `pt` \| `ru` \| `system` | Set the in-app language override; `system` (alias `auto`) clears it and follows the macOS language. Lenient: `zh-CN`→`zh-Hans`, `zh-TW`→`zh-Hant`, `fr-CA`→`fr`, … |

### Enhanced mode & per-URL rules

Per-URL rules require the optional Accessibility-gated **enhanced mode**.

| Command | Parameters | Effect |
|---|---|---|
| `set-enhanced-mode` | `enabled` = `true` \| `false` \| `toggle` | Turn enhanced mode on/off (or flip it). |
| `set-url-rule` | `host` *(req)*, `source` \| `source-name` *(req)*, `action` = `lock` \| `switch` *(default `lock`)*, `id` *(optional UUID)* | Create or replace a per-URL rule. `host` is a pattern like `github.com` (matches subdomains) or `*.example.com`. Without `id`, an existing rule for the same host is updated rather than duplicated. |
| `remove-url-rule` | `id` *(UUID)* \| `host` | Delete a URL rule by its `id` (from `list-url-rules`) or by `host`. |
| `clear-url-rules` | — | Remove **all** per-URL rules. |

### App

| Command | Parameters | Effect |
|---|---|---|
| `quit` | — | Quit LockIME. |

(See also [`set-language`](#general-settings) and [`set-launch-at-login`](#general-settings).)

LockIME deliberately exposes **no commands that open its UI** (Settings, About,
update window): the API is for headless automation, not for driving windows.

### Queries

Query commands return a JSON payload through the `x-success` callback (see
[x-callback-url](#x-callback-url)).

| Command | Result |
|---|---|
| `status` | The whole state — see [below](#status-payload). |
| `current-source` | `{ "id": "...", "name": "..." }` of the live source. |
| `list-sources` *(alias `sources`)* | Array of installed sources: `{ "id", "name", "isCJKV", "isEnabled", "isSelectCapable" }`. |
| `list-app-rules` *(alias `app-rules`)* | Array of `{ "bundleID", "mode", "source"? }`. |
| `list-url-rules` *(alias `url-rules`)* | Array of `{ "id", "host", "action", "source" }`. |
| `list-log` *(aliases `log`, `recent-activations`)* | The last 24 h of forced-switch entries, newest first: `{ "timestamp", "inputSource", "inputSourceName", "reason", "durationMs", "fromSourceName"?, "app"?, "bundleID"?, "ruleSource"?, "matchedHost"? }`. |
| `get-config` *(alias `config`)* | The full persisted configuration object. |
| `version` | `{ "version": "x.y.z", "build": "n" }`. |
| `ping` | `{ "ok": true, "app": "LockIME", "version": "x.y.z", "build": "n" }` — a cheap presence/version probe. |

#### `status` payload

```json
{
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

`currentSource`, `defaultSource`, and `frontmostApp` are present only when known.

---

## Errors

On failure (and with an `x-error` callback present) LockIME appends a stable
machine `errorCode` and a human `errorMessage`. Error text is **English and
stable** by design — it crosses into your app and into logs, so it is never
localized.

| `errorCode` | When |
|---|---|
| `api_disabled` | The API is off — enable it in Settings ▸ General ▸ Automation. |
| `malformed_url` | The URL could not be parsed. |
| `no_command` | No command token was supplied. |
| `unknown_command` | The command token is not recognized. |
| `missing_parameter` | A required parameter is absent. |
| `invalid_parameter` | A parameter value is out of range (bad `mode`, `action`, `direction`, `code`, or UUID). |
| `unknown_source` | The `id`/`name` matches no installed selectable source. |
| `no_input_sources` | No selectable input sources are installed. |
| `rule_not_found` | The targeted app/URL rule does not exist. |
| `not_supported` | The operation could not be completed (e.g. config serialization). |

---

## Examples

**Shell / `open(1)`**

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
open "lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&action=switch"
open "lockime://set-launch-at-login?enabled=on"
```

**AppleScript**

```applescript
open location "lockime://toggle-lock"
```

**Shortcuts (macOS)**

Add an **Open URLs** action with `lockime://lock`, or **Get Contents of URL**
plus the x-callback-url form to read state back.

**Read status from a script** (using a callback receiver app/URL):

```sh
open "lockime://status?x-success=myreceiver%3A%2F%2Fstatus"
```

---

## Notes & guarantees

- **Idempotent and reversible.** Re-sending a command is safe; nothing is
  destroyed beyond rule edits you ask for.
- **Never steals focus.** No command brings LockIME to the foreground or opens
  any of its windows — the API is headless by design.
- **Locks stay authoritative.** `switch-source` is a one-shot courtesy switch; a
  standing continuous lock will re-assert its source.
- **Source identity is the `id`.** Display names are a convenience and depend on
  the system locale; prefer `id` (from `list-sources`) for stable automation.
- **Backups don't include the API.** Config export/import (`.lockime` files)
  covers your rules, not anything API-specific — there is no separate API state
  to carry.
