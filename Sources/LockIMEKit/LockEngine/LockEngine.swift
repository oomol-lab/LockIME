import Foundation

/// Integration facade tying together the input-source provider, the lock state
/// machine, the change observer, and the frontmost-app monitor. Driven entirely
/// by a `LockConfiguration`; the testable logic lives in `LockController` and
/// `RuleResolver`.
@MainActor
public final class LockEngine {
    private let provider: any InputSourceProviding
    private let controller: LockController
    private let observer: InputSourceChangeObserver
    private let enabledSourcesObserver: InputSourceChangeObserver
    private let appMonitor: any FrontmostAppMonitoring
    private let floatingAppMonitor: any FloatingAppMonitoring
    private let urlProvider: (any BrowserURLProviding)?
    private var urlPollTask: Task<Void, Never>?

    /// Fired after every successful forced switch.
    public var onActivation: (@MainActor (ActivationEvent) -> Void)?
    /// Fired whenever the displayed current-source name may have changed.
    public var onCurrentSourceChange: (@MainActor (String) -> Void)?
    /// Fired when the frontmost app changes.
    public var onFrontmostChange: (@MainActor (String?) -> Void)?
    /// Fired when the system's enabled input sources change (e.g. the user adds
    /// or removes one in System Settings), with the refreshed selectable list.
    public var onSelectableSourcesChange: (@MainActor ([InputSource]) -> Void)?

    private var config: LockConfiguration = .default
    private var frontmostBundleID: String?
    /// The launcher overlay (Spotlight, Raycast, …) currently holding keyboard
    /// focus, if any. It shadows `frontmostBundleID` for rule resolution because
    /// macOS leaves the frontmost app unchanged while an overlay is up.
    private var launcherBundleID: String?

    /// Identity of the one-shot switch rule currently in effect, so the engine
    /// fires a `.switchOnce` resolution only on a *genuine transition into* the
    /// rule — never again on a re-activation, a URL poll over the same matched
    /// pattern, or a config edit while the user is still in that rule.
    private struct SwitchKey: Equatable {
        let ruleSource: RuleSource
        /// The frontmost/launcher bundle for an app rule, or the matched host
        /// *pattern* for a URL rule (so a single wildcard rule fires once across
        /// all its subdomains, matching how a lock treats the whole pattern).
        let context: String?
        let sourceID: InputSourceID
    }

    /// In-memory only (never persisted): a fresh process re-fires the one-shot on
    /// the first enable, which is the intended "switch me on engage" behavior.
    private var lastSwitchKey: SwitchKey?

    /// The one-shot memory for a launcher overlay's *own* switch rule, kept
    /// separate from `lastSwitchKey` so a launcher excursion never clobbers the
    /// frontmost app's switch memory. Without this, focusing a launcher whose own
    /// rule is `.switched` would overwrite `lastSwitchKey`, and dismissing it
    /// would re-fire the frontmost app's one-shot — re-yanking a user who had
    /// switched away. Cleared whenever no launcher is up, so each excursion is a
    /// fresh re-entry. (The `.lock`/`.ignore` arms avoid this by simply not
    /// touching `lastSwitchKey` while a launcher is up.)
    private var lastLauncherSwitchKey: SwitchKey?

    /// The app rules should resolve against right now: the focused launcher
    /// overlay when one is up, otherwise the `NSWorkspace` frontmost app.
    private var effectiveBundleID: String? { launcherBundleID ?? frontmostBundleID }

    public var activationCount: Int { controller.activationCount }

    public init(
        provider: (any InputSourceProviding)? = nil,
        appMonitor: (any FrontmostAppMonitoring)? = nil,
        floatingAppMonitor: (any FloatingAppMonitoring)? = nil,
        urlProvider: (any BrowserURLProviding)? = nil
    ) {
        let provider = provider ?? TISInputSourceProvider()
        self.provider = provider
        self.controller = LockController(provider: provider)
        self.observer = InputSourceChangeObserver()
        self.enabledSourcesObserver = InputSourceChangeObserver(.enabledSourcesChanged)
        self.appMonitor = appMonitor ?? AppActivationMonitor()
        self.floatingAppMonitor = floatingAppMonitor ?? FloatingAppMonitor()
        self.urlProvider = urlProvider
        self.controller.onActivation = { [weak self] event in
            self?.onActivation?(event)
        }
    }

    public func start() {
        frontmostBundleID = appMonitor.currentBundleID()
        observer.start { [weak self] in self?.handleSourceChange() }
        enabledSourcesObserver.start { [weak self] in self?.handleEnabledSourcesChange() }
        appMonitor.start { [weak self] id in self?.handleFrontmostChange(id) }
        floatingAppMonitor.start { [weak self] id in self?.handleLauncherChange(id) }
        notifyCurrent()
    }

    public func stop() {
        observer.stop()
        enabledSourcesObserver.stop()
        appMonitor.stop()
        floatingAppMonitor.stop()
        urlPollTask?.cancel()
        urlPollTask = nil
    }

    /// Re-attempt launcher-overlay observer attachment. macOS doesn't notify us
    /// when Accessibility is granted, so the app calls this once it detects the
    /// grant — only then can the overlay observers attach.
    public func accessibilityDidChange() {
        floatingAppMonitor.refresh()
    }

    /// Apply a configuration: update rules/default, set master enable, and
    /// re-resolve + enforce the appropriate target for the frontmost app.
    ///
    /// `reason` attributes the enforcing force to its cause — a config edit
    /// (`.configChanged`, the default), turning the master toggle on
    /// (`.lockEngaged`), or the launch/restore apply (`.startupApplied`). It
    /// flows into both the target re-resolution and the enable-time enforce,
    /// since whichever fires is the one that emits the activation event.
    public func apply(_ config: LockConfiguration, reason: ActivationReason = .configChanged) {
        self.config = config
        // Order matters so disabling is side-effect free. When enabling (or
        // re-applying while on), set the target first, then enforce. When
        // disabling, stop enforcing *first* — otherwise reevaluate could force
        // one last switch under the still-enabled state before the lock turns
        // off (e.g. the source has drifted off target and the revert is pending).
        if config.isEnabled {
            reevaluate(reason: reason)                       // set target
            controller.setEnabled(true, reason: reason)      // then enforce on enable
        } else {
            controller.setEnabled(false, reason: reason)     // stop enforcing first
            reevaluate(reason: reason)                       // update cached target only
        }
        updateURLPolling()
        notifyCurrent()
    }

    public func selectableSources() -> [InputSource] { provider.selectableSources() }

    public func currentSourceID() -> InputSourceID? { provider.currentSourceID() }

    public func currentSourceName() -> String {
        guard let id = provider.currentSourceID() else { return "—" }
        return provider.source(for: id)?.localizedName ?? id.rawValue
    }

    // MARK: - Internal event handling

    private func handleSourceChange() {
        controller.selectedSourceDidChange()
        notifyCurrent()
    }

    private func handleEnabledSourcesChange() {
        onSelectableSourcesChange?(provider.selectableSources())
    }

    private func handleFrontmostChange(_ bundleID: String?) {
        frontmostBundleID = bundleID
        // A normal app activating means no launcher overlay is up (overlays
        // never raise an activation), so clear any stale launcher attribution.
        launcherBundleID = nil
        onFrontmostChange?(effectiveBundleID)
        reevaluate(reason: .appActivated)
        updateURLPolling()
        notifyCurrent()
    }

    /// A launcher overlay (Spotlight, Raycast, …) took or released keyboard
    /// focus. While it holds focus, rules resolve against *it* rather than the
    /// unchanged frontmost app; `nil` reverts to the frontmost app.
    private func handleLauncherChange(_ bundleID: String?) {
        launcherBundleID = bundleID
        onFrontmostChange?(effectiveBundleID)
        reevaluate(reason: bundleID != nil ? .launcherFocused : .launcherDismissed)
        updateURLPolling()
        notifyCurrent()
    }

    private func reevaluate(reason: ActivationReason) {
        // A launcher excursion uses its own one-shot slot; clear it whenever no
        // launcher is up so the next excursion is a fresh re-entry and the
        // frontmost slot below is the only memory consulted for the real app.
        if launcherBundleID == nil { lastLauncherSwitchKey = nil }

        let urlMatch = enhancedURLMatch()
        switch RuleResolver.resolve(
            config: config,
            frontmostBundleID: effectiveBundleID,
            urlMatch: urlMatch.map { (id: $0.id, action: $0.action) }
        ) {
        case .lock(let id, let ruleSource):
            controller.setTarget(
                id,
                reason: effectiveReason(for: reason, ruleSource: ruleSource),
                bundleID: effectiveBundleID,
                ruleSource: ruleSource,
                matchedHost: ruleSource == .urlRule ? urlMatch?.host : nil
            )
            // Re-arm the one-shot for a genuine frontmost/URL state — but NOT for a
            // launcher overlay shadowing the app (see the `.switchOnce` arm).
            if launcherBundleID == nil { lastSwitchKey = nil }
        case .switchOnce(let id, let ruleSource):
            // A one-shot switch never holds the lock: clear any standing target
            // from a prior lock rule first, unconditionally.
            controller.setTarget(nil)
            let context = ruleSource == .urlRule ? urlMatch?.host : effectiveBundleID
            let key = SwitchKey(ruleSource: ruleSource, context: context, sourceID: id)
            // Dedup against the launcher slot during an excursion, the frontmost
            // slot otherwise — so a launcher's own `.switched` rule firing while it
            // shadows the app never overwrites the app's memory and re-yanks the
            // user on dismiss.
            if launcherBundleID != nil {
                fireSwitchOnceIfNeeded(id, ruleSource: ruleSource, reason: reason, context: context, slot: &lastLauncherSwitchKey, key: key)
            } else {
                fireSwitchOnceIfNeeded(id, ruleSource: ruleSource, reason: reason, context: context, slot: &lastSwitchKey, key: key)
            }
        case .ignore, .noTarget:
            controller.setTarget(nil)
            // Re-arm only on a genuine state, never on a launcher excursion: a
            // Spotlight/Raycast overlay (handleLauncherChange sets launcherBundleID
            // before this runs) over an already-switched app resolves here, and
            // resetting the key would re-yank the user back to the switch target
            // on dismiss. Preserving it makes the return a no-op (key unchanged).
            if launcherBundleID == nil { lastSwitchKey = nil }
        }
    }

    /// Fire the one-shot switch exactly once per genuine transition, tracked in
    /// `slot`. A disabled config nils the slot (so a later enable re-enters and
    /// fires — the OFF→ON escape hatch); a matching key is a no-op (already
    /// switched: a re-activation, a same-pattern poll, or a config edit).
    private func fireSwitchOnceIfNeeded(
        _ id: InputSourceID,
        ruleSource: RuleSource,
        reason: ActivationReason,
        context: String?,
        slot: inout SwitchKey?,
        key: SwitchKey
    ) {
        if !config.isEnabled {
            slot = nil
        } else if key != slot {
            // The source must be readable to switch; if it can't be resolved yet
            // (a transient TIS failure), do NOT consume the key — leave the
            // one-shot eligible for the next reevaluation rather than marking it
            // fired when it never ran. When the source *is* known but already
            // equals the target, `switchOnce` no-ops and we still consume the key
            // (the one-shot is satisfied, and re-arming would re-yank a user who
            // later switches away from an app they entered already on target).
            guard provider.currentSourceID() != nil else { return }
            controller.switchOnce(
                id,
                reason: effectiveReason(for: reason, ruleSource: ruleSource),
                bundleID: effectiveBundleID,
                ruleSource: ruleSource,
                matchedHost: ruleSource == .urlRule ? context : nil
            )
            slot = key
        }
    }

    /// The reason to attribute the resulting forced switch to. A URL match
    /// outranks a *trigger* reason (app switch, launcher, poll) — the URL is the
    /// why, so log `.urlMatched`. But an apply-driven reason (lock engaged /
    /// settings changed / startup restore) is the why itself; keep it, with the
    /// URL provenance carried by `ruleSource`. Shared by the lock and switch arms.
    private func effectiveReason(for reason: ActivationReason, ruleSource: RuleSource) -> ActivationReason {
        switch reason {
        case .startupApplied, .lockEngaged, .configChanged:
            return reason
        default:
            return ruleSource == .urlRule ? .urlMatched : reason
        }
    }

    /// The targeted source, matched host, and action from a URL rule, when
    /// enhanced mode is on and the current page matches one.
    private func enhancedURLMatch() -> (id: InputSourceID, host: String, action: RuleAction)? {
        guard config.enhancedModeEnabled, let urlProvider, !config.urlRules.isEmpty else { return nil }
        let urlString = urlProvider.currentURL(forBundleID: effectiveBundleID) ?? ""
        guard let rule = URLMatcher.matchedRule(host: URLMatcher.host(from: urlString), rules: config.urlRules)
        else { return nil }
        return (rule.lockedSourceID, rule.hostPattern, rule.action)
    }

    /// Poll the URL only while a browser is frontmost and enhanced mode is on,
    /// so in-page navigation re-resolves the rule without a global event tap. A
    /// launcher overlay over a browser suspends the poll (its bundle isn't a
    /// browser), and dismissing it resumes it.
    private func updateURLPolling() {
        urlPollTask?.cancel()
        urlPollTask = nil
        guard config.enhancedModeEnabled, urlProvider != nil, !config.urlRules.isEmpty,
              BrowserBundleIDs.isBrowser(effectiveBundleID)
        else { return }
        urlPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1500))
                if Task.isCancelled { break }
                guard let self else { break }
                // reevaluate() upgrades the reason to .urlMatched when a URL
                // rule actually matches; otherwise this is a periodic re-check
                // of the app/default rule, not an app switch.
                self.reevaluate(reason: .urlPolled)
            }
        }
    }

    private func notifyCurrent() {
        onCurrentSourceChange?(currentSourceName())
    }
}
