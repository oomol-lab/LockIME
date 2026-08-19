import AppKit
import LockIMEKit
import SwiftUI

/// A searchable list of installed apps for adding a per-app rule.
struct AppPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (InstalledApp) -> Void

    @State private var apps: [InstalledApp] = []
    @State private var icons: [String: NSImage] = [:]
    @State private var query = ""
    @State private var manualBundleID = ""

    private var filtered: [InstalledApp] {
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleID.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose an App")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(DS.Spacing.xl)

            Divider()

            Group {
                if apps.isEmpty {
                    ContentUnavailableView {
                        Label("Loading apps…", systemImage: "hourglass")
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    // One flat, name-sorted list. Bare-executable processes
                    // (e.g. Minecraft's `java`, discoverable only while
                    // running) are deliberately NOT split into their own
                    // section: how a program is packaged is an implementation
                    // detail, and a "process" heading would only raise
                    // questions the picker can't answer.
                    List(filtered) { row($0) }
                }
            }
            // Greedy on purpose: a `List` fills the remaining height by itself,
            // but the empty/no-results `ContentUnavailableView`s size to their
            // content — without this the whole VStack falls short of the fixed
            // sheet frame and gets centered, "collapsing" the header and the
            // bundle-ID row toward the middle.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .searchable(text: $query, placement: .toolbar)

            Divider()

            // Escape hatch for apps the scan can't discover — most notably a
            // process that isn't running right now, or one launched from a bare
            // executable (e.g. Minecraft's `java`, which does appear above, but
            // only while the game is running).
            HStack(spacing: DS.Spacing.md) {
                TextField("Bundle ID", text: $manualBundleID)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addManualBundleID)
                Button("Add") { addManualBundleID() }
                    .disabled(trimmedManualBundleID.isEmpty)
            }
            .padding(DS.Spacing.xl)
            .help("Add an app that isn't in the list by its bundle identifier.")
        }
        .frame(width: DS.Window.pickerWidth, height: DS.Window.pickerHeight)
        .overlayScrollers()
        .task {
            let scanned = InstalledAppsScanner.scan()
            apps = scanned
            // Resolve each icon once, up front, so list re-renders (e.g. while
            // searching) reuse them instead of hitting NSWorkspace per row.
            var resolved: [String: NSImage] = [:]
            for app in scanned {
                resolved[app.bundleID] = AppDisplay.icon(for: app.bundleID)
            }
            icons = resolved
        }
    }

    private func row(_ app: InstalledApp) -> some View {
        Button {
            onSelect(app)
            dismiss()
        } label: {
            AppRowLabel(bundleID: app.bundleID, name: app.name, icon: icons[app.bundleID], iconSize: DS.Size.pickerIcon)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// The typed bundle ID with surrounding whitespace stripped; empty (the Add
    /// button stays disabled) when blank or containing internal whitespace — a
    /// bundle ID never has any, so this catches an accidental app *name* early.
    private var trimmedManualBundleID: String {
        let trimmed = manualBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return "" }
        return trimmed
    }

    /// Commit the manually typed bundle ID as if a list row had been picked. The
    /// rule keys on the bundle ID alone, so a placeholder name/path is fine —
    /// `AppRowLabel` re-resolves the display name live (falling back to the
    /// running app, then the raw ID).
    private func addManualBundleID() {
        let id = trimmedManualBundleID
        guard !id.isEmpty else { return }
        onSelect(InstalledApp(bundleID: id, name: id, path: ""))
        dismiss()
    }
}
