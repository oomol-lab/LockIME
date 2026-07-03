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

        Form {
            Section {
                Toggle("Enable LockIME", isOn: masterBinding)
                LabeledContent("Current source", value: state.currentSourceName)
                LabeledContent("Activations", value: state.activationCount.formatted())
            } header: {
                Text("Status")
            } footer: {
                SectionFooter("Enable LockIME to apply your rules.")
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
                let secureInputBinding = Binding(
                    get: { state.config.revertsInSecureInput },
                    set: { state.setRevertsInSecureInput($0) }
                )
                Toggle("Enforce in password fields", isOn: secureInputBinding)
            } header: {
                Text("Password Fields")
            } footer: {
                SectionFooter("By default, LockIME respects macOS secure input and doesn't change your input source in password fields. Turn this on to keep enforcing the locked source even there.")
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
