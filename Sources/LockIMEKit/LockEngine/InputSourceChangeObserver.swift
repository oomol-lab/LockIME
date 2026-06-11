import Carbon
import Foundation

/// A Text Input Source distributed notification this observer can watch. Keeps
/// the Carbon constants encapsulated here (the only file that imports Carbon)
/// so callers like `LockEngine` stay Foundation-only.
public enum InputSourceEvent: Sendable {
    /// The selected keyboard input source changed.
    case selectionChanged
    /// The set of enabled input sources changed — e.g. the user added or
    /// removed one in System Settings ▸ Keyboard ▸ Input Sources.
    case enabledSourcesChanged

    var notificationName: CFString {
        switch self {
        case .selectionChanged: kTISNotifySelectedKeyboardInputSourceChanged
        case .enabledSourcesChanged: kTISNotifyEnabledKeyboardInputSourcesChanged
        }
    }
}

/// Observes a system-wide Text Input Source distributed notification and invokes
/// a handler on the main actor. Defaults to the selected-source-changed event;
/// pass `.enabledSourcesChanged` to watch the enabled list instead.
///
/// CFNotificationCenter's distributed center delivers on the run loop of the
/// registering thread; we register from the main actor, so delivery is on main.
@MainActor
public final class InputSourceChangeObserver {
    private let notification: CFString
    private var handler: (@MainActor () -> Void)?
    private var isRegistered = false

    public init(_ event: InputSourceEvent = .selectionChanged) {
        self.notification = event.notificationName
    }

    public func start(_ handler: @escaping @MainActor () -> Void) {
        guard !isRegistered else { return }
        self.handler = handler

        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDistributedCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let instance = Unmanaged<InputSourceChangeObserver>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                MainActor.assumeIsolated {
                    instance.handler?()
                }
            },
            notification,
            nil,
            .deliverImmediately
        )
        isRegistered = true
    }

    public func stop() {
        guard isRegistered else { return }
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
        isRegistered = false
        handler = nil
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }
}
