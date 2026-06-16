import Foundation

public extension URLRule {
    /// Whether this rule's pattern is the same as `pattern`, **ignoring case** —
    /// the same notion of sameness the URL-scheme API's host fallback uses
    /// (`compare(options: .caseInsensitive)`). `hostPattern` is a rule's portable
    /// identity, *match-type-independent* — the import diff keys a URL rule by
    /// `"url:<hostPattern>"` regardless of type, so two rules with an **identical**
    /// pattern collapse (losing one) on the next export→import. Case-*variant*
    /// patterns don't collapse on import (it keys on the exact string) but are
    /// functionally redundant, since host matching is itself case-insensitive — so
    /// the mutation paths fold them too, by comparing case-insensitively here.
    func hasSamePattern(as pattern: String) -> Bool {
        hostPattern.compare(pattern, options: .caseInsensitive) == .orderedSame
    }
}

/// Pure list operations for URL rules, holding the two load-bearing invariants in
/// one testable place (the `AppState` mutators are thin wrappers over these):
///
/// 1. **Order is priority** — rules resolve top-to-bottom, first match wins — so an
///    edit must keep a rule's slot, never demote it to the bottom.
/// 2. **Pattern is identity** — these mutation paths never produce two rules sharing
///    a pattern (case-insensitively): backups/import key on `hostPattern`, so an
///    identical pair would collapse (losing one) on the next export→import, and a
///    case-variant pair is functionally redundant (host matching is case-insensitive).
///    The import diff de-dupes by the exact string; these guards are stricter, so a
///    case-variant pair can never be minted here in the first place.
public enum URLRuleList {
    /// Insert or update `rule`, preserving both invariants and returning the new
    /// list. The slot is resolved so a duplicate pattern can never be minted:
    ///
    /// - If `rule`'s pattern is unused by any *other* rule and a rule with its id
    ///   exists, update that rule **in place** (an edit keeps its priority slot).
    /// - Else if some rule already owns the pattern (an add of an existing pattern,
    ///   or an edit that moved a rule's pattern onto another's), update **that**
    ///   rule in place (the documented upsert-by-host) and drop the rule the edit
    ///   vacated, so the pattern stays unique.
    /// - Else append.
    ///
    /// Callers that can surface feedback (the editor, the URL-scheme API) reject a
    /// collision *before* calling this, so the lossy fold is a last-resort net that
    /// keeps the persisted config self-consistent even if a future caller forgets.
    public static func upserting(_ rule: URLRule, into rules: [URLRule]) -> [URLRule] {
        var rules = rules
        let collidesWithOther = rules.contains { $0.id != rule.id && $0.hasSamePattern(as: rule.hostPattern) }

        if let idIndex = rules.firstIndex(where: { $0.id == rule.id }), !collidesWithOther {
            rules[idIndex] = rule
        } else if let patternIndex = rules.firstIndex(where: { $0.hasSamePattern(as: rule.hostPattern) }) {
            let existingID = rules[patternIndex].id
            rules[patternIndex] = URLRule(
                id: existingID,
                hostPattern: rule.hostPattern,
                lockedSourceID: rule.lockedSourceID,
                action: rule.action,
                matchType: rule.matchType
            )
            // If the edit moved a *different* rule (`rule.id`) onto this pattern,
            // remove its vacated slot so the pattern isn't duplicated.
            rules.removeAll { $0.id == rule.id && $0.id != existingID }
        } else {
            rules.append(rule)
        }
        return rules
    }

    /// The result of committing a drag-reorder: `rules` re-sequenced to match the
    /// id order of `ordered`, or `nil` when the reorder is a no-op (unchanged
    /// order) or invalid (a non-permutation — a stale drag-start snapshot whose id
    /// set no longer matches the live rules). Rules are relinked to the **live**
    /// objects by id rather than carrying `ordered`'s snapshotted bindings, so a
    /// content edit that landed mid-drag (e.g. a `lockime://set-url-rule`) survives
    /// the reorder instead of being clobbered by the drag-start snapshot.
    public static func reordered(_ rules: [URLRule], by ordered: [URLRule]) -> [URLRule]? {
        let byID = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let orderedIDs = ordered.map(\.id)
        // A valid permutation has the same length, no repeats, and the same id
        // set as the live rules. Checking only set-equality would accept a
        // non-permutation like `[a, a, b]` (against `[a, b]`) and return a list
        // with a duplicated rule, corrupting the persisted priority order.
        guard orderedIDs.count == rules.count,
              Set(orderedIDs).count == orderedIDs.count,
              Set(orderedIDs) == Set(byID.keys),
              orderedIDs != rules.map(\.id)
        else { return nil }
        return orderedIDs.compactMap { byID[$0] }
    }
}
