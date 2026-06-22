import Foundation

/// Abstraction over browser address-bar focus tracking, so the engine can be
/// tested with a mock instead of the real Accessibility-backed monitor.
@MainActor
public protocol AddressBarFocusMonitoring: AnyObject {
    /// Begin observing. `onChange(true)` fires when the observed browser's
    /// address bar (omnibox / unified URL field) gains keyboard focus;
    /// `onChange(false)` when it loses focus or observation stops.
    func start(onChange: @escaping @MainActor (Bool) -> Void)
    /// Observe the given browser process for address-bar focus, or stop
    /// observing (pass `nil`). The engine calls this as the frontmost app
    /// changes and the feature toggles — it observes only the frontmost browser,
    /// and only while the feature is on.
    func observe(bundleID: String?)
    /// Re-attempt observer attachment after an Accessibility grant change. macOS
    /// doesn't notify us when access is granted, so the engine calls this once
    /// the grant is detected.
    func refresh()
    func stop()
}
