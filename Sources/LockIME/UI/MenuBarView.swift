import AppKit
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
        let lockBinding = Binding(
            get: { state.isLocked },
            set: { state.setMasterEnabled($0) }
        )
        let pendingUpdate = state.updateController.pendingUpdateVersion
        // The menu is a native NSMenu (.menuBarExtraStyle(.menu)) — an AppKit
        // surface that bypasses the injected `\.locale`, so resolve the status
        // word through `loc` (app's chosen language) rather than a live
        // LocalizedStringKey. The source name stays verbatim.
        let status = state.loc(state.isLocked ? "Locked" : "Unlocked")

        // Status header — current lock state + source, non-interactive.
        Text(verbatim: "\(status) · \(state.currentSourceName)")

        Divider()

        Toggle("Lock input source", isOn: lockBinding)
            .keyboardShortcut("l", modifiers: .command)

        Divider()

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
