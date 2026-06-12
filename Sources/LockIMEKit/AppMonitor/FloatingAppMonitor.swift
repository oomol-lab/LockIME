import AppKit
import ApplicationServices
import Foundation

/// Tracks launcher overlays (Spotlight, Raycast, …) that take keyboard focus
/// without changing `NSWorkspace.frontmostApplication`, via the Accessibility
/// API. The technique mirrors InputSourcePro: register `AXObserver`s on the
/// known launcher *processes* (which run persistently — Spotlight always does)
/// for window/focus lifecycle notifications, then read the system-wide focused
/// UI element to learn which app actually owns the keyboard.
///
/// Empirically (macOS 26): opening a launcher fires `windowCreated` /
/// `focusedUIElementChanged`, at which point the system-wide focused element
/// resolves to the launcher; dismissing it fires `uiElementDestroyed`, after
/// which focus resolves back to the underlying app. So the whole thing is
/// event-driven — no polling.
///
/// **Accessibility-gated.** Without the grant `AXObserverAddNotification` fails
/// and we observe nothing, leaving the permission-free core unchanged; the
/// engine calls `refresh()` once the grant is detected to attach for real.
@MainActor
public final class FloatingAppMonitor: FloatingAppMonitoring {
    private var onChange: (@MainActor (String?) -> Void)?
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [any NSObjectProtocol] = []
    /// The launcher bundle ID last reported, for change de-duplication.
    private var current: String?

    private let systemWide: AXUIElement

    public init() {
        systemWide = AXUIElementCreateSystemWide()
        // Reading the focused element round-trips to the focused app; cap the
        // wait so an unresponsive app can't stall the main thread.
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
    }

    public func start(onChange: @escaping @MainActor (String?) -> Void) {
        guard self.onChange == nil else { return }
        self.onChange = onChange

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                // Pull the Sendable bits out of the (non-Sendable) Notification
                // before hopping onto the main actor.
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let bundleID = app?.bundleIdentifier,
                      LauncherOverlayCatalog.isLauncher(bundleID),
                      let pid = app?.processIdentifier
                else { return }
                let launched = note.name == NSWorkspace.didLaunchApplicationNotification
                MainActor.assumeIsolated {
                    self?.handleRunningAppsChange(pid: pid, launched: launched)
                }
            }
            workspaceTokens.append(token)
        }

        attachAll()
    }

    public func refresh() {
        guard onChange != nil else { return }
        if AXIsProcessTrusted() {
            attachAll()   // (re)attach to running launchers now that we can
        } else {
            // Trust was revoked: existing observers are dead and won't fire even
            // if access is re-granted, so detach them (a later refresh recreates
            // fresh ones). evaluate() then clears any stale launcher attribution.
            for pid in Array(observers.keys) { detach(pid) }
        }
        evaluate()
    }

    public func stop() {
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceTokens.removeAll()
        for pid in Array(observers.keys) { detach(pid) }
        onChange = nil
        current = nil
    }

    deinit {
        // Observers and workspace tokens are torn down in `stop()` (called from
        // the engine's `stop()`); a nonisolated deinit can't touch them.
    }

    // MARK: - Attachment

    private func attachAll() {
        for app in NSWorkspace.shared.runningApplications
        where LauncherOverlayCatalog.isLauncher(app.bundleIdentifier) {
            attach(app.processIdentifier)
        }
    }

    private func handleRunningAppsChange(pid: pid_t, launched: Bool) {
        if launched {
            attach(pid)
        } else {
            detach(pid)
            evaluate()   // the terminated launcher can't hold focus any more
        }
    }

    /// AX notifications worth a re-read: a launcher overlay appearing, taking
    /// focus, or being torn down.
    private static let watchedNotifications: [CFString] = [
        kAXWindowCreatedNotification as CFString,
        kAXFocusedUIElementChangedNotification as CFString,
        kAXMainWindowChangedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString,
    ]

    private func attach(_ pid: pid_t) {
        guard observers[pid] == nil, AXIsProcessTrusted() else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, floatingAXCallback, &observer) == .success,
              let observer
        else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var attached = false
        for name in Self.watchedNotifications {
            if AXObserverAddNotification(observer, appElement, name, context) == .success {
                attached = true
            }
        }
        // Not trusted yet (every add failed) — leave unattached so `refresh()`
        // retries once Accessibility is granted.
        guard attached else { return }

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        observers[pid] = observer
    }

    private func detach(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    // MARK: - Evaluation

    /// Called from the AX callback on every watched notification. Reads the
    /// real keyboard-focused app and reports the launcher overlay (or `nil`).
    fileprivate func evaluate() {
        let launcher = LauncherOverlayCatalog.launcher(forFocusedBundleID: focusedBundleID())
        guard launcher != current else { return }
        current = launcher
        onChange?(launcher)
    }

    /// The bundle identifier of the app owning the system-wide focused UI
    /// element — which, unlike `NSWorkspace.frontmostApplication`, follows a
    /// launcher overlay when it takes keyboard focus.
    private func focusedBundleID() -> String? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return nil }

        var pid: pid_t = 0
        // Safe: the CFGetTypeID check above guarantees this is an AXUIElement.
        guard AXUIElementGetPid(element as! AXUIElement, &pid) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}

/// Free C callback (an `AXObserverCallback` cannot capture context). The monitor
/// is passed through `refcon`; it owns the observers and outlives them, so an
/// unretained reference is safe. The run-loop source lives on the main thread,
/// so the callback is already main-actor isolated in practice.
private func floatingAXCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    // Reconstruct the instance *outside* the main-actor hop (matching
    // `InputSourceChangeObserver`): sending the raw pointer across the
    // isolation boundary trips strict-concurrency region analysis.
    let monitor = Unmanaged<FloatingAppMonitor>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.evaluate()
    }
}
