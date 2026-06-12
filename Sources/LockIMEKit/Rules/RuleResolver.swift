import Foundation

/// Which branch of the rule precedence produced the locked target. Carried into
/// the activation log so a row can say *why* a source was locked.
public enum RuleSource: String, Sendable, Codable, CaseIterable {
    /// A per-app rule with an explicit locked source.
    case appRule
    /// The global default source (no app rule applied).
    case globalDefault
    /// An enhanced-mode URL rule.
    case urlRule
}

/// The outcome of resolving which source (if any) to enforce right now.
public enum LockResolution: Equatable, Sendable {
    /// Enforce this source, produced by the given rule branch.
    case lock(InputSourceID, RuleSource)
    /// The frontmost app is explicitly ignored — do not enforce.
    case ignore
    /// No applicable target — locking is effectively idle.
    case noTarget
}

/// Pure resolution of the active lock target. Precedence:
/// enhanced URL match → per-app rule → global default.
public enum RuleResolver {
    public static func resolve(
        config: LockConfiguration,
        frontmostBundleID: String?,
        urlMatch: InputSourceID? = nil
    ) -> LockResolution {
        // 1. Enhanced mode (P6): a matched browser-URL rule wins outright.
        if let urlMatch {
            return .lock(urlMatch, .urlRule)
        }

        // 2. Per-app rule.
        if let bundleID = frontmostBundleID, let rule = config.rule(for: bundleID) {
            switch rule.mode {
            case .ignored:
                return .ignore
            case .locked:
                if let id = rule.lockedSourceID {
                    return .lock(id, .appRule)
                }
                // "locked" with no source set → fall through to the default.
            case .useDefault:
                break
            }
        }

        // 3. Global default.
        if let def = config.defaultSourceID {
            return .lock(def, .globalDefault)
        }
        return .noTarget
    }
}
