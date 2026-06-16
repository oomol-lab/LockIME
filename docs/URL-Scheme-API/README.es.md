# URL Scheme API

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · **Español** · [Português](README.pt.md) · [Русский](README.ru.md)

LockIME expone un esquema de URL `lockime://` para que otras aplicaciones, scripts, Shortcuts,
Stream Deck, Alfred/Raycast, AppleScript — cualquier cosa que pueda abrir una URL — puedan
controlarlo: activar o desactivar el bloqueo, recambiar la fuente de entrada, gestionar reglas y leer
el estado de vuelta.

Cada comando es una URL, fire-and-forget por defecto, con callbacks opcionales de
[x-callback-url](https://x-callback-url.com) para el éxito o el error y para
devolver datos desde los comandos de consulta.

> **Actívala primero.** La URL Scheme API está **desactivada por defecto**. Actívala en
> **LockIME ▸ Ajustes ▸ General ▸ Automatización ▸ URL Scheme API**. Mientras esté desactivada,
> cada comando devuelve el error `api_disabled` y no ocurre nada.

> **Nota de seguridad.** Una vez activada, los comandos se ejecutan **sin una confirmación
> por comando** — cualquier proceso que pueda abrir una URL `lockime://` (incluida una página
> web) puede controlar LockIME. Todos los comandos son reversibles y ninguno toca tus archivos;
> lo peor que puede hacer un llamador malintencionado es activar o desactivar el bloqueo de tu
> fuente de entrada o editar reglas. Mantén la API desactivada cuando no la estés usando.

---

## URL shape

Se aceptan dos formas equivalentes:

```
lockime://<command>?<param>=<value>&<param>=<value>
lockime://x-callback-url/<command>?<param>=<value>&…
```

- El **token de comando** (`<command>`) no distingue entre mayúsculas y minúsculas.
- Los **nombres de parámetro** no distinguen entre mayúsculas y minúsculas; los **valores de parámetro** se toman
  literalmente (así los bundle IDs y los source IDs conservan sus mayúsculas y minúsculas).
- Codifica siempre con **percent-encode** los valores que contengan caracteres reservados
  (`?`, `&`, `=`, `/`, espacios, …). Un nombre visible de fuente como `ABC – Extended`
  se convierte en `name=ABC%20%E2%80%93%20Extended`.

El prefijo `x-callback-url/` es azúcar opcional para las herramientas de x-callback-url; los
parámetros de callback de más abajo también funcionan en la forma simple.

> **Compilaciones de desarrollo.** Una compilación Debug de LockIME registra `lockime-dev://`
> en lugar de `lockime://`, de modo que una compilación local nunca secuestra el esquema de la
> versión instalada. Todo lo demás es idéntico.

---

## x-callback-url

Cualquier comando puede llevar estos parámetros reservados:

| Parameter | Meaning |
|---|---|
| `x-success` | URL que se abre después de que el comando tiene éxito. Para los comandos de **consulta** el resultado JSON se añade como `result=<json>` (codificado con percent-encode). |
| `x-error`   | URL que se abre si el comando falla, con `errorCode=<code>&errorMessage=<text>` añadido. |
| `x-source`  | Un nombre visible de la aplicación que llama (informativo; LockIME lo registra). |

Los comandos de acción disparan `x-success` sin `result`. Los comandos de consulta devuelven su
carga útil a través de `x-success`; sin una URL `x-success` una consulta simplemente no tiene
adónde enviar su resultado (igual se ejecuta, sin causar daño).

Ejemplo de ida y vuelta — solicita el estado y recíbelo de vuelta en tu propia aplicación:

```
lockime://status?x-success=myapp%3A%2F%2Fgot-status
```

Si tiene éxito, LockIME abre:

```
myapp://got-status?result=%7B%22locked%22%3Atrue%2C…%7D
```

---

## Command reference

### Master lock

| Command | Parameters | Effect |
|---|---|---|
| `lock` | — | Activa el bloqueo maestro (**on**). |
| `unlock` | — | Desactiva el bloqueo maestro (**off**). |
| `toggle-lock` *(alias `toggle`)* | — | Invierte el bloqueo maestro. |

### Global input source

Una **fuente** se identifica por `id` (el identificador canónico de Text Input Source, p. ej.
`com.apple.keylayout.ABC`, tal como lo devuelve [`list-sources`](#queries)) o por
`name` (su nombre visible localizado, sin distinguir mayúsculas y minúsculas). Debe nombrar una fuente
instalada y seleccionable actualmente, o el comando devuelve `unknown_source`.

| Command | Parameters | Effect |
|---|---|---|
| `lock-to-source` | `id` \| `name` | Establece la fuente predeterminada global **y** activa el bloqueo. |
| `set-default-source` | `id` \| `name` *(omite ambos para borrarla)* | Establece (o borra) la fuente predeterminada global sin cambiar el estado activado/desactivado. |
| `cycle-source` | `direction` = `next` \| `previous` | Avanza el objetivo global a la fuente instalada siguiente/anterior (con vuelta al inicio) y activa el bloqueo. |
| `switch-source` | `id` \| `name` | Cambia la fuente de entrada actual **una sola vez**, ahora mismo: **no** activa ni modifica ningún bloqueo continuo. Si ya hay un bloqueo continuo activo, este prevalece y devuelve la fuente a su objetivo. |

`direction` también acepta los alias `prev`, `forward`, `back`, `up`, `down`.

### Per-app rules

| Command | Parameters | Effect |
|---|---|---|
| `set-app-rule` | `bundle` *(req)*, `mode` = `lock` \| `switch` \| `ignore` \| `default` *(default `lock`)*, `source` \| `source-name` *(req for `lock`/`switch`)* | Crea o reemplaza la regla de una aplicación. `lock` aplica la fuente de forma continua; `switch` cambia una vez al activarse y luego la suelta; `ignore` desactiva el bloqueo para esa aplicación; `default` recurre a la fuente predeterminada global. |
| `remove-app-rule` | `bundle` *(req)* | Elimina la regla de `bundle`. `rule_not_found` si no hay ninguna. |
| `cycle-app-source` | `direction` *(req)*, `bundle` *(optional; default = frontmost app)* | Avanza la propia regla de esa aplicación a la fuente siguiente/anterior. No hace nada (`rule_not_found`) si la aplicación no tiene regla. |
| `remove-frontmost-app-rule` | — | Elimina la regla de la aplicación que esté en primer plano. |
| `clear-app-rules` | — | Elimina **todas** las reglas por aplicación. |

### General settings

| Command | Parameters | Effect |
|---|---|---|
| `set-launch-at-login` *(alias `launch-at-login`)* | `enabled` = `true` \| `false` \| `toggle` | Registra/anula el registro de LockIME como elemento de inicio de sesión. |
| `set-language` | `code` = `en` \| `zh-Hans` \| `zh-Hant` \| `ja` \| `fr` \| `de` \| `es` \| `pt` \| `ru` \| `system` | Establece la anulación de idioma en la aplicación; `system` (alias `auto`) la borra y sigue el idioma de macOS. Indulgente: `zh-CN`→`zh-Hans`, `zh-TW`→`zh-Hant`, `fr-CA`→`fr`, … |

### Enhanced mode & per-URL rules

Las reglas por URL requieren el **modo mejorado** opcional protegido por Accessibility.

| Command | Parameters | Effect |
|---|---|---|
| `set-enhanced-mode` | `enabled` = `true` \| `false` \| `toggle` | Activa o desactiva el modo mejorado (o lo invierte). |
| `set-url-rule` | `host` *(req)*, `source` \| `source-name` *(req)*, `action` = `lock` \| `switch` *(default `lock`)*, `id` *(optional UUID)* | Crea o reemplaza una regla por URL. `host` es un patrón como `github.com` (coincide con subdominios) o `*.example.com`. Sin `id`, se actualiza una regla existente del mismo host en lugar de duplicarla. |
| `remove-url-rule` | `id` *(UUID)* \| `host` | Elimina una regla de URL por su `id` (de `list-url-rules`) o por `host`. |
| `clear-url-rules` | — | Elimina **todas** las reglas por URL. |

### App

| Command | Parameters | Effect |
|---|---|---|
| `quit` | — | Cierra LockIME. |

(Ver también [`set-language`](#general-settings) y [`set-launch-at-login`](#general-settings).)

LockIME no expone deliberadamente **ningún comando que abra su interfaz** (Ajustes, Acerca de,
ventana de actualización): la API es para automatización sin interfaz, no para controlar ventanas.

### Queries

Los comandos de consulta devuelven una carga útil JSON a través del callback `x-success` (ver
[x-callback-url](#x-callback-url)).

| Command | Result |
|---|---|
| `status` | El estado completo — ver [más abajo](#status-payload). |
| `current-source` | `{ "id": "...", "name": "..." }` de la fuente activa. |
| `list-sources` *(alias `sources`)* | Array de fuentes instaladas: `{ "id", "name", "isCJKV", "isEnabled", "isSelectCapable" }`. |
| `list-app-rules` *(alias `app-rules`)* | Array de `{ "bundleID", "mode", "source"? }`. |
| `list-url-rules` *(alias `url-rules`)* | Array de `{ "id", "host", "action", "source" }`. |
| `list-log` *(aliases `log`, `recent-activations`)* | Las últimas 24 h de entradas de cambio forzado, las más recientes primero: `{ "timestamp", "inputSource", "inputSourceName", "reason", "durationMs", "fromSourceName"?, "app"?, "bundleID"?, "ruleSource"?, "matchedHost"? }`. |
| `get-config` *(alias `config`)* | El objeto de configuración persistido completo. |
| `version` | `{ "version": "x.y.z", "build": "n" }`. |
| `ping` | `{ "ok": true, "app": "LockIME", "version": "x.y.z", "build": "n" }` — una sonda barata de presencia/versión. |

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

`currentSource`, `defaultSource` y `frontmostApp` están presentes solo cuando se conocen.

---

## Errors

En caso de fallo (y si hay un callback `x-error` presente) LockIME añade un `errorCode`
estable para máquinas y un `errorMessage` para humanos. El texto de error es **inglés y
estable** por diseño — cruza hacia tu aplicación y hacia los registros, por lo que nunca se
localiza.

| `errorCode` | When |
|---|---|
| `api_disabled` | La API está desactivada — actívala en Ajustes ▸ General ▸ Automatización. |
| `malformed_url` | No se pudo analizar la URL. |
| `no_command` | No se proporcionó ningún token de comando. |
| `unknown_command` | El token de comando no se reconoce. |
| `missing_parameter` | Falta un parámetro obligatorio. |
| `invalid_parameter` | El valor de un parámetro está fuera de rango (`mode`, `action`, `direction`, `code` o UUID incorrecto). |
| `unknown_source` | El `id`/`name` no coincide con ninguna fuente instalada y seleccionable. |
| `no_input_sources` | No hay ninguna fuente de entrada seleccionable instalada. |
| `rule_not_found` | La regla por aplicación/URL indicada no existe. |
| `not_supported` | La operación no se pudo completar (p. ej. la serialización de la configuración). |

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

Añade una acción **Open URLs** con `lockime://lock`, o **Get Contents of URL**
más la forma de x-callback-url para leer el estado de vuelta.

**Leer el estado desde un script** (usando una aplicación/URL receptora del callback):

```sh
open "lockime://status?x-success=myreceiver%3A%2F%2Fstatus"
```

---

## Notes & guarantees

- **Idempotente y reversible.** Reenviar un comando es seguro; no se destruye
  nada más allá de las ediciones de reglas que solicites.
- **Nunca roba el foco.** Ningún comando trae LockIME al primer plano ni abre
  ninguna de sus ventanas — la API es sin interfaz por diseño.
- **Los bloqueos siguen siendo la autoridad.** `switch-source` es un cambio de cortesía de
  una sola vez; un bloqueo continuo en vigor volverá a imponer su fuente.
- **La identidad de la fuente es el `id`.** Los nombres visibles son una comodidad y dependen del
  idioma del sistema; prefiere `id` (de `list-sources`) para una automatización estable.
- **Las copias de seguridad no incluyen la API.** La exportación/importación de la configuración (archivos `.lockime`)
  cubre tus reglas, no nada específico de la API — no hay un estado de API separado
  que transportar.
