import Foundation
import ServiceManagement

/// A normalized view of the app's login-item registration status.
public enum LoginItemState: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case notFound
    case unknown

    public init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .notRegistered: self = .disabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .unknown
        }
    }

    public var isActive: Bool { self == .enabled }
}

/// The registration change implied by a desired enable state and the current
/// service status. Pure decision logic, kept separate from the `SMAppService`
/// calls so it can be unit-tested without registering a real login item.
enum LoginItemAction: Equatable {
    case register, unregister, noChange
}

/// Launch-at-login via `SMAppService.mainApp` (no helper bundle).
@MainActor
public final class LoginItemController {
    public init() {}

    /// Always read live — never cache (per Apple guidance).
    public var state: LoginItemState { LoginItemState(SMAppService.mainApp.status) }

    public var isEnabled: Bool { state.isActive }

    /// What `setEnabled` should do given the desired state and the live status.
    /// Registering is idempotent-by-intent: only act when the status disagrees.
    static func action(desiredEnabled: Bool, current status: SMAppService.Status) -> LoginItemAction {
        if desiredEnabled {
            return status == .enabled ? .noChange : .register
        } else {
            return status == .enabled ? .unregister : .noChange
        }
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
        let service = SMAppService.mainApp
        do {
            switch Self.action(desiredEnabled: enabled, current: service.status) {
            case .register: try service.register()
            case .unregister: try service.unregister()
            case .noChange: break
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
