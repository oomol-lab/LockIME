import Foundation

/// Persists `LockConfiguration` to `UserDefaults` as JSON (small data, no
/// querying — SwiftData would be overkill here).
///
/// `UserDefaults` is thread-safe and `key` is immutable, so this is safely
/// `@unchecked Sendable`.
public final class RuleStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "lockConfiguration") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> LockConfiguration {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(LockConfiguration.self, from: data)
        else {
            return .default
        }
        return config
    }

    /// Whether a configuration has ever been written to `defaults`. This is the
    /// only way to tell a genuine **first run** — where the app seeds the global
    /// default from the currently active input source — apart from a returning
    /// user who deliberately set that default to **None**. Both surface as a
    /// loaded config with `defaultSourceID == nil`, so gating the first-run seed
    /// on `defaultSourceID == nil` alone would silently overwrite a chosen "None"
    /// with whatever source happened to be active at launch, on *every* relaunch.
    public var hasPersistedConfiguration: Bool {
        defaults.data(forKey: key) != nil
    }

    public func save(_ config: LockConfiguration) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key)
    }
}
