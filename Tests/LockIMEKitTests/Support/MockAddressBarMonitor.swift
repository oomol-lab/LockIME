import Foundation

@testable import LockIMEKit

/// A test double for the address-bar focus monitor. The engine drives
/// `observe(bundleID:)`; tests drive focus transitions with `setFocused`.
@MainActor
final class MockAddressBarMonitor: AddressBarFocusMonitoring {
    private var handler: (@MainActor (Bool) -> Void)?
    /// The bundle id the engine last asked to observe (`nil` = stopped).
    private(set) var observedBundleID: String?
    private(set) var refreshCount = 0
    /// When true, `refresh()` reports `false` — modelling the real monitor
    /// clearing its focus attribution after Accessibility is revoked.
    var refreshClearsFocus = false

    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        handler = onChange
    }

    func observe(bundleID: String?) {
        observedBundleID = bundleID
    }

    func refresh() {
        refreshCount += 1
        if refreshClearsFocus { handler?(false) }
    }

    func stop() { handler = nil }

    /// Simulate the observed browser's address bar gaining (`true`) or losing
    /// (`false`) keyboard focus.
    func setFocused(_ focused: Bool) {
        handler?(focused)
    }
}
