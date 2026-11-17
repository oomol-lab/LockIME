import AppKit
import Foundation

/// Last-resort nudge for the **fallback** path of `TISInputSourceProvider.select`:
/// the key-focus selection (`KeyFocusInputSourceSelector`) was unavailable, the
/// public `TISSelectInputSource` returned `noErr`, and a read-back shows the
/// active source still did not flip. Never invoked for a switch that took.
///
/// Note: this used to re-activate the previously-frontmost app after the nudge.
/// That `activate()` made the window server re-take the cursor environment on
/// *every* CJKV switch, which leaves the mouse pointer stuck as an arrow in
/// Chromium/Electron apps until the next mouse move (issue #1), so it was
/// removed. The borderless window below cannot become key, so this is a weak
/// fallback. The real fix for input methods that end up half-switched is the
/// key-focus selection (issue #69), not a stronger focus dance here.
@MainActor
enum FocusNudge {
    static func perform() {
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 3, height: 3),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderOut(nil)
    }
}
