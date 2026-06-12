import ServiceManagement
import Testing

@testable import LockIMEKit

/// Pure decision logic split out of `LoginItemController.setEnabled` so it can
/// be tested without touching `SMAppService` (which registers a real login
/// item). The `SMAppService.Status` values referenced here are plain enum
/// cases — constructing them performs no system call.
@MainActor
@Suite("LoginItemController.action")
struct LoginItemControllerActionTests {
    @Test("enabling registers unless the service is already enabled")
    func enabling() {
        #expect(LoginItemController.action(desiredEnabled: true, current: .notRegistered) == .register)
        #expect(LoginItemController.action(desiredEnabled: true, current: .requiresApproval) == .register)
        #expect(LoginItemController.action(desiredEnabled: true, current: .notFound) == .register)
        #expect(LoginItemController.action(desiredEnabled: true, current: .enabled) == .noChange)
    }

    @Test("disabling unregisters only when the service is currently enabled")
    func disabling() {
        #expect(LoginItemController.action(desiredEnabled: false, current: .enabled) == .unregister)
        #expect(LoginItemController.action(desiredEnabled: false, current: .notRegistered) == .noChange)
        #expect(LoginItemController.action(desiredEnabled: false, current: .requiresApproval) == .noChange)
        #expect(LoginItemController.action(desiredEnabled: false, current: .notFound) == .noChange)
    }
}
