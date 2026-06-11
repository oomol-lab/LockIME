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

    /// Master on/off, mirroring `config.isEnabled`.
    var isLocked: Bool { config.isEnabled }

    /// The SwiftData container backing the activation log (for `.modelContainer`).
    var modelContainer: ModelContainer { logStore.container }

    /// The locale to inject into every scene root.
    var locale: Locale { Locale(identifier: languagePreference.effectiveLanguage.localeIdentifier) }
    var localeIdentifier: String { languagePreference.effectiveLanguage.localeIdentifier }

    init() {
        languagePreference = .load()
        ThirdPartyBundleLocalization.apply(language: languagePreference.effectiveLanguage)
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
        config = store.load()
        activationCount = activationStore.count

        let engine = LockEngine(urlProvider: AccessibilityBrowserURLReader())
        self.engine = engine
        accessibilityGranted = AXIsProcessTrusted()
        engine.onActivation = { [weak self] event in
            guard let self else { return }
            self.activationCount = self.activationStore.increment()
            self.logStore.record(event)
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
        // First run: default the global lock to the currently active source.
        if config.defaultSourceID == nil, let current = engine.currentSourceID() {
            config.defaultSourceID = current
        }
        engine.apply(config)
        store.save(config)

        loginItemState = loginItem.state
        updateController.onPresentUpdateWindow = { [weak self] in self?.updateWindow.show() }
        updateController.onCheckOutcome = { [weak self] outcome in self?.presentUpdateOutcome(outcome) }
        updateController.start()

        // Global toggle-lock shortcut.
        KeyboardShortcuts.onKeyUp(for: .toggleLock) { [weak self] in
            guard let self else { return }
            self.setMasterEnabled(!self.isLocked)
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
        commit()
    }

    func setDefaultSource(_ id: InputSourceID?) {
        config.defaultSourceID = id
        commit()
    }

    /// Lock to a specific source from the menu bar: make it the global target
    /// and turn locking on in a single commit. Clicking the already-locked
    /// source instead disables locking via `setMasterEnabled(false)`.
    func lockToSource(_ id: InputSourceID) {
        config.defaultSourceID = id
        config.isEnabled = true
        commit()
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

    func upsertURLRule(_ rule: URLRule) {
        config.urlRules.removeAll { $0.id == rule.id }
        config.urlRules.append(rule)
        commit()
    }

    func removeURLRule(id: UUID) {
        config.urlRules.removeAll { $0.id == id }
        commit()
    }

    func refreshAccessibilityStatus() {
        accessibilityGranted = AXIsProcessTrusted()
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
        permissionFlow.closePanel(returnToPreviousApp: true)
        accessibilityGranted = true
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

    private func commit() {
        engine?.apply(config)
        store.save(config)
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
