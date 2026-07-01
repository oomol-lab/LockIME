import LockIMEKit
import SwiftUI

@main
struct LockIMEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// Scene-reactive mirror of `AppState.menuBarIconHidden` (same `UserDefaults`
    /// key). `@Observable` reads inside a `Binding`'s `get` closure don't register
    /// with the `App`'s scene graph, so the scene would never re-evaluate when the
    /// flag flips; `@AppStorage` is the `DynamicProperty` that does. `AppState`
    /// still owns the writes — the `set` below and the General toggle both route
    /// through `setMenuBarIconHidden`, and this mirror just follows the key via
    /// UserDefaults observation — so there is one source of truth, not two.
    @AppStorage(AppState.menuBarIconHiddenKey) private var menuBarIconHidden = false

    private var appState: AppState { delegate.appState }

    var body: some Scene {
        // `isInserted: false` removes the status item; the app survives it (see
        // `AppDelegate.applicationShouldTerminate`). Route the write through
        // `AppState` so the cached value its terminate/reveal guards read stays in
        // step with the persisted key.
        MenuBarExtra(isInserted: Binding(
            get: { !menuBarIconHidden },
            set: { appState.setMenuBarIconHidden(!$0) }
        )) {
            MenuBarView()
                .localized(with: appState)
        } label: {
            // Centered monochrome template glyphs let the system supply the
            // menu-bar tint for light, dark, and active states.
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
