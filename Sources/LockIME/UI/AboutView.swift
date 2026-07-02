import AppKit
import SwiftUI

/// A clean, native About panel: the real app icon, name, version, a one-line
/// description, links, and copyright — in the style of Things / Reeder / Tower.
struct AboutView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL
    @State private var showingAcknowledgements = false

    private static let repoURL = URL(string: "https://github.com/oomol-lab/LockIME")!

    var body: some View {
        VStack(spacing: 0) {
            // The mascot mirrors the live lock state: hugging the keyboard
            // while locked, off duty with bamboo while unlocked.
            stateIcon
                .resizable()
                .interpolation(.high)
                .frame(width: DS.Size.aboutIcon, height: DS.Size.aboutIcon)
                .clipShape(RoundedRectangle(cornerRadius: DS.Size.aboutIcon * 0.2237, style: .continuous))
                .padding(.top, 28)
                .padding(.bottom, 14)

            Text(verbatim: "LockIME")
                .font(DS.Font.appName)

            Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildVersion))")
                .font(DS.Font.version)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, DS.Spacing.xxs)

            Text("Keep your keyboard input source locked.")
                .font(DS.Font.subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, DS.Spacing.lg)
                .padding(.horizontal, 28)

            HStack(spacing: DS.Spacing.xl) {
                Button(action: { openURL(Self.repoURL) }) {
                    Text(verbatim: "GitHub")
                }
                Button("Acknowledgements") { showingAcknowledgements = true }
            }
            .buttonStyle(.link)
            .padding(.top, 14)

            Spacer(minLength: DS.Spacing.xl)

            Text(Bundle.main.copyright)
                .font(DS.Font.copyright)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.bottom, DS.Spacing.xl)
                .padding(.horizontal, DS.Spacing.xxl)
        }
        .frame(width: DS.Window.aboutWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .sheet(isPresented: $showingAcknowledgements) {
            AcknowledgementsView()
                // A sheet bridges into its own AppKit window that doesn't inherit
                // the app's in-app language override — re-inject it.
                .environment(\.locale, state.locale)
                .id(state.localeIdentifier)
        }
    }

    private var stateIcon: Image {
        state.isAppEnabled ? Image(nsImage: .lockIMEAppIcon) : Image("AppIconUnlocked")
    }
}

/// A small sheet crediting the open-source libraries LockIME builds on.
struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private struct Library: Identifiable {
        let name: String
        let license: String
        let url: URL
        var id: String { name }
    }

    private let libraries: [Library] = [
        .init(name: "Sparkle", license: "Sparkle License", url: URL(string: "https://github.com/sparkle-project/Sparkle")!),
        .init(name: "KeyboardShortcuts", license: "MIT License", url: URL(string: "https://github.com/sindresorhus/KeyboardShortcuts")!),
        .init(name: "PermissionFlow", license: "MIT License", url: URL(string: "https://github.com/jaywcjlove/PermissionFlow")!),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Acknowledgements")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Spacing.xl)

            Divider()

            List(libraries) { library in
                Button {
                    openURL(library.url)
                } label: {
                    HStack(spacing: DS.Spacing.lg) {
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text(verbatim: library.name)
                                .font(DS.Font.rowTitle)
                            Text(verbatim: library.license)
                                .font(DS.Font.rowSubtitle)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: DS.Window.acknowledgementsWidth, height: DS.Window.acknowledgementsHeight)
        .overlayScrollers()
    }
}
