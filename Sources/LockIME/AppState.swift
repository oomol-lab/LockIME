import AppKit
import ApplicationServices
import Foundation
import KeyboardShortcuts
import LockIMEKit
import Observation
import PermissionFlow
import SwiftData
import SwiftUI

/// Top-level observable UI state, backed by the `LockEngine` and persisted
/// `LockConfiguration`.
@MainActor
@Observable
final class AppState {
    private(set) var config: LockConfiguration = .default
    private(set) var activationCount: Int = 0
    private(set) var currentSourceName: String = "—"
    private(set) var frontmostBundleID: String?
    private(set) var availableSources: [InputSource] = []
    private(set) var loginItemState: LoginItemState = .unknown
    private(set) var accessibilityGranted: Bool = false

    /// Whether the `lockime://` URL-scheme API is allowed to act. **Off by
    /// default** — the user must opt in (Settings ▸ General ▸ Automation) before
    /// any external command takes effect. Stored in its own `UserDefaults` key,
    /// deliberately *not* part of `LockConfiguration`, so it is per-device and
    /// never travels through config export/import.
    private(set) var apiEnabled: Bool = false
    @ObservationIgnored private static let apiEnabledKey = "apiEnabled"

    /// Whether the user has hidden LockIME's menu-bar icon (Settings ▸ General ▸
    /// Menu Bar). Per-device like `apiEnabled` — its own `UserDefaults` key,
    /// deliberately **not** part of `LockConfiguration`, so it never travels
    /// through config export/import. Drives the `MenuBarExtra`'s `isInserted`
    /// binding (mirrored by an `@AppStorage` on the same key so the scene reacts
    /// live). Hiding does not stop the app: the lock engine keeps running, the
    /// AppDelegate terminate guard treats a hidden icon as a sanctioned state, and
    /// relaunching re-presents Settings. The key is non-private so the scene's
    /// `@AppStorage` mirror can name it.
    private(set) var menuBarIconHidden: Bool = false
    @ObservationIgnored static let menuBarIconHiddenKey = "menuBarIconHidden"

    /// The configured global toggle-lock shortcut, mirrored as observable state
    /// so the menu-bar header re-renders the moment the user binds or clears it
    /// in Settings (a plain `getShortcut` read isn't tracked by `@Observable`).
    private(set) var toggleLockShortcut: KeyboardShortcuts.Shortcut?

    let updateController = UpdateController()

    /// About window, hosted in AppKit so it reliably comes to the foreground.
    @ObservationIgnored private lazy var aboutWindow = HostedWindowController(
        id: "about",
        title: { [weak self] in self?.loc("About LockIME") ?? "About LockIME" },
        styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
        transparentTitleBar: true
    ) { [weak self] in
        guard let self else { return AnyView(EmptyView()) }
        return AnyView(self.localizedRoot { AboutView() })
    }

    /// Update window, only shown when an update is actually available.
    @ObservationIgnored private lazy var updateWindow = HostedWindowController(
        id: "update",
        title: { [weak self] in self?.loc("Updates") ?? "Updates" },
        onClose: { [weak self] in self?.updateController.model.dismissReply() }
    ) { [weak self] in
        guard let self else { return AnyView(EmptyView()) }
        return AnyView(self.localizedRoot { UpdateWindowView() })
    }

    @ObservationIgnored private let store = RuleStore()
    @ObservationIgnored private let activationStore = ActivationCountStore()
    @ObservationIgnored private let loginItem = LoginItemController()
    @ObservationIgnored let logStore = LogStore()
    @ObservationIgnored private var engine: LockEngine?
    @ObservationIgnored private var purgeTask: Task<Void, Never>?
    @ObservationIgnored private var shortcutObserver: (any NSObjectProtocol)?

    /// KeyboardShortcuts posts this (internal) notification whenever a name's
    /// shortcut is set or cleared. It isn't public, so observe it by its raw
    /// string — the same way the library's own `NSMenuItem` helper does.
    @ObservationIgnored private static let shortcutChanged =
        Notification.Name("KeyboardShortcuts_shortcutByNameDidChange")

    /// Guides the user to grant Accessibility access via the floating drag
    /// helper. Created lazily so it does no work until the user actually
    /// requests access.
    @ObservationIgnored private lazy var permissionFlow = PermissionFlowController(
        configuration: .init(promptForAccessibilityTrust: false)
    )

    /// Polls for the Accessibility grant after a request. macOS doesn't notify
    /// us when access is allowed, so we watch `AXIsProcessTrusted()` ourselves.
    @ObservationIgnored private let accessibilityWatcher = AccessibilityGrantWatcher()

    /// User language choice, loaded eagerly so scenes get the right locale.
    private(set) var languagePreference: LanguagePreference = .system

    /// The selected Settings tab. Held here (not as view `@State`) so a feature
    /// pane can route the user to General's single Accessibility grant.
    var settingsTab: SettingsTab = .general

    /// The master on/off — "Enable LockIME". Mirrors `config.isEnabled`; gates
    /// the whole app (both locking and switching). Bound by the General master
    /// toggle.
    var isAppEnabled: Bool { config.isEnabled }

    /// Whether a **continuous lock** is in force right now: the master is on *and*
    /// the lock sub-toggle is on. This is what the padlock surfaces represent
    /// (tray/About icon, menu glyph + "Locked/Unlocked" header, the locked-source
    /// checkmark) — they speak to the *lock* capability, not mere app activeness.
    /// For anyone who leaves locking on (the default) this equals `isEnabled`, so
    /// those surfaces look exactly as before; only the opt-in pure-switch mode
    /// (master on, locking off) shows them "unlocked".
    var isLocked: Bool { config.isEnabled && config.lockingEnabled }

    /// The SwiftData container backing the activation log (for `.modelContainer`).
    var modelContainer: ModelContainer { logStore.container }

    /// The locale to inject into every scene root.
    var locale: Locale { Locale(identifier: languagePreference.effectiveLanguage.localeIdentifier) }
    var localeIdentifier: String { languagePreference.effectiveLanguage.localeIdentifier }

    init() {
        languagePreference = .load()
        apiEnabled = UserDefaults.standard.bool(forKey: Self.apiEnabledKey) // absent ⇒ false (opt-in)
        menuBarIconHidden = UserDefaults.standard.bool(forKey: Self.menuBarIconHiddenKey) // absent ⇒ false (icon shown)
        ThirdPartyBundleLocalization.apply(language: languagePreference.effectiveLanguage)
    }

    /// Opt the `lockime://` URL-scheme API in or out. Persisted immediately so the
    /// choice survives relaunch; takes effect for the next incoming command.
    func setAPIEnabled(_ enabled: Bool) {
        apiEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.apiEnabledKey)
    }

    /// Hide or show LockIME's menu-bar icon. Persisted immediately (the key the
    /// `MenuBarExtra` `isInserted` mirror watches) so the change takes effect live
    /// and survives relaunch. This is the single write path for the preference —
    /// the scene's `@AppStorage` mirror and the terminate/reveal guards all read
    /// back through here — so the cached value the guards see is always fresh.
    func setMenuBarIconHidden(_ hidden: Bool) {
        menuBarIconHidden = hidden
        UserDefaults.standard.set(hidden, forKey: Self.menuBarIconHiddenKey)
    }

    /// GitHub URL of the URL-scheme API reference, in the app's current language
    /// (mirrors the `docs/URL-Scheme-API/README.<code>.md` naming). Points at
    /// `main`, so it resolves once this work lands there.
    var apiDocumentationURL: URL {
        let file: String
        switch languagePreference.effectiveLanguage {
        case .english: file = "README.md"
        case .simplifiedChinese: file = "README.zh-CN.md"
        case .traditionalChinese: file = "README.zh-TW.md"
        case .japanese: file = "README.ja.md"
        case .french: file = "README.fr.md"
        case .german: file = "README.de.md"
        case .spanish: file = "README.es.md"
        case .portuguese: file = "README.pt.md"
        case .russian: file = "README.ru.md"
        }
        // A constant, URL-safe GitHub address — not user-facing copy.
        return URL(string: "https://github.com/oomol-lab/LockIME/blob/main/docs/URL-Scheme-API/\(file)")!
    }

    func setLanguagePreference(_ preference: LanguagePreference) {
        languagePreference = preference
        preference.save()
        ThirdPartyBundleLocalization.apply(language: preference.effectiveLanguage)
        // Hosted-window *content* re-localizes via observation, but the AppKit
        // window titles are plain strings that need an explicit refresh.
        aboutWindow.refreshTitle()
        updateWindow.refreshTitle()
    }

    /// Build and start the engine. Called once at launch from the app delegate.
    func start() {
        guard engine == nil else { return }
        // Capture this *before* loading (and before the save below writes one):
        // it tells a genuine first run apart from a returning user who set the
        // global default to "None". Both load as `defaultSourceID == nil`.
        let isFirstRun = !store.hasPersistedConfiguration
        config = store.load()
        activationCount = activationStore.count

        let engine = LockEngine(urlProvider: AccessibilityBrowserURLReader())
        self.engine = engine
        accessibilityGranted = AXIsProcessTrusted()
        engine.onActivation = { [weak self] event in
            guard let self else { return }
            self.activationCount = self.activationStore.increment()
            // Resolve the triggering app's display name here (AppKit lives in
            // the app, not the kit) so the log row keeps it even after that app
            // quits. App names are proper nouns shown verbatim — the same
            // treatment as the rules UI (AppRow) and the input-source column —
            // not catalog strings, so they bypass the in-app language override.
            let appName = event.triggeringBundleID.map(AppDisplay.name(for:))
            self.logStore.record(event, triggeringAppName: appName)
        }
        engine.onCurrentSourceChange = { [weak self] name in
            self?.currentSourceName = name
        }
        engine.onFrontmostChange = { [weak self] bundleID in
            self?.frontmostBundleID = bundleID
        }
        // Keep the tray switcher and Settings pickers in sync when the user
        // adds or removes an input source in System Settings while we run.
        engine.onSelectableSourcesChange = { [weak self] sources in
            self?.availableSources = sources
        }
        engine.start()

        availableSources = engine.selectableSources()
        // First run only: seed the global lock from the currently active source.
        // Gated on `isFirstRun` — a returning user who set the default to "None"
        // persists `nil`, and re-seeding that would silently turn "None" back
        // into whatever source was active at launch (e.g. ABC) on every relaunch.
        if isFirstRun, config.defaultSourceID == nil, let current = engine.currentSourceID() {
            config.defaultSourceID = current
        }
        engine.apply(config, reason: .startupApplied)
        store.save(config)

        loginItemState = loginItem.state
        updateController.onPresentUpdateWindow = { [weak self] in self?.updateWindow.show() }
        updateController.onCheckOutcome = { [weak self] outcome in self?.presentUpdateOutcome(outcome) }
        updateController.start()

        // Global toggle-lock shortcut: flips the master ("Enable LockIME") on/off,
        // the app's quick stop/start. `lockingEnabled` persists across toggles, so
        // a pure-switch user (locking off) toggling the app off then on stays in
        // pure-switch mode rather than silently re-engaging the lock.
        KeyboardShortcuts.onKeyUp(for: .toggleLock) { [weak self] in
            guard let self else { return }
            self.setMasterEnabled(!self.isAppEnabled)
        }

        // Global "lock to previous/next source" — cycle the global target
        // through the input-source list (wrapping), turning locking on.
        KeyboardShortcuts.onKeyUp(for: .globalPreviousSource) { [weak self] in
            self?.cycleGlobalSource(.previous)
        }
        KeyboardShortcuts.onKeyUp(for: .globalNextSource) { [weak self] in
            self?.cycleGlobalSource(.next)
        }

        // Frontmost-app "lock to previous/next source" — cycle that app's own
        // rule. No rule for the frontmost app ⇒ nothing happens.
        KeyboardShortcuts.onKeyUp(for: .appPreviousSource) { [weak self] in
            self?.cycleFrontmostAppSource(.previous)
        }
        KeyboardShortcuts.onKeyUp(for: .appNextSource) { [weak self] in
            self?.cycleFrontmostAppSource(.next)
        }

        // Frontmost-app "remove rule" — drop that app's rule. No rule ⇒ no-op.
        KeyboardShortcuts.onKeyUp(for: .removeFrontmostAppRule) { [weak self] in
            self?.removeFrontmostAppRule()
        }

        // Mirror the configured shortcut into observable state, and keep it in
        // sync so the menu header reflects binds/clears made in Settings live.
        toggleLockShortcut = KeyboardShortcuts.getShortcut(for: .toggleLock)
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: Self.shortcutChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.toggleLockShortcut = KeyboardShortcuts.getShortcut(for: .toggleLock)
            }
        }

        // Purge the 24h log now and hourly thereafter.
        logStore.purgeExpired()
        purgeTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                if Task.isCancelled { break }
                self?.logStore.purgeExpired()
            }
        }
    }

    /// Tear down observers and the purge loop for a clean shutdown.
    func stop() {
        engine?.stop()
        purgeTask?.cancel()
        purgeTask = nil
        accessibilityWatcher.stop()
        if let shortcutObserver {
            NotificationCenter.default.removeObserver(shortcutObserver)
            self.shortcutObserver = nil
        }
    }

    /// Set when the user (menu **Quit** / `lockime://quit`) deliberately asks us
    /// to exit, so `AppDelegate.applicationShouldTerminate` can tell a *wanted*
    /// quit apart from the unsolicited `terminate:` AppKit fires the moment our
    /// menu bar icon is hidden — which must never kill the app.
    private(set) var terminationRequested = false

    /// The one sanctioned exit path: flag the termination as wanted, then quit.
    /// Works even when the menu bar icon is hidden (the terminate guard lets a
    /// flagged termination through).
    func quit() {
        terminationRequested = true
        NSApp.terminate(nil)
    }

    /// Bridge to SwiftUI's `\.openSettings` action, captured by a tiny view in the
    /// MenuBarExtra label (see `LockIMEApp`). The AppKit `showSettingsWindow:`
    /// selector returns success but never actually opens the SwiftUI `Settings`
    /// scene for this accessory app, so the recovery path (`AppDelegate`, when the
    /// menu bar icon is hidden) calls this instead.
    @ObservationIgnored var openSettingsAction: (() -> Void)?

    deinit {
        purgeTask?.cancel()
        // The shortcut observer is torn down in `stop()`; a nonisolated deinit
        // can't touch the non-Sendable token, and it captures `self` weakly so a
        // lingering registration is harmless (AppState lives for the app's life).
    }

    func purgeLog() {
        logStore.purgeExpired()
    }

    // MARK: - Mutations (each persists + re-applies)

    func setLaunchAtLogin(_ enabled: Bool) {
        _ = loginItem.setEnabled(enabled)
        loginItemState = loginItem.state
    }

    func refreshLoginItemState() {
        loginItemState = loginItem.state
    }

    func setMasterEnabled(_ on: Bool) {
        config.isEnabled = on
        commit(reason: .lockEngaged)
    }

    /// Toggle the **continuous-lock** capability (the General "Enable locking"
    /// sub-toggle), subordinate to the master. Turning it off drops every standing
    /// lock — the global default, per-app `.locked` rules, URL `.lock` rules, and
    /// the address-bar lock all go inert — while one-shot switch rules keep firing.
    /// That is the "act like Input Source Pro" mode: per-context auto-switch with
    /// no global lock. No effect while the master is off (the app is fully idle).
    func setLockingEnabled(_ on: Bool) {
        config.lockingEnabled = on
        commit(reason: .lockEngaged)
    }

    func setDefaultSource(_ id: InputSourceID?) {
        config.defaultSourceID = id
        commit()
    }

    /// Lock to a specific source from the menu bar: make it the global target and
    /// engage the lock in a single commit — turning **both** the master and the
    /// lock sub-toggle on, so a one-tap menu pick always pins, even from a
    /// pure-switch or fully-off state. Clicking the already-locked source instead
    /// clears the global target via `setDefaultSource(nil)` (leaving the app and
    /// switching alive).
    func lockToSource(_ id: InputSourceID) {
        config.defaultSourceID = id
        config.isEnabled = true
        config.lockingEnabled = true
        commit(reason: .lockEngaged)
    }

    // MARK: - Shortcut-driven source cycling

    /// Lock the *global* target to the previous/next input source in the list,
    /// wrapping around the ends, and turn locking on — the same write path as
    /// `lockToSource`. Never lands on "none", and does nothing when fewer than
    /// two input sources are installed (there's nowhere to cycle).
    func cycleGlobalSource(_ direction: CycleDirection) {
        let reference = config.defaultSourceID ?? engine?.currentSourceID()
        guard let next = SourceCycler.step(
            from: reference, in: availableSources.map(\.id), direction: direction
        ) else { return }
        config.defaultSourceID = next
        config.isEnabled = true
        config.lockingEnabled = true
        commit(reason: .lockEngaged)
    }

    /// Lock the *frontmost app's* rule to the previous/next input source,
    /// scoped to that app. Does nothing when the frontmost app has no rule of
    /// its own, and never lands on "none" (it pins the rule to a valid source).
    func cycleFrontmostAppSource(_ direction: CycleDirection) {
        guard let bundleID = frontmostApplicationBundleID else { return }
        _ = cycleAppSource(bundleID: bundleID, direction: direction)
    }

    /// Cycle a *specific* app's rule to the previous/next input source. Shared by
    /// the frontmost-app hotkey and the `lockime://cycle-app-source` URL command.
    /// Returns `false` (a no-op) when that app has no rule or there is nowhere to
    /// cycle, so the API can report `rule_not_found`.
    @discardableResult
    func cycleAppSource(bundleID: String, direction: CycleDirection) -> Bool {
        guard var rule = config.rule(for: bundleID) else { return false }
        let reference = rule.lockedSourceID ?? engine?.currentSourceID()
        guard let next = SourceCycler.step(
            from: reference, in: availableSources.map(\.id), direction: direction
        ) else { return false }
        // Cycling pins a source; keep a `.switched` rule a switch (don't demote
        // it to a continuous lock), and turn a non-pinning rule into a lock.
        if !rule.mode.pinsSource { rule.mode = .locked }
        rule.lockedSourceID = next
        upsertRule(rule)
        return true
    }

    /// Remove the rule bound to the frontmost app. Does nothing when that app
    /// has no rule, so pressing it in an unconfigured app is harmless.
    func removeFrontmostAppRule() {
        guard let bundleID = frontmostApplicationBundleID,
              config.rule(for: bundleID) != nil
        else { return }
        removeRule(bundleID: bundleID)
    }

    /// The app the user is actually looking at when a global shortcut fires.
    /// Read fresh from `NSWorkspace` rather than the mirrored `frontmostBundleID`
    /// (which only updates on the *next* activation, so it can be stale or nil
    /// right after launch) — a global hotkey doesn't steal focus, so this is the
    /// same app the engine resolves rules against.
    private var frontmostApplicationBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func upsertRule(_ rule: AppRule) {
        config.appRules.removeAll { $0.bundleID == rule.bundleID }
        config.appRules.append(rule)
        config.appRules.sort { $0.bundleID < $1.bundleID }
        commit()
    }

    func removeRule(bundleID: String) {
        config.appRules.removeAll { $0.bundleID == bundleID }
        commit()
    }

    func setEnhancedMode(_ enabled: Bool) {
        config.enhancedModeEnabled = enabled
        commit()
    }

    // MARK: - Address-bar focus rule

    /// Turn the address-bar focus rule on or off. Enabling with no target yet
    /// pre-fills it with the global default source so the rule isn't inert (a
    /// `nil` target makes the resolver skip it); the source picker can change it.
    func setAddressBarFocusEnabled(_ enabled: Bool) {
        config.addressBarFocusEnabled = enabled
        if enabled, config.addressBarSourceID == nil {
            config.addressBarSourceID = config.defaultSourceID
        }
        commit()
    }

    /// Choose whether the address-bar rule continuously locks its source or
    /// switches to it once on focus.
    func setAddressBarAction(_ action: RuleAction) {
        config.addressBarAction = action
        commit()
    }

    /// Set the source the address-bar rule targets.
    func setAddressBarSource(_ id: InputSourceID?) {
        config.addressBarSourceID = id
        commit()
    }

    /// Choose which wins when both the address-bar rule and a URL rule apply:
    /// `true` = address bar, `false` = URL rule (the default).
    func setAddressBarOutranksURLRules(_ outranks: Bool) {
        config.addressBarOutranksURLRules = outranks
        commit()
    }

    func upsertURLRule(_ rule: URLRule) {
        // Insert/update in place so editing a rule's binding (match type / action /
        // source) keeps its position — order is priority now, and an edit must not
        // silently demote a rule to the bottom — while never minting two rules with
        // the same pattern (the portable identity; a duplicate pair collapses on the
        // next export→import). The `URLRuleList` helper holds both invariants and is
        // unit-tested; the editor and the URL-scheme API reject a pattern collision
        // before reaching here so the user/automation gets feedback.
        config.urlRules = URLRuleList.upserting(rule, into: config.urlRules)
        commit()
    }

    func removeURLRule(id: UUID) {
        config.urlRules.removeAll { $0.id == id }
        commit()
    }

    /// Commit a drag-reordered URL-rule list. Order *is* priority — rules resolve
    /// top-to-bottom and the first match wins — so this is a meaningful edit, not
    /// cosmetic. The live drag reorders a view-local draft (never `config`), so the
    /// engine/disk stay untouched mid-drag — a cancelled drag persists nothing —
    /// and this commits once when the drop lands. A no-op (saving + re-applying the
    /// engine) when the order is unchanged, and a guard against a non-permutation
    /// (mismatched rule set) so a stale draft can never replace the live rules.
    func reorderURLRules(_ ordered: [URLRule]) {
        // `URLRuleList.reordered` returns nil for a no-op (unchanged order) or a
        // non-permutation (a stale drag-start snapshot whose id set no longer
        // matches the live rules), and otherwise relinks to the *live* rules by id
        // so a content edit that landed mid-drag survives the reorder.
        guard let reordered = URLRuleList.reordered(config.urlRules, by: ordered) else { return }
        config.urlRules = reordered
        commit()
    }

    // MARK: - URL-scheme API support

    /// Live current input-source id (the engine's view), for status queries.
    var currentSourceID: InputSourceID? { engine?.currentSourceID() }

    /// Live launch-at-login state (read fresh from `SMAppService`, never cached),
    /// for the `set-launch-at-login` toggle and the status query.
    var launchAtLoginActive: Bool { loginItem.isEnabled }

    /// Recent activation-log entries (newest first, within the 24h window) for
    /// the `lockime://list-log` query.
    func recentActivationLog(limit: Int = 200) -> [ActivationLogEntry] {
        logStore.recent(limit: limit)
    }

    /// The bundle ID of the app the user is currently looking at, read fresh from
    /// `NSWorkspace`. A global URL command doesn't steal focus, so this is the app
    /// a frontmost-scoped command (`cycle-app-source`, `remove-frontmost-app-rule`)
    /// should target — the same source the engine resolves rules against.
    var liveFrontmostBundleID: String? { frontmostApplicationBundleID }

    /// Resolve an API source selector to a canonical id, requiring it to name a
    /// currently-installed selectable source (so the API can report
    /// `unknown_source` rather than silently configuring an unusable target).
    func resolveSourceID(_ selector: SourceSelector) -> InputSourceID? {
        switch selector {
        case .id(let id):
            return availableSources.first { $0.id == id }?.id
        case .name(let name):
            return availableSources.first {
                $0.localizedName.compare(name, options: .caseInsensitive) == .orderedSame
            }?.id
        }
    }

    /// The installed display name for a source id, if any.
    func sourceDisplayName(for id: InputSourceID) -> String? {
        availableSources.first { $0.id == id }?.localizedName
    }

    /// Perform a transient one-shot switch (no standing lock) for the
    /// `lockime://switch-source` command. An active continuous lock still wins.
    func switchSourceOnce(_ id: InputSourceID) {
        engine?.switchSourceOnce(id)
    }

    /// Remove every per-app rule in one commit (`lockime://clear-app-rules`).
    func clearAppRules() {
        guard !config.appRules.isEmpty else { return }
        config.appRules.removeAll()
        commit()
    }

    /// Remove every per-URL rule in one commit (`lockime://clear-url-rules`).
    func clearURLRules() {
        guard !config.urlRules.isEmpty else { return }
        config.urlRules.removeAll()
        commit()
    }


    /// Reconcile the cached flag with the live trust state, reacting to either
    /// transition. The user may grant while the polling watcher is stopped (e.g.
    /// after closing the window mid-flow) or entirely out-of-band in System
    /// Settings, so a refresh that observes a *new* grant must run the same
    /// completion the watcher would have. A *revoke* is just as important: the
    /// launcher-overlay observers are now dead, so the engine must detach them
    /// and clear any stale overlay attribution (otherwise re-granting later
    /// wouldn't re-attach, and rules could keep resolving against a launcher).
    func refreshAccessibilityStatus() {
        let trusted = AXIsProcessTrusted()
        let wasGranted = accessibilityGranted
        accessibilityGranted = trusted
        guard trusted != wasGranted else { return }
        if trusted {
            handleAccessibilityGranted()
        } else {
            engine?.accessibilityDidChange()
        }
    }

    /// Open System Settings with the floating drag helper, then start watching
    /// for the grant. The moment access is allowed we close the helper panel
    /// (the system never does) and flip `accessibilityGranted`, so the toggle
    /// becomes usable without the user having to switch tabs.
    func requestAccessibilityAccess(localeIdentifier: String?, suggestedAppURLs: [URL], sourceFrame: CGRect) {
        permissionFlow.setLocaleIdentifier(localeIdentifier)
        permissionFlow.authorize(
            pane: .accessibility,
            suggestedAppURLs: suggestedAppURLs,
            sourceFrameInScreen: sourceFrame
        )
        accessibilityWatcher.start { [weak self] in self?.completeAccessibilityGrant() }
    }

    /// Stop watching for the grant (e.g. when the pane disappears) so an
    /// abandoned request doesn't keep polling in the background.
    func stopAccessibilityWatch() {
        accessibilityWatcher.stop()
    }

    /// Run when the grant is detected: close the floating helper (the system
    /// never does) and flip the flag so the toggle becomes usable at once.
    private func completeAccessibilityGrant() {
        accessibilityGranted = true
        handleAccessibilityGranted()
    }

    /// Run once when the grant is first observed — by the polling watcher *or* a
    /// status refresh. Closes the floating helper (the system never does), stops
    /// the now-finished watcher, and attaches the launcher-overlay monitor
    /// (Spotlight, Raycast, …) which needs the grant to register its observers.
    /// All three are idempotent, so observing the grant twice is harmless.
    private func handleAccessibilityGranted() {
        permissionFlow.closePanel(returnToPreviousApp: true)
        accessibilityWatcher.stop()
        engine?.accessibilityDidChange()
    }

    #if DEBUG
    /// In-process end-to-end self-test for the Accessibility grant UX, run via
    /// `LOCKIME_AXFLOW_TEST=1`. It shows the REAL floating helper panel and runs
    /// the REAL grant reaction, then observes the two user-facing artifacts
    /// directly in this live app process: the helper panel window disappears
    /// (problem ①) and `accessibilityGranted` — the value the toggle's
    /// `.disabled` reads — flips true (problem ②). Only the trust *signal* is
    /// simulated, because granting Accessibility is SIP-protected and GUI-only;
    /// every reaction the app performs is the real production code path.
    func runAccessibilityGrantSelfTest() async {
        func visibleHelperPanels() -> Int {
            NSApp.windows.filter {
                String(describing: type(of: $0)).contains("FloatingDropPanel") && $0.isVisible
            }.count
        }

        accessibilityGranted = false
        print("AXFLOW: start — visible helper panels=\(visibleHelperPanels()), accessibilityGranted=\(accessibilityGranted)")

        // 1) Show the real helper panel — the window the user sees and that, in
        //    the bug report, refused to disappear.
        permissionFlow.showPanel()
        try? await Task.sleep(for: .milliseconds(400))
        let shown = visibleHelperPanels()
        print("AXFLOW: after showPanel() — visible helper panels=\(shown)")

        // 2) Run the real reaction to a detected grant.
        completeAccessibilityGrant()
        try? await Task.sleep(for: .milliseconds(400))
        let remaining = visibleHelperPanels()
        print("AXFLOW: after grant reaction — visible helper panels=\(remaining), accessibilityGranted=\(accessibilityGranted)")

        let panelClosed = shown >= 1 && remaining == 0
        let toggleEnabled = accessibilityGranted
        print("AXFLOW: problem①(helper panel disappears on grant) = \(panelClosed ? "PASS" : "FAIL")")
        print("AXFLOW: problem②(toggle becomes enabled on grant)  = \(toggleEnabled ? "PASS" : "FAIL")")
        print("AXFLOW: \(panelClosed && toggleEnabled ? "ALL PASS" : "FAILED")")
    }
    #endif

    func refreshSources() {
        if let engine { availableSources = engine.selectableSources() }
    }

    /// Persist + re-apply the config. `reason` attributes any resulting forced
    /// switch in the activation log: a config edit (the default) vs the master
    /// lock being engaged (menu toggle / lock-to-source / hotkey cycling).
    private func commit(reason: ActivationReason = .configChanged) {
        engine?.apply(config, reason: reason)
        store.save(config)
    }

    // MARK: - Backup (export / import)

    /// Snapshot the portable configuration (rules + binding intent) into a
    /// backup envelope, capturing the current display name of every installed
    /// source so a target machine missing one can still show a label. Per-device
    /// runtime state (master lock, enhanced mode, language, login item) is not
    /// included — see `ConfigBackup.make`.
    func makeBackup() -> ConfigBackup {
        var names: [InputSourceID: String] = [:]
        for source in availableSources { names[source.id] = source.localizedName }
        return ConfigBackup.make(from: config, appVersion: Bundle.main.shortVersion, sourceNames: names)
    }

    /// Read and version-gate a backup file, building an in-memory staging plan
    /// diffed against the live configuration and installed sources. **Nothing is
    /// persisted here** — the plan is editable and only `applyImport` commits.
    func loadImportPlan(from url: URL) -> Result<ImportPlan, BackupReadError> {
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        switch ConfigBackup.read(data) {
        case .success(let backup):
            return .success(ImportPlan(current: config, backup: backup, installedSources: availableSources))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Commit a staging plan: fold it into the configuration, persist, and
    /// re-apply the engine. The only state-changing step of the whole import.
    @discardableResult
    func applyImport(_ plan: ImportPlan) -> ImportOutcome {
        let outcome = plan.outcome()
        config = plan.resolvedConfiguration()
        commit(reason: .configChanged)
        return outcome
    }

    // MARK: - Windows & update presentation

    /// Bring the About window to the foreground (creating it on first use).
    func showAbout() {
        aboutWindow.show()
    }

    /// A user-initiated update check. The window only opens if an update is
    /// found; otherwise the result shows as a toast (see `presentUpdateOutcome`).
    func checkForUpdates() {
        updateController.checkForUpdates()
    }

    /// Surface a finished user-initiated check as a native, fully appearance-
    /// adaptive alert (replacing the old off-brand center-screen toast).
    private func presentUpdateOutcome(_ outcome: UpdateCheckOutcome) {
        let alert = NSAlert()
        alert.icon = .lockIMEAppIconRounded
        switch outcome {
        case .upToDate:
            alert.alertStyle = .informational
            alert.messageText = loc("You're up to date.")
            alert.informativeText = loc(
                "LockIME %@ is currently the newest version available.",
                Bundle.main.shortVersion
            )
        case .failed(let failure):
            alert.alertStyle = .warning
            alert.messageText = loc("Update failed")
            alert.informativeText = loc(failure.messageKey)
        #if DEBUG
        case .disabledInDevelopment:
            alert.alertStyle = .informational
            alert.messageText = loc("Development build")
            alert.informativeText = loc("Automatic updates are disabled in development builds. To test the update flow, use the make update-test-* lab.")
        #endif
        }
        alert.addButton(withTitle: loc("OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Resolve a string in the app's chosen language for AppKit surfaces
    /// (NSAlert, window titles) that don't get SwiftUI's `\.locale`.
    func loc(_ key: String) -> String {
        AppKitStrings.string(key, language: languagePreference.effectiveLanguage)
    }

    func loc(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: loc(key), arguments: arguments)
    }

    /// Wrap a window's root view with the shared state and chosen locale so its
    /// strings resolve live, mirroring the scene-level `localized(with:)` helper.
    private func localizedRoot<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        LocalizedHostedRoot(appState: self, content: content())
    }
}

/// Root wrapper for AppKit-hosted windows. The hosting controller's root view
/// is built exactly once, so the locale must be applied *inside a view body*
/// (where observation tracks the language preference) rather than baked in at
/// creation — otherwise an open or reopened window keeps its original language.
private struct LocalizedHostedRoot<Content: View>: View {
    let appState: AppState
    let content: Content

    var body: some View {
        content
            .environment(appState)
            .environment(\.locale, appState.locale)
            .id(appState.localeIdentifier)
    }
}
