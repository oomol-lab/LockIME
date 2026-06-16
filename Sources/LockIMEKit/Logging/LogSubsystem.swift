import Foundation

/// The unified-logging subsystem for every LockIME `os.Logger`.
///
/// It is the **running** bundle's identifier, so a Debug build logs under
/// `com.oomol.LockIME.dev` and a Release build under `com.oomol.LockIME` —
/// matching how the app is actually installed, instead of a baked-in release id.
/// Falls back to the release id only when there is no bundle identifier at all
/// (e.g. a bare test host).
public enum LogSubsystem {
    public static let current = Bundle.main.bundleIdentifier ?? "com.oomol.LockIME"
}
