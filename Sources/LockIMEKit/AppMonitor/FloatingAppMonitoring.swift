import Foundation

/// Abstraction over launcher-overlay tracking, so the engine can be tested with
/// a mock instead of the real Accessibility-backed monitor.
@MainActor
public protocol FloatingAppMonitoring: AnyObject {
    /// Begin observing launcher overlays. `onChange` is invoked with the bundle
    /// identifier of the launcher overlay that just took keyboard focus, or
    /// `nil` when focus returned to a normal app (resolve against the
    /// `NSWorkspace` frontmost app again).
    func start(onChange: @escaping @MainActor (String?) -> Void)
    /// Re-attempt observer attachment. macOS doesn't notify us when Accessibility
    /// is granted, so the engine calls this once the grant is detected.
    func refresh()
    func stop()
}
