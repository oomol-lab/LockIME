import AppKit
import LockIMEKit
import SwiftUI

struct GeneralSettingsPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let lockBinding = Binding(
            get: { state.isLocked },
            set: { newValue in
                withAnimation(DS.Motion.toggle) { state.setMasterEnabled(newValue) }
            }
        )

        Form {
            Section {
                Toggle("Enable input-source locking", isOn: lockBinding)
                LabeledContent("Current source", value: state.currentSourceName)
                LabeledContent("Activations", value: state.activationCount.formatted())
            } header: {
                Text("Status")
            } footer: {
                SectionFooter("When enabled, LockIME keeps the keyboard input source pinned to the configured target.")
            }

            Section {
                let launchBinding = Binding(
                    get: { state.loginItemState.isActive },
                    set: { state.setLaunchAtLogin($0) }
                )
                Toggle("Launch at login", isOn: launchBinding)

                if state.loginItemState == .requiresApproval {
                    Button("Open Login Items settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Startup")
            } footer: {
                if state.loginItemState == .requiresApproval {
                    SectionFooter("Approval is required in System Settings ▸ General ▸ Login Items.")
                }
            }

            Section {
                let languageBinding = Binding(
                    get: { state.languagePreference },
                    set: { state.setLanguagePreference($0) }
                )
                Picker("Language", selection: languageBinding) {
                    Text("Follow System").tag(LanguagePreference.system)
                    Divider()
                    ForEach(SupportedLanguage.allCases) { language in
                        Text(language.nativeName).tag(LanguagePreference.specific(language))
                    }
                }
            } header: {
                Text("Language")
            }

            Section {
                let apiBinding = Binding(
                    get: { state.apiEnabled },
                    set: { state.setAPIEnabled($0) }
                )
                Toggle("URL Scheme API", isOn: apiBinding)
                Link("API documentation", destination: state.apiDocumentationURL)
            } header: {
                Text("Automation")
            } footer: {
                SectionFooter("When on, other apps and scripts can control LockIME with `lockime://` URL commands.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(state.loc("General"))
        .onAppear { state.refreshLoginItemState() }
    }
}
