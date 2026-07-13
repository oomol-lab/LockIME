# URL Scheme API

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · **Français** · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md)

LockIME expose un schéma d'URL `lockime://` afin que d'autres applications, scripts,
Shortcuts, Stream Deck, Alfred/Raycast, AppleScript — tout ce qui peut ouvrir une URL —
puissent le piloter : l'activer ou le désactiver, recibler la source de saisie,
gérer les règles et relire l'état.

Chaque commande est une URL, par défaut sans attente de réponse, avec des rappels
[x-callback-url](https://x-callback-url.com) optionnels pour le succès/l'erreur et pour
retourner des données depuis les commandes de requête.

> **Activez-la d'abord.** L'API URL Scheme est **désactivée par défaut**. Activez-la dans
> **LockIME ▸ Réglages ▸ Général ▸ Automatisation ▸ URL Scheme API**. Tant qu'elle est
> désactivée, chaque commande renvoie l'erreur `api_disabled` et rien ne se passe.

> **Note de sécurité.** Une fois activée, les commandes s'exécutent **sans confirmation
> par commande** — n'importe quel processus capable d'ouvrir une URL `lockime://` (y compris
> une page web) peut piloter LockIME. Chaque commande est réversible et aucune ne touche à
> vos fichiers ; le pire qu'un appelant malveillant puisse faire est de basculer votre verrou
> de source de saisie ou de modifier des règles. Laissez l'API désactivée lorsque vous ne
> l'utilisez pas.

---

## URL shape

Deux formes équivalentes sont acceptées :

```
lockime://<command>?<param>=<value>&<param>=<value>
lockime://x-callback-url/<command>?<param>=<value>&…
```

- Le **jeton de commande** (`<command>`) est insensible à la casse.
- Les **noms de paramètres** sont insensibles à la casse ; les **valeurs de paramètres**
  sont prises telles quelles (les bundle IDs et source IDs conservent donc leur casse).
- Encodez **toujours en pourcentage** les valeurs contenant des caractères réservés
  (`?`, `&`, `=`, `/`, espaces, …). Un nom d'affichage de source comme `ABC – Extended`
  devient `name=ABC%20%E2%80%93%20Extended`.

Le préfixe `x-callback-url/` est un sucre syntaxique optionnel pour l'outillage
x-callback-url ; les paramètres de rappel ci-dessous fonctionnent aussi sur la forme nue.

> **Development builds.** Un build Debug de LockIME enregistre `lockime-dev://`
> au lieu de `lockime://`, de sorte qu'un build local ne détourne jamais le schéma
> de la version installée. Tout le reste est identique.

---

## x-callback-url

Toute commande peut porter ces paramètres réservés :

| Parameter | Meaning |
|---|---|
| `x-success` | URL ouverte une fois la commande réussie. Pour les commandes de **requête**, le résultat JSON est ajouté sous la forme `result=<json>` (encodé en pourcentage). |
| `x-error`   | URL ouverte si la commande échoue, avec `errorCode=<code>&errorMessage=<text>` ajouté. |
| `x-source`  | Un nom d'affichage pour l'application appelante (informatif ; LockIME le journalise). |

Les commandes d'action déclenchent `x-success` sans `result`. Les commandes de requête
retournent leur charge utile via `x-success` ; sans URL `x-success`, une requête n'a
simplement nulle part où envoyer son résultat (elle s'exécute quand même, sans dommage).

Exemple d'aller-retour — demander l'état et le recevoir dans votre propre application :

```
lockime://status?x-success=myapp%3A%2F%2Fgot-status
```

En cas de succès, LockIME ouvre :

```
myapp://got-status?result=%7B%22enabled%22%3Atrue%2C…%7D
```

---

## Command reference

### Enable & disable

`lock` / `unlock` / `toggle-lock` activent ou désactivent **LockIME** — l'interrupteur unique qui conditionne tout (le verrouillage comme la bascule). Pour cesser d'épingler globalement tandis que vos règles de bascule par application/par site continuent de se déclencher — le mode « se comporter comme un simple commutateur » — réglez plutôt la source par défaut globale sur **Aucune** (`set-default-source` sans source).

| Command | Parameters | Effect |
|---|---|---|
| `lock` | — | Activer **LockIME** — applique vos règles. |
| `unlock` | — | Désactiver **LockIME** — totalement inactif. |
| `toggle-lock` *(alias `toggle`)* | — | Inverser l'état de LockIME. |

### Global input source

Une **source** est désignée par `id` (l'identifiant canonique Text Input Source, p. ex.
`com.apple.keylayout.ABC`, tel que retourné par [`list-sources`](#queries)) ou par
`name` (son nom d'affichage localisé, insensible à la casse). Elle doit désigner une source
actuellement installée et sélectionnable, sinon la commande renvoie `unknown_source`.

| Command | Parameters | Effect |
|---|---|---|
| `lock-to-source` | `id` \| `name` | Définir la source par défaut globale **et** activer LockIME. |
| `set-default-source` | `id` \| `name` *(omit both to clear)*, `action` = `lock` \| `switch` *(default `lock`)* | Définir (ou effacer) la source par défaut globale sans changer l'état activé/désactivé. `action` détermine si la valeur par défaut **verrouille** (impose continuellement la source) ou **bascule** vers elle une seule fois chaque fois qu'une application retombe sur la valeur par défaut globale (aucune règle d'URL ou d'application de priorité supérieure n'épingle de source), puis relâche ; il est ignoré sur le chemin d'effacement. |
| `cycle-source` | `direction` = `next` \| `previous` | Faire passer la cible globale à la source installée suivante/précédente (avec bouclage) et activer LockIME. |
| `switch-source` | `id` \| `name` | Change la source de saisie actuelle **une seule fois**, maintenant — cela n'**active ni ne modifie** aucun verrou continu. Si un verrou continu est déjà actif, il l'emporte et rétablit la source sur sa cible. |

`direction` accepte aussi les alias `prev`, `forward`, `back`, `up`, `down`.

### Per-app rules

| Command | Parameters | Effect |
|---|---|---|
| `set-app-rule` | `bundle` *(req)*, `mode` = `lock` \| `switch` \| `ignore` \| `default` *(default `lock`)*, `source` \| `source-name` *(req for `lock`/`switch`)* | Créer ou remplacer la règle d'une application. `lock` impose continuellement la source ; `switch` bascule une fois à l'activation puis relâche ; `ignore` désactive le verrouillage pour cette application ; `default` revient à la valeur par défaut globale. |
| `remove-app-rule` | `bundle` *(req)* | Supprimer la règle pour `bundle`. `rule_not_found` s'il n'y en a aucune. |
| `cycle-app-source` | `direction` *(req)*, `bundle` *(optional; default = frontmost app)* | Faire passer la règle propre à cette application à la source suivante/précédente. Sans effet (`rule_not_found`) si l'application n'a pas de règle. |
| `remove-frontmost-app-rule` | — | Supprimer la règle de l'application qui est au premier plan. |
| `clear-app-rules` | — | Supprimer **toutes** les règles par application. |

### General settings

| Command | Parameters | Effect |
|---|---|---|
| `set-launch-at-login` *(alias `launch-at-login`)* | `enabled` = `true` \| `false` \| `toggle` | Enregistrer/désenregistrer LockIME comme élément de connexion. |
| `set-language` | `code` = `en` \| `zh-Hans` \| `zh-Hant` \| `ja` \| `fr` \| `de` \| `es` \| `pt` \| `ru` \| `system` | Définir le remplacement de langue dans l'application ; `system` (alias `auto`) l'efface et suit la langue de macOS. Tolérant : `zh-CN`→`zh-Hans`, `zh-TW`→`zh-Hant`, `fr-CA`→`fr`, … |

### Enhanced mode & per-URL rules

Les règles par URL nécessitent le **mode renforcé** optionnel, soumis à l'autorisation Accessibility.

| Command | Parameters | Effect |
|---|---|---|
| `set-enhanced-mode` | `enabled` = `true` \| `false` \| `toggle` | Activer/désactiver le mode renforcé (ou l'inverser). |
| `set-url-rule` | `host` *(alias `pattern`, req)*, `source` \| `source-name` *(req)*, `match-type` = `domain-suffix` \| `domain` \| `domain-keyword` \| `url-regex` *(default `domain-suffix`)*, `action` = `lock` \| `switch` *(default `lock`)*, `id` *(optional UUID)* | Créer ou remplacer une règle par URL. La manière dont le motif est mis en correspondance dépend de `match-type` (voir [ci-dessous](#match-types)). Sans `id`, une règle existante pour le même motif est mise à jour plutôt que dupliquée. |
| `remove-url-rule` | `id` *(UUID)* \| `host` | Supprimer une règle d'URL par son `id` (issu de `list-url-rules`) ou par `host`. |
| `clear-url-rules` | — | Supprimer **toutes** les règles par URL. |

#### Match types

`match-type` détermine comment le motif d'une règle est comparé à l'URL actuelle
du navigateur. Les règles sont évaluées **de haut en bas et la première
correspondance l'emporte** ; leur ordre est donc leur priorité (réorganisez-les
par glisser-déposer dans **Réglages ▸ Règles par URL**).

| `match-type` | Pattern is… | Matches |
|---|---|---|
| `domain-suffix` *(default)* | un hôte, p. ex. `github.com` | l'hôte **et tous ses sous-domaines** (`github.com`, `gist.github.com`). Un `*.` en tête est toléré. |
| `domain` | un hôte, p. ex. `github.com` | **uniquement cet hôte exact**, jamais un sous-domaine. |
| `domain-keyword` | une sous-chaîne, p. ex. `google` | tout hôte qui la **contient** (`google.com`, `mail.google.com`, `googleapis.com`). |
| `url-regex` | une expression régulière | l'**URL entière** (schéma · hôte · chemin · requête · fragment) — insensible à la casse et non ancrée. Le seul type capable de distinguer les pages d'un même site par le chemin ou la requête. Un motif non compilable est rejeté avec `invalid_parameter`. |

`match-type` accepte aussi des alias tels que `suffix`, `keyword` et `regex`. Pour une
règle `url-regex`, le motif contient généralement des caractères (`?`, `&`, `/`, `\`)
qui doivent être encodés en pourcentage dans l'URL.

### App

| Command | Parameters | Effect |
|---|---|---|
| `quit` | — | Quitter LockIME. |

(Voir aussi [`set-language`](#general-settings) et [`set-launch-at-login`](#general-settings).)

LockIME n'expose délibérément **aucune commande qui ouvre son interface** (Réglages, À propos,
fenêtre de mise à jour) : l'API est destinée à l'automatisation sans interface, pas au pilotage de fenêtres.

### Queries

Les commandes de requête retournent une charge utile JSON via le rappel `x-success` (voir
[x-callback-url](#x-callback-url)).

| Command | Result |
|---|---|
| `status` | L'état complet — voir [ci-dessous](#status-payload). |
| `current-source` | `{ "id": "...", "name": "..." }` de la source active. |
| `list-sources` *(alias `sources`)* | Tableau des sources installées : `{ "id", "name", "isCJKV", "isEnabled", "isSelectCapable" }`. |
| `list-app-rules` *(alias `app-rules`)* | Tableau de `{ "bundleID", "mode", "source"? }`. |
| `list-url-rules` *(alias `url-rules`)* | Tableau de `{ "id", "host", "action", "matchType", "source" }`, par ordre de priorité (la première correspondance l'emporte). |
| `list-log` *(aliases `log`, `recent-activations`)* | Les 24 dernières heures d'entrées de basculement forcé, du plus récent au plus ancien : `{ "timestamp", "inputSource", "inputSourceName", "reason", "durationMs", "fromSourceName"?, "app"?, "bundleID"?, "ruleSource"?, "matchedHost"? }`. |
| `get-config` *(alias `config`)* | L'objet de configuration persistée complet. |
| `version` | `{ "version": "x.y.z", "build": "n" }`. |
| `ping` | `{ "ok": true, "app": "LockIME", "version": "x.y.z", "build": "n" }` — une sonde de présence/version peu coûteuse. |

#### `status` payload

```json
{
  "enabled": true,
  "enhancedMode": false,
  "launchAtLogin": true,
  "accessibilityGranted": true,
  "activationCount": 42,
  "language": "en",
  "version": "1.2.0",
  "build": "20260615",
  "currentSource": { "id": "com.apple.keylayout.ABC", "name": "ABC" },
  "defaultSource": { "id": "com.apple.keylayout.ABC", "name": "ABC" },
  "defaultAction": "lock",
  "frontmostApp": "com.apple.Safari"
}
```

`enabled` est l'unique interrupteur « Activer LockIME » — lorsqu'il est activé, vos règles sont en vigueur.
`currentSource`, `defaultSource` et `frontmostApp` ne sont présents que lorsqu'ils sont connus ;
`defaultAction` (`lock` \| `switch`) accompagne `defaultSource` lorsqu'une source par défaut globale est définie.

---

## Errors

En cas d'échec (et lorsqu'un rappel `x-error` est présent), LockIME ajoute un
`errorCode` machine stable et un `errorMessage` lisible par un humain. Le texte d'erreur est
**en anglais et stable** par conception — il franchit la frontière vers votre application et
vers les journaux, il n'est donc jamais localisé.

| `errorCode` | When |
|---|---|
| `api_disabled` | L'API est désactivée — activez-la dans Réglages ▸ Général ▸ Automatisation. |
| `malformed_url` | L'URL n'a pas pu être analysée. |
| `no_command` | Aucun jeton de commande n'a été fourni. |
| `unknown_command` | Le jeton de commande n'est pas reconnu. |
| `missing_parameter` | Un paramètre requis est absent. |
| `invalid_parameter` | Une valeur de paramètre est hors plage (mauvais `mode`, `action`, `match-type`, `direction`, `code`, un motif `url-regex` non compilable, ou un UUID mal formé). |
| `unknown_source` | L'`id`/`name` ne correspond à aucune source installée et sélectionnable. |
| `no_input_sources` | Aucune source de saisie sélectionnable n'est installée. |
| `rule_not_found` | La règle d'application/URL ciblée n'existe pas. |
| `not_supported` | L'opération n'a pas pu être menée à bien (p. ex. sérialisation de la configuration). |

---

## Examples

**Shell / `open(1)`**

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-default-source?id=com.apple.keylayout.ABC&action=switch"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
open "lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&action=switch"
open "lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&match-type=domain"
# url-regex correspond à l'URL entière — encodez le motif en pourcentage (ici : github\.com/.*/pull)
open "lockime://set-url-rule?pattern=github%5C.com%2F.%2A%2Fpull&source=com.apple.keylayout.ABC&match-type=url-regex"
open "lockime://set-launch-at-login?enabled=on"
```

**AppleScript**

```applescript
open location "lockime://toggle-lock"
```

**Shortcuts (macOS)**

Ajoutez une action **Open URLs** avec `lockime://lock`, ou **Get Contents of URL**
plus la forme x-callback-url pour relire l'état.

**Lire l'état depuis un script** (à l'aide d'une application/URL réceptrice de rappel) :

```sh
open "lockime://status?x-success=myreceiver%3A%2F%2Fstatus"
```

---

## Notes & guarantees

- **Idempotent et réversible.** Renvoyer une commande est sans risque ; rien n'est
  détruit au-delà des modifications de règles que vous demandez.
- **Ne vole jamais le focus.** Aucune commande ne met LockIME au premier plan ni n'ouvre
  l'une de ses fenêtres — l'API est sans interface par conception.
- **Les verrous restent autoritaires.** `switch-source` est un basculement de courtoisie
  unique ; un verrou continu en place réimposera sa source.
- **L'identité d'une source est son `id`.** Les noms d'affichage sont une commodité et
  dépendent de la locale système ; préférez `id` (issu de `list-sources`) pour une
  automatisation stable.
- **Les sauvegardes n'incluent pas l'API.** L'export/import de configuration (fichiers
  `.lockime`) couvre vos règles, pas ce qui est spécifique à l'API — il n'y a pas d'état
  d'API séparé à transporter.
