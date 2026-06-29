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
                    List(filtered) { app in
                        Button {
                            onSelect(app)
                            dismiss()
                        } label: {
                            AppRowLabel(bundleID: app.bundleID, name: app.name, icon: icons[app.bundleID], iconSize: DS.Size.pickerIcon)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $query, placement: .toolbar)
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
}
