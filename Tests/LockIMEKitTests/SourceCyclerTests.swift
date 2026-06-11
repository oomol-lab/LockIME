import Foundation
import Testing

@testable import LockIMEKit

@Suite("SourceCycler")
struct SourceCyclerTests {
    private let a: InputSourceID = "com.apple.keylayout.ABC"
    private let b: InputSourceID = "com.apple.keylayout.US"
    private let c: InputSourceID = "com.apple.inputmethod.SCIM.ITABC"

    private var three: [InputSourceID] { [a, b, c] }

    @Test("next advances by one")
    func nextAdvances() {
        #expect(SourceCycler.step(from: a, in: three, direction: .next) == b)
        #expect(SourceCycler.step(from: b, in: three, direction: .next) == c)
    }

    @Test("previous retreats by one")
    func previousRetreats() {
        #expect(SourceCycler.step(from: c, in: three, direction: .previous) == b)
        #expect(SourceCycler.step(from: b, in: three, direction: .previous) == a)
    }

    @Test("next wraps from the last source to the first")
    func nextWraps() {
        #expect(SourceCycler.step(from: c, in: three, direction: .next) == a)
    }

    @Test("previous wraps from the first source to the last")
    func previousWraps() {
        #expect(SourceCycler.step(from: a, in: three, direction: .previous) == c)
    }

    @Test("a single source is a no-op in both directions")
    func singleSourceIsNoOp() {
        #expect(SourceCycler.step(from: a, in: [a], direction: .next) == nil)
        #expect(SourceCycler.step(from: a, in: [a], direction: .previous) == nil)
        // Even with no reference, one source has nowhere to go.
        #expect(SourceCycler.step(from: nil, in: [a], direction: .next) == nil)
    }

    @Test("an empty list is a no-op")
    func emptyIsNoOp() {
        #expect(SourceCycler.step(from: nil, in: [], direction: .next) == nil)
        #expect(SourceCycler.step(from: a, in: [], direction: .previous) == nil)
    }

    @Test("a missing reference starts at the first source for next, last for previous")
    func missingReferenceStartsAtEnd() {
        #expect(SourceCycler.step(from: nil, in: three, direction: .next) == a)
        #expect(SourceCycler.step(from: nil, in: three, direction: .previous) == c)
        // A reference that isn't in the list (e.g. removed) behaves the same.
        let stale: InputSourceID = "com.apple.keylayout.Removed"
        #expect(SourceCycler.step(from: stale, in: three, direction: .next) == a)
        #expect(SourceCycler.step(from: stale, in: three, direction: .previous) == c)
    }

    @Test("two sources toggle back and forth")
    func twoSourcesToggle() {
        #expect(SourceCycler.step(from: a, in: [a, b], direction: .next) == b)
        #expect(SourceCycler.step(from: b, in: [a, b], direction: .next) == a)
        #expect(SourceCycler.step(from: a, in: [a, b], direction: .previous) == b)
        #expect(SourceCycler.step(from: b, in: [a, b], direction: .previous) == a)
    }
}
