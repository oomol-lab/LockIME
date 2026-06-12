import AppKit
import LockIMEKit
import SwiftUI

/// Per-URL rules, gated behind the Accessibility-powered "enhanced mode". Rules
/// can only be edited once enhanced mode is enabled (which itself needs the
/// Accessibility permission).
struct URLRulesSettingsPane: View {
    @Environment(AppState.self) private var state

    @State private var newHost = ""
    @State private var newSourceID: InputSourceID?

    var body: some View {
        let enhancedBinding = Binding(
            get: { state.config.enhancedModeEnabled },
            set: { state.setEnhancedMode($0) }
        )

        Form {
            Section {
                Toggle("Enhanced mode (per-URL rules)", isOn: enhancedBinding)
                    .disabled(!state.accessibilityGranted)

                if !state.accessibilityGranted {
                    AccessibilityRequiredNote("Enhanced mode requires Accessibility")
                }
            } header: {
                Text("Enhanced mode")
            } footer: {
                SectionFooter("Enhanced mode reads the active browser URL via Accessibility to apply per-URL rules. The core lock needs no permissions.")
            }

            Section {
                if state.config.enhancedModeEnabled {
                    if state.config.urlRules.isEmpty {
                        emptyState
                    } else {
                        ForEach(state.config.urlRules) { rule in
                            URLRuleRow(rule: rule)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    addRow
                } else {
                    HStack(spacing: DS.Spacing.md) {
                        Image(systemName: "lock")
                            .foregroundStyle(.secondary)
                        Text("Enable enhanced mode to add per-URL rules.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, DS.Spacing.xxs)
                }
            } header: {
                Text("URL rules")
            } footer: {
                SectionFooter("Per-URL rules work in Safari, Firefox, and Chromium-based browsers (Chrome, Edge, Brave, Arc, Vivaldi, Opera).")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(state.loc("URL Rules"))
        // The grant button (and its watcher lifecycle) now lives in General; this
        // pane only reflects the shared status, refreshing to catch a revoke.
        .onAppear { state.refreshAccessibilityStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshAccessibilityStatus()
        }
    }

    private var emptyState: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
            Text("No URL rules yet.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Spacing.xxs)
    }

    private var addRow: some View {
        HStack(spacing: DS.Spacing.md) {
            TextField("Host (e.g. github.com)", text: $newHost)
                .textFieldStyle(.roundedBorder)
            Picker("", selection: $newSourceID) {
                Text("Default").tag(InputSourceID?.none)
                ForEach(state.availableSources) { source in
                    Text(source.localizedName).tag(InputSourceID?.some(source.id))
                }
            }
            .labelsHidden()
            .fixedSize()
            Button("Add") {
                let host = newHost.trimmingCharacters(in: .whitespaces)
                guard !host.isEmpty, let sourceID = newSourceID ?? state.config.defaultSourceID else { return }
                withAnimation(DS.Motion.list) {
                    state.upsertURLRule(URLRule(hostPattern: host, lockedSourceID: sourceID))
                }
                newHost = ""
                newSourceID = nil
            }
            .disabled(
                newHost.trimmingCharacters(in: .whitespaces).isEmpty
                    || (newSourceID == nil && state.config.defaultSourceID == nil)
            )
        }
    }
}

private struct URLRuleRow: View {
    @Environment(AppState.self) private var state
    let rule: URLRule

    var body: some View {
        HStack(spacing: DS.Spacing.lg) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
            Text(rule.hostPattern)
            Spacer(minLength: DS.Spacing.md)
            Picker("", selection: sourceBinding) {
                ForEach(state.availableSources) { source in
                    Text(source.localizedName).tag(source.id)
                }
            }
            .labelsHidden()
            .fixedSize()
            Button(role: .destructive) {
                withAnimation(DS.Motion.list) {
                    state.removeURLRule(id: rule.id)
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove rule")
        }
        .padding(.vertical, DS.Spacing.xxs)
    }

    private var sourceBinding: Binding<InputSourceID> {
        Binding(
            get: { rule.lockedSourceID },
            set: { state.upsertURLRule(URLRule(id: rule.id, hostPattern: rule.hostPattern, lockedSourceID: $0)) }
        )
    }
}
