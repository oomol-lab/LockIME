import Testing

@testable import LockIMEKit

@Suite("DirectSelectionConfirmation")
struct DirectSelectionConfirmationTests {
    private let wetype = InputSourceID("com.tencent.inputmethod.wetype.pinyin")
    private let abc = InputSourceID("com.apple.keylayout.ABC")

    @Test("a fresh tracker tries the direct path")
    func freshTriesDirect() {
        var tracker = DirectSelectionConfirmation()
        let attempt1 = tracker.shouldTryDirect(for: wetype)
        #expect(attempt1)
    }

    @Test("a repeat of an unconfirmed direct selection falls back exactly once")
    func unconfirmedRepeatFallsBackOnce() {
        var tracker = DirectSelectionConfirmation()
        tracker.didSelectDirectly(wetype)
        // The lock's reconcile asks again: the acknowledged switch never showed
        // up as current, so this attempt must use the public API…
        let attempt2 = tracker.shouldTryDirect(for: wetype)
        #expect(!attempt2)
        // …and the one after that gets the direct path back.
        let attempt3 = tracker.shouldTryDirect(for: wetype)
        #expect(attempt3)
    }

    @Test("seeing the source as current confirms it, keeping the next selection direct")
    func confirmationKeepsDirect() {
        var tracker = DirectSelectionConfirmation()
        tracker.didSelectDirectly(wetype)
        tracker.observed(current: wetype)
        #expect(tracker.pending == nil)
        // A user toggling away twice in a row: the second revert must not be
        // demoted to the unreliable public path.
        let attempt4 = tracker.shouldTryDirect(for: wetype)
        #expect(attempt4)
    }

    @Test("reading a different or unknown source does not confirm")
    func otherSourceDoesNotConfirm() {
        var tracker = DirectSelectionConfirmation()
        tracker.didSelectDirectly(wetype)
        tracker.observed(current: abc)
        tracker.observed(current: nil)
        #expect(tracker.pending == wetype)
        let attempt5 = tracker.shouldTryDirect(for: wetype)
        #expect(!attempt5)
    }

    @Test("a different target is unaffected by a pending selection")
    func differentTargetStaysDirect() {
        var tracker = DirectSelectionConfirmation()
        tracker.didSelectDirectly(wetype)
        let attempt6 = tracker.shouldTryDirect(for: abc)
        #expect(attempt6)
        // The unrelated request must not consume the pending fallback.
        #expect(tracker.pending == wetype)
    }
}
