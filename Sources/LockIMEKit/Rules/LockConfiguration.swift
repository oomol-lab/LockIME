import Foundation

/// Whether a per-URL rule **continuously locks** its source or just **switches
/// to it once** on entry.
///
/// `lock` is the original behavior — while the rule applies the engine keeps
/// re-applying the source, so any drift (the user, another app) is reverted.
/// `switchOnce` fires exactly once when the rule first becomes active, then steps
/// out of the way: the user may switch away and stays switched. For per-app rules
/// the equivalent distinction is carried by `AppRuleMode` (`.locked` vs
/// `.switched`); URL rules always pin a source, so they need only this 2-way axis.
public enum RuleAction: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Continuously enforce the source while the rule applies.
    case lock
    /// Switch to the source once on entry, then release (no enforcement).
    case switchOnce

    public var id: String { rawValue }
}

/// How LockIME behaves while a particular app is frontmost.
public enum AppRuleMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Continuously lock to `AppRule.lockedSourceID` while this app is frontmost.
    case locked
    /// Switch to `AppRule.lockedSourceID` once when this app activates, then
    /// release — the user may freely change the source afterward.
    case switched
    /// Do not enforce any lock while this app is frontmost.
    case ignored
    /// Fall back to the global default source.
    case useDefault

    public var id: String { rawValue }

    /// Whether this mode targets a specific input source (`.locked`/`.switched`)
    /// rather than deferring (`.ignored`/`.useDefault`). The two source-pinning
    /// modes differ only in *how* — a continuous lock vs a one-shot switch.
    public var pinsSource: Bool { self == .locked || self == .switched }
}

/// A per-app locking rule.
public struct AppRule: Codable, Sendable, Hashable, Identifiable {
    public var bundleID: String
    public var mode: AppRuleMode
    /// The targeted source when `mode` pins one (`.locked` or `.switched`).
    public var lockedSourceID: InputSourceID?

    public var id: String { bundleID }

    public init(bundleID: String, mode: AppRuleMode = .locked, lockedSourceID: InputSourceID? = nil) {
        self.bundleID = bundleID
        self.mode = mode
        self.lockedSourceID = lockedSourceID
    }
}

/// A per-URL rule for the optional Accessibility-gated enhanced mode.
public struct URLRule: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// Host pattern, e.g. `github.com` (matches subdomains) or `*.google.com`.
    public var hostPattern: String
    public var lockedSourceID: InputSourceID
    /// Whether a matched URL locks to the source or just switches to it once.
    public var action: RuleAction

    public init(
        id: UUID = UUID(),
        hostPattern: String,
        lockedSourceID: InputSourceID,
        action: RuleAction = .lock
    ) {
        self.id = id
        self.hostPattern = hostPattern
        self.lockedSourceID = lockedSourceID
        self.action = action
    }

    // Explicit keys (preserving the v1.x names) so the custom decoder below can
    // reference `.action`; `encode(to:)` stays synthesized off these.
    private enum CodingKeys: String, CodingKey {
        case id, hostPattern, lockedSourceID, action
    }

    // Lenient decoding: rules persisted before the lock/switch distinction carry
    // no `action`, so a missing key decodes to `.lock` (the original behavior).
    // This matters load-bearingly: `LockConfiguration` decodes `[URLRule]` with
    // `decodeIfPresent`, which *propagates* a per-element throw — a non-lenient
    // decoder would make one legacy URL rule abort the whole config load and
    // silently drop every rule (see `RuleStore.load`'s `try?`).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        hostPattern = try container.decode(String.self, forKey: .hostPattern)
        lockedSourceID = try container.decode(InputSourceID.self, forKey: .lockedSourceID)
        action = try container.decodeIfPresent(RuleAction.self, forKey: .action) ?? .lock
    }
}

/// The full persisted locking configuration.
public struct LockConfiguration: Codable, Sendable, Equatable {
    /// Master on/off (the tray "activate" toggle).
    public var isEnabled: Bool
    /// Global default locked source, used when no app rule applies.
    public var defaultSourceID: InputSourceID?
    /// Per-app overrides.
    public var appRules: [AppRule]
    /// Whether the Accessibility-gated enhanced mode is on.
    public var enhancedModeEnabled: Bool
    /// Per-URL rules (enhanced mode).
    public var urlRules: [URLRule]

    public init(
        isEnabled: Bool = false,
        defaultSourceID: InputSourceID? = nil,
        appRules: [AppRule] = [],
        enhancedModeEnabled: Bool = false,
        urlRules: [URLRule] = []
    ) {
        self.isEnabled = isEnabled
        self.defaultSourceID = defaultSourceID
        self.appRules = appRules
        self.enhancedModeEnabled = enhancedModeEnabled
        self.urlRules = urlRules
    }

    // Forward/backward-compatible decoding: missing keys fall back to defaults
    // so older saved configurations keep loading after upgrades.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        defaultSourceID = try container.decodeIfPresent(InputSourceID.self, forKey: .defaultSourceID)
        appRules = try container.decodeIfPresent([AppRule].self, forKey: .appRules) ?? []
        enhancedModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .enhancedModeEnabled) ?? false
        urlRules = try container.decodeIfPresent([URLRule].self, forKey: .urlRules) ?? []
    }

    public static let `default` = LockConfiguration()

    public func rule(for bundleID: String) -> AppRule? {
        appRules.first { $0.bundleID == bundleID }
    }
}
