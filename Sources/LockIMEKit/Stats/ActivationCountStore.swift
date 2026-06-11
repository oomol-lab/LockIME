import Foundation

/// Persists the lifetime activation count to `UserDefaults`.
///
/// The count is a running total the user sees in Settings, so it must survive
/// app restarts *and* Sparkle updates (which relaunch the process). Keeping it
/// in memory would reset it to zero on every launch, so it lives here instead.
///
/// `UserDefaults` is thread-safe and `key` is immutable, so this is safely
/// `@unchecked Sendable`.
public final class ActivationCountStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "activationCount") {
        self.defaults = defaults
        self.key = key
    }

    /// The stored lifetime total (zero when nothing has been recorded yet).
    public var count: Int { defaults.integer(forKey: key) }

    /// Increment the stored total by one and return the new value.
    @discardableResult
    public func increment() -> Int {
        let next = defaults.integer(forKey: key) + 1
        defaults.set(next, forKey: key)
        return next
    }
}
