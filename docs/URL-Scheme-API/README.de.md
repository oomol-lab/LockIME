# URL Scheme API

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Français](README.fr.md) · **Deutsch** · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md)

LockIME stellt ein `lockime://`-URL-Schema bereit, damit andere Apps, Skripte,
Kurzbefehle, Stream Deck, Alfred/Raycast, AppleScript — alles, was eine URL
öffnen kann — es steuern können: das Sperren umschalten, die Eingabequelle neu
festlegen, Regeln verwalten und den Zustand auslesen.

Jeder Befehl ist eine URL, standardmäßig nach dem Prinzip „abschicken und vergessen",
mit optionalen [x-callback-url](https://x-callback-url.com)-Rückrufen für
Erfolg/Fehler und zur Rückgabe von Daten aus Abfragebefehlen.

> **Zuerst aktivieren.** Die URL Scheme API ist **standardmäßig aus**. Schalte sie
> unter **LockIME ▸ Einstellungen ▸ Allgemein ▸ Automatisierung ▸ URL Scheme API**
> ein. Solange sie aus ist, gibt jeder Befehl den Fehler `api_disabled` zurück und
> nichts passiert.

> **Sicherheitshinweis.** Einmal aktiviert, laufen Befehle **ohne Bestätigung pro
> Befehl** — jeder Prozess, der eine `lockime://`-URL öffnen kann (einschließlich
> einer Webseite), kann LockIME steuern. Jeder Befehl ist umkehrbar und keiner
> rührt deine Dateien an; das Schlimmste, was ein bösartiger Aufrufer tun kann, ist
> deine Eingabequellen-Sperre umzuschalten oder Regeln zu bearbeiten. Lass die API
> aus, wenn du sie nicht nutzt.

---

## URL shape

Zwei gleichwertige Formen werden akzeptiert:

```
lockime://<command>?<param>=<value>&<param>=<value>
lockime://x-callback-url/<command>?<param>=<value>&…
```

- Das **Befehlstoken** (`<command>`) ist nicht zwischen Groß- und Kleinschreibung
  unterscheidend.
- **Parameternamen** sind nicht zwischen Groß- und Kleinschreibung
  unterscheidend; **Parameterwerte** werden wörtlich übernommen (sodass Bundle-IDs
  und Source-IDs ihre Schreibweise behalten).
- Werte, die reservierte Zeichen enthalten (`?`, `&`, `=`, `/`, Leerzeichen, …),
  müssen immer **prozentkodiert** werden. Ein Anzeigename einer Quelle wie
  `ABC – Extended` wird zu `name=ABC%20%E2%80%93%20Extended`.

Das Präfix `x-callback-url/` ist optionaler Zucker für x-callback-url-Tools; die
folgenden Callback-Parameter funktionieren auch mit der bloßen Form.

> **Entwicklungs-Builds.** Ein Debug-Build von LockIME registriert
> `lockime-dev://` statt `lockime://`, sodass ein lokaler Build niemals das Schema
> des installierten Release entführt. Alles andere ist identisch.

---

## x-callback-url

Jeder Befehl darf diese reservierten Parameter mitführen:

| Parameter | Meaning |
|---|---|
| `x-success` | URL, die geöffnet wird, nachdem der Befehl erfolgreich war. Bei **Abfrage**befehlen wird das JSON-Ergebnis als `result=<json>` (prozentkodiert) angehängt. |
| `x-error`   | URL, die geöffnet wird, falls der Befehl fehlschlägt, mit angehängtem `errorCode=<code>&errorMessage=<text>`. |
| `x-source`  | Ein Anzeigename für die aufrufende App (informativ; LockIME protokolliert ihn). |

Aktionsbefehle lösen `x-success` ohne `result` aus. Abfragebefehle geben ihre
Nutzlast über `x-success` zurück; ohne eine `x-success`-URL hat eine Abfrage
schlicht keinen Ort, an den sie ihr Ergebnis schicken kann (sie läuft dennoch,
harmlos).

Beispiel für einen Hin- und Rückweg — den Status abfragen und ihn in der eigenen
App empfangen:

```
lockime://status?x-success=myapp%3A%2F%2Fgot-status
```

Bei Erfolg öffnet LockIME:

```
myapp://got-status?result=%7B%22locked%22%3Atrue%2C…%7D
```

---

## Command reference

### Master lock

| Command | Parameters | Effect |
|---|---|---|
| `lock` | — | Die Hauptsperre **einschalten**. |
| `unlock` | — | Die Hauptsperre **ausschalten**. |
| `toggle-lock` *(alias `toggle`)* | — | Die Hauptsperre umschalten. |

### Global input source

Eine **Quelle** wird über `id` (die kanonische Text Input Source-Kennung, z. B.
`com.apple.keylayout.ABC`, wie von [`list-sources`](#queries) zurückgegeben) oder
über `name` (ihren lokalisierten Anzeigenamen, nicht zwischen Groß- und
Kleinschreibung unterscheidend) benannt. Sie muss eine derzeit installierte,
auswählbare Quelle benennen, sonst gibt der Befehl `unknown_source` zurück.

| Command | Parameters | Effect |
|---|---|---|
| `lock-to-source` | `id` \| `name` | Die globale Standardquelle festlegen **und** das Sperren einschalten. |
| `set-default-source` | `id` \| `name` *(beide weglassen zum Löschen)* | Die globale Standardquelle festlegen (oder löschen), ohne den Ein/Aus-Zustand zu ändern. |
| `cycle-source` | `direction` = `next` \| `previous` | Das globale Ziel zur nächsten/vorherigen installierten Quelle (umlaufend) weiterschalten und das Sperren einschalten. |
| `switch-source` | `id` \| `name` | Schaltet die aktuelle Eingabequelle **einmalig**, sofort, um — eine kontinuierliche Sperre wird dabei **weder aktiviert noch geändert**. Ist bereits eine kontinuierliche Sperre aktiv, gewinnt sie und schaltet die Quelle auf ihr Ziel zurück. |

`direction` akzeptiert auch die Aliasse `prev`, `forward`, `back`, `up`, `down`.

### Per-app rules

| Command | Parameters | Effect |
|---|---|---|
| `set-app-rule` | `bundle` *(erf.)*, `mode` = `lock` \| `switch` \| `ignore` \| `default` *(Standard `lock`)*, `source` \| `source-name` *(erf. für `lock`/`switch`)* | Die Regel für eine App erstellen oder ersetzen. `lock` erzwingt die Quelle kontinuierlich; `switch` wechselt bei Aktivierung einmalig und gibt dann frei; `ignore` deaktiviert das Sperren für diese App; `default` fällt auf die globale Standardquelle zurück. |
| `remove-app-rule` | `bundle` *(erf.)* | Die Regel für `bundle` löschen. `rule_not_found`, wenn keine vorhanden ist. |
| `cycle-app-source` | `direction` *(erf.)*, `bundle` *(optional; Standard = vorderste App)* | Die eigene Regel dieser App zur nächsten/vorherigen Quelle weiterschalten. Wirkungslos (`rule_not_found`), wenn die App keine Regel hat. |
| `remove-frontmost-app-rule` | — | Die Regel für die jeweils vorderste App löschen. |
| `clear-app-rules` | — | **Alle** Regeln pro App entfernen. |

### General settings

| Command | Parameters | Effect |
|---|---|---|
| `set-launch-at-login` *(alias `launch-at-login`)* | `enabled` = `true` \| `false` \| `toggle` | LockIME als Anmeldeobjekt registrieren/deregistrieren. |
| `set-language` | `code` = `en` \| `zh-Hans` \| `zh-Hant` \| `ja` \| `fr` \| `de` \| `es` \| `pt` \| `ru` \| `system` | Die in-App-Sprachüberschreibung festlegen; `system` (alias `auto`) löscht sie und folgt der macOS-Sprache. Nachsichtig: `zh-CN`→`zh-Hans`, `zh-TW`→`zh-Hant`, `fr-CA`→`fr`, … |

### Enhanced mode & per-URL rules

Regeln pro URL erfordern den optionalen, über Accessibility freigeschalteten
**erweiterten Modus**.

| Command | Parameters | Effect |
|---|---|---|
| `set-enhanced-mode` | `enabled` = `true` \| `false` \| `toggle` | Den erweiterten Modus ein-/ausschalten (oder umschalten). |
| `set-url-rule` | `host` *(Alias `pattern`, erf.)*, `source` \| `source-name` *(erf.)*, `match-type` = `domain-suffix` \| `domain` \| `domain-keyword` \| `url-regex` *(Standard `domain-suffix`)*, `action` = `lock` \| `switch` *(Standard `lock`)*, `id` *(optionale UUID)* | Eine Regel pro URL erstellen oder ersetzen. Wie das Muster verglichen wird, hängt von `match-type` ab (siehe [unten](#match-types)). Ohne `id` wird eine bestehende Regel für dasselbe Muster aktualisiert statt dupliziert. |
| `remove-url-rule` | `id` *(UUID)* \| `host` | Eine URL-Regel über ihre `id` (aus `list-url-rules`) oder über `host` löschen. |
| `clear-url-rules` | — | **Alle** Regeln pro URL entfernen. |

#### Match types

`match-type` entscheidet, wie das Muster einer Regel mit der aktuellen URL des
Browsers verglichen wird. Regeln werden **von oben nach unten ausgewertet, und der
erste Treffer gewinnt**, sodass ihre Reihenfolge ihre Priorität ist (zum Umordnen
unter **Einstellungen ▸ URL-Regeln** ziehen).

| `match-type` | Pattern is… | Matches |
|---|---|---|
| `domain-suffix` *(default)* | ein Host, z. B. `github.com` | den Host **und alle seine Subdomains** (`github.com`, `gist.github.com`). Ein führendes `*.` wird toleriert. |
| `domain` | ein Host, z. B. `github.com` | **nur genau diesen Host**, niemals eine Subdomain. |
| `domain-keyword` | eine Teilzeichenkette, z. B. `google` | jeden Host, der sie **enthält** (`google.com`, `mail.google.com`, `googleapis.com`). |
| `url-regex` | ein regulärer Ausdruck | die **gesamte URL** (Schema · Host · Pfad · Query · Fragment) — ohne Beachtung der Groß-/Kleinschreibung und nicht verankert. Der einzige Typ, der Seiten einer Website nach Pfad oder Query unterscheiden kann. Ein nicht kompilierbares Muster wird mit `invalid_parameter` abgelehnt. |

`match-type` akzeptiert auch Aliasse wie `suffix`, `keyword` und `regex`. Bei einer
`url-regex`-Regel enthält das Muster meist Zeichen (`?`, `&`, `/`, `\`), die in der
URL prozentkodiert werden müssen.

### App

| Command | Parameters | Effect |
|---|---|---|
| `quit` | — | LockIME beenden. |

(Siehe auch [`set-language`](#general-settings) und [`set-launch-at-login`](#general-settings).)

LockIME stellt bewusst **keine Befehle bereit, die seine Oberfläche öffnen**
(Settings, About, Update-Fenster): Die API dient der kopflosen Automatisierung,
nicht dem Steuern von Fenstern.

### Queries

Abfragebefehle geben eine JSON-Nutzlast über den `x-success`-Rückruf zurück
(siehe [x-callback-url](#x-callback-url)).

| Command | Result |
|---|---|
| `status` | Der gesamte Zustand — siehe [unten](#status-payload). |
| `current-source` | `{ "id": "...", "name": "..." }` der aktiven Quelle. |
| `list-sources` *(alias `sources`)* | Array installierter Quellen: `{ "id", "name", "isCJKV", "isEnabled", "isSelectCapable" }`. |
| `list-app-rules` *(alias `app-rules`)* | Array von `{ "bundleID", "mode", "source"? }`. |
| `list-url-rules` *(alias `url-rules`)* | Array von `{ "id", "host", "action", "matchType", "source" }`, in Prioritätsreihenfolge (der erste Treffer gewinnt). |
| `list-log` *(aliases `log`, `recent-activations`)* | Die letzten 24 h an Zwangsumschaltungs-Einträgen, neueste zuerst: `{ "timestamp", "inputSource", "inputSourceName", "reason", "durationMs", "fromSourceName"?, "app"?, "bundleID"?, "ruleSource"?, "matchedHost"? }`. |
| `get-config` *(alias `config`)* | Das vollständige persistierte Konfigurationsobjekt. |
| `version` | `{ "version": "x.y.z", "build": "n" }`. |
| `ping` | `{ "ok": true, "app": "LockIME", "version": "x.y.z", "build": "n" }` — eine günstige Präsenz-/Versionssonde. |

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

`currentSource`, `defaultSource` und `frontmostApp` sind nur vorhanden, wenn sie
bekannt sind.

---

## Errors

Bei einem Fehlschlag (und wenn ein `x-error`-Rückruf vorhanden ist) hängt LockIME
einen stabilen maschinenlesbaren `errorCode` und eine menschenlesbare
`errorMessage` an. Der Fehlertext ist **bewusst englisch und stabil** — er gelangt
in deine App und in Protokolle, daher wird er niemals lokalisiert.

| `errorCode` | When |
|---|---|
| `api_disabled` | Die API ist aus — aktiviere sie unter Einstellungen ▸ Allgemein ▸ Automatisierung. |
| `malformed_url` | Die URL konnte nicht geparst werden. |
| `no_command` | Es wurde kein Befehlstoken angegeben. |
| `unknown_command` | Das Befehlstoken wird nicht erkannt. |
| `missing_parameter` | Ein erforderlicher Parameter fehlt. |
| `invalid_parameter` | Ein Parameterwert liegt außerhalb des gültigen Bereichs (ungültiges `mode`, `action`, `match-type`, `direction`, `code`, ein nicht kompilierbares `url-regex`-Muster oder eine fehlerhafte UUID). |
| `unknown_source` | Die `id`/`name` passt auf keine installierte auswählbare Quelle. |
| `no_input_sources` | Es sind keine auswählbaren Eingabequellen installiert. |
| `rule_not_found` | Die anvisierte Regel pro App/URL existiert nicht. |
| `not_supported` | Der Vorgang konnte nicht abgeschlossen werden (z. B. Konfigurations-Serialisierung). |

---

## Examples

**Shell / `open(1)`**

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
open "lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&action=switch"
open "lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&match-type=domain"
# url-regex passt auf die gesamte URL — kodiere das Muster prozentual (hier: github\.com/.*/pull)
open "lockime://set-url-rule?pattern=github%5C.com%2F.%2A%2Fpull&source=com.apple.keylayout.ABC&match-type=url-regex"
open "lockime://set-launch-at-login?enabled=on"
```

**AppleScript**

```applescript
open location "lockime://toggle-lock"
```

**Shortcuts (macOS)**

Füge eine **Open URLs**-Aktion mit `lockime://lock` hinzu oder **Get Contents of
URL** plus die x-callback-url-Form, um den Zustand auszulesen.

**Status aus einem Skript lesen** (mithilfe einer Callback-Empfänger-App/-URL):

```sh
open "lockime://status?x-success=myreceiver%3A%2F%2Fstatus"
```

---

## Notes & guarantees

- **Idempotent und umkehrbar.** Einen Befehl erneut zu senden ist sicher; nichts
  wird über die von dir erbetenen Regeländerungen hinaus zerstört.
- **Stiehlt niemals den Fokus.** Kein Befehl bringt LockIME in den Vordergrund
  oder öffnet eines seiner Fenster — die API ist von Grund auf kopflos.
- **Sperren bleiben maßgeblich.** `switch-source` ist eine einmalige
  Höflichkeitsumschaltung; eine bestehende kontinuierliche Sperre setzt ihre
  Quelle erneut durch.
- **Die Quellidentität ist die `id`.** Anzeigenamen sind eine Bequemlichkeit und
  hängen von der System-Locale ab; bevorzuge für stabile Automatisierung die `id`
  (aus `list-sources`).
- **Backups schließen die API nicht ein.** Der Konfigurations-Export/-Import
  (`.lockime`-Dateien) umfasst deine Regeln, nicht etwas API-Spezifisches — es gibt
  keinen separaten API-Zustand, der mitgeführt werden müsste.
