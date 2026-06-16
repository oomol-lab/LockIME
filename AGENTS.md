# LockIME

Design spec: `docs/DESIGN.md`. Release process: `docs/RELEASING.md`.
Build/test: `make build` / `make test` (xcodegen + xcodebuild; see `Makefile`).
Update flows: `make update-test-{none,download-fail,extract-fail,success}`
runs Sparkle against a local feed (see `scripts/update-lab/README.md`).

## Localization (i18n) — hard rules

The app has an **in-app language override** (`LanguagePreference`), so the
macOS system language is irrelevant to what the user must see. Consequences:

- **Never display text localized by someone else's bundle.** Foundation/Sparkle
  `error.localizedDescription` resolves against the *system* language and
  produces mixed-language UI. Map errors to semantic categories whose messages
  are catalog keys (see `UpdateFailure`), and log the original error instead.
- SwiftUI surfaces resolve string literals live via the injected `\.locale`.
  AppKit surfaces (`NSAlert`, window titles) bypass that — route them through
  `AppKitStrings` / `AppState.loc`. This includes SwiftUI modifiers that
  *bridge into AppKit*: `.navigationTitle("Key")` resolves the key against the
  system language when it becomes the `NSWindow` title — pass
  `state.loc("Key")` instead.
- Third-party **views** are third-party bundles too: KeyboardShortcuts'
  `Recorder` localizes its placeholder and conflict alerts from its own
  `.lproj`s against the system language. Any package that draws its own text
  must have its resource bundle listed in `ThirdPartyBundleLocalization`,
  which re-classes it to resolve in the app's chosen language (English
  fallback, never system).
- Every user-facing string needs an entry in `Localizable.xcstrings` translated
  for **all** `SupportedLanguage` cases. Keys reached only via
  `loc(...)`/`LocalizedStringKey(variable)` are invisible to Xcode's extractor —
  add them to the catalog by hand.
- `Tests/LockIMEKitTests/LocalizationGuardTests.swift` enforces the above
  (no `localizedDescription` in `Sources/LockIME`, no literal
  `.navigationTitle("...")`, redirected third-party bundles exist and cover
  every `SupportedLanguage`, full catalog coverage, dynamic keys exist). Keep
  it green; extend it when adding new dynamic-key entry points or third-party
  UI packages.
- Manual smoke test for any new surface: set the app language to something
  *different* from the system language and walk the flow — any mixed-language
  screen is a bug.

## Documentation translations — hard rules

The README ships in **every `SupportedLanguage`**. English is the authoritative
source and lives at the repo root (`README.md` — the **only** README there);
the translations live in `docs/README/`, kept in sync. The **URL Scheme API**
reference ships in every language too: English authoritative at
`docs/URL-Scheme-API/README.md`, translations at
`docs/URL-Scheme-API/README.<code>.md` (same `<code>` naming and language-switcher
convention as the README, switcher links by bare sibling filename; the H1 and all
`##`/`###` headings stay English, and every `lockime://` token, parameter, error
code, URL, and JSON key/value stays byte-for-byte identical). The remaining docs
under `docs/` (`DESIGN.md`, `RELEASING.md`) are **English-only — do not translate
them.**

- **Naming:** translations are `docs/README/README.<code>.md` with **region**
  codes for Chinese (`zh-CN`, `zh-TW` — *not* the script codes
  `zh-Hans`/`zh-Hant`) and bare language codes otherwise:
  `ja`, `fr`, `de`, `es`, `pt`, `ru`.
- **Language switcher:** every README carries a nav line directly under the H1
  listing **all** languages in `SupportedLanguage` declaration order, with the
  current language **bold and unlinked**. Autonyms (`English`, `简体中文`,
  `繁體中文`, `日本語`, `Français`, `Deutsch`, `Español`, `Português`,
  `Русский`) are never translated. From `docs/README/` the English link is
  `../../README.md`; sibling translations are linked by bare filename.
- **Intra-doc links point at the English docs.** From `docs/README/` that is
  `../DESIGN.md` / `../RELEASING.md` (there are no translated docs), and the
  license link is `../../LICENSE`.
- **Badges:** the license badge is a **static** shields.io badge
  (`img.shields.io/badge/license-GPL--3.0-3A5BD9`) — never the dynamic
  `github/license/...` endpoint, which hits the GitHub API and breaks when
  rate-limited. Localized screenshots exist for `en` and `zh-CN` only; every
  other translation uses the `en` screenshots.
- **Never translate code.** Fenced/inline code, shell commands, file paths,
  identifiers, `make` targets, env-var and secret names, URLs, hex colors,
  version strings, framework and brand names (LockIME, Sparkle, SwiftUI,
  macOS, Tahoe, …) stay byte-for-byte identical. The H1 keeps the bare
  `# LockIME` brand. Section headings (`## Features`, …) also stay in English.
- **When you edit `README.md`, update every translation in `docs/README/` in
  the same change** (or explicitly flag the drift). When a language is added
  to `SupportedLanguage`, add its README and extend every nav line.
