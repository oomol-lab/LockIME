# URL Scheme API

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · **日本語** · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md)

LockIME は `lockime://` URL スキームを公開しており、他のアプリ・スクリプト・ショートカット・
Stream Deck・Alfred/Raycast・AppleScript——URL を開けるものなら何でも——から操作できます：
ロックの切り替え、入力ソースの再設定、ルールの管理、そして状態の読み取りが可能です。

各コマンドは URL であり、デフォルトでは fire-and-forget（撃ちっぱなし）ですが、成功/エラー時、
そしてクエリコマンドからのデータ返却のために、オプションで
[x-callback-url](https://x-callback-url.com) コールバックを利用できます。

> **まず有効化してください。** URL Scheme API は**デフォルトでオフ**です。
> **LockIME ▸ 設定 ▸ 一般 ▸ 自動化 ▸ URL Scheme API** でオンにしてください。オフの
> 間は、すべてのコマンドが `api_disabled` エラーを返し、何も起こりません。

> **セキュリティに関する注意。** 有効化すると、コマンドは**コマンドごとの確認なしで**
> 実行されます——`lockime://` URL を開けるプロセスなら何でも（Web ページも含めて）
> LockIME を操作できます。すべてのコマンドは取り消し可能で、ファイルに触れるものは一つも
> ありません。悪意のある呼び出し元にできる最悪のことは、入力ソースのロックを切り替えたり、
> ルールを編集したりすることだけです。使用していないときは API をオフにしておいてください。

---

## URL shape

同等の 2 つの形式を受け付けます：

```
lockime://<command>?<param>=<value>&<param>=<value>
lockime://x-callback-url/<command>?<param>=<value>&…
```

- **コマンドトークン**（`<command>`）は大文字小文字を区別しません。
- **パラメータ名**は大文字小文字を区別しません。**パラメータ値**はそのまま
  受け取られます（そのため bundle ID や source ID は大文字小文字が保持されます）。
- 予約文字（`?`、`&`、`=`、`/`、スペースなど）を含む値は、常に
  **パーセントエンコード**してください。`ABC – Extended` のようなソースの表示名は
  `name=ABC%20%E2%80%93%20Extended` になります。

`x-callback-url/` プレフィックスは x-callback-url ツール向けのオプションの糖衣構文です。
以下のコールバックパラメータは、プレフィックスなしの形式でも機能します。

> **Development builds.** LockIME の Debug ビルドは `lockime://` の代わりに
> `lockime-dev://` を登録します。そのため、ローカルビルドがインストール済みの
> リリースのスキームを乗っ取ることはありません。それ以外はすべて同一です。

---

## x-callback-url

どのコマンドも、これらの予約パラメータを持つことができます：

| Parameter | Meaning |
|---|---|
| `x-success` | コマンドの成功後に開く URL。**query** コマンドの場合は、JSON 結果が `result=<json>`（パーセントエンコード済み）として付加されます。 |
| `x-error`   | コマンドが失敗した場合に開く URL。`errorCode=<code>&errorMessage=<text>` が付加されます。 |
| `x-source`  | 呼び出し元アプリの表示名（情報目的。LockIME はこれをログに記録します）。 |

アクションコマンドは `result` なしで `x-success` を発火します。クエリコマンドはその
ペイロードを `x-success` 経由で返します。`x-success` URL がなければ、クエリは結果を
送る先がないだけです（それでも無害に実行されます）。

往復の例——ステータスを問い合わせ、それを自分のアプリへ受け取ります：

```
lockime://status?x-success=myapp%3A%2F%2Fgot-status
```

成功すると LockIME は次を開きます：

```
myapp://got-status?result=%7B%22locked%22%3Atrue%2C…%7D
```

---

## Command reference

### Master lock

| Command | Parameters | Effect |
|---|---|---|
| `lock` | — | マスターロックを**オン**にします。 |
| `unlock` | — | マスターロックを**オフ**にします。 |
| `toggle-lock` *(alias `toggle`)* | — | マスターロックを反転します。 |

### Global input source

**ソース**は `id`（正準的な Text Input Source 識別子。例：
`com.apple.keylayout.ABC`。[`list-sources`](#queries) が返すもの）または `name`
（ローカライズされた表示名。大文字小文字を区別しない）で指定します。現在
インストール済みで選択可能なソースを指定する必要があり、そうでなければコマンドは
`unknown_source` を返します。

| Command | Parameters | Effect |
|---|---|---|
| `lock-to-source` | `id` \| `name` | グローバルのデフォルトソースを設定し、**かつ**ロックをオンにします。 |
| `set-default-source` | `id` \| `name` *(omit both to clear)* | オン/オフの状態を変えずに、グローバルのデフォルトソースを設定（またはクリア）します。 |
| `cycle-source` | `direction` = `next` \| `previous` | グローバルのターゲットをインストール済みの次/前のソースへ（循環して）進め、ロックをオンにします。 |
| `switch-source` | `id` \| `name` | 現在の入力ソースを今ここで**一度だけ**切り替えます——継続ロックを有効化したり変更したりは**しません**。すでに継続ロックがアクティブな場合は、そちらが優先され、入力ソースをロックの目標に戻します。 |

`direction` はエイリアス `prev`、`forward`、`back`、`up`、`down` も受け付けます。

### Per-app rules

| Command | Parameters | Effect |
|---|---|---|
| `set-app-rule` | `bundle` *(req)*, `mode` = `lock` \| `switch` \| `ignore` \| `default` *(default `lock`)*, `source` \| `source-name` *(req for `lock`/`switch`)* | アプリのルールを作成または置き換えます。`lock` はソースを継続的に強制します。`switch` はアクティブ化時に一度だけ切り替えてから解放します。`ignore` はそのアプリのロックを無効にします。`default` はグローバルのデフォルトに従います。 |
| `remove-app-rule` | `bundle` *(req)* | `bundle` のルールを削除します。ルールがなければ `rule_not_found`。 |
| `cycle-app-source` | `direction` *(req)*, `bundle` *(optional; default = frontmost app)* | そのアプリ自身のルールを次/前のソースへ進めます。アプリにルールがなければ何もしません（`rule_not_found`）。 |
| `remove-frontmost-app-rule` | — | 最前面にあるアプリのルールを削除します。 |
| `clear-app-rules` | — | **すべて**のアプリごとのルールを削除します。 |

### General settings

| Command | Parameters | Effect |
|---|---|---|
| `set-launch-at-login` *(alias `launch-at-login`)* | `enabled` = `true` \| `false` \| `toggle` | LockIME をログイン項目として登録/登録解除します。 |
| `set-language` | `code` = `en` \| `zh-Hans` \| `zh-Hant` \| `ja` \| `fr` \| `de` \| `es` \| `pt` \| `ru` \| `system` | アプリ内の言語オーバーライドを設定します。`system`（エイリアス `auto`）はそれをクリアし、macOS の言語に従います。寛容に解釈します：`zh-CN`→`zh-Hans`、`zh-TW`→`zh-Hant`、`fr-CA`→`fr`、… |

### Enhanced mode & per-URL rules

URL ごとのルールには、オプションの Accessibility ゲート付き**拡張モード**が必要です。

| Command | Parameters | Effect |
|---|---|---|
| `set-enhanced-mode` | `enabled` = `true` \| `false` \| `toggle` | 拡張モードをオン/オフ（または反転）します。 |
| `set-url-rule` | `host` *(req)*, `source` \| `source-name` *(req)*, `action` = `lock` \| `switch` *(default `lock`)*, `id` *(optional UUID)* | URL ごとのルールを作成または置き換えます。`host` は `github.com`（サブドメインにマッチ）や `*.example.com` のようなパターンです。`id` がなければ、同じ host の既存ルールが複製されずに更新されます。 |
| `remove-url-rule` | `id` *(UUID)* \| `host` | URL ルールを、その `id`（`list-url-rules` から）または `host` で削除します。 |
| `clear-url-rules` | — | **すべて**の URL ごとのルールを削除します。 |

### App

| Command | Parameters | Effect |
|---|---|---|
| `quit` | — | LockIME を終了します。 |

（[`set-language`](#general-settings) と [`set-launch-at-login`](#general-settings) も参照。）

LockIME は設計上、**UI を開くコマンドを一切公開していません**（設定・About・
アップデートウィンドウ）：この API はヘッドレスな自動化のためのものであり、
ウィンドウを操作するためのものではありません。

### Queries

クエリコマンドは `x-success` コールバック経由で JSON ペイロードを返します
（[x-callback-url](#x-callback-url) を参照）。

| Command | Result |
|---|---|
| `status` | 状態全体——[下記](#status-payload)を参照。 |
| `current-source` | ライブソースの `{ "id": "...", "name": "..." }`。 |
| `list-sources` *(alias `sources`)* | インストール済みソースの配列：`{ "id", "name", "isCJKV", "isEnabled", "isSelectCapable" }`。 |
| `list-app-rules` *(alias `app-rules`)* | `{ "bundleID", "mode", "source"? }` の配列。 |
| `list-url-rules` *(alias `url-rules`)* | `{ "id", "host", "action", "source" }` の配列。 |
| `list-log` *(aliases `log`, `recent-activations`)* | 直近 24 時間の強制切り替えエントリ。新しいものから順に：`{ "timestamp", "inputSource", "inputSourceName", "reason", "durationMs", "fromSourceName"?, "app"?, "bundleID"?, "ruleSource"?, "matchedHost"? }`。 |
| `get-config` *(alias `config`)* | 永続化された設定オブジェクト全体。 |
| `version` | `{ "version": "x.y.z", "build": "n" }`。 |
| `ping` | `{ "ok": true, "app": "LockIME", "version": "x.y.z", "build": "n" }`——軽量な存在確認/バージョンプローブ。 |

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

`currentSource`、`defaultSource`、`frontmostApp` は、判明している場合にのみ含まれます。

---

## Errors

失敗時（かつ `x-error` コールバックが存在する場合）、LockIME は安定したマシン向けの
`errorCode` と人間向けの `errorMessage` を付加します。エラーテキストは設計上**英語かつ
安定**です——あなたのアプリやログへと渡るため、決してローカライズされません。

| `errorCode` | When |
|---|---|
| `api_disabled` | API がオフです——「設定 ▸ 一般 ▸ 自動化」で有効化してください。 |
| `malformed_url` | URL を解析できませんでした。 |
| `no_command` | コマンドトークンが指定されませんでした。 |
| `unknown_command` | コマンドトークンが認識されませんでした。 |
| `missing_parameter` | 必須パラメータが存在しません。 |
| `invalid_parameter` | パラメータ値が範囲外です（不正な `mode`、`action`、`direction`、`code`、または UUID）。 |
| `unknown_source` | `id`/`name` がインストール済みで選択可能なソースのいずれにもマッチしません。 |
| `no_input_sources` | 選択可能な入力ソースが一つもインストールされていません。 |
| `rule_not_found` | 対象のアプリ/URL ルールが存在しません。 |
| `not_supported` | 操作を完了できませんでした（例：設定のシリアライズ）。 |

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

**Open URLs** アクションに `lockime://lock` を指定するか、**Get Contents of URL**
と x-callback-url 形式を組み合わせて状態を読み取ります。

**スクリプトからステータスを読み取る**（コールバック受信アプリ/URL を使用）：

```sh
open "lockime://status?x-success=myreceiver%3A%2F%2Fstatus"
```

---

## Notes & guarantees

- **冪等かつ取り消し可能。** コマンドの再送信は安全です。あなたが要求したルール編集を
  超えて破壊されるものはありません。
- **フォーカスを決して奪いません。** LockIME を前面に持ってきたり、そのウィンドウの
  いずれかを開いたりするコマンドはありません——この API は設計上ヘッドレスです。
- **ロックは権威を保ちます。** `switch-source` は一度きりの好意的な切り替えです。
  常駐する継続ロックは自身のソースを再主張します。
- **ソースの同一性は `id`。** 表示名は便宜的なもので、システムロケールに依存します。
  安定した自動化には `id`（`list-sources` から）を優先してください。
- **バックアップに API は含まれません。** 設定のエクスポート/インポート（`.lockime`
  ファイル）はルールを対象とし、API 固有のものは対象外です——別途持ち運ぶべき API
  状態は存在しません。
