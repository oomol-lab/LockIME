# LockIME Design Specification — macOS 26 "Tahoe" First-Class

> The single source of truth for LockIME's visual & interaction design. Grounded
> in Apple HIG (macOS 26 / Liquid Glass) and the patterns of top menu-bar apps
> (Ice, Loop, Stats, Bartender, System Settings, Apple Software Update).
>
> **Deployment floor: macOS 14.0** (anchored by `@Observable`; going lower
> means rewriting the observation layer). "Tahoe first-class" is a design
> target, not an API dependency: the glass aesthetic comes from the system
> rendering standard controls on macOS 26. Newer-OS API is allowed solely
> behind `#available` with a sane fallback — currently two cases: the
> `dsGlass*ButtonStyle()` helpers in `DesignSystem.swift` (26 → bordered
> styles) and the settings `Tab` builder + Updates badge in
> `SettingsRootView.swift` (15 → `.tabItem`, no badge). Everything else must
> compile against the 14.0 target, which the compiler enforces. Pre-26 the
> app renders with standard Sonoma/Sequoia materials.

## 1. North star

LockIME is a **calm, native, system-native security utility** that looks like it
shipped with macOS 26. *If it isn't a System Settings pane, an Apple Software
Update sheet, or the system volume HUD, we don't ship it.*

- Liquid Glass is **navigation-layer only** (update-window action buttons, the
  menu-bar popup chrome the OS gives us for free). **Never** glass on content
  (Forms, changelog, log rows, rule rows).
- Hand-roll nothing the OS supplies: **semantic colors, system materials, SF
  Symbols** drive light/dark/accessibility adaptation automatically.
- Brand expresses itself through exactly three levers: **one indigo accent, one
  sharp full-bleed app icon, one signature lock/unlock symbol transition.**
- Never hardcode `.white`/`.black`/RGB. Never import iOS 17pt type — macOS body
  is **13pt**.

## 2. Design tokens — `DS` namespace (`Sources/LockIME/UI/DesignSystem.swift`)

Caseless namespaced enums. Reference tokens everywhere; never inline literals.
**Inside `.formStyle(.grouped)` Forms, add no spacing/padding — the Form owns its
insets.** Tokens apply to custom views (About, Update, picker).

### Spacing (4pt grid)
`xxs 2 · xs 4 · sm 6 · md 8 · lg 12 · xl 16 · xxl 24 · section 32`

### Corner radii
`control 6 · row 10 · panel 12 · sheet 16` · capsule for confirmation/glass.
For nested custom containers prefer `RoundedRectangle(cornerRadius: .containerConcentric)`.

### Accent — brand "Lock Indigo" (asset-catalog `AccentColor`, set as Global Accent)
`.tint()` alone does **not** reach AppKit `Picker`/checkbox/focus-ring on macOS,
and App/URL Rules use Pickers heavily — so the asset + `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME=AccentColor` is mandatory.

| Appearance | Hex (sRGB) |
|---|---|
| Light | `#3A5BD9` |
| Dark | `#5B7BF0` |
| Light · Increase Contrast | `#2A46B8` |
| Dark · Increase Contrast | `#7E98FF` |

Accent **only** on: the locked state, the one prominent update button, links.
Destructive (trash) = `Button(role: .destructive)` system red. Status semantics
(success `.green`, error `.orange`/`.red`) confined to update-window results.

### Typography (macOS scale — semantic styles, never `.system(size:)`)
`appName .title semibold` · `windowTitle .title2 bold` · `rowTitle .body` ·
`version .callout` · `rowSubtitle .caption2` · `sectionFooter .footnote` ·
`copyright .caption`. Foreground ramp: `.primary` · `.secondary` · `.tertiary` ·
`.quaternary`.

### Materials
Settings content: **no material**. Transient confirmation / About panel / Update
backdrop: `.regularMaterial`. Update action buttons: `.glassProminent` (one
primary) + `.glass` (secondary). Never `NSVisualEffectView` by hand; never
`.clear` glass; never glass-on-glass without `GlassEffectContainer`.

### Motion
`toggle .spring(response:0.3, dampingFraction:0.85)` · `list .smooth(0.25)` ·
`confirmIn .easeOut(0.18)` · `confirmOut .easeIn(0.22)` · dwell `2.0s`.
One signature moment only: `.contentTransition(.symbolEffect(.replace))` on
`lock.fill`↔`lock.open`. Gate manual springs on `accessibilityReduceMotion`.

## 3. App icon — `Assets.xcassets/AppIcon.appiconset` (full PNG set)

Classic 10-image macOS `.appiconset`, **not** Icon Composer `.icon` (headless/CI
friendly). The source master stays full-bleed, but the shipped appicon PNGs are
composed onto the **standard macOS icon grid** — an ~824px rounded body inset on
a transparent margin (the central ~80.5% of the 1024 canvas) with a soft system
drop shadow — so the icon renders the same size as every native app and never
exposes raw square corners. A full-bleed PNG renders ~24% larger than its
neighbours on older Launchpad/Finder surfaces that draw the resource verbatim.
macOS 26 (Tahoe) instead **re-normalizes** legacy icons — it scales the opaque
art to its own uniform grid and re-masks — so it caps the old full-bleed PNG to
the right size at draw time but renders an *under*-filled body too small; the fix
is to match Apple's own on-disk geometry exactly (body 824, opaque bbox ≈842/1024
incl. shadow, measured from `/System/Applications/*.app`), which then tracks the
system icons on **both** the verbatim (≤15) and normalizing (26) paths. Verified
on Tahoe: the composed icon renders at the same 844px/82.4% as Calculator.
`.icon` (Icon Composer / full Liquid Glass) deferred as future polish.

- **Master 1024×1024, PNG-24, sRGB, opaque, FULL-BLEED source art.** Do **not**
  add a gutter, gloss, bevel, or shadow — the generator adds the margin, mask,
  and shadow. Glyph within ~10% safe inset (central ~820²). The shipped body is
  inset to `824/1024` of the canvas (margins matched empirically to
  `/System/Applications/*.app`) and rounded at `cornerRadius ~= body * 0.225`.
- Required 10 images (idiom=mac): 16, 32(16@2x), 32, 64(32@2x), 128, 256(128@2x),
  256, 512(256@2x), 512, 1024(512@2x). **All ten** — one PNG → empty plist → grey
  generic icon.
- Pipeline: `scripts/MakeIcon.swift` (SwiftUI `ImageRenderer`) renders the 1024
  master when the committed raster master is absent;
  `scripts/icon-tools/ComposeAppIcon.swift` composes the grid-correct 1024 (inset
  body + mask + shadow); `sips` downscales that single 1024 into every size;
  hand-written `Contents.json`. Cache-bust when verifying:
  `sudo rm -rf /Library/Caches/com.apple.iconservices.store; killall Dock`.
- **Visual:** opaque diagonal indigo→blue (`#2A5BE0`→`#1840B4`); near-white
  `#F5F7FF` closed padlock with a subtle IME affordance (文/A monogram or caret);
  flat/clean, at most a faint top inner highlight. Keep the blue art full-bleed
  in the *master*; the generator insets it onto the icon body. Do not bake the
  margin, shadow, or new-system glass into the master PNG.
- Wiring: `project.yml` → target `resources: - path: Sources/LockIME/Assets.xcassets`
  and `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. **Do not** add
  `CFBundleIconName`/`CFBundleIconFile` to Info.plist — actool injects them.

## 4. Per-surface specs

### 4.1 Menu-bar menu — native `.menuBarExtraStyle(.menu)`
Bar glyph: template `lock.fill`/`lock.open`, swapped by state, optional one-shot
`.symbolEffect`. Header: a padlock glyph (`lock.fill` when locked,
`lock.open.fill` when unlocked) plus the lock state word only ("Locked" /
"Unlocked"), with the configured global toggle-lock shortcut echoed on the right.
The current source name is **deliberately not repeated** here — the list below
already marks the locked source with a checkmark. It's a **disabled** `Button`:
a `Label` alone won't render a menu accelerator, but a disabled Button draws the
key-equivalent glyphs natively while never firing them, so it stays a pure hint
with no clash against the real global handler. The shortcut is read from
`AppState.toggleLockShortcut` (mirrored from `KeyboardShortcuts` and kept in sync
via the library's `shortcutByNameDidChange` notification — a plain `getShortcut`
read isn't `@Observable`-tracked, so the header wouldn't refresh when the user
binds/clears it in Settings). It's mapped through `menuDisplayShortcut`, a
best-effort `KeyboardShortcut` for single printable keys (any modifiers, up to
"⌃⌥⇧⌘X"); exotic keys (Space, arrows, F-keys) still work globally but aren't
echoed. **The system input sources are flattened directly into the
menu**, bracketed by one divider above and one below — no master toggle, no
submenu. Each source is a `Button` carrying a leading checkmark **image** (the
`CheckmarkSlot` NSImages), shown on the locked one and a same-size transparent
slot otherwise; a source is checked iff locking is on **and** it is the global
target (`config.defaultSourceID`). The image (not a `Toggle`'s native checkmark,
which lives in NSMenu's *state* column and collapses to zero width when nothing
is checked) keeps the gutter reserved at a constant width, so the menu never
grows or shrinks as the lock toggles — and NSMenu drops SwiftUI's `.opacity` on a
Label's system-image icon, so the slot must swap the image itself, not hide a
symbol. Clicking an unchecked source locks to it (`AppState.lockToSource` sets
the target *and* turns the master **and** the lock sub-toggle on in one commit,
re-resolving and flipping the active source immediately); clicking the checked
source clears just the global lock target (`setDefaultSource(nil)`) — the app and
any one-shot switch rules stay live. This is the same
write path as the App Rules "Global default" picker. Source names are
`Text(verbatim:)` system strings, not catalog keys. The
engine keeps the list live via a second
`InputSourceChangeObserver(.enabledSourcesChanged)`, so adding/removing an input
source in System Settings updates both this menu and the Settings pickers. The
global toggle-lock shortcut (Settings ▸ Shortcuts) flips the master
(Enable LockIME) on/off; `lockingEnabled` persists across toggles, so a
pure-switch user stays in pure-switch mode.
Collapse Settings / Check for Updates / About into one `Section` (fewer dividers).
Keep `.keyboardShortcut` hints. Zero custom color — NSMenu supplies everything.
(Active-scope `.badge` is a nice-to-have — verify it renders on the real macOS 26
build before relying on it.)

### 4.2 Settings window — top 7-tab `TabView`, widened
No sidebar (`.sidebarAdaptable` breaks `ToolbarSpacer` on macOS). Frame
`minWidth 680, idealWidth 700, minHeight 600`, growable. (`minHeight` sized so the
tallest pane — General, now with the **Automation** ▸ URL Scheme API toggle —
fits without a scrollbar even at the minimum window height.) `.scenePadding()` at
window level; panes own internal insets — verify no double-padding. Tab
selection is bound to `AppState.settingsTab` (so a feature pane can route the
user to **Permissions** for the single Accessibility grant); the root view's
`onDisappear` (window close, not a tab switch) is the abandon signal that stops
the grant watcher.

- **General:** two stacked toggles — the master **Enable LockIME**
  (`config.isEnabled`, gates everything) and the subordinate **Enable locking**
  (`config.lockingEnabled`, the continuous lock), the latter `.disabled` while the
  master is off (HIG dependency: indent + dim). Locking off is the "act like Input
  Source Pro" mode — switch rules still fire, nothing is pinned. Both animate with
  `withAnimation(DS.Motion.toggle)`. Then current source + activation count via
  `LabeledContent`, launch-at-login, language. The padlock surfaces (tray/About
  icon, menu glyph/header, checkmark) track `isLocked = isEnabled &&
  lockingEnabled`, so they look unchanged for anyone who leaves locking on.
- **App / URL Rules:** rows via shared `AppRowLabel(bundleID:)` (icon 22 + name
  `.body` + bundle ID `.caption2 .secondary`). Empty state =
  `ContentUnavailableView` with an action. Rows `.transition(.move(edge:.top)
  .combined(with:.opacity))`; wrap upsert/remove in `withAnimation(DS.Motion.list)`.
  Each source-pinning rule carries a **lock vs switch** action: *lock* (`.locked`
  / URL `.lock`) continuously re-applies the source while the rule is in force;
  *switch* (`AppRuleMode.switched` / URL `RuleAction.switchOnce`) fires a one-shot
  switch on entry and then releases, so the user may change the source and is
  never reverted. App rules express it as a fourth mode-picker option ("Switch
  to", beside Lock to / Ignore / Use default); URL rows carry a small Lock to /
  Switch to picker. The **global default stays lock-only**. The one-shot's
  fire-exactly-once-per-entry is owned by `LockEngine` (an in-memory transition
  key, with a separate slot for a launcher overlay's own switch so an excursion
  never re-yanks the underlying app); the kit's `LockController.switchOnce`
  performs the switch without installing a standing target.
- **Shortcuts:** native recorder rows in two sections — **Global** (toggle lock,
  lock to previous/next input source) and **Current app** (cycle, or remove, the
  frontmost app's rule). Recorder titles must be `LocalizedStringKey(...)`, not a
  bare `String` literal, or the label renders in the system language (see the
  i18n guards in CLAUDE.md).
- **Permissions:** the single home for the optional Accessibility grant
  (`AXIsProcessTrusted`), which unlocks two features — per-URL rules and
  launcher-overlay detection (Spotlight/Raycast/…). One `GrantAccessibilityButton`
  (shared in `Components.swift`) lives **only** here; App Rules and URL Rules show
  a passive `AccessibilityRequiredNote` that routes here, so the permission reads
  as one capability with a single grant, never a prompt duplicated per feature.
  The core lock stays permission-free.
- **Updates:** `LabeledContent` "Last checked: …" ("Never" fallback), Check
  button, inline up-to-date/error result (see 4.6), badge the tab when an update
  is available.
- **Log:** plain rows on content background; `.controlSize(.small)` dense; no glass.

Shared layer in `Sources/LockIME/UI`: `AppRowLabel`, `SectionFooter(_:)`, tokens.

### 4.3 About window
Frame 340 wide, content-driven height (~330), non-resizable, no toolbar/title.
Background `.regularMaterial`. Rhythm: 28 top · icon **128** (`NSApp.applicationIconImage`)
· 14 · name `.title` semibold · 2 · "Version x (y)" `.callout .secondary`
selectable · 12 · tagline `.subheadline .secondary` · 14 · links row · Spacer ·
copyright `.caption .tertiary` · 20 bottom. Links (`.buttonStyle(.link)`): GitHub,
Website, Acknowledgements (sheet listing Sparkle / KeyboardShortcuts /
PermissionFlow licenses).

### 4.4 Update window — Apple Software Update parity
Fixed **540×480**, non-reflowing across phases. Header: **real app icon 52pt**
(not the lock SF Symbol), title `.title2.bold` "Software Update", subtitle
`.subheadline .secondary` "Version X is available", 20pt padding, Divider.
Body: `ScrollView` + Markdown `.gitHub` ~13pt, 16–20pt padding, empty/long handled.
Footer: 16–20pt padding, Divider above, determinate `ProgressView(value:)` ~220pt
or small spinner; trailing buttons 8–12 gap: primary `.glassProminent`
("Install Update" → "Install and Relaunch"), secondary `.glass` "Later", tertiary
link **"Skip This Version"** on `.found` only (one-shot reply guard). Result states
centered with semantic color + text.

### 4.5 App picker (sheet)
Searchable list, rows reuse `AppRowLabel` (icon 32). Sorted by name. Standard sheet
footer (Add / Cancel). No glass.

### 4.6 Toast replacement — DELETE `ToastPresenter`/`ToastView`
The black capsule is the single most off-brand element (ignores light/dark, accent,
Reduce Transparency). Replace with:
1. **User-initiated up-to-date/error → native `NSAlert`** (app icon, single OK,
   fully adaptive) and update the "Last checked" timestamp; when the Updates pane
   is open, also reflect the result inline next to the Check button.
2. **Scheduled/background find → gentle, non-modal:**
   `supportsGentleScheduledUpdateReminders = true`; post a `UNUserNotification` +
   badge the Updates tab. **Never** auto-open the window for background checks or
   "no update".

## 5. Key decisions

| Question | Decision |
|---|---|
| Toast | Delete; NSAlert + inline Updates result + "Last checked" |
| Settings nav | Keep top TabView (7 tabs incl. Permissions), widen to 680 |
| Icon format | `.appiconset` PNG set, full-bleed source, pre-masked shipped PNGs |
| Accent delivery | Asset-catalog `AccentColor` as Global Accent |
| Update header art | Real app icon, not lock SF Symbol |
| Menu style | Native `.menu` |
| About icon | 128pt |
| Glass scope | Update buttons + transient confirmation only |
| About/Update window host | **Keep `HostedWindowController`** — SwiftUI `Window` scenes opened from an `LSUIElement` menu fall behind other windows (project-verified P11 bug). Give the hosted window Tahoe styling itself. |

## 6. Risks (Xcode 26 / macOS 26)

- Opaque full-bleed appiconset PNGs expose square corners on older Launchpad.
  Keep the source full-bleed, but ship the masked PNGs in all 10 sizes.
- Icon caching hides rebuilds — bust the iconservices cache + `killall Dock`.
- No manual `CFBundleIcon*` keys — actool owns them.
- `.tint()` no-ops on macOS `Picker` — use the `AccentColor` asset (app target,
  not the SPM module).
- No glass on content; never animate persistent glass (battery for a bg app).
- macOS body 13pt, not iOS 17pt. Verify no double-padding (scenePadding + Form).
- NSMenu `.badge`/Section SwiftUI bridge is historically quirky — verify on device.
- Removing the toast must not leave the user-check silent.
- "Skip This Version" only on the found prompt; extend the one-shot-reply guard.
