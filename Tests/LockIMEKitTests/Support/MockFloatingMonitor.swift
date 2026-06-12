import Foundation

@testable import LockIMEKit

@MainActor
final class MockFloatingMonitor: FloatingAppMonitoring {
    private var handler: (@MainActor (String?) -> Void)?
    private(set) var refreshCount = 0

    func start(onChange: @escaping @MainActor (String?) -> Void) {
        handler = onChange
    }

    func refresh() { refreshCount += 1 }

    func stop() { handler = nil }

    /// Simulate a launcher overlay taking (`bundleID`) or releasing (`nil`)
    /// keyboard focus.
    func setLauncher(_ bundleID: String?) {
        handler?(bundleID)
    }
}
