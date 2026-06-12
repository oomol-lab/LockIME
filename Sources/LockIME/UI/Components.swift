import AppKit
import LockIMEKit
import SwiftUI

/// The single Accessibility grant action, shared so it lives in exactly one
/// place (General's Accessibility section). Opens the Accessibility privacy pane
/// with the floating drag helper; the grant is detected by `AppState`, which
/// closes the helper and flips `accessibilityGranted` the instant access is
/// allowed (the system sends no notification).
struct GrantAccessibilityButton: View {
    @Environment(AppState.self) private var state
    @Environment(\.locale) private var locale

    var body: some View {
        Button {
            state.requestAccessibilityAccess(
                localeIdentifier: locale.identifier,
                suggestedAppURLs: [Bundle.main.bundleURL],
                sourceFrame: Self.clickSourceFrame()
            )
        } label: {
            Label("Grant Accessibility Access", systemImage: "arrow.right.circle.fill")
        }
    }

    /// Uses the click location so the helper panel flies out from the button.
    private static func clickSourceFrame() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x - 16, y: mouse.y - 16, width: 32, height: 32)
    }
}

/// A passive "Requires Accessibility" note for feature panes (App Rules, URL
/// Rules). It carries no grant button of its own — that lives only in General —
/// it just explains the dependency in its own words and routes there, so the
/// permission reads as one capability with a single grant, never a prompt
/// duplicated per feature.
struct AccessibilityRequiredNote: View {
    @Environment(AppState.self) private var state
    private let message: LocalizedStringKey

    init(_ message: LocalizedStringKey) { self.message = message }

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "accessibility")
                .foregroundStyle(.secondary)
            Text(message)
                .font(DS.Font.sectionFooter)
                .foregroundStyle(.secondary)
            Spacer(minLength: DS.Spacing.sm)
            Button("Set Up in Permissions…") {
                state.settingsTab = .permissions
            }
            .buttonStyle(.link)
        }
        .padding(.vertical, DS.Spacing.xxs)
    }
}

/// A standard app row — icon + display name + bundle identifier — shared by the
/// App Rules pane and the app picker so both read with identical rhythm.
struct AppRowLabel: View {
    let bundleID: String
    /// Optional pre-resolved display name (e.g. from `InstalledApp`), avoiding a
    /// second workspace lookup.
    var name: String?
    /// Optional pre-resolved icon (e.g. cached by a long list), avoiding a
    /// `NSWorkspace` lookup on every row render.
    var icon: NSImage?
    var iconSize: CGFloat = DS.Size.rowIcon

    init(bundleID: String, name: String? = nil, icon: NSImage? = nil, iconSize: CGFloat = DS.Size.rowIcon) {
        self.bundleID = bundleID
        self.name = name
        self.icon = icon
        self.iconSize = iconSize
    }

    var body: some View {
        HStack(spacing: DS.Spacing.lg) {
            iconView
                .frame(width: iconSize, height: iconSize)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name ?? AppDisplay.name(for: bundleID))
                    .font(DS.Font.rowTitle)
                Text(bundleID)
                    .font(DS.Font.rowSubtitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let nsImage = icon ?? AppDisplay.icon(for: bundleID) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(.quaternary)
                .overlay(
                    Image(systemName: "app.dashed")
                        .foregroundStyle(.secondary)
                )
        }
    }
}

/// A grouped-`Form` section footer with the standard footnote/secondary styling,
/// replacing the repeated `Text(...).font(.footnote).foregroundStyle(.secondary)`.
struct SectionFooter: View {
    private let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(DS.Font.sectionFooter)
            .foregroundStyle(.secondary)
    }
}
