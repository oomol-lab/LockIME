import AppKit
import LockIMEKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// The Backup tab: the single home for exporting and importing the portable
/// configuration. Export writes a `.lockime` file via `NSSavePanel`; import
/// reads one via `NSOpenPanel`, then opens the **one** Review Import sheet —
/// never a chain of alerts. Bad files are reported inline at this entry point,
/// never as a system-localized `error.localizedDescription`.
struct BackupSettingsPane: View {
    @Environment(AppState.self) private var state

    @State private var reviewModel: ImportReviewModel?
    @State private var importError: BackupReadError?
    @State private var exportFailed = false
    @State private var receipt: ImportOutcome?

    private static let log = Logger(subsystem: "com.oomol.LockIME", category: "backup")

    var body: some View {
        Form {
            Section {
                Button {
                    exportConfiguration()
                } label: {
                    Label("Export Configuration…", systemImage: "square.and.arrow.up")
                }
                if exportFailed {
                    inlineNote("Couldn't save the backup file.", systemImage: "exclamationmark.triangle", tint: DS.Palette.warning)
                }
            } header: {
                Text("Export")
            } footer: {
                SectionFooter("Saves your global default source, app rules, and URL rules to a .lockime file. The master lock, enhanced mode, language, and login item aren't included.")
            }

            Section {
                Button {
                    importConfiguration()
                } label: {
                    Label("Import Configuration…", systemImage: "square.and.arrow.down")
                }
                if let importError {
                    importErrorNote(importError)
                }
                if let receipt {
                    receiptNote(receipt)
                }
            } header: {
                Text("Import")
            } footer: {
                SectionFooter("You'll review every change before it's applied. Nothing is modified until you tap Apply.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(state.loc("Backup"))
        .sheet(item: $reviewModel) { model in
            ImportReviewSheet(model: model) { outcome in
                receipt = outcome
                reviewModel = nil
            }
            // A sheet bridges into its own AppKit window, which doesn't reliably
            // inherit the app's in-app language override — re-inject it (and
            // rebuild on language change) so the Review screen isn't half-English.
            .environment(\.locale, state.locale)
            .id(state.localeIdentifier)
        }
    }

    // MARK: - Export

    private func exportConfiguration() {
        exportFailed = false
        let panel = NSSavePanel()
        panel.title = state.loc("Export Configuration")
        panel.prompt = state.loc("Export")
        panel.nameFieldStringValue = "LockIME Backup.\(ConfigBackup.fileExtension)"
        if let type = UTType(filenameExtension: ConfigBackup.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.isExtensionHidden = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try state.makeBackup().encoded().write(to: url, options: .atomic)
        } catch {
            // Never surface a system-localized message; log the original, show a
            // semantic note instead. Keep the error private (it can embed the
            // user's file path) — hashed so identical failures still correlate.
            Self.log.error("Backup export failed: \(String(describing: error), privacy: .private(mask: .hash))")
            exportFailed = true
        }
    }

    // MARK: - Import

    private func importConfiguration() {
        importError = nil
        receipt = nil
        let panel = NSOpenPanel()
        panel.title = state.loc("Import Configuration")
        panel.prompt = state.loc("Import")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let type = UTType(filenameExtension: ConfigBackup.fileExtension) {
            panel.allowedContentTypes = [type, .json]
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch state.loadImportPlan(from: url) {
        case .success(let plan):
            reviewModel = ImportReviewModel(plan: plan) { state.applyImport($0) }
        case .failure(let error):
            importError = error
        }
    }

    // MARK: - Inline notes

    @ViewBuilder
    private func importErrorNote(_ error: BackupReadError) -> some View {
        let icon = "exclamationmark.triangle"
        switch error {
        case .unreadable:
            inlineNote("Couldn't read the selected file. Check permissions and try again.", systemImage: icon, tint: DS.Palette.warning)
        case .notABackup:
            inlineNote("This file isn't a LockIME backup.", systemImage: icon, tint: DS.Palette.warning)
        case .damaged:
            inlineNote("This backup file is damaged and can't be read.", systemImage: icon, tint: DS.Palette.warning)
        case .incompatibleVersion(let appVersion):
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: icon).foregroundStyle(DS.Palette.warning)
                Text("This backup was made by a newer LockIME (\(appVersion)). Update LockIME, then try again.")
                    .font(DS.Font.sectionFooter)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Spacing.xxs)
        }
    }

    private func receiptNote(_ outcome: ImportOutcome) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // Neutral, not green: DESIGN.md confines success green to the update
            // window; Settings content (e.g. Permissions "granted") stays secondary.
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("Rules imported: \(outcome.imported)")
                    .font(DS.Font.sectionFooter)
                if outcome.inactive > 0 {
                    Text("Not active until installed: \(outcome.inactive)")
                        .font(DS.Font.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.xxs)
    }

    private func inlineNote(_ message: LocalizedStringKey, systemImage: String, tint: Color) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(message)
                .font(DS.Font.sectionFooter)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.xxs)
    }
}
