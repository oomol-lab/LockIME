import Foundation
import Testing

@testable import LockIMEKit

/// The pure URL-rule list operations behind `AppState.upsertURLRule` /
/// `reorderURLRules`. These hold two load-bearing invariants that were previously
/// only exercised through the (untestable) app-target mutators:
///   1. order is priority — an edit keeps a rule's slot, never demotes it;
///   2. pattern is identity — no two rules ever share a pattern (case-insensitively),
///      else the pair collapses, losing one, on the next export→import.
@Suite("URLRuleList")
struct URLRuleListTests {
    private let us: InputSourceID = "com.apple.keylayout.US"
    private let pinyin: InputSourceID = "com.apple.inputmethod.SCIM.ITABC"

    private func rule(
        _ host: String, _ src: InputSourceID, id: UUID = UUID(),
        action: RuleAction = .lock, type: URLMatchType = .domainSuffix
    ) -> URLRule {
        URLRule(id: id, hostPattern: host, lockedSourceID: src, action: action, matchType: type)
    }

    // MARK: upserting

    @Test("editing a rule's binding keeps its position (order is priority)")
    func editKeepsPosition() {
        let a = rule("a.com", us), b = rule("b.com", us), c = rule("c.com", us)
        let edited = URLRule(id: b.id, hostPattern: "b.com", lockedSourceID: pinyin, action: .switchOnce, matchType: .domain)
        let out = URLRuleList.upserting(edited, into: [a, b, c])
        #expect(out.map(\.id) == [a.id, b.id, c.id])  // slot unchanged
        #expect(out[1].lockedSourceID == pinyin)      // binding updated in place
        #expect(out[1].matchType == .domain)
        #expect(out[1].action == .switchOnce)
    }

    @Test("adding a unique pattern appends to the end")
    func addUniqueAppends() {
        let a = rule("a.com", us)
        let out = URLRuleList.upserting(rule("b.com", pinyin), into: [a])
        #expect(out.map(\.hostPattern) == ["a.com", "b.com"])
    }

    @Test("adding a rule whose pattern already exists updates it in place, never duplicating")
    func addDuplicatePatternUpdatesInPlace() {
        let a = rule("a.com", us), b = rule("b.com", us)
        // A brand-new id but an existing pattern → update the existing rule, keep slot.
        let out = URLRuleList.upserting(rule("a.com", pinyin, action: .switchOnce), into: [a, b])
        #expect(out.count == 2)                                // no duplicate
        #expect(out.map(\.hostPattern) == ["a.com", "b.com"])  // slot preserved
        #expect(out[0].id == a.id)                             // existing id kept
        #expect(out[0].lockedSourceID == pinyin)               // binding adopted
        #expect(out[0].action == .switchOnce)
    }

    @Test("a same-pattern collision is case-insensitive (mirrors the URL-scheme host fallback)")
    func collisionCaseInsensitive() {
        let a = rule("GitHub.com", us)
        let out = URLRuleList.upserting(rule("github.com", pinyin), into: [a])
        #expect(out.count == 1)            // folded, not duplicated
        #expect(out[0].id == a.id)
        #expect(out[0].lockedSourceID == pinyin)
    }

    @Test("editing a rule's pattern onto ANOTHER rule's collapses them — never two same-pattern rules")
    func editOntoAnotherPatternCollapses() {
        let a = rule("a.com", us), b = rule("b.com", pinyin)
        // Edit a (by id) so its pattern becomes b's pattern.
        let edited = URLRule(id: a.id, hostPattern: "b.com", lockedSourceID: us, action: .switchOnce, matchType: .domain)
        let out = URLRuleList.upserting(edited, into: [a, b])
        #expect(out.count == 1)  // the invariant: exactly one rule per pattern
        #expect(out.filter { $0.hasSamePattern(as: "b.com") }.count == 1)
        // The surviving rule sits in b's slot/id, carrying the edited binding.
        #expect(out[0].id == b.id)
        #expect(out[0].lockedSourceID == us)
        #expect(out[0].matchType == .domain)
        #expect(out[0].action == .switchOnce)
    }

    @Test("upserting never produces two rules sharing a pattern, across paths")
    func upsertKeepsPatternsUnique() {
        var rules = [rule("a.com", us), rule("b.com", us), rule("c.com", us)]
        rules = URLRuleList.upserting(rule("a.com", pinyin), into: rules)             // re-add existing
        rules = URLRuleList.upserting(rule("B.COM", pinyin), into: rules)             // case-variant
        let editC = URLRule(id: rules[2].id, hostPattern: "a.com", lockedSourceID: us, action: .lock, matchType: .domain)
        rules = URLRuleList.upserting(editC, into: rules)                             // edit onto another
        let patterns = rules.map { $0.hostPattern.lowercased() }
        #expect(Set(patterns).count == patterns.count)  // no duplicate pattern, any casing
    }

    // MARK: reordered

    @Test("reordered re-sequences the live rules by id")
    func reorderBasic() {
        let a = rule("a.com", us), b = rule("b.com", us), c = rule("c.com", us)
        let out = URLRuleList.reordered([a, b, c], by: [c, a, b])
        #expect(out?.map(\.id) == [c.id, a.id, b.id])
    }

    @Test("reordered returns nil for an unchanged order (a no-op)")
    func reorderUnchangedIsNil() {
        let a = rule("a.com", us), b = rule("b.com", us)
        #expect(URLRuleList.reordered([a, b], by: [a, b]) == nil)
    }

    @Test("reordered returns nil for a non-permutation (a stale drag-start snapshot)")
    func reorderNonPermutationIsNil() {
        let a = rule("a.com", us), b = rule("b.com", us), c = rule("c.com", us)
        #expect(URLRuleList.reordered([a, b, c], by: [a, b]) == nil)   // missing an id
        #expect(URLRuleList.reordered([a, b], by: [a, b, c]) == nil)   // extra/unknown id
        #expect(URLRuleList.reordered([a, b], by: [a, a, b]) == nil)   // duplicate id (right id set, wrong count)
    }

    @Test("reordered relinks to the LIVE rule, discarding the snapshot's stale binding")
    func reorderRelinksToLive() {
        let a = rule("a.com", us), b = rule("b.com", us)
        // A drag-start snapshot of b carrying a STALE binding; the live b was rebound
        // (e.g. a `lockime://set-url-rule` landed mid-drag). The reorder must keep the
        // live binding, not the snapshot's.
        let staleB = URLRule(id: b.id, hostPattern: "b.com", lockedSourceID: us, action: .lock, matchType: .domainSuffix)
        let liveB = URLRule(id: b.id, hostPattern: "b.com", lockedSourceID: pinyin, action: .switchOnce, matchType: .domain)
        let out = URLRuleList.reordered([a, liveB], by: [staleB, a])
        #expect(out?.map(\.id) == [b.id, a.id])
        #expect(out?.first?.lockedSourceID == pinyin)  // live binding, not the stale snapshot
        #expect(out?.first?.action == .switchOnce)
        #expect(out?.first?.matchType == .domain)
    }
}
