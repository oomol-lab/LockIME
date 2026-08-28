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
    /// Spotlight's own bundle identifier: the identity a Spotlight rule keys on
    /// (and the picker offers) on every macOS version, whichever process happens
    /// to draw the panel — see `siriAI`.
    public static let spotlight = "com.apple.Spotlight"

    /// The Siri AI process (`/System/Applications/Siri AI.app`, shown as "Siri"),
    /// which on macOS 27 hosts the Cmd-Space Spotlight panel. The `Spotlight`
    /// process no longer runs there at all, so while the panel is up the
    /// system-wide focused element resolves to *this* process (issue #63).
    /// The same process also owns Siri's regular chat window, which — unlike the
    /// panel — activates it as the frontmost app; `ruleIdentity` tells the two
    /// apart.
    public static let siriAI = "com.apple.campo"

    /// Bundle identifiers of the launcher-overlay **processes** to observe.
    /// Spotlight is the headline case and is the only one that is *exclusively*
    /// an overlay; the others are regular apps whose command bar happens to
    /// float over the frontmost app — resolving their own bundle ID is correct
    /// in both modes, so listing them is safe.
    public static let bundleIDs: Set<String> = [
        spotlight,                        // Spotlight (Cmd-Space), macOS 26 and earlier
        siriAI,                           // Siri AI, hosting the Spotlight panel on macOS 27
        "com.raycast.macos",              // Raycast
        "com.runningwithcrayons.Alfred",  // Alfred
        "at.obdev.LaunchBar",             // LaunchBar
    ]

    /// Processes that draw *another* launcher's overlay, keyed by host process
    /// and valued by the identity whose rule the overlay should resolve. Kept
    /// separate from `bundleIDs` so an existing Spotlight rule (and the picker's
    /// Spotlight entry, backups, the activation log) keeps meaning "the Cmd-Space
    /// panel" after the OS moved that panel into a different process.
    private static let overlayHosts: [String: String] = [
        siriAI: spotlight,
    ]

    /// Whether `bundleID` is a known launcher overlay (or a process hosting one).
    public static func isLauncher(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }

    /// The launcher overlay currently holding keyboard focus, given the bundle
    /// ID resolved from the system-wide focused UI element. Returns the id when
    /// it names a known launcher, or `nil` to mean "focus is on a normal app —
    /// fall back to `NSWorkspace.frontmostApplication`".
    ///
    /// This is the *process* identity; map it through `ruleIdentity` before
    /// resolving rules against it.
    public static func launcher(forFocusedBundleID focusedBundleID: String?) -> String? {
        isLauncher(focusedBundleID) ? focusedBundleID : nil
    }

    /// The identity app rules resolve against while `launcher` (as reported by
    /// `launcher(forFocusedBundleID:)`) holds keyboard focus.
    ///
    /// A process hosting another launcher's overlay maps to the hosted identity
    /// — Siri AI drawing the Spotlight panel resolves the *Spotlight* rule —
    /// **unless the host is itself the frontmost app**: an overlay never
    /// activates its process (that is what makes it an overlay), so a frontmost
    /// host is being used as a regular app (Siri's chat window) and keeps its
    /// own identity, so a rule for it can coexist with the Spotlight rule.
    /// Every other launcher resolves as itself, in either mode.
    public static func ruleIdentity(forLauncher launcher: String, frontmostBundleID: String?) -> String {
        guard let hosted = overlayHosts[launcher], launcher != frontmostBundleID else { return launcher }
        return hosted
    }
}
