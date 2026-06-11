import Foundation
import Testing

@testable import LockIMEKit

@Suite("ActivationCountStore")
struct ActivationCountStoreTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "lockime.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("a fresh store reports zero")
    func startsAtZero() {
        let store = ActivationCountStore(defaults: freshDefaults())
        #expect(store.count == 0)
    }

    @Test("increment advances and returns the new total")
    func incrementReturnsNewTotal() {
        let store = ActivationCountStore(defaults: freshDefaults())
        #expect(store.increment() == 1)
        #expect(store.increment() == 2)
        #expect(store.count == 2)
    }

    @Test("the total persists across store instances on the same defaults")
    func persistsAcrossInstances() {
        let defaults = freshDefaults()
        ActivationCountStore(defaults: defaults).increment()
        ActivationCountStore(defaults: defaults).increment()
        // A new instance (mimicking a relaunch) reads the accumulated total.
        #expect(ActivationCountStore(defaults: defaults).count == 2)
    }
}
