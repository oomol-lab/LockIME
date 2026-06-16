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

    private enum CodingKeys: String, CodingKey {
        case bundleID, mode, lockedSourceID
    }

    // Lenient decoding (same rationale as `URLRule`): `mode` is decoded as a raw
    // string and mapped, so a value this build doesn't recognize (a newer build
    // added an `AppRuleMode` case, then the file is read after a downgrade) falls
    // back to `.locked` instead of throwing — a per-element throw would propagate
    // through `decodeIfPresent([AppRule].self)` and silently drop the whole config.
    // `encode(to:)` stays synthesized off these keys.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        let rawMode = try container.decodeIfPresent(String.self, forKey: .mode)
        mode = rawMode.flatMap(AppRuleMode.init(rawValue:)) ?? .locked
        lockedSourceID = try container.decodeIfPresent(InputSourceID.self, forKey: .lockedSourceID)
    }
}

/// How a `URLRule`'s pattern string is matched against the browser's current URL.
///
/// The pattern (`URLRule.hostPattern`) is interpreted differently per case, so a
/// single rule type can be a domain, a domain family, a substring, or an
/// arbitrary regular expression. `domainSuffix` is the original behavior and the
/// lenient-decode default — every rule persisted before this field existed keeps
/// matching exactly as before. Rules are evaluated **top-to-bottom, first match
/// wins**, so the order of `LockConfiguration.urlRules` is the priority.
public enum URLMatchType: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Match the host *and all its subdomains* — `github.com` matches
    /// `github.com` and `gist.github.com`. The original (and default) behavior;
    /// a leading `*.` in the pattern is tolerated and ignored.
    case domainSuffix = "domain-suffix"
    /// Match *only* the exact host, never a subdomain — `github.com` matches
    /// `github.com` but not `gist.github.com`.
    case domain = "domain"
    /// Match when the host *contains* the pattern as a substring — `google`
    /// matches `google.com`, `mail.google.com`, and `googleapis.com`.
    case domainKeyword = "domain-keyword"
    /// Match the **whole URL** (scheme · host · path · query · fragment) against
    /// the pattern as a regular expression. The only type that sees past the
    /// host, so it can distinguish pages of one site by path or query. Matching
    /// is case-insensitive and unanchored (use `^`/`$` to anchor).
    case urlRegex = "url-regex"

    public var id: String { rawValue }
}

/// A per-URL rule for the optional Accessibility-gated enhanced mode.
public struct URLRule: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// The pattern string, interpreted per `matchType`: a host for
    /// `domainSuffix`/`domain`, a substring for `domainKeyword`, or a regular
    /// expression over the whole URL for `urlRegex`. Named `hostPattern` for
    /// backward compatibility — it is the persisted key and the original meaning
    /// (a host) is still the default interpretation.
    public var hostPattern: String
    public var lockedSourceID: InputSourceID
    /// Whether a matched URL locks to the source or just switches to it once.
    public var action: RuleAction
    /// How `hostPattern` is matched against the browser's current URL.
    public var matchType: URLMatchType

    public init(
        id: UUID = UUID(),
        hostPattern: String,
        lockedSourceID: InputSourceID,
        action: RuleAction = .lock,
        matchType: URLMatchType = .domainSuffix
    ) {
        self.id = id
        self.hostPattern = hostPattern
        self.lockedSourceID = lockedSourceID
        self.action = action
        self.matchType = matchType
    }

    // Explicit keys (preserving the v1.x names) so the custom decoder below can
    // reference `.action`/`.matchType`; `encode(to:)` stays synthesized off these.
    private enum CodingKeys: String, CodingKey {
        case id, hostPattern, lockedSourceID, action, matchType
    }

    // Lenient decoding: rules persisted before the lock/switch distinction carry
    // no `action`, and rules persisted before match types carry no `matchType`,
    // so a missing key decodes to the original behavior (`.lock` / `.domainSuffix`).
    // Crucially we decode `action`/`matchType` as raw *strings* and map them
    // ourselves rather than as the enums directly: a missing key AND an
    // *unrecognized* value (e.g. a newer build wrote a match type this build
    // doesn't know, then the file is read after a downgrade) both fall back to the
    // default instead of throwing. This matters load-bearingly: `LockConfiguration`
    // decodes `[URLRule]` with `decodeIfPresent`, which *propagates* a per-element
    // throw — a decoder that threw on an unknown value would make one such URL rule
    // abort the whole config load and silently drop every rule (see
    // `RuleStore.load`'s `try?`).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        hostPattern = try container.decode(String.self, forKey: .hostPattern)
        lockedSourceID = try container.decode(InputSourceID.self, forKey: .lockedSourceID)
        let rawAction = try container.decodeIfPresent(String.self, forKey: .action)
        action = rawAction.flatMap(RuleAction.init(rawValue:)) ?? .lock
        let rawMatchType = try container.decodeIfPresent(String.self, forKey: .matchType)
        matchType = rawMatchType.flatMap(URLMatchType.init(rawValue:)) ?? .domainSuffix
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
