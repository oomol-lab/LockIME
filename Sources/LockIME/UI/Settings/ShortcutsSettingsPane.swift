import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section {
                // KeyboardShortcuts.Recorder has both a `String` and a
                // `LocalizedStringKey` initializer; a bare string literal binds
                // to the `String` one, which renders verbatim and bypasses the
                // app's language override. Wrap in `LocalizedStringKey` so the
                // label resolves against the injected `\.locale` (English
                // fallback, never the system language).
                KeyboardShortcuts.Recorder(LocalizedStringKey("Toggle lock"), name: .toggleLock)
                KeyboardShortcuts.Recorder(LocalizedStringKey("Lock to previous input source"), name: .globalPreviousSource)
                KeyboardShortcuts.Recorder(LocalizedStringKey("Lock to next input source"), name: .globalNextSource)
            } header: {
                Text("Global shortcuts")
            } footer: {
                SectionFooter("Works anywhere. Prefer a Command- or Control-based combination.")
            }

            Section {
                KeyboardShortcuts.Recorder(LocalizedStringKey("Lock to previous input source"), name: .appPreviousSource)
                KeyboardShortcuts.Recorder(LocalizedStringKey("Lock to next input source"), name: .appNextSource)
                KeyboardShortcuts.Recorder(LocalizedStringKey("Remove this app's rule"), name: .removeFrontmostAppRule)
            } header: {
                Text("Current app")
            } footer: {
                SectionFooter("Act on whichever app is frontmost. Nothing happens if it has no rule.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(state.loc("Shortcuts"))
    }
}
