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
                appState.quit()
            }
            return
        }
        #endif
        appState.start()

        // A *user* cold launch while the menu bar icon is hidden would show
        // nothing at all — no icon, no Dock tile, no window — leaving the user
        // unable to reach the app. Open Settings so they can see it's alive and
        // re-enable the icon. The hidden state isn't observable yet at launch (the
        // system applies it a beat later — the same action that fires the
        // terminate we veto), so re-check after a short delay. Two guards keep
        // this off *system* launches:
        //  • `launchAtLoginActive` — a launch can only be the silent login
        //    auto-start if the app is registered for it, so registered users never
        //    get a window popped at login; they recover via the reopen path above
        //    (their app is normally already running). This is the load-bearing
        //    login guard. We deliberately don't read the per-launch login Apple
        //    Event (`keyAELaunchedAsLogInItem`), whose firing under
        //    `SMAppService.mainApp` is unverified.
        //  • a non-default launch — opening a file/URL, a Service, state
        //    restoration — reports `NSApplicationLaunchIsDefaultLaunchKey` false;
        //    that's the key's documented purpose, and it's all we use it for (it
        //    is NOT a reliable login-vs-user signal).
        let isDefaultLaunch = notification.userInfo?["NSApplicationLaunchIsDefaultLaunchKey"] as? Bool ?? true
        guard isDefaultLaunch, !appState.launchAtLoginActive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            // Reveal for either hidden state: a system hide (the persisted default,
            // only observable a beat after launch) or the in-app "Hide menu bar
            // icon" toggle (known immediately, but re-checked here all the same).
            guard let self, self.statusItemPersistedHidden || self.appState.menuBarIconHidden else { return }
            self.openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stop()
    }

    /// Veto the one termination we never asked for. A SwiftUI `MenuBarExtra`-only
    /// app self-terminates the instant its status item is hidden — Apple documents
    /// this: "An app that only shows in the menu bar will be automatically
    /// terminated if the user removes the extra from the menu bar." The user can
    /// hide it via the menu-bar/Control-Center settings (macOS 26+) or by
    /// ⌘-dragging the icon off the bar; macOS then posts
    /// `NSStatusItemChangeVisibilityAction` and AppKit calls `terminate:`. Because
    /// that hidden state is *persisted* (a `NSStatusItem Visible…` default), an
    /// unguarded app re-terminates on every later launch before any UI appears —
    /// it looks like it crashed and can never be reopened. So when the icon is
    /// hidden we stay alive: the lock engine keeps running and relaunching reopens
    /// Settings (see `applicationShouldHandleReopen`). Every *wanted* exit still
    /// goes through —
    /// an explicit Quit / `lockime://quit` (`terminationRequested`), a Sparkle
    /// install-and-relaunch, and a logout/restart/shutdown (the
    /// `kAEQuitApplication` Apple Event).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if appState.terminationRequested { return .terminateNow }
        if appState.updateController.isInstallingUpdate { return .terminateNow }
        if isSystemTerminationEvent { return .terminateNow }
        if statusItemPersistedHidden || appState.menuBarIconHidden { return .terminateCancel }
        return .terminateNow
    }

    /// Relaunching a running app (Finder / Spotlight / Dock / `open`) is the
    /// user's way back in when the menu bar icon is hidden — there is no other
    /// affordance. Always (re)present Settings; we ignore `hasVisibleWindows`,
    /// which counts a *minimized* window as visible and would otherwise leave a
    /// minimized Settings window buried with nothing surfaced.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openSettings()
        return true
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

    // MARK: - Menu bar icon recovery

    /// True when the icon was hidden *by the system* — the user ⌘-dragged it off
    /// the bar or hid it in Control Center. AppKit saves each MenuBarExtra item's
    /// visibility in our own defaults domain under an "NSStatusItem Visible…" key
    /// (the suffix carries an index and, on recent macOS, a "CC" infix for
    /// Control-Center-managed items), so match the family by prefix rather than one
    /// literal key. If Apple ever renames it this reads `false` and we fall back to
    /// default termination — no crash, no veto. The *in-app* "Hide menu bar icon"
    /// toggle is tracked separately by `appState.menuBarIconHidden`; the guards
    /// above honor either signal.
    private var statusItemPersistedHidden: Bool {
        UserDefaults.standard.dictionaryRepresentation().contains { key, value in
            key.hasPrefix("NSStatusItem Visible")
                && (value as? NSNumber)?.boolValue == false
        }
    }

    /// Whether the in-flight termination is a logout/restart/shutdown — those
    /// carry the `kAEQuitApplication` Apple Event; the status-item-hide
    /// `terminate:` does not. Lets the user log out even while our icon is hidden.
    private var isSystemTerminationEvent: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        // 'aevt' / 'quit' four-char codes, spelled out to avoid a Carbon import.
        return event.eventClass == 0x6165_7674 && event.eventID == 0x7175_6974
    }

    /// Open the SwiftUI `Settings` scene. The AppKit `showSettingsWindow:`
    /// selector reports success but never actually opens the scene for this
    /// accessory app, so go through the captured `\.openSettings` action instead
    /// (see `SettingsActionBridge` in `LockIMEApp`).
    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        appState.openSettingsAction?()
    }
}
