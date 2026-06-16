import LockIMEKit
import SwiftUI

/// The Settings window's tabs. A stable identity lets one pane route the user to
/// another — App Rules / URL Rules point at General's single Accessibility grant.
enum SettingsTab: Hashable {
    case general, appRules, urlRules, shortcuts, permissions, updates, log, backup
}

/// Root of the Settings window — a standard multi-pane macOS settings TabView,
/// the same shape as System Settings. Each pane is its own grouped `Form`.
///
/// Two bodies for one view: the `Tab` builder (and tab badges) is macOS 15+,
/// and the deployment floor is 14 — Sonoma falls back to the `.tabItem` API,
/// which draws the same settings tabs minus the Updates badge. Keep both in
/// sync when adding a pane. Both drive their selection off `AppState.settingsTab`
/// so the Accessibility badges can programmatically switch to General.
struct SettingsRootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let selection = Binding(
            get: { state.settingsTab },
            set: { state.settingsTab = $0 }
        )
        Group {
            if #available(macOS 15.0, *) {
                tabs(selection: selection)
            } else {
                legacyTabs(selection: selection)
            }
        }
        .scenePadding()
        .frame(minWidth: 680, idealWidth: 700, minHeight: 600)
        // The Settings *window* closing (not a tab switch — this root outlives
        // those) is the "abandon" signal for an in-flight Accessibility grant.
        .onDisappear { state.stopAccessibilityWatch() }
    }

    @available(macOS 15.0, *)
    private func tabs(selection: Binding<SettingsTab>) -> some View {
        TabView(selection: selection) {
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) {
                GeneralSettingsPane()
            }
            Tab("App Rules", systemImage: "macwindow.on.rectangle", value: SettingsTab.appRules) {
                AppRulesSettingsPane()
            }
            Tab("URL Rules", systemImage: "globe", value: SettingsTab.urlRules) {
                URLRulesSettingsPane()
            }
            Tab("Shortcuts", systemImage: "command", value: SettingsTab.shortcuts) {
                ShortcutsSettingsPane()
            }
            Tab("Permissions", systemImage: "hand.raised", value: SettingsTab.permissions) {
                PermissionsSettingsPane()
            }
            Tab("Updates", systemImage: "arrow.down.circle", value: SettingsTab.updates) {
                UpdatesSettingsPane()
            }
            .badge(state.updateController.pendingUpdateVersion != nil ? 1 : 0)
            Tab("Log", systemImage: "list.bullet.rectangle", value: SettingsTab.log) {
                ActivationLogPane()
            }
            Tab("Backup", systemImage: "arrow.up.arrow.down.square", value: SettingsTab.backup) {
                BackupSettingsPane()
            }
        }
    }

    private func legacyTabs(selection: Binding<SettingsTab>) -> some View {
        TabView(selection: selection) {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AppRulesSettingsPane()
                .tabItem { Label("App Rules", systemImage: "macwindow.on.rectangle") }
                .tag(SettingsTab.appRules)
            URLRulesSettingsPane()
                .tabItem { Label("URL Rules", systemImage: "globe") }
                .tag(SettingsTab.urlRules)
            ShortcutsSettingsPane()
                .tabItem { Label("Shortcuts", systemImage: "command") }
                .tag(SettingsTab.shortcuts)
            PermissionsSettingsPane()
                .tabItem { Label("Permissions", systemImage: "hand.raised") }
                .tag(SettingsTab.permissions)
            UpdatesSettingsPane()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
                .tag(SettingsTab.updates)
            ActivationLogPane()
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
                .tag(SettingsTab.log)
            BackupSettingsPane()
                .tabItem { Label("Backup", systemImage: "arrow.up.arrow.down.square") }
                .tag(SettingsTab.backup)
        }
    }
}
