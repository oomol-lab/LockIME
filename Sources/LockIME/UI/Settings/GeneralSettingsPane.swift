import AppKit
import LockIMEKit
import SwiftUI

struct GeneralSettingsPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let masterBinding = Binding(
            get: { state.isAppEnabled },
            set: { newValue in
                withAnimation(DS.Motion.toggle) { state.setMasterEnabled(newValue) }
            }
        )
        let lockingBinding = Binding(
            get: { state.config.lockingEnabled },
            set: { newValue in
                withAnimation(DS.Motion.toggle) { state.setLockingEnabled(newValue) }
            }
        )

        Form {
            Section {
                Toggle("Enable LockIME", isOn: masterBinding)
                // Subordinate to the master (HIG dependency): dimmed and inert
                // while LockIME is off. Turning it off is the "act like Input
                // Source Pro" mode — switch rules still fire, nothing is pinned.
                Toggle("Enable locking", isOn: lockingBinding)
                    .disabled(!state.isAppEnabled)
                LabeledContent("Current source", value: state.currentSourceName)
                LabeledContent("Activations", value: state.activationCount.formatted())
            } header: {
                Text("Status")
            } footer: {
                SectionFooter("Enable LockIME to apply your rules. With locking on, it keeps the input source pinned to your target; turn locking off to only switch on entry — for the apps and sites you set — and stay free to change it.")
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
                let hideIconBinding = Binding(
                    get: { state.menuBarIconHidden },
                    set: { newValue in
                        withAnimation(DS.Motion.toggle) { state.setMenuBarIconHidden(newValue) }
                    }
                )
                Toggle("Hide menu bar icon", isOn: hideIconBinding)
            } header: {
                Text("Menu Bar")
            } footer: {
                SectionFooter("LockIME keeps running in the background with its icon hidden. To show this window again, open LockIME from the Applications folder or Spotlight.")
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
