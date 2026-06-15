import AppKit
import SwiftUI

/// Custom Sparkle update window in the style of Apple Software Update: app icon +
/// title + version headline, a scrollable Markdown changelog, and a footer with
/// progress and the install/later/skip actions, driven by `UpdateViewModel`.
struct UpdateWindowView: View {
    @Environment(AppState.self) private var state
    @Environment(\.closeHostedWindow) private var closeWindow

    private var model: UpdateViewModel { state.updateController.model }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(width: DS.Window.updateWidth, height: DS.Window.updateHeight)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.Spacing.lg) {
            Image(nsImage: .lockIMEAppIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: DS.Size.updateHeaderIcon, height: DS.Size.updateHeaderIcon)
                .clipShape(RoundedRectangle(cornerRadius: DS.Size.updateHeaderIcon * 0.2237, style: .continuous))
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("Software Update")
                    .font(DS.Font.windowTitle)
                headlineText
                    .font(DS.Font.subtitle)
                    .foregroundStyle(.secondary)
                if isUpdateSession {
                    Text("Current version: \(Bundle.main.shortVersion) (\(Bundle.main.buildVersion))")
                        .font(DS.Font.subtitle)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.xl)
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .found, .readyToInstall, .downloading, .extracting, .installing:
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    if !model.availableVersion.isEmpty {
                        notesHeadline
                    }
                    let notes = model.releaseNotesMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
                    if notes.isEmpty {
                        Text("No release notes.")
                            .foregroundStyle(.secondary)
                    } else {
                        ReleaseNotesView(markdown: notes)
                    }
                }
                .padding(DS.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .checking:
            centered { ProgressView("Checking for updates…") }
        case .upToDate:
            centered {
                resultLabel("You're up to date.", systemImage: "checkmark.circle.fill", tint: DS.Palette.success)
            }
        case .error(let failure):
            centered {
                VStack(spacing: DS.Spacing.md) {
                    resultLabel("Update failed", systemImage: "exclamationmark.triangle.fill", tint: DS.Palette.warning)
                    Text(LocalizedStringKey(failure.messageKey))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        case .idle:
            centered {
                Text("Check for updates from the menu or Settings.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: DS.Spacing.lg) {
            if case .found = model.phase, model.canSkip {
                Button("Skip This Version") {
                    model.skip()
                    closeWindow()
                }
                .buttonStyle(.link)
            }
            progressView
            Spacer(minLength: 0)
            buttons
        }
        .padding(DS.Spacing.xl)
    }

    @ViewBuilder
    private var progressView: some View {
        switch model.phase {
        case .downloading(let fraction):
            ProgressView(value: fraction) {
                Text("Downloading…")
            } currentValueLabel: {
                downloadDetail
            }
            .frame(width: DS.Size.progressBar)
        case .extracting(let fraction):
            ProgressView(value: fraction) { Text("Extracting…") }
                .frame(width: DS.Size.progressBar)
        case .installing:
            ProgressView().controlSize(.small)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch model.phase {
        case .found:
            Button("Later") { model.dismissReply(); closeWindow() }
                .dsGlassButtonStyle()
            Button("Install Update") { model.install() }
                .dsGlassProminentButtonStyle()
                .keyboardShortcut(.defaultAction)
        case .readyToInstall:
            Button("Later") { model.dismissReply(); closeWindow() }
                .dsGlassButtonStyle()
            Button("Install and Relaunch") { model.install() }
                .dsGlassProminentButtonStyle()
                .keyboardShortcut(.defaultAction)
        case .checking, .downloading, .extracting:
            Button("Cancel") { model.dismissReply(); closeWindow() }
                .dsGlassButtonStyle()
        case .upToDate, .error, .idle:
            Button("Close") { closeWindow() }
                .dsGlassProminentButtonStyle()
                .keyboardShortcut(.defaultAction)
        case .installing:
            EmptyView()
        }
    }

    // MARK: Helpers

    /// Whether an update is on offer / in flight — the states that show release
    /// notes and version details (vs. check results and idle).
    private var isUpdateSession: Bool {
        switch model.phase {
        case .found, .readyToInstall, .downloading, .extracting, .installing: true
        case .idle, .checking, .upToDate, .error: false
        }
    }

    /// "Version 1.2.3" headline with the publish-date/channel chips at its
    /// right, above the release notes (Apple Software Update style).
    private var notesHeadline: some View {
        // Center, not baseline: the chips carry vertical padding, so baseline
        // alignment visually sinks them below the headline.
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            Text("Version \(model.availableVersion)")
                .font(DS.Font.notesVersion)
            if let date = model.publishedDate {
                InfoChip(color: DS.Palette.accent) {
                    Text(date, format: .dateTime.year().month().day())
                }
            }
            if model.isBetaChannel {
                InfoChip(color: DS.Palette.warning) {
                    Text("Beta")
                }
            }
        }
    }

    /// "5.2 MB of 20.9 MB — 1 MB/s, 15s remaining" under the download bar.
    /// One left-aligned sentence, Apple-style: the model only refreshes the
    /// readout once a second, so width changes are rare and confined to the
    /// tail of the line. `Text` format interpolations resolve against the
    /// environment locale, so the readout follows the in-app language override
    /// like every other string.
    @ViewBuilder
    private var downloadDetail: some View {
        if model.expectedBytes > 0 {
            let done = Int64(model.downloadedBytes)
            let total = Int64(model.expectedBytes)
            Group {
                if model.downloadSpeed > 0 {
                    let left = model.expectedBytes > model.downloadedBytes
                        ? model.expectedBytes - model.downloadedBytes : 0
                    let remaining = Duration.seconds(Double(left) / model.downloadSpeed)
                    Text("""
                    \(done, format: .byteCount(style: .file)) of \
                    \(total, format: .byteCount(style: .file)) — \
                    \(Int64(model.downloadSpeed), format: .byteCount(style: .file))/s, \
                    \(remaining, format: .units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2)) remaining
                    """)
                } else {
                    Text("\(done, format: .byteCount(style: .file)) of \(total, format: .byteCount(style: .file))")
                }
            }
            .font(DS.Font.progressDetail)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private func resultLabel(_ title: LocalizedStringKey, systemImage: String, tint: Color) -> some View {
        Label {
            Text(title).font(.headline)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
    }

    private func centered<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity)
            .padding(DS.Spacing.section)
    }

    /// A small colored capsule tag (publish date, channel) under the notes
    /// headline.
    private struct InfoChip<Label: View>: View {
        let color: Color
        @ViewBuilder var label: Label

        var body: some View {
            label
                .font(DS.Font.chip)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .background(color, in: Capsule())
        }
    }

    private var headlineText: Text {
        switch model.phase {
        case .found, .readyToInstall, .downloading, .extracting, .installing:
            model.availableVersion.isEmpty
                ? Text("A new version is available")
                : Text("Version \(model.availableVersion) is available")
        case .checking: Text("Checking…")
        case .upToDate: Text("No updates available")
        case .error: Text("Something went wrong")
        case .idle: Text(verbatim: "LockIME")
        }
    }
}
