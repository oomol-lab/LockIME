import AppKit

/// Owns the shared `AppState` and starts the lock engine at launch. Using a
/// delegate guarantees startup runs even though menu-bar scenes are lazy.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    /// Dispatches incoming `lockime://` URLs. Created lazily off `appState` so it
    /// shares the one live state the engine and UI are bound to.
    private lazy var urlHandler = URLCommandHandler(state: appState)

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Headless self-test of the Accessibility grant UX. Skips engine startup
        // (no input-source side effects) and exits when done.
        if ProcessInfo.processInfo.environment["LOCKIME_AXFLOW_TEST"] == "1" {
            Task { @MainActor in
                await appState.runAccessibilityGrantSelfTest()
                NSApp.terminate(nil)
            }
            return
        }
        #endif
        appState.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stop()
    }

    /// Handle `lockime://` (and the Debug `lockime-dev://`) URL-scheme commands.
    /// LaunchServices delivers only the schemes the app registered in its
    /// `CFBundleURLTypes`, so each URL is one of ours; the parser keys off the
    /// command token, not the scheme. Multiple URLs may arrive in one event.
    func application(_ application: NSApplication, open urls: [URL]) {
        // On a URL-triggered COLD launch, AppKit can call this before
        // `applicationDidFinishLaunching`, i.e. before `appState.start()` has
        // loaded the persisted config. Running a command against the unloaded
        // (empty .default) state would let `commit()` overwrite the user's saved
        // rules. `start()` is idempotent (guards on `engine == nil`), so calling
        // it here guarantees the config is loaded first; the later
        // `applicationDidFinishLaunching` call becomes a no-op.
        appState.start()
        for url in urls {
            urlHandler.handle(url)
        }
    }
}
