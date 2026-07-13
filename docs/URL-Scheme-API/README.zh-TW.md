# URL Scheme API

[English](README.md) · [简体中文](README.zh-CN.md) · **繁體中文** · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md)

LockIME 提供一個 `lockime://` URL scheme，讓其他應用程式、指令稿、「捷徑」（Shortcuts）、
Stream Deck、Alfred/Raycast、AppleScript——任何能開啟 URL 的東西——都能驅動它：
開啟或關閉它、重新指定輸入法、管理規則，並讀回狀態。

每個指令都是一個 URL，預設為發出即不管（fire-and-forget），並可選擇搭配
[x-callback-url](https://x-callback-url.com) 回呼，用於成功/錯誤，以及從查詢指令回傳資料。

> **請先啟用。** URL Scheme API **預設為關閉**。請到
> **LockIME ▸ 設定 ▸ 一般 ▸ 自動化 ▸ URL Scheme API** 把它開啟。在它關閉期間，
> 每個指令都會回傳 `api_disabled` 錯誤，且不會有任何動作。

> **安全提示。** 一旦啟用，指令執行時**不會逐一出現確認提示**——任何
> 能開啟 `lockime://` URL 的程序（包括一個網頁）都能驅動 LockIME。每個指令都可逆，
> 而且都不會碰你的檔案；惡意呼叫者最多只能切換你的輸入法鎖定或編輯規則。
> 不使用時，請讓 API 保持關閉。

---

## URL shape

接受兩種等效的形式：

```
lockime://<command>?<param>=<value>&<param>=<value>
lockime://x-callback-url/<command>?<param>=<value>&…
```

- **指令權杖**（`<command>`）不分大小寫。
- **參數名稱**不分大小寫；**參數值**會被原樣採用
  （所以 bundle ID 和 source ID 會保留其大小寫）。
- 對於含有保留字元（`?`、`&`、`=`、`/`、空格、…）的值，
  務必進行 **percent-encode**。一個像 `ABC – Extended` 這樣的輸入法顯示名稱
  會變成 `name=ABC%20%E2%80%93%20Extended`。

`x-callback-url/` 前綴是給 x-callback-url 工具用的可選糖衣語法；
下方的回呼參數在裸形式上同樣有效。

> **Development builds.** LockIME 的 Debug 建置會註冊 `lockime-dev://`
> 而非 `lockime://`，所以本地建置永遠不會劫持已安裝
> 正式版的 scheme。其餘一切完全相同。

---

## x-callback-url

任何指令都可以攜帶這些保留參數：

| Parameter | Meaning |
|---|---|
| `x-success` | 指令成功後開啟的 URL。對於**查詢**指令，JSON 結果會以 `result=<json>`（經 percent-encode）附加在後面。 |
| `x-error`   | 指令失敗時開啟的 URL，並在後面附加 `errorCode=<code>&errorMessage=<text>`。 |
| `x-source`  | 呼叫端應用程式的顯示名稱（僅供參考；LockIME 會記錄它）。 |

動作指令會觸發 `x-success` 但不帶 `result`。查詢指令會透過
`x-success` 回傳其酬載；若沒有 `x-success` URL，查詢就沒有地方
送出其結果（它仍會執行，且無害）。

往返範例——索取狀態並把它收回你自己的應用程式：

```
lockime://status?x-success=myapp%3A%2F%2Fgot-status
```

成功時 LockIME 會開啟：

```
myapp://got-status?result=%7B%22enabled%22%3Atrue%2C…%7D
```

---

## Command reference

### Enable & disable

`lock` / `unlock` / `toggle-lock` 負責開關 **LockIME**——這個唯一的開關把關一切（鎖定與切換皆然）。若想在全域停止固定任何輸入法，同時讓你的依應用程式／依站台切換規則繼續觸發——也就是「像純粹切換器那樣運作」的模式——請改為把全域預設輸入法設為**無**（不帶輸入法參數的 `set-default-source`）。

| Command | Parameters | Effect |
|---|---|---|
| `lock` | — | 開啟 **LockIME**——套用你的規則。 |
| `unlock` | — | 關閉 **LockIME**——完全閒置。 |
| `toggle-lock` *(alias `toggle`)* | — | 翻轉 LockIME 的開／關。 |

### Global input source

一個**輸入法**由 `id`（標準的 Text Input Source 識別字，例如
`com.apple.keylayout.ABC`，即 [`list-sources`](#queries) 回傳的值）或由
`name`（其在地化的顯示名稱，不分大小寫）指定。它必須指向一個目前已
安裝、可選取的輸入法，否則指令會回傳 `unknown_source`。

| Command | Parameters | Effect |
|---|---|---|
| `lock-to-source` | `id` \| `name` | 設定全域預設輸入法**並**開啟 LockIME。 |
| `set-default-source` | `id` \| `name` *(omit both to clear)*, `action` = `lock` \| `switch` *(default `lock`)* | 設定（或清除）全域預設輸入法，不改變開/關狀態。`action` 決定這個預設是要**鎖定**（持續強制使用該輸入法），還是在應用程式退回全域預設時（沒有更高優先序的 URL 或應用程式規則固定住某個輸入法）**切換**到它一次，然後放手；在清除路徑上它會被忽略。 |
| `cycle-source` | `direction` = `next` \| `previous` | 把全域目標推進到下一個/上一個已安裝的輸入法（循環），並開啟 LockIME。 |
| `switch-source` | `id` \| `name` | 立刻把目前的輸入法**切換一次**，僅此一次——它**不會**開啟或修改持續鎖定。若此時已有持續鎖定在生效，它會勝出，並把輸入法切回鎖定目標。 |

`direction` 也接受別名 `prev`、`forward`、`back`、`up`、`down`。

### Per-app rules

| Command | Parameters | Effect |
|---|---|---|
| `set-app-rule` | `bundle` *(req)*, `mode` = `lock` \| `switch` \| `ignore` \| `default` *(default `lock`)*, `source` \| `source-name` *(req for `lock`/`switch`)* | 為一個應用程式建立或取代規則。`lock` 會持續強制使用該輸入法；`switch` 會在啟用時切換一次然後放手；`ignore` 會為該應用程式停用鎖定；`default` 會退回使用全域預設。 |
| `remove-app-rule` | `bundle` *(req)* | 刪除 `bundle` 的規則。若不存在則回傳 `rule_not_found`。 |
| `cycle-app-source` | `direction` *(req)*, `bundle` *(optional; default = frontmost app)* | 把該應用程式自己的規則推進到下一個/上一個輸入法。若該應用程式沒有規則則為無操作（`rule_not_found`）。 |
| `remove-frontmost-app-rule` | — | 刪除目前最前方應用程式的規則。 |
| `clear-app-rules` | — | 移除**所有**依應用程式規則。 |

### General settings

| Command | Parameters | Effect |
|---|---|---|
| `set-launch-at-login` *(alias `launch-at-login`)* | `enabled` = `true` \| `false` \| `toggle` | 把 LockIME 註冊/取消註冊為登入項目。 |
| `set-language` | `code` = `en` \| `zh-Hans` \| `zh-Hant` \| `ja` \| `fr` \| `de` \| `es` \| `pt` \| `ru` \| `system` | 設定應用程式內的語言覆寫；`system`（別名 `auto`）會清除它並跟隨 macOS 語言。寬鬆相容：`zh-CN`→`zh-Hans`、`zh-TW`→`zh-Hant`、`fr-CA`→`fr`、…。 |

### Enhanced mode & per-URL rules

依 URL 規則需要可選的、由 Accessibility 把關的**增強模式**。

| Command | Parameters | Effect |
|---|---|---|
| `set-enhanced-mode` | `enabled` = `true` \| `false` \| `toggle` | 開啟/關閉增強模式（或翻轉它）。 |
| `set-url-rule` | `host` *(alias `pattern`, req)*, `source` \| `source-name` *(req)*, `match-type` = `domain-suffix` \| `domain` \| `domain-keyword` \| `url-regex` *(default `domain-suffix`)*, `action` = `lock` \| `switch` *(default `lock`)*, `id` *(optional UUID)* | 建立或取代一條依 URL 規則。模式如何比對取決於 `match-type`（見[下方](#match-types)）。若不帶 `id`，會更新同一模式的既有規則，而不是建立重複的。 |
| `remove-url-rule` | `id` *(UUID)* \| `host` | 依其 `id`（來自 `list-url-rules`）或依 `host` 刪除一條 URL 規則。 |
| `clear-url-rules` | — | 移除**所有**依 URL 規則。 |

#### Match types

`match-type` 決定一條規則的模式如何與瀏覽器目前的 URL 比對。規則會
**由上而下評估，第一個比對到的勝出**，所以它們的順序就是它們的優先序
（在 **設定 ▸ 依 URL 規則** 中拖曳即可重新排序）。

| `match-type` | Pattern is… | Matches |
|---|---|---|
| `domain-suffix` *(default)* | 一個 host，例如 `github.com` | 該 host **及其所有子網域**（`github.com`、`gist.github.com`）。開頭的 `*.` 可被容忍。 |
| `domain` | 一個 host，例如 `github.com` | **只比對該確切 host**，絕不含子網域。 |
| `domain-keyword` | 一個子字串，例如 `google` | 任何**包含**它的 host（`google.com`、`mail.google.com`、`googleapis.com`）。 |
| `url-regex` | 一個正規表示式 | **整個 URL**（scheme · host · path · query · fragment）——不分大小寫且不錨定。唯一能依 path 或 query 區分同一站台不同頁面的類型。無法編譯的模式會以 `invalid_parameter` 被拒。 |

`match-type` 也接受 `suffix`、`keyword`、`regex` 等別名。對於一條
`url-regex` 規則，模式通常含有必須在 URL 中 percent-encode 的字元
（`?`、`&`、`/`、`\`）。

### App

| Command | Parameters | Effect |
|---|---|---|
| `quit` | — | 結束 LockIME。 |

（另見 [`set-language`](#general-settings) 與 [`set-launch-at-login`](#general-settings)。）

LockIME 刻意**不提供任何開啟其 UI 的指令**（Settings、About、更新視窗）：
這個 API 是給無介面（headless）的自動化用的，而不是用來驅動視窗。

### Queries

查詢指令會透過 `x-success` 回呼回傳一個 JSON 酬載（見
[x-callback-url](#x-callback-url)）。

| Command | Result |
|---|---|
| `status` | 整個狀態——見[下方](#status-payload)。 |
| `current-source` | 使用中輸入法的 `{ "id": "...", "name": "..." }`。 |
| `list-sources` *(alias `sources`)* | 已安裝輸入法的陣列：`{ "id", "name", "isCJKV", "isEnabled", "isSelectCapable" }`。 |
| `list-app-rules` *(alias `app-rules`)* | `{ "bundleID", "mode", "source"? }` 的陣列。 |
| `list-url-rules` *(alias `url-rules`)* | `{ "id", "host", "action", "matchType", "source" }` 的陣列，依優先序排列（第一個比對到的勝出）。 |
| `list-log` *(aliases `log`, `recent-activations`)* | 過去 24 小時的強制切換條目，最新的在前：`{ "timestamp", "inputSource", "inputSourceName", "reason", "durationMs", "fromSourceName"?, "app"?, "bundleID"?, "ruleSource"?, "matchedHost"? }`。 |
| `get-config` *(alias `config`)* | 完整的持久化設定物件。 |
| `version` | `{ "version": "x.y.z", "build": "n" }`。 |
| `ping` | `{ "ok": true, "app": "LockIME", "version": "x.y.z", "build": "n" }`——一個低成本的存在/版本探測。 |

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

`enabled` 就是那個唯一的「啟用 LockIME」開關——它開啟時，你的規則便會生效。
`currentSource`、`defaultSource` 和 `frontmostApp` 只在已知時才會出現；
`defaultAction`（`lock` \| `switch`）會在設定了全域預設時，隨 `defaultSource` 一起出現。

---

## Errors

失敗時（且存在 `x-error` 回呼時），LockIME 會附加一個穩定的
機器用 `errorCode` 和一個人類可讀的 `errorMessage`。錯誤文字在設計上是**英文且
穩定的**——它會跨入你的應用程式並進入記錄，所以永遠不會被在地化。

| `errorCode` | When |
|---|---|
| `api_disabled` | API 已關閉——請到「設定 ▸ 一般 ▸ 自動化」啟用它。 |
| `malformed_url` | 無法解析此 URL。 |
| `no_command` | 未提供指令權杖。 |
| `unknown_command` | 無法辨識此指令權杖。 |
| `missing_parameter` | 缺少一個必要參數。 |
| `invalid_parameter` | 一個參數值超出範圍（不正確的 `mode`、`action`、`match-type`、`direction`、`code`，無法編譯的 `url-regex` 模式，或格式錯誤的 UUID）。 |
| `unknown_source` | 此 `id`/`name` 沒有比對到任何已安裝且可選取的輸入法。 |
| `no_input_sources` | 沒有安裝任何可選取的輸入法。 |
| `rule_not_found` | 目標的應用程式/URL 規則不存在。 |
| `not_supported` | 無法完成此操作（例如設定序列化）。 |

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
# url-regex 會比對整個 URL——請把模式 percent-encode（此處為：github\.com/.*/pull）
open "lockime://set-url-rule?pattern=github%5C.com%2F.%2A%2Fpull&source=com.apple.keylayout.ABC&match-type=url-regex"
open "lockime://set-launch-at-login?enabled=on"
```

**AppleScript**

```applescript
open location "lockime://toggle-lock"
```

**Shortcuts (macOS)**

新增一個 **Open URLs** 動作搭配 `lockime://lock`，或用 **Get Contents of URL**
加上 x-callback-url 形式來讀回狀態。

**Read status from a script**（使用一個回呼接收端應用程式/URL）：

```sh
open "lockime://status?x-success=myreceiver%3A%2F%2Fstatus"
```

---

## Notes & guarantees

- **幂等且可逆。** 重送一個指令是安全的；除了你要求的規則編輯之外，
  不會有任何東西被破壞。
- **永不搶奪焦點。** 沒有任何指令會把 LockIME 帶到前景或開啟它的任何視窗
  ——這個 API 在設計上就是無介面（headless）的。
- **鎖定始終具有權威性。** `switch-source` 是一次性的禮貌切換；一個
  常駐的持續鎖定會重新堅持使用它的輸入法。
- **輸入法的身分是 `id`。** 顯示名稱只是方便起見，而且取決於
  系統語言；要做穩定的自動化，請優先使用 `id`（來自 `list-sources`）。
- **備份不包含 API。** 設定的匯出/匯入（`.lockime` 檔案）
  涵蓋的是你的規則，而非任何 API 專屬的東西——沒有獨立的 API 狀態
  需要攜帶。
