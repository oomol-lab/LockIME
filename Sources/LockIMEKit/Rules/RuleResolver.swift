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
    /// The address-bar focus rule — a browser's address bar has keyboard focus.
    case addressBarRule
}

/// The outcome of resolving which source (if any) to enforce right now.
public enum LockResolution: Equatable, Sendable {
    /// Continuously enforce this source, produced by the given rule branch.
    case lock(InputSourceID, RuleSource)
    /// Switch to this source **once** (no standing enforcement), produced by the
    /// given rule branch. A per-app `.switched` rule, a per-URL `.switchOnce`
    /// rule, or a global default whose `defaultAction` is `.switchOnce` yields this.
    case switchOnce(InputSourceID, RuleSource)
    /// The frontmost app is explicitly ignored — do not enforce.
    case ignore
    /// No applicable target — locking is effectively idle.
    case noTarget
}

/// Pure resolution of the active lock target. Precedence:
/// {enhanced URL match, address-bar focus} → per-app rule → global default,
/// where the relative order of the two browser-scoped rules is user-controlled
/// (`addressBarOutranksURLRules`, default address-bar-first).
public enum RuleResolver {
    public static func resolve(
        config: LockConfiguration,
        frontmostBundleID: String?,
        urlMatch: (id: InputSourceID, action: RuleAction)? = nil,
        addressBarFocused: Bool = false
    ) -> LockResolution {
        // 1. Browser-scoped rules: a matched URL rule and/or the focused address
        //    bar. Both outrank the per-app/default rule; which of the *two* wins
        //    when both apply is user-controlled (`addressBarOutranksURLRules`,
        //    default true → the address bar wins, since typing in it is the more
        //    immediate intent). Each rule's action decides lock vs one-shot
        //    switch. A `nil` address-bar target makes that rule inert (it
        //    contributes no candidate), so an enabled-but-unconfigured rule never acts.
        let urlResolution: LockResolution? = urlMatch.map {
            $0.action == .switchOnce ? .switchOnce($0.id, .urlRule) : .lock($0.id, .urlRule)
        }
        let addressBarResolution: LockResolution? = {
            guard addressBarFocused, config.addressBarFocusEnabled, let id = config.addressBarSourceID
            else { return nil }
            return config.addressBarAction == .switchOnce
                ? .switchOnce(id, .addressBarRule)
                : .lock(id, .addressBarRule)
        }()
        // Array index = priority (element 0 outranks element 1); `compactMap`
        // drops an inactive (nil) candidate so it neither wins nor blocks the
        // one behind it, and `.first` takes the highest-priority survivor.
        let browserScoped = config.addressBarOutranksURLRules
            ? [addressBarResolution, urlResolution]
            : [urlResolution, addressBarResolution]
        if let winner = browserScoped.compactMap({ $0 }).first {
            return winner
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
            case .switched:
                if let id = rule.lockedSourceID {
                    return .switchOnce(id, .appRule)
                }
                // "switched" with no source set → fall through to the default
                // (which honors `defaultAction`).
            case .useDefault:
                break
            }
        }

        // 3. Global default. Continuously locks (the original behavior) or fires a
        //    one-shot switch on entering a no-rule app, per `config.defaultAction`.
        if let def = config.defaultSourceID {
            return config.defaultAction == .switchOnce
                ? .switchOnce(def, .globalDefault)
                : .lock(def, .globalDefault)
        }
        return .noTarget
    }
}
