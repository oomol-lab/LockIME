import Foundation
import Testing

@testable import LockIMEKit

/// Guards for the menu-bar menu, which is a real `NSMenu`
/// (`.menuBarExtraStyle(.menu)`) and therefore plays by AppKit's rules rather
/// than SwiftUI's.
@Suite("Menu bar guards")
struct MenuBarGuardTests {
    private static let menuBarView = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // LockIMEKitTests/
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent()
        .appending(path: "Sources/LockIME/UI/MenuBarView.swift")

    @Test("menu rows never carry an SF Symbol image directly")
    func menuIconsAreBitmapBacked() throws {
        // macOS 27 hides *all* menu-item symbol images by default (for apps
        // linked against the macOS 26 SDK or newer). So an item whose `image`
        // came out of `NSImage(systemSymbolName:)` — which is what
        // `Label(_:systemImage:)` and `Image(systemName:)` bridge to — draws no
        // glyph *and* reserves no width. The whole icon column disappears, and
        // any row still holding a non-symbol image is left indented past the
        // rest. Route every glyph through `MenuIcon`, which bakes the symbol
        // into a bitmap-backed template image of one fixed box.
        let text = try String(contentsOf: Self.menuBarView, encoding: .utf8)
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            // Comments explain the trap by name; only flag code.
            let code = line.prefix(upTo: line.firstRange(of: "//")?.lowerBound ?? line.endIndex)
            guard code.contains("systemImage:") || code.contains("Image(systemName:") else { continue }
            Issue.record(
                "MenuBarView.swift:\(index + 1) puts an SF Symbol straight into an NSMenu row — NSMenu won't draw it; use MenuIcon"
            )
        }
    }

    @Test("every MenuIcon glyph is drawn into the shared fixed box")
    func menuIconsShareOneBox() throws {
        // A single box size across every row is what keeps NSMenu's image
        // column at a constant width — so titles line up and the menu neither
        // grows nor shrinks as the lock moves between input sources. A glyph
        // declared outside `MenuIcon` would escape that.
        let text = try String(contentsOf: Self.menuBarView, encoding: .utf8)
        let iconUses = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.prefix(upTo: $0.firstRange(of: "//")?.lowerBound ?? $0.endIndex) }
            .filter { $0.contains("Image(nsImage:") }
        #expect(!iconUses.isEmpty, "MenuBarView draws no menu glyphs at all — did the menu lose its icons?")
        for use in iconUses {
            #expect(
                use.contains("MenuIcon."),
                "menu glyph bypasses MenuIcon, so it won't share the fixed icon box: \(use.trimmingCharacters(in: .whitespaces))"
            )
        }
    }
}
