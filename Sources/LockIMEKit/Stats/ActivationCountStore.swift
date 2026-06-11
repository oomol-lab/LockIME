import Foundation

/// Persists the lifetime activation count to `UserDefaults`.
///
/// The count is a running total the user sees in Settings, so it must survive
/// app restarts *and* Sparkle updates (which relaunch the process). Keeping it
/// in memory would reset it to zero on every launch, so it lives here instead.
///
/// `UserDefaults` is itself thread-safe and `key` is immutable, so *reading*
/// the total needs no lock — a single `integer(forKey:)` is already atomic.
/// Only `increment()` does: it is a read-modify-write, and without a lock two
/// concurrent callers could read the same value and both write back the same
/// `+1`, losing a count. The lock serializes just that compound write, which
/// is all the `@unchecked Sendable` claim requires.
public final class ActivationCountStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = "activationCount") {
        self.defaults = defaults
        self.key = key
    }

    /// The stored lifetime total (zero when nothing has been recorded yet).
    /// Unlocked on purpose: the single `UserDefaults` read is atomic and yields
    /// a consistent value — the count just before or just after an in-flight
    /// increment, never a torn one.
    public var count: Int { defaults.integer(forKey: key) }

    /// Increment the stored total by one and return the new value.
    @discardableResult
    public func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let next = defaults.integer(forKey: key) + 1
        defaults.set(next, forKey: key)
        return next
    }
}
