import LockIMEKit
import SwiftUI

@main
struct LockIMEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private var appState: AppState { delegate.appState }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .localized(with: appState)
        } label: {
            // The mascot is the state: hugging the keyboard = locked,
            // snacking on bamboo = unlocked. Monochrome template glyphs so the
            // system supplies the menu-bar tint (light/dark/active).
            Image(appState.isLocked ? "TrayLocked" : "TrayUnlocked")
                .background(SettingsActionBridge(appState: appState))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRootView()
                .localized(with: appState)
                .modelContainer(appState.modelContainer)
        }
    }
}

/// Captures SwiftUI's `\.openSettings` action into `AppState` so AppKit (the
/// `AppDelegate` menu-bar-icon recovery) can open the `Settings` scene the only
/// way that actually works for this accessory app. Lives in the MenuBarExtra
/// *label* — the one view instantiated at launch even while the icon is hidden —
/// as a zero-size, invisible background.
private struct SettingsActionBridge: View {
    let appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { appState.openSettingsAction = { openSettings() } }
    }
}

private extension View {
    /// Inject the shared state plus the chosen locale, rebuilding the subtree
    /// on language change so every string re-resolves live (no restart).
    func localized(with appState: AppState) -> some View {
        environment(appState)
            .environment(\.locale, appState.locale)
            .id(appState.localeIdentifier)
    }
}
