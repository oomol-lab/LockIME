# URL Scheme API

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · **Português** · [Русский](README.ru.md)

O LockIME expõe um esquema de URL `lockime://` para que outros apps, scripts, o
Shortcuts, o Stream Deck, o Alfred/Raycast, o AppleScript — qualquer coisa que
consiga abrir uma URL — possam controlá-lo: ativá-lo ou desativá-lo,
redirecionar a fonte de entrada, gerenciar regras e ler o estado de volta.

Cada comando é uma URL, do tipo dispare-e-esqueça por padrão, com callbacks
[x-callback-url](https://x-callback-url.com) opcionais para sucesso/erro e para
retornar dados dos comandos de consulta.

> **Ative-a primeiro.** A URL Scheme API está **desativada por padrão**. Ative-a
> em **LockIME ▸ Ajustes ▸ Geral ▸ Automação ▸ URL Scheme API**. Enquanto estiver
> desativada, todo comando retorna o erro `api_disabled` e nada acontece.

> **Nota de segurança.** Uma vez ativada, os comandos são executados **sem uma
> confirmação por comando** — qualquer processo que consiga abrir uma URL
> `lockime://` (incluindo uma página da web) pode controlar o LockIME. Todo
> comando é reversível e nenhum toca nos seus arquivos; o pior que um chamador
> mal-intencionado pode fazer é alternar o bloqueio da sua fonte de entrada ou
> editar regras. Deixe a API desativada quando não estiver usando-a.

---

## URL shape

São aceitas duas formas equivalentes:

```
lockime://<command>?<param>=<value>&<param>=<value>
lockime://x-callback-url/<command>?<param>=<value>&…
```

- O **token de comando** (`<command>`) não diferencia maiúsculas de minúsculas.
- Os **nomes dos parâmetros** não diferenciam maiúsculas de minúsculas; os
  **valores dos parâmetros** são tomados literalmente (de modo que bundle IDs e
  source IDs mantêm sua capitalização).
- Sempre **codifique em percent-encode** os valores que contenham caracteres
  reservados (`?`, `&`, `=`, `/`, espaços, …). Um nome de exibição de fonte como
  `ABC – Extended` torna-se `name=ABC%20%E2%80%93%20Extended`.

O prefixo `x-callback-url/` é um açúcar opcional para ferramentas de
x-callback-url; os parâmetros de callback abaixo também funcionam na forma
simples.

> **Builds de desenvolvimento.** Uma build de Debug do LockIME registra
> `lockime-dev://` em vez de `lockime://`, de modo que uma build local nunca
> sequestra o esquema do release instalado. Todo o resto é idêntico.

---

## x-callback-url

Qualquer comando pode carregar estes parâmetros reservados:

| Parameter | Meaning |
|---|---|
| `x-success` | URL aberta após o comando ter sucesso. Para comandos de **consulta**, o resultado JSON é anexado como `result=<json>` (em percent-encode). |
| `x-error`   | URL aberta se o comando falhar, com `errorCode=<code>&errorMessage=<text>` anexado. |
| `x-source`  | Um nome de exibição para o app chamador (informativo; o LockIME o registra). |

Os comandos de ação disparam `x-success` sem `result`. Os comandos de consulta
retornam seu payload através de `x-success`; sem uma URL `x-success`, uma
consulta simplesmente não tem para onde enviar seu resultado (ela ainda é
executada, de forma inofensiva).

Exemplo de ida e volta — peça o status e receba-o de volta no seu próprio app:

```
lockime://status?x-success=myapp%3A%2F%2Fgot-status
```

Em caso de sucesso, o LockIME abre:

```
myapp://got-status?result=%7B%22enabled%22%3Atrue%2C…%7D
```

---

## Command reference

### Enable & disable

`lock` / `unlock` / `toggle-lock` ligam ou desligam o **LockIME** — o único
interruptor que comanda tudo (tanto o bloqueio quanto a alternância). Para parar
de fixar globalmente enquanto suas regras de alternância por app/por site
continuam disparando — o modo "agir como um alternador puro" — defina a fonte
padrão global como **Nenhuma** (`set-default-source` sem fonte).

| Command | Parameters | Effect |
|---|---|---|
| `lock` | — | Liga o **LockIME** — aplica suas regras. |
| `unlock` | — | Desliga o **LockIME** — totalmente ocioso. |
| `toggle-lock` *(alias `toggle`)* | — | Inverte o LockIME (liga/desliga). |

### Global input source

Uma **fonte** é identificada por `id` (o identificador canônico de Text Input
Source, p. ex. `com.apple.keylayout.ABC`, conforme retornado por
[`list-sources`](#queries)) ou por `name` (seu nome de exibição localizado, sem
diferenciar maiúsculas de minúsculas). Ela deve nomear uma fonte atualmente
instalada e selecionável, ou o comando retorna `unknown_source`.

| Command | Parameters | Effect |
|---|---|---|
| `lock-to-source` | `id` \| `name` | Define a fonte padrão global **e** liga o LockIME. |
| `set-default-source` | `id` \| `name` *(omita ambos para limpar)* | Define (ou limpa) a fonte padrão global sem alterar o estado ligado/desligado. |
| `cycle-source` | `direction` = `next` \| `previous` | Avança o alvo global para a próxima/anterior fonte instalada (com retorno cíclico) e liga o LockIME. |
| `switch-source` | `id` \| `name` | Alterna a fonte de entrada atual **uma vez**, agora — **não** ativa nem modifica nenhum bloqueio contínuo. Se um bloqueio contínuo já estiver ativo, ele prevalece e devolve a fonte ao seu alvo. |

`direction` também aceita os apelidos `prev`, `forward`, `back`, `up`, `down`.

### Per-app rules

| Command | Parameters | Effect |
|---|---|---|
| `set-app-rule` | `bundle` *(obrigatório)*, `mode` = `lock` \| `switch` \| `ignore` \| `default` *(padrão `lock`)*, `source` \| `source-name` *(obrigatório para `lock`/`switch`)* | Cria ou substitui a regra de um app. `lock` impõe a fonte continuamente; `switch` alterna uma vez na ativação e depois libera; `ignore` desativa o bloqueio para esse app; `default` recorre ao padrão global. |
| `remove-app-rule` | `bundle` *(obrigatório)* | Exclui a regra de `bundle`. Retorna `rule_not_found` se não houver nenhuma. |
| `cycle-app-source` | `direction` *(obrigatório)*, `bundle` *(opcional; padrão = app em primeiro plano)* | Avança a própria regra desse app para a próxima/anterior fonte. Sem efeito (`rule_not_found`) se o app não tiver regra. |
| `remove-frontmost-app-rule` | — | Exclui a regra do app que estiver em primeiro plano. |
| `clear-app-rules` | — | Remove **todas** as regras por app. |

### General settings

| Command | Parameters | Effect |
|---|---|---|
| `set-launch-at-login` *(alias `launch-at-login`)* | `enabled` = `true` \| `false` \| `toggle` | Registra/cancela o registro do LockIME como item de login. |
| `set-language` | `code` = `en` \| `zh-Hans` \| `zh-Hant` \| `ja` \| `fr` \| `de` \| `es` \| `pt` \| `ru` \| `system` | Define a substituição de idioma no app; `system` (alias `auto`) a limpa e segue o idioma do macOS. Tolerante: `zh-CN`→`zh-Hans`, `zh-TW`→`zh-Hant`, `fr-CA`→`fr`, … |

### Enhanced mode & per-URL rules

As regras por URL exigem o **modo aprimorado** opcional, condicionado à
permissão de Accessibility.

| Command | Parameters | Effect |
|---|---|---|
| `set-enhanced-mode` | `enabled` = `true` \| `false` \| `toggle` | Liga/desliga o modo aprimorado (ou o inverte). |
| `set-url-rule` | `host` *(apelido `pattern`, obrigatório)*, `source` \| `source-name` *(obrigatório)*, `match-type` = `domain-suffix` \| `domain` \| `domain-keyword` \| `url-regex` *(padrão `domain-suffix`)*, `action` = `lock` \| `switch` *(padrão `lock`)*, `id` *(UUID opcional)* | Cria ou substitui uma regra por URL. A forma como o padrão é correspondido depende de `match-type` (veja [abaixo](#match-types)). Sem `id`, uma regra existente para o mesmo padrão é atualizada em vez de duplicada. |
| `remove-url-rule` | `id` *(UUID)* \| `host` | Exclui uma regra de URL pelo seu `id` (de `list-url-rules`) ou pelo `host`. |
| `clear-url-rules` | — | Remove **todas** as regras por URL. |

#### Match types

`match-type` decide como o padrão de uma regra é comparado com a URL atual do
navegador. As regras são avaliadas **de cima para baixo e a primeira
correspondência vence**, de modo que sua ordem é sua prioridade (arraste para
reordenar em **Ajustes ▸ Regras por URL**).

| `match-type` | Pattern is… | Matches |
|---|---|---|
| `domain-suffix` *(default)* | um host, p. ex. `github.com` | o host **e todos os seus subdomínios** (`github.com`, `gist.github.com`). Um `*.` no início é tolerado. |
| `domain` | um host, p. ex. `github.com` | **apenas esse host exato**, nunca um subdomínio. |
| `domain-keyword` | uma substring, p. ex. `google` | qualquer host que a **contenha** (`google.com`, `mail.google.com`, `googleapis.com`). |
| `url-regex` | uma expressão regular | a **URL inteira** (esquema · host · caminho · consulta · fragmento) — sem diferenciar maiúsculas de minúsculas e sem âncoras. O único tipo que consegue distinguir páginas de um mesmo site por caminho ou consulta. Um padrão que não compila é rejeitado com `invalid_parameter`. |

`match-type` também aceita apelidos como `suffix`, `keyword` e `regex`. Para uma
regra `url-regex`, o padrão geralmente contém caracteres (`?`, `&`, `/`, `\`)
que devem ser codificados em percent-encode na URL.

### App

| Command | Parameters | Effect |
|---|---|---|
| `quit` | — | Encerra o LockIME. |

(Veja também [`set-language`](#general-settings) e [`set-launch-at-login`](#general-settings).)

O LockIME deliberadamente não expõe **nenhum comando que abra sua interface**
(Ajustes, Sobre, janela de atualização): a API é para automação headless, não
para controlar janelas.

### Queries

Os comandos de consulta retornam um payload JSON através do callback
`x-success` (veja [x-callback-url](#x-callback-url)).

| Command | Result |
|---|---|
| `status` | O estado completo — veja [abaixo](#status-payload). |
| `current-source` | `{ "id": "...", "name": "..." }` da fonte ao vivo. |
| `list-sources` *(alias `sources`)* | Array das fontes instaladas: `{ "id", "name", "isCJKV", "isEnabled", "isSelectCapable" }`. |
| `list-app-rules` *(alias `app-rules`)* | Array de `{ "bundleID", "mode", "source"? }`. |
| `list-url-rules` *(alias `url-rules`)* | Array de `{ "id", "host", "action", "matchType", "source" }`, em ordem de prioridade (a primeira correspondência vence). |
| `list-log` *(aliases `log`, `recent-activations`)* | As últimas 24 h de entradas de troca forçada, da mais recente para a mais antiga: `{ "timestamp", "inputSource", "inputSourceName", "reason", "durationMs", "fromSourceName"?, "app"?, "bundleID"?, "ruleSource"?, "matchedHost"? }`. |
| `get-config` *(alias `config`)* | O objeto de configuração persistida completo. |
| `version` | `{ "version": "x.y.z", "build": "n" }`. |
| `ping` | `{ "ok": true, "app": "LockIME", "version": "x.y.z", "build": "n" }` — uma sonda barata de presença/versão. |

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
  "frontmostApp": "com.apple.Safari"
}
```

`enabled` é o único interruptor "Ativar o LockIME" — quando ele está ligado, suas
regras estão em vigor.
`currentSource`, `defaultSource` e `frontmostApp` estão presentes apenas quando conhecidos.

---

## Errors

Em caso de falha (e com um callback `x-error` presente), o LockIME anexa um
`errorCode` de máquina estável e um `errorMessage` legível por humanos. O texto
de erro é **em inglês e estável** por design — ele atravessa para o seu app e
para os logs, portanto nunca é localizado.

| `errorCode` | When |
|---|---|
| `api_disabled` | A API está desativada — ative-a em Ajustes ▸ Geral ▸ Automação. |
| `malformed_url` | A URL não pôde ser analisada. |
| `no_command` | Nenhum token de comando foi fornecido. |
| `unknown_command` | O token de comando não é reconhecido. |
| `missing_parameter` | Um parâmetro obrigatório está ausente. |
| `invalid_parameter` | O valor de um parâmetro está fora do intervalo (`mode`, `action`, `match-type`, `direction`, `code` inválido, um padrão `url-regex` que não compila, ou um UUID malformado). |
| `unknown_source` | O `id`/`name` não corresponde a nenhuma fonte selecionável instalada. |
| `no_input_sources` | Nenhuma fonte de entrada selecionável está instalada. |
| `rule_not_found` | A regra de app/URL visada não existe. |
| `not_supported` | A operação não pôde ser concluída (p. ex. serialização da configuração). |

---

## Examples

**Shell / `open(1)`**

```sh
open "lockime://lock"
open "lockime://lock-to-source?id=com.apple.keylayout.ABC"
open "lockime://set-app-rule?bundle=com.apple.Terminal&mode=lock&source=com.apple.keylayout.ABC"
open "lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&action=switch"
open "lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&match-type=domain"
# url-regex corresponde à URL inteira — codifique o padrão em percent-encode (aqui: github\.com/.*/pull)
open "lockime://set-url-rule?pattern=github%5C.com%2F.%2A%2Fpull&source=com.apple.keylayout.ABC&match-type=url-regex"
open "lockime://set-launch-at-login?enabled=on"
```

**AppleScript**

```applescript
open location "lockime://toggle-lock"
```

**Shortcuts (macOS)**

Adicione uma ação **Open URLs** com `lockime://lock`, ou **Get Contents of URL**
mais a forma x-callback-url para ler o estado de volta.

**Ler o status a partir de um script** (usando um app/URL receptor de callback):

```sh
open "lockime://status?x-success=myreceiver%3A%2F%2Fstatus"
```

---

## Notes & guarantees

- **Idempotente e reversível.** Reenviar um comando é seguro; nada é destruído
  além das edições de regra que você solicitar.
- **Nunca rouba o foco.** Nenhum comando traz o LockIME para o primeiro plano
  nem abre qualquer uma de suas janelas — a API é headless por design.
- **Os bloqueios permanecem autoritativos.** `switch-source` é uma troca de
  cortesia única; um bloqueio contínuo em vigor reafirmará sua fonte.
- **A identidade da fonte é o `id`.** Os nomes de exibição são uma conveniência
  e dependem do idioma do sistema; prefira o `id` (de `list-sources`) para uma
  automação estável.
- **Os backups não incluem a API.** A exportação/importação de configuração
  (arquivos `.lockime`) cobre suas regras, não nada específico da API — não há
  um estado de API separado a transportar.
