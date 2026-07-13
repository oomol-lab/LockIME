import AppKit
import LockIMEKit
import SwiftUI

struct AppRulesSettingsPane: View {
    @Environment(AppState.self) private var state
    @State private var isPickingApp = false

    var body: some View {
        let defaultBinding = Binding<InputSourceID?>(
            get: { state.config.defaultSourceID },
            set: { state.setDefaultSource($0) }
        )
        let defaultActionBinding = Binding<RuleAction>(
            get: { state.config.defaultAction },
            set: { state.setDefaultAction($0) }
        )
        let newRuleModeBinding = Binding<AppRuleMode>(
            get: { state.newAppRuleMode },
            set: { state.setNewAppRuleMode($0) }
        )

        Form {
            Section {
                Picker("Input source", selection: defaultBinding) {
                    Text("None").tag(InputSourceID?.none)
                    ForEach(state.availableSources) { source in
                        Text(source.localizedName).tag(InputSourceID?.some(source.id))
                    }
                }
                // Lock vs one-shot switch only matters once a source is set — the
                // picker is inert (and hidden) while the default is "None".
                if state.config.defaultSourceID != nil {
                    Picker("Behavior", selection: defaultActionBinding) {
                        Text("Lock to").tag(RuleAction.lock)
                        Text("Switch to").tag(RuleAction.switchOnce)
                    }
                }
            } header: {
                Text("Global default")
            } footer: {
                SectionFooter("Used whenever the frontmost app has no rule of its own.")
            }

            Section {
                Picker("Default behavior", selection: newRuleModeBinding) {
                    Text("Lock to").tag(AppRuleMode.locked)
                    Text("Switch to").tag(AppRuleMode.switched)
                    Text("Ignore").tag(AppRuleMode.ignored)
                    Text("Use default").tag(AppRuleMode.useDefault)
                }
            } header: {
                Text("New app rules")
            } footer: {
                SectionFooter("The behavior a newly added app rule starts with. You can change any rule afterward.")
            }

            Section {
                if state.config.appRules.isEmpty {
                    emptyState
                } else {
                    ForEach(state.config.appRules) { rule in
                        AppRuleRow(rule: rule)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                Button {
                    isPickingApp = true
                } label: {
                    Label("Add App…", systemImage: "plus")
                }

                // Launcher overlays (Spotlight, Raycast, …) are the only app
                // rules that need Accessibility — show the routing note only
                // when one is configured but access isn't granted yet.
                if hasLauncherRule, !state.accessibilityGranted {
                    AccessibilityRequiredNote("Detecting launchers like Spotlight requires Accessibility")
                }
            } header: {
                Text("Per-app rules")
            } footer: {
                SectionFooter("Lock an app to its own input source, switch to one on activation, ignore it, or fall back to the global default.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(state.loc("App Rules"))
        .onAppear { state.refreshAccessibilityStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshAccessibilityStatus()
        }
        .sheet(isPresented: $isPickingApp) {
            AppPickerSheet { app in
                withAnimation(DS.Motion.list) {
                    // Seed the row with the user's chosen default mode (issue #54);
                    // the source stays the global default, so switching the seeded
                    // mode to a non-pinning one later just ignores it.
                    state.upsertRule(
                        AppRule(
                            bundleID: app.bundleID,
                            mode: state.newAppRuleMode,
                            lockedSourceID: state.config.defaultSourceID
                        )
                    )
                }
            }
            // A sheet bridges into its own AppKit window that doesn't inherit the
            // app's in-app language override — re-inject it (rebuilding on change).
            .environment(\.locale, state.locale)
            .id(state.localeIdentifier)
        }
    }

    /// Whether any configured rule targets a launcher overlay — the only app
    /// rules whose enforcement depends on Accessibility.
    private var hasLauncherRule: Bool {
        state.config.appRules.contains { LauncherOverlayCatalog.isLauncher($0.bundleID) }
    }

    private var emptyState: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "macwindow")
                .foregroundStyle(.secondary)
            Text("No app rules yet.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Spacing.xs)
    }
}

private struct AppRuleRow: View {
    @Environment(AppState.self) private var state
    let rule: AppRule

    var body: some View {
        HStack(spacing: DS.Spacing.lg) {
            AppRowLabel(bundleID: rule.bundleID)

            Spacer(minLength: DS.Spacing.md)

            Picker("", selection: modeBinding) {
                Text("Lock to").tag(AppRuleMode.locked)
                Text("Switch to").tag(AppRuleMode.switched)
                Text("Ignore").tag(AppRuleMode.ignored)
                Text("Use default").tag(AppRuleMode.useDefault)
            }
            .labelsHidden()
            .fixedSize()

            if rule.mode.pinsSource {
                Picker("", selection: sourceBinding) {
                    Text("Default").tag(InputSourceID?.none)
                    ForEach(state.availableSources) { source in
                        Text(source.localizedName).tag(InputSourceID?.some(source.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            Button(role: .destructive) {
                withAnimation(DS.Motion.list) {
                    state.removeRule(bundleID: rule.bundleID)
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove rule")
        }
        .padding(.vertical, DS.Spacing.xxs)
    }

    private var modeBinding: Binding<AppRuleMode> {
        Binding(
            get: { rule.mode },
            set: { state.upsertRule(AppRule(bundleID: rule.bundleID, mode: $0, lockedSourceID: rule.lockedSourceID)) }
        )
    }

    private var sourceBinding: Binding<InputSourceID?> {
        Binding(
            get: { rule.lockedSourceID },
            set: { state.upsertRule(AppRule(bundleID: rule.bundleID, mode: rule.mode, lockedSourceID: $0)) }
        )
    }
}
