import Foundation

/// Launcher-overlay apps — Spotlight, Raycast, Alfred, LaunchBar — that draw a
/// transient search field *over* whatever app is frontmost **without becoming
/// the frontmost application themselves**.
///
/// macOS never updates `NSWorkspace.frontmostApplication` for these overlays, so
/// `AppActivationMonitor` keeps reporting the app behind the overlay. Per-app
/// rules therefore resolve against the wrong app: locking is impossible to scope
/// to the launcher, and a CJKV lock on the underlying app leaks into the search
/// field (the reported bug — issue #9). `FloatingAppMonitor` recovers the real
/// keyboard-focused app via the Accessibility API and consults this catalog to
/// decide whether that app is a launcher overlay worth treating as the active
/// app for rule resolution.
///
/// Scoped to a curated allow-list (mirrors InputSourcePro's "Spotlight-like
/// apps" set) rather than "any app whose focused element differs from the
/// frontmost", which would misfire for helper processes and our own panels.
public enum LauncherOverlayCatalog {
    /// Bundle identifiers of known launcher overlays. Spotlight is the headline
    /// case and is the only one that is *exclusively* an overlay; the others are
    /// regular apps whose command bar happens to float over the frontmost app —
    /// resolving their own bundle ID is correct in both modes, so listing them
    /// is safe.
    public static let bundleIDs: Set<String> = [
        "com.apple.Spotlight",            // Spotlight (Cmd-Space)
        "com.raycast.macos",              // Raycast
        "com.runningwithcrayons.Alfred",  // Alfred
        "at.obdev.LaunchBar",             // LaunchBar
    ]

    /// Whether `bundleID` is a known launcher overlay.
    public static func isLauncher(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }

    /// The launcher overlay currently holding keyboard focus, given the bundle
    /// ID resolved from the system-wide focused UI element. Returns the id when
    /// it names a known launcher, or `nil` to mean "focus is on a normal app —
    /// fall back to `NSWorkspace.frontmostApplication`".
    public static func launcher(forFocusedBundleID focusedBundleID: String?) -> String? {
        isLauncher(focusedBundleID) ? focusedBundleID : nil
    }
}
