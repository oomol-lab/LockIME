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
        let status = state.loc(state.isLocked ? "Locked" : "Unlocked")
        let toggleShortcut = state.toggleLockShortcut?.menuDisplayShortcut

        // Status header — the lock state with a padlock glyph (closed when
        // locked, open when unlocked) and, on the right, the configured global
        // toggle-lock shortcut. Non-interactive: a *disabled* Button still draws
        // the accelerator natively but can't fire it, so it never clashes with
        // the real global handler — it's a pure hint. The source name is omitted:
        // the list below already marks the locked source with a checkmark.
        Button {} label: {
            Label {
                Text(verbatim: status)
            } icon: {
                Image(systemName: state.isLocked ? "lock.fill" : "lock.open.fill")
            }
        }
        .keyboardShortcut(toggleShortcut)
        .disabled(true)

        Divider()

        // The system input sources, flattened directly into the menu. Each is a
        // Button carrying a leading checkmark in the menu-item *image* column —
        // visible on the locked source (locking on AND this is the global
        // target), kept as a transparent placeholder otherwise. That reserves
        // the gutter at a constant width, so the menu doesn't grow/shrink as the
        // lock toggles. (A `Toggle`'s native checkmark lives in NSMenu's *state*
        // column, which collapses to zero width when nothing is checked — that
        // is what made the menu jump.) Clicking an unchecked source locks to it
        // (sets target + enables, one commit); clicking the checked source
        // disables locking. No separate master toggle, no submenu. Source names
        // are verbatim system strings, not catalog keys. The global toggle-lock
        // shortcut (Settings ▸ Shortcuts) is unchanged: it flips locking on/off
        // against the remembered target.
        ForEach(state.availableSources) { source in
            let isLockedTo = state.isLocked && state.config.defaultSourceID == source.id
            Button {
                if isLockedTo {
                    state.setMasterEnabled(false)
                } else {
                    state.lockToSource(source.id)
                }
            } label: {
                Label {
                    Text(verbatim: source.localizedName)
                } icon: {
                    // NSMenu draws a Label's system-image icon as a raw template
                    // symbol and drops SwiftUI's `.opacity`, so a hidden-via-
                    // opacity checkmark would show on every row. Swap the image
                    // itself instead: the real checkmark when locked, a same-size
                    // transparent slot otherwise — keeping the gutter reserved at
                    // a constant width either way.
                    Image(nsImage: isLockedTo ? CheckmarkSlot.on : CheckmarkSlot.off)
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
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button {
            state.checkForUpdates()
        } label: {
            if pendingUpdate != nil {
                Label("Install Update…", systemImage: "arrow.down.circle.fill")
            } else {
                Label("Check for Updates…", systemImage: "arrow.down.circle")
            }
        }
        .keyboardShortcut("u", modifiers: .command)
        .disabled(!state.updateController.canCheckForUpdates)

        Button {
            state.showAbout()
        } label: {
            Label("About", systemImage: "info.circle")
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit", systemImage: "power")
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

/// Leading-gutter images for the input-source rows. Using fixed NSImages (not a
/// `Toggle`'s native state checkmark, nor an opacity-hidden symbol) keeps the
/// menu's image column reserved at a constant width whether or not anything is
/// locked, so the menu never grows or shrinks as the lock toggles.
private enum CheckmarkSlot {
    /// Shown on the locked source. Template so NSMenu tints it like native chrome.
    static let on: NSImage = {
        let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 12, height: 12))
        image.isTemplate = true
        return image
    }()

    /// A transparent placeholder of the same size for unlocked rows.
    static let off = NSImage(size: CheckmarkSlot.on.size)
}
