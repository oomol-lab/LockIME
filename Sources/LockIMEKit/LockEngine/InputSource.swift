import Foundation

/// A keyboard input source (layout or input method) as surfaced by the
/// Text Input Sources (TIS) API.
public struct InputSource: Hashable, Sendable, Identifiable {
    public let id: InputSourceID
    public let localizedName: String
    public let isSelectCapable: Bool
    public let isEnabled: Bool
    /// Whether this is a Chinese/Japanese/Korean/Vietnamese input *method*,
    /// which needs the focus-stealing workaround to switch reliably.
    public let isCJKV: Bool

    public init(
        id: InputSourceID,
        localizedName: String,
        isSelectCapable: Bool,
        isEnabled: Bool,
        isCJKV: Bool
    ) {
        self.id = id
        self.localizedName = localizedName
        self.isSelectCapable = isSelectCapable
        self.isEnabled = isEnabled
        self.isCJKV = isCJKV
    }
}

/// Why the engine forced the input source — recorded in the activation log.
///
/// The cases distinguish events that previously collapsed into one another, so
/// the log can tell a real app switch from a launcher overlay, a periodic URL
/// re-check from a navigation, and "locking turned on" from "a rule was edited".
public enum ActivationReason: String, Sendable, Codable, CaseIterable {
    /// An external "selected source changed" (user hotkey, another app, a menu
    /// pick) drifted off target and we reverted.
    case revertedSwitch
    /// A real `NSWorkspace` frontmost-app change applied that app's rule.
    case appActivated
    /// A launcher/command-bar overlay (Spotlight, Raycast, …) took keyboard
    /// focus without changing the frontmost app, and its rule was applied.
    case launcherFocused
    /// A launcher overlay was dismissed and focus returned to the frontmost
    /// app, whose rule was re-applied.
    case launcherDismissed
    /// Enhanced mode: the periodic URL poll re-affirmed the app/default rule
    /// because the page URL matched no URL rule (a timer re-check, not a switch).
    case urlPolled
    /// Enhanced mode: the browser URL matched a rule and that rule was applied.
    case urlMatched
    /// The master lock toggle was turned on while the source was off target.
    case lockEngaged
    /// A configuration edit while already locked (default source, an app rule,
    /// enhanced mode, or a URL rule) re-resolved and applied a new target.
    case configChanged
    /// The launch/restore apply (including after a Sparkle relaunch) enforced
    /// the locked source at startup because the live source already differed.
    case startupApplied
    /// An external `lockime://switch-source` URL-scheme command forced a transient
    /// switch. Logged at the moment the switch takes effect; a standing continuous
    /// lock targeting a different source still wins and reverts it on the next
    /// change (recorded separately as `.revertedSwitch`).
    case apiCommand
}

/// A single enforcement event, emitted whenever the engine forces the source.
public struct ActivationEvent: Hashable, Sendable {
    public let timestamp: Date
    public let inputSource: InputSourceID
    public let inputSourceName: String
    public let reason: ActivationReason
    /// Wall time the `select` call took, in milliseconds.
    public let durationMs: Double
    /// Localized name of the source switched *away from*, when known — the most
    /// diagnostic datum for `revertedSwitch` ("what did it drift to?").
    public let fromSourceName: String?
    /// Bundle ID of the app (or launcher overlay) the rule resolved against.
    public let triggeringBundleID: String?
    /// Which rule branch produced the target (per-app rule, global default, or
    /// a URL rule), so the log can say *why* this source was locked.
    public let ruleSource: RuleSource?
    /// The matched URL rule's host pattern, for `urlMatched` events only.
    public let matchedHost: String?

    public init(
        timestamp: Date,
        inputSource: InputSourceID,
        inputSourceName: String,
        reason: ActivationReason,
        durationMs: Double,
        fromSourceName: String? = nil,
        triggeringBundleID: String? = nil,
        ruleSource: RuleSource? = nil,
        matchedHost: String? = nil
    ) {
        self.timestamp = timestamp
        self.inputSource = inputSource
        self.inputSourceName = inputSourceName
        self.reason = reason
        self.durationMs = durationMs
        self.fromSourceName = fromSourceName
        self.triggeringBundleID = triggeringBundleID
        self.ruleSource = ruleSource
        self.matchedHost = matchedHost
    }
}
