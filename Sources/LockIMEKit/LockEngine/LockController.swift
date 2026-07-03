import Carbon
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
///
/// Because the machine is otherwise purely event-driven (it acts only when the
/// system posts a "selected source changed" notification), a mismatch that goes
/// *stable* with no follow-up notification — a flaky CJKV `select` that didn't
/// take, or a secure/password field re-coercing ABC — would sit off-target
/// forever. Every `force` therefore arms a bounded **trailing reconcile** that
/// re-checks once the settle window closes, even absent any new notification.
@MainActor
public final class LockController {
    /// How long after a forced switch to ignore further change notifications.
    public static let suppressionWindow: TimeInterval = 0.30

    /// Cap on consecutive reconcile-driven re-forces before the controller stops
    /// re-arming, so a target the OS keeps overriding (a secure field that keeps
    /// re-coercing) degrades to a brief flicker instead of an unbounded fight.
    /// The budget refills when the lock is observed satisfied or the target
    /// changes.
    public static let maxReconcileRetries = 3

    /// How often to poll for macOS secure event input turning off while we are
    /// respecting it (default policy). Leaving a password field *ends* secure
    /// input but does **not** reliably post a source-change notification, so the
    /// lock cannot re-assert on the event path alone — we poll instead, but only
    /// while a secure field keeps us gated, and stop as soon as it ends. Cheap
    /// (an `IsSecureEventInputEnabled()` syscall) and short-lived (a password
    /// field's focus lifetime).
    public static let secureInputPollInterval: TimeInterval = 0.5

    /// Production default for the secure-input probe: the process-GLOBAL Carbon
    /// flag. Injected (see `init`) so tests drive it deterministically. Declared
    /// `public static` so it can serve as a default argument at external call
    /// sites (e.g. `LockEngine.init`).
    public static let defaultIsSecureInputEnabled: @MainActor () -> Bool = { IsSecureEventInputEnabled() }

    /// Production default for the reconcile scheduler: run `work` on the main
    /// actor after `delay` (mirrors `LockEngine.urlPollTask`'s Task+sleep style).
    public static let defaultScheduler: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            work()
        }
    }

    private let provider: any InputSourceProviding
    private let uptime: @MainActor () -> TimeInterval
    private let clock: @MainActor () -> Date

    public private(set) var target: InputSourceID?
    public private(set) var isEnabled: Bool
    public private(set) var activationCount: Int = 0

    /// Invoked on every successful forced switch (for logging / UI counters).
    public var onActivation: (@MainActor (ActivationEvent) -> Void)?

    private var settleUntil: TimeInterval = 0

    /// Whether the lock keeps enforcing while macOS **secure event input** is
    /// active. `false` (default) respects the OS's ASCII coercion in
    /// password/secure fields. Set from config via `setSecureInputPolicy`.
    private var revertsInSecureInput: Bool
    /// Process-global "is secure event input on right now" probe.
    private let isSecureInputEnabled: @MainActor () -> Bool
    /// Defers the trailing reconcile past the settle window.
    private let scheduler: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void
    /// Consecutive reconcile-driven re-forces since the lock was last satisfied
    /// or the target last changed. Bounded by `maxReconcileRetries`.
    private var reconcileRetries = 0
    /// Coalesces overlapping reconcile schedules into a single in-flight check.
    private var pendingRecheck = false
    /// Coalesces overlapping secure-input watches into a single in-flight poll.
    private var secureWatchPending = false

    /// Context describing where the current `target` came from, set alongside it
    /// by `setTarget` and attached to every event the target produces (including
    /// later reverts), so a log row can name the app and rule behind the lock.
    private var targetBundleID: String?
    private var targetRuleSource: RuleSource?
    private var targetMatchedHost: String?

    public init(
        provider: any InputSourceProviding,
        isEnabled: Bool = false,
        revertsInSecureInput: Bool = false,
        uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        clock: @escaping @MainActor () -> Date = { Date() },
        isSecureInputEnabled: @escaping @MainActor () -> Bool = LockController.defaultIsSecureInputEnabled,
        scheduler: @escaping @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void = LockController.defaultScheduler
    ) {
        self.provider = provider
        self.isEnabled = isEnabled
        self.revertsInSecureInput = revertsInSecureInput
        self.uptime = uptime
        self.clock = clock
        self.isSecureInputEnabled = isSecureInputEnabled
        self.scheduler = scheduler
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

    /// Thread the secure-input policy from config. `false` (default) respects the
    /// OS's ASCII coercion in password/secure fields; `true` keeps enforcing the
    /// locked target even while secure event input is active. Pure policy — it
    /// does not itself force; the next enforcement honors the new value.
    public func setSecureInputPolicy(revertsInSecureInput: Bool) {
        self.revertsInSecureInput = revertsInSecureInput
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
        // It is also a fresh enforcement context, so refill the reconcile budget.
        if changed { settleUntil = 0; reconcileRetries = 0 }
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
        // Respect macOS secure input the same way the continuous lock does: in
        // the default policy, an autonomous one-shot (a `.switched` app rule or a
        // `.switchOnce` URL rule) must not change the source while a secure/
        // password field holds focus. The standing lock is still cleared above,
        // so this only declines the switch, never leaves a stale lock. (The
        // explicit `lockime://switch-source` API — `commandSwitch` — is a
        // deliberate external command and is intentionally *not* gated.)
        if !revertsInSecureInput, isSecureInputEnabled() { return }
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
        // Respect macOS secure event input unless the user opted into enforcing
        // in password fields. While a secure field holds focus the OS coerces
        // the layout to ASCII; by default we leave that alone. NOTE:
        // `IsSecureEventInputEnabled()` is process-GLOBAL — true whenever *any*
        // app holds secure input, not scoped to our frontmost field. This single
        // gate covers both the notification path and the reconcile path.
        //
        // Crucially, leaving the field *ends* secure input but does NOT reliably
        // post a source-change notification, so the event path alone would leave
        // the lock un-asserted (stuck on ABC) after blur. Arm a poll that
        // re-checks once secure input turns off; it self-cancels the moment the
        // field is gone (enforceIfNeeded then falls through and re-asserts).
        if !revertsInSecureInput, isSecureInputEnabled() {
            scheduleSecureInputWatch()
            return
        }
        guard let current = provider.currentSourceID() else { return }
        if current == target {                 // (1) idempotent — absorbs our echo;
            reconcileRetries = 0               //     lock satisfied → refill budget
            return
        }
        if uptime() < settleUntil { return }   // (2) recent force still settling
        force(target, reason: reason, from: current) // (3) verified mismatch → re-force
    }

    /// Arm one deferred re-check just past the settle window. Skipped when there
    /// is no standing target (a one-shot switch releases the lock), a check is
    /// already pending (coalesce a burst into one), or the retry budget is spent
    /// (bound a losing fight). Called from `force`, so every lock force gets a
    /// trailing "did it actually stick?" probe.
    private func scheduleReconcileCheck() {
        guard target != nil, !pendingRecheck else { return }
        guard reconcileRetries < Self.maxReconcileRetries else { return }
        reconcileRetries += 1
        pendingRecheck = true
        scheduler(Self.suppressionWindow + 0.02) { [weak self] in
            self?.performReconcileCheck()
        }
    }

    /// The deferred re-check. Clears the pending flag *first* (so a re-force may
    /// arm the next link in the chain), then re-runs the enforcement decision.
    /// Routed through `enforceIfNeeded` — never a raw `force` — so it honors the
    /// secure-input gate, the settle window, and the satisfied-lock budget reset.
    private func performReconcileCheck() {
        pendingRecheck = false
        enforceIfNeeded(reason: .revertedSwitch)
    }

    /// Arm a single poll for secure event input turning off. Only ever called
    /// from the respect-mode gate, so it runs exclusively while a secure field
    /// keeps the lock suppressed. Coalesced to one in-flight poll.
    private func scheduleSecureInputWatch() {
        guard !secureWatchPending else { return }
        secureWatchPending = true
        scheduler(Self.secureInputPollInterval) { [weak self] in
            self?.performSecureInputWatch()
        }
    }

    /// A poll tick: re-run the enforcement decision. If secure input is still on
    /// (still gated), `enforceIfNeeded` re-arms this watch and returns; once it
    /// has turned off, `enforceIfNeeded` falls through the gate and re-asserts
    /// the lock (no re-arm), so the poll naturally stops. This is what recovers
    /// the lock after leaving a password field despite the missing blur
    /// notification.
    private func performSecureInputWatch() {
        secureWatchPending = false
        enforceIfNeeded(reason: .revertedSwitch)
    }

    private func force(_ id: InputSourceID, reason: ActivationReason, from: InputSourceID?) {
        let start = uptime()
        // Resolve the source we're leaving *before* the switch takes effect.
        let fromName = from.flatMap { provider.source(for: $0)?.localizedName ?? $0.rawValue }
        let ok = provider.select(id)
        settleUntil = uptime() + Self.suppressionWindow
        // Arm a bounded trailing re-check so a switch that silently didn't take
        // (a flaky CJKV select) or is immediately re-coerced (a secure field)
        // with no follow-up notification is still reconciled, instead of sitting
        // stuck off-target until the next unrelated event.
        scheduleReconcileCheck()
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
