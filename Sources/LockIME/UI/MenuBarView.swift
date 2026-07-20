import AppKit
import KeyboardShortcuts
import LockIMEKit
import SwiftUI

/// The menu-bar menu (`.menuBarExtraStyle(.menu)`): a native macOS status menu
/// with SF Symbol icons and keyboard-shortcut hints, in the style of well-made
/// menu-bar utilities. Zero custom color — NSMenu supplies all light/dark chrome.
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let state = appState
        let pendingUpdate = state.updateController.pendingUpdateVersion
        // The menu is a native NSMenu (.menuBarExtraStyle(.menu)) — an AppKit
        // surface that bypasses the injected `\.locale`, so resolve the status
        // word through `loc` (app's chosen language) rather than a live
        // LocalizedStringKey.
        let status = state.loc(state.isAppEnabled ? "Enabled" : "Disabled")
        let toggleShortcut = state.toggleLockShortcut?.menuDisplayShortcut

        // Status header — the on/off state with a padlock glyph (closed when
        // enabled, open when disabled) and, on the right, the configured global
        // toggle-lock shortcut. Non-interactive: a *disabled* Button still draws
        // the accelerator natively but can't fire it, so it never clashes with
        // the real global handler — it's a pure hint. The source name is omitted:
        // the list below already marks the locked source with a checkmark.
        Button {} label: {
            Label {
                Text(verbatim: status)
            } icon: {
                Image(nsImage: state.isAppEnabled ? MenuIcon.lockClosed : MenuIcon.lockOpen)
            }
        }
        .keyboardShortcut(toggleShortcut)
        .disabled(true)

        Divider()

        // The system input sources, flattened directly into the menu. Each is a
        // Button carrying a leading checkmark in the menu-item *image* column —
        // visible on the locked source (LockIME on AND this is the global
        // target), kept as an empty slot of the same size otherwise. That
        // reserves the gutter at a constant width, so the menu doesn't
        // grow/shrink as the lock toggles. (A `Toggle`'s native checkmark lives
        // in NSMenu's *state* column, which collapses to zero width when nothing
        // is checked — that is what made the menu jump, and it still does on
        // macOS 27: 144pt unlocked vs 158pt locked.) Clicking an unchecked
        // source targets it (sets the global source + turns LockIME on, one
        // commit, preserving the configured lock/switch default behavior);
        // clicking the checked source clears the global target (app and switch
        // rules stay live). No separate on/off toggle, no submenu. Source names are
        // verbatim system strings, not catalog keys. The global toggle-lock
        // shortcut (Settings ▸ Shortcuts) flips LockIME on/off.
        ForEach(state.availableSources) { source in
            let isLockedTo = state.isAppEnabled && state.config.defaultSourceID == source.id
            Button {
                if isLockedTo {
                    // Clear just the global lock target — the app and any one-shot
                    // switch rules stay alive. (Use Settings to turn LockIME off
                    // entirely.)
                    state.setDefaultSource(nil)
                } else {
                    state.lockToSource(source.id)
                }
            } label: {
                Label {
                    Text(verbatim: source.localizedName)
                } icon: {
                    // NSMenu drops SwiftUI's `.opacity`, so a hidden-via-opacity
                    // checkmark would show on every row. Swap the image itself
                    // instead: the real checkmark when locked, a same-size empty
                    // slot otherwise — keeping the gutter reserved at a constant
                    // width either way.
                    Image(nsImage: isLockedTo ? MenuIcon.checkmark : MenuIcon.blank)
                }
            }
        }

        if !state.availableSources.isEmpty {
            Divider()
        }

        Button {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Label { Text("Settings…") } icon: { Image(nsImage: MenuIcon.gear) }
        }
        .keyboardShortcut(",", modifiers: .command)

        Button {
            state.checkForUpdates()
        } label: {
            if pendingUpdate != nil {
                Label { Text("Install Update…") } icon: { Image(nsImage: MenuIcon.updateReady) }
            } else {
                Label { Text("Check for Updates…") } icon: { Image(nsImage: MenuIcon.update) }
            }
        }
        .keyboardShortcut("u", modifiers: .command)
        .disabled(!state.updateController.canCheckForUpdates)

        Button {
            state.showAbout()
        } label: {
            Label { Text("About") } icon: { Image(nsImage: MenuIcon.about) }
        }

        Divider()

        Button {
            // Route through AppState so the termination is flagged as wanted —
            // the AppDelegate terminate guard otherwise vetoes a bare terminate:
            // (it can't tell a real quit from AppKit hiding our status item).
            state.quit()
        } label: {
            Label { Text("Quit") } icon: { Image(nsImage: MenuIcon.quit) }
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

private extension KeyboardShortcuts.Shortcut {
    /// A SwiftUI `KeyboardShortcut` for *echoing* this shortcut as the header's
    /// menu accelerator (right-aligned glyphs, drawn natively by NSMenu).
    ///
    /// Covers single printable keys (letters/digits/symbols) with any
    /// combination of modifiers — the case a user actually configures, up to the
    /// four-modifier "⌃⌥⇧⌘X" maximum. Exotic keys (Space, arrows, F-keys,
    /// keypad) keep working as a global shortcut but aren't echoed here, since
    /// they can't round-trip through a single `KeyEquivalent` for display. The
    /// key glyph is parsed off `description` (e.g. "⌃⌥⇧⌘L" → "L") after dropping
    /// the leading modifier glyphs; the modifiers come from the typed property.
    var menuDisplayShortcut: KeyboardShortcut? {
        let keyPart = description.drop { "⌃⌥⇧⌘⇪🌐".contains($0) }
        guard keyPart.count == 1, let key = keyPart.first, key.isASCII,
              key.isLetter || key.isNumber || key.isPunctuation || key.isSymbol
        else { return nil }
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(key), modifiers: eventModifiers)
    }
}

/// Every glyph this menu draws, baked into a bitmap-backed template `NSImage` of
/// one fixed box.
///
/// Two things force that shape, and neither is optional:
///
/// 1. **`NSMenu` hides symbol-backed images.** macOS 27 walks back macOS 26's
///    icon-heavy menus: `NSMenu` now hides *all* menu-item symbol images by
///    default, leaving non-symbol images visible, for every app linked against
///    the macOS 26 SDK or newer. (macOS 27 release notes, AppKit.) So an item
///    whose `image` came out of `NSImage(systemSymbolName:)` — which is what
///    `Label(_:systemImage:)` bridges to — draws *no glyph and reserves no
///    width*. That emptied this menu's whole icon column, checkmark included,
///    while the one leftover non-symbol image (the blank placeholder) kept
///    claiming width: hence input-source rows indented past every other row.
///    The discriminator is the image's representation, not `isTemplate`, so
///    drawing the symbol into an `NSCustomImageRep` opts back in — and the rep
///    re-renders at the destination scale, so it stays crisp on Retina.
///
///    macOS 27 adds `NSMenuItem.preferredImageVisibility` as the sanctioned way
///    to ask for `.visible`. It isn't reachable yet: it's absent from the SDK
///    Xcode 26.6 builds against, and `MenuBarExtra` hands out no `NSMenuItem`
///    to set it on. Revisit once both land.
/// 2. **The column has to stay put.** A single box size for every row keeps
///    NSMenu's image column at a constant width, so titles line up and the menu
///    neither grows nor shrinks as the lock moves between sources. NSMenu's
///    native *state* column can't stand in: it still collapses to zero width
///    when no item is checked.
private enum MenuIcon {
    /// Sized to sit comfortably next to the 13pt menu font.
    private static let box = NSSize(width: 16, height: 16)

    static let lockClosed = symbol("lock.fill")
    static let lockOpen = symbol("lock.open.fill")
    static let checkmark = symbol("checkmark")
    static let gear = symbol("gearshape")
    static let update = symbol("arrow.down.circle")
    static let updateReady = symbol("arrow.down.circle.fill")
    static let about = symbol("info.circle")
    static let quit = symbol("power")

    /// An empty slot that holds the gutter open on rows without a glyph.
    static let blank: NSImage = {
        let image = NSImage(size: box, flipped: false) { _ in true }
        image.isTemplate = true
        return image
    }()

    /// `name` centred in the box, flagged template so NSMenu tints it like
    /// native chrome (including white-on-highlight).
    private static func symbol(_ name: String) -> NSImage {
        guard let source = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return blank
        }
        source.isTemplate = true
        let image = NSImage(size: box, flipped: false) { rect in
            let size = source.size
            guard size.width > 0, size.height > 0 else { return true }
            let scale = min(rect.width / size.width, rect.height / size.height)
            let drawn = NSSize(width: size.width * scale, height: size.height * scale)
            source.draw(in: NSRect(
                x: rect.midX - drawn.width / 2,
                y: rect.midY - drawn.height / 2,
                width: drawn.width,
                height: drawn.height
            ))
            return true
        }
        image.isTemplate = true
        return image
    }
}
