import Foundation

/// The heart of LockIME: a small state machine that keeps the active input
/// source pinned to a target, debouncing against its own forced switches.
///
/// Anti-loop design (mirrors InputSourcePro):
///  1. On a change, if the current source already equals the target, do nothing
///     (idempotent — this absorbs the echo of our own `select`).
///  2. Otherwise, if we are still inside the suppression window of a recent
///     force, do nothing (let the switch settle).
///  3. Only a *verified* mismatch outside the window triggers a re-force.
@MainActor
public final class LockController {
    /// How long after a forced switch to ignore further change notifications.
    public static let suppressionWindow: TimeInterval = 0.30

    private let provider: any InputSourceProviding
    private let uptime: @MainActor () -> TimeInterval
    private let clock: @MainActor () -> Date

    public private(set) var target: InputSourceID?
    public private(set) var isEnabled: Bool
    public private(set) var activationCount: Int = 0

    /// Invoked on every successful forced switch (for logging / UI counters).
    public var onActivation: (@MainActor (ActivationEvent) -> Void)?

    private var settleUntil: TimeInterval = 0

    /// Context describing where the current `target` came from, set alongside it
    /// by `setTarget` and attached to every event the target produces (including
    /// later reverts), so a log row can name the app and rule behind the lock.
    private var targetBundleID: String?
    private var targetRuleSource: RuleSource?
    private var targetMatchedHost: String?

    public init(
        provider: any InputSourceProviding,
        isEnabled: Bool = false,
        uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        clock: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.provider = provider
        self.isEnabled = isEnabled
        self.uptime = uptime
        self.clock = clock
    }

    // MARK: - Public commands

    /// Engage or disengage locking. Engaging while mismatched forces immediately.
    /// `reason` lets the caller attribute the engaging force (e.g. a master
    /// toggle vs a startup restore), since `setTarget`'s force may be suppressed
    /// while still disabled and this is what actually enforces on enable.
    public func setEnabled(_ on: Bool, reason: ActivationReason = .lockEngaged) {
        isEnabled = on
        guard on else { return }
        enforceIfNeeded(reason: reason)
    }

    /// Set (or clear) the locked target, plus the context describing where it
    /// came from. A non-nil target that differs from the current source is
    /// enforced immediately.
    public func setTarget(
        _ id: InputSourceID?,
        reason: ActivationReason = .lockEngaged,
        bundleID: String? = nil,
        ruleSource: RuleSource? = nil,
        matchedHost: String? = nil
    ) {
        let changed = id != target
        target = id
        targetBundleID = bundleID
        targetRuleSource = ruleSource
        targetMatchedHost = matchedHost
        // A genuinely new target supersedes any in-flight suppression window
        // (which only guarded re-forcing the *previous* target), so enforce now.
        if changed { settleUntil = 0 }
        enforceIfNeeded(reason: reason)
    }

    /// Perform a **one-shot** switch to `id` without installing a standing lock.
    ///
    /// Unlike `setTarget`, this clears `target` (so `selectedSourceDidChange` has
    /// nothing to revert to — the user may freely switch away afterward) and
    /// forces the source exactly once, only if it actually differs. It deliberately
    /// does **not** consult `isEnabled`: the engine gates the call on the *config*
    /// being enabled, which it knows synchronously, whereas the controller's own
    /// `isEnabled` lags during the enable path (`apply` enables only after
    /// re-resolving). The switch is still logged and counted like any forced
    /// switch, via the same `force` path.
    public func switchOnce(
        _ id: InputSourceID,
        reason: ActivationReason = .appActivated,
        bundleID: String? = nil,
        ruleSource: RuleSource? = nil,
        matchedHost: String? = nil
    ) {
        // A one-shot switch never holds the lock: drop any standing target so a
        // later "source changed" notification is a no-op.
        target = nil
        targetBundleID = bundleID
        targetRuleSource = ruleSource
        targetMatchedHost = matchedHost
        settleUntil = 0
        guard let current = provider.currentSourceID() else { return }
        guard current != id else { return } // already there → nothing to switch
        force(id, reason: reason, from: current)
    }

    /// Perform a **transient** switch for an external command (the
    /// `lockime://switch-source` URL API), independent of the standing lock.
    ///
    /// Unlike `switchOnce`, this does **not** clear or adopt the lock `target` or
    /// its context. It also **clears** the suppression window (`settleUntil = 0`)
    /// instead of extending it: if a continuous lock is active and targets a
    /// different source, the change notification this switch raises must not be
    /// shielded by a *prior* force's still-open settle window — otherwise the API
    /// switch could stick. Cleared, the lock reverts it promptly and stays
    /// authoritative (that revert is logged separately as `.revertedSwitch`).
    /// No-ops when already on `id`. The switch itself is always logged/counted at
    /// the moment it takes effect, even if a lock then reverts it.
    public func commandSwitch(_ id: InputSourceID) {
        guard let current = provider.currentSourceID(), current != id else { return }
        let start = uptime()
        let fromName = provider.source(for: current)?.localizedName ?? current.rawValue
        guard provider.select(id) else { return }
        // Clear any inherited suppression window so a standing lock's revert
        // (driven by the change notification this select raises) is not muffled.
        settleUntil = 0
        activationCount += 1
        let name = provider.source(for: id)?.localizedName ?? id.rawValue
        let durationMs = max(0, (uptime() - start) * 1000)
        // A command switch belongs to no rule, so it carries no app/rule context.
        onActivation?(
            ActivationEvent(
                timestamp: clock(),
                inputSource: id,
                inputSourceName: name,
                reason: .apiCommand,
                durationMs: durationMs,
                fromSourceName: fromName
            )
        )
    }

    /// Call when the system posts a "selected input source changed" notification.
    public func selectedSourceDidChange() {
        enforceIfNeeded(reason: .revertedSwitch)
    }

    // MARK: - Core state machine

    private func enforceIfNeeded(reason: ActivationReason) {
        guard isEnabled, let target else { return }
        guard let current = provider.currentSourceID() else { return }
        if current == target { return }        // (1) idempotent — absorbs our echo
        if uptime() < settleUntil { return }   // (2) recent force still settling
        force(target, reason: reason, from: current) // (3) verified mismatch → re-force
    }

    private func force(_ id: InputSourceID, reason: ActivationReason, from: InputSourceID?) {
        let start = uptime()
        // Resolve the source we're leaving *before* the switch takes effect.
        let fromName = from.flatMap { provider.source(for: $0)?.localizedName ?? $0.rawValue }
        let ok = provider.select(id)
        settleUntil = uptime() + Self.suppressionWindow
        guard ok else { return }
        activationCount += 1
        let name = provider.source(for: id)?.localizedName ?? id.rawValue
        let durationMs = max(0, (uptime() - start) * 1000)
        onActivation?(
            ActivationEvent(
                timestamp: clock(),
                inputSource: id,
                inputSourceName: name,
                reason: reason,
                durationMs: durationMs,
                fromSourceName: fromName,
                triggeringBundleID: targetBundleID,
                ruleSource: targetRuleSource,
                matchedHost: targetMatchedHost
            )
        )
    }
}
