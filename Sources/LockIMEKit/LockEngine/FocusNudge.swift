import AppKit
import Foundation

/// Best-effort nudge to make a background `TISSelectInputSource` for a CJKV
/// source take effect. Invoked by `TISInputSourceProvider.select` only after a
/// read-back shows the active source did not flip — never on a switch that
/// already took.
///
/// Note: this used to re-activate the previously-frontmost app after the nudge.
/// That `activate()` made the window server re-take the cursor environment on
/// *every* CJKV switch, which leaves the mouse pointer stuck as an arrow in
/// Chromium/Electron apps until the next mouse move (issue #1), so it was
/// removed. The borderless window below cannot become key, so this is a weak
/// fallback; if real per-app input-method context misses surface, replace it
/// with a key-capable text-input window (macism-style).
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
