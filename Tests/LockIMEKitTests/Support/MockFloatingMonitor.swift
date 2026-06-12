import Foundation

@testable import LockIMEKit

@MainActor
final class MockFloatingMonitor: FloatingAppMonitoring {
    private var handler: (@MainActor (String?) -> Void)?
    private(set) var refreshCount = 0
    /// When true, `refresh()` emits `nil` — modelling the real monitor clearing
    /// its launcher attribution after Accessibility is revoked (the focused-
    /// element read fails, so it reports "no launcher").
    var refreshClearsLauncher = false

    func start(onChange: @escaping @MainActor (String?) -> Void) {
        handler = onChange
    }

    func refresh() {
        refreshCount += 1
        if refreshClearsLauncher { handler?(nil) }
    }

    func stop() { handler = nil }

    /// Simulate a launcher overlay taking (`bundleID`) or releasing (`nil`)
    /// keyboard focus.
    func setLauncher(_ bundleID: String?) {
        handler?(bundleID)
    }
}
