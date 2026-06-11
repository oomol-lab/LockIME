import Foundation

/// Persists the lifetime activation count to `UserDefaults`.
///
/// The count is a running total the user sees in Settings, so it must survive
/// app restarts *and* Sparkle updates (which relaunch the process). Keeping it
/// in memory would reset it to zero on every launch, so it lives here instead.
///
/// `UserDefaults` is thread-safe and `key` is immutable. `increment()` is a
/// read-modify-write, though, so a lock serializes it to keep the compound
/// step atomic — without it concurrent callers could race and undercount,
/// which would defeat the `@unchecked Sendable` claim.
public final class ActivationCountStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = "activationCount") {
        self.defaults = defaults
        self.key = key
    }

    /// The stored lifetime total (zero when nothing has been recorded yet).
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return defaults.integer(forKey: key)
    }

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
