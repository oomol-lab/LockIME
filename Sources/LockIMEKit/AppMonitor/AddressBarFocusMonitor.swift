import AppKit
import ApplicationServices
import Foundation

/// Tracks whether the frontmost browser's address bar (omnibox / unified URL
/// field) has keyboard focus, via the Accessibility API. The technique mirrors
/// `FloatingAppMonitor`: register an `AXObserver` on the browser *process* for
/// `kAXFocusedUIElementChangedNotification`, then read the system-wide focused
/// UI element and classify it (`AddressBarHeuristic`) on each change.
///
/// Unlike the launcher monitor (which watches a fixed catalog of persistent
/// launcher processes), this observes only the **single** browser the engine
/// asks for — the frontmost one — and only while the feature is on. The engine
/// drives `observe(bundleID:)` as the frontmost app and the feature toggle
/// change, so exactly one browser is observed at a time, or none.
///
/// Empirically (macOS 26, Chrome/Safari/Firefox): focusing the address bar (via
/// ⌘L or a click) fires `focusedUIElementChanged`, at which point the focused
/// element resolves to the address-bar field; a single ⌘L fires several such
/// notifications, so the change is de-duplicated against `current`.
///
/// **Accessibility-gated.** Without the grant `AXObserverAddNotification` fails
/// and nothing is observed, leaving the permission-free core unchanged; the
/// engine calls `refresh()` once the grant is detected to attach for real.
@MainActor
public final class AddressBarFocusMonitor: AddressBarFocusMonitoring {
    private var onChange: (@MainActor (Bool) -> Void)?
    private var observer: AXObserver?
    private var observedBundleID: String?
    private var observedPID: pid_t?
    /// Last reported state, for change de-duplication (a single focus fires
    /// several notifications).
    private var current = false

    private let systemWide: AXUIElement
    /// How far up the ancestor chain to look for the chrome-vs-web-area signal.
    private let ancestorDepth: Int

    public init(ancestorDepth: Int = 12) {
        self.ancestorDepth = ancestorDepth
        systemWide = AXUIElementCreateSystemWide()
        // Reading the focused element round-trips to the focused app; cap the
        // wait so an unresponsive app can't stall the main thread.
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
    }

    public func start(onChange: @escaping @MainActor (Bool) -> Void) {
        guard self.onChange == nil else { return }
        self.onChange = onChange
    }

    public func observe(bundleID: String?) {
        guard onChange != nil else { return }
        // No-op when already observing the same browser, so a launcher dismiss
        // returning to the same browser doesn't churn the observer.
        if bundleID == observedBundleID, observer != nil { return }

        detach()
        observedBundleID = bundleID
        guard let bundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else {
            report(false)
            return
        }
        attach(pid: app.processIdentifier)
        evaluate()
    }

    public func refresh() {
        guard onChange != nil else { return }
        if AXIsProcessTrusted() {
            // (Re)attach to the browser we should be observing now that we can.
            if let bundleID = observedBundleID, observer == nil {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                    attach(pid: app.processIdentifier)
                }
            }
            evaluate()
        } else {
            // Trust was revoked: the observer is dead and won't fire even if
            // access is re-granted, so detach it (a later refresh recreates it)
            // and clear any stale focus attribution.
            detach()
            report(false)
        }
    }

    public func stop() {
        detach()
        onChange = nil
        observedBundleID = nil
        current = false
    }

    deinit {
        // The observer is torn down in `stop()` (called from the engine's
        // `stop()`); a nonisolated deinit can't touch it.
    }

    // MARK: - Attachment

    private func attach(pid: pid_t) {
        guard observer == nil, AXIsProcessTrusted() else { return }

        let appElement = AXUIElementCreateApplication(pid)
        // Chromium and Gecko build their accessibility tree lazily; wake it so
        // the focused element (and its identifying attributes) become readable,
        // mirroring `AccessibilityBrowserURLReader`. Safari is always live.
        if BrowserBundleIDs.isChromium(observedBundleID) {
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        } else if BrowserBundleIDs.isGecko(observedBundleID) {
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }

        var newObserver: AXObserver?
        guard AXObserverCreate(pid, addressBarAXCallback, &newObserver) == .success,
              let newObserver
        else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(
            newObserver, appElement, kAXFocusedUIElementChangedNotification as CFString, context
        ) == .success else {
            // Not trusted yet — leave unattached so `refresh()` retries once
            // Accessibility is granted.
            return
        }

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(newObserver),
            .defaultMode
        )
        observer = newObserver
        observedPID = pid
    }

    private func detach() {
        guard let observer else { observedPID = nil; return }
        CFRunLoopRemoveSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        self.observer = nil
        observedPID = nil
    }

    // MARK: - Evaluation

    /// Called from the AX callback on every focus change. Reads the system-wide
    /// focused element, classifies it, and reports the de-duplicated state.
    fileprivate func evaluate() {
        report(focusedElementIsAddressBar())
    }

    private func report(_ focused: Bool) {
        guard focused != current else { return }
        current = focused
        onChange?(focused)
    }

    private func focusedElementIsAddressBar() -> Bool {
        guard let element = focusedElement() else { return false }
        // The focused element must belong to the browser we're observing — a
        // stray read while focus is elsewhere (e.g. a launcher overlay mid-
        // transition) must not be mistaken for the address bar.
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == observedPID else { return false }
        return AddressBarHeuristic.isAddressBar(
            identifier: string(element, "AXIdentifier"),
            domIdentifier: string(element, "AXDOMIdentifier"),
            domClassList: stringArray(element, "AXDOMClassList"),
            ancestorRoles: ancestorRoles(of: element)
        )
    }

    private func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // Safe: the CFGetTypeID check above guarantees this is an AXUIElement.
        return (value as! AXUIElement)
    }

    private func ancestorRoles(of element: AXUIElement) -> [String] {
        var roles: [String] = []
        var current: AXUIElement? = parent(of: element)
        var depth = 0
        while let node = current, depth < ancestorDepth {
            if let role = string(node, kAXRoleAttribute as String) { roles.append(role) }
            current = parent(of: node)
            depth += 1
        }
        return roles
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let string = value as? String
        else { return nil }
        return string
    }

    private func stringArray(_ element: AXUIElement, _ attribute: String) -> [String] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [String]
        else { return [] }
        return array
    }
}

/// Free C callback (an `AXObserverCallback` cannot capture context). The monitor
/// is passed through `refcon`; it owns the observer and outlives it, so an
/// unretained reference is safe. The run-loop source lives on the main thread,
/// so the callback is already main-actor isolated in practice.
private func addressBarAXCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    // Reconstruct the instance *outside* the main-actor hop (matching
    // `FloatingAppMonitor`): sending the raw pointer across the isolation
    // boundary trips strict-concurrency region analysis.
    let monitor = Unmanaged<AddressBarFocusMonitor>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.evaluate()
    }
}
