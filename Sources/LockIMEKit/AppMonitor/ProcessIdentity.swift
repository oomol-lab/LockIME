import AppKit
import Foundation

/// Fallback identity for GUI processes that expose **no bundle identifier**: a
/// bare executable spawned by another program rather than launched from an
/// `.app` wrapper. Minecraft's `java` (started by a third-party launcher such
/// as PCL.Mac) is the canonical case — `NSRunningApplication.bundleIdentifier`
/// is `nil` for it, yet it owns windows, becomes frontmost, and fights over the
/// input source, so users need to target it with a rule.
///
/// Rules, the picker, the activation log, and the URL-scheme API all key apps
/// by a single opaque string. For bundle-less processes that string is a
/// synthetic `process:<executable-name>` — e.g. `process:java` — chosen so:
///
/// - It can never collide with a real bundle identifier: `CFBundleIdentifier`
///   may contain only alphanumerics, `.`, and `-`; a `:` is impossible.
/// - It is stable where it matters. The executable's *name* survives JVM
///   upgrades, launcher changes, and machine moves, while its *path* does not
///   (Minecraft's is versioned: `mojang-25.0.1.bundle/…/bin/java`). The flip
///   side — every bundle-less `java` process matches the same rule — is the
///   desired grouping for exactly this use case.
public enum ProcessIdentity {
    /// The namespace marker for synthetic identities.
    public static let prefix = "process:"

    /// The synthetic identity for an executable name, or `nil` when there is
    /// no usable name to key on.
    public static func syntheticID(executableName: String?) -> String? {
        guard let executableName, !executableName.isEmpty else { return nil }
        return prefix + executableName
    }

    /// The synthetic identity for a bundle-less process's coordinates. Prefers
    /// the executable's basename; falls back to the process name
    /// (`localizedName`), which for a bare executable is not localized — it
    /// *is* the basename. Pure so the preference order is directly testable.
    public static func syntheticID(executableURL: URL?, processName: String?) -> String? {
        syntheticID(executableName: executableURL?.lastPathComponent ?? processName)
    }

    /// The synthetic identity for a running bundle-less process.
    public static func syntheticID(for app: NSRunningApplication) -> String? {
        syntheticID(executableURL: app.executableURL, processName: app.localizedName)
    }

    /// The executable name inside a synthetic identity, or `nil` for a real
    /// bundle identifier (or a degenerate `process:` with nothing after it).
    public static func executableName(from id: String) -> String? {
        guard id.hasPrefix(prefix) else { return nil }
        let name = String(id.dropFirst(prefix.count))
        return name.isEmpty ? nil : name
    }

    /// Whether `id` is a synthetic `process:` identity rather than a bundle ID.
    public static func isSynthetic(_ id: String) -> Bool {
        executableName(from: id) != nil
    }
}

extension NSRunningApplication {
    /// The string rules key on: the real bundle identifier when the process has
    /// one, else the synthetic `process:` identity, else `nil`. Every reader of
    /// "which app is this?" (frontmost monitor, running-apps scan, display
    /// lookup) must go through this one property so the identity the picker
    /// offers is byte-identical to the one the engine resolves at runtime.
    public var ruleIdentity: String? {
        bundleIdentifier ?? ProcessIdentity.syntheticID(for: self)
    }
}
