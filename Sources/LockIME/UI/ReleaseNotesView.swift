import AppKit
import LockIMEKit
import SwiftUI

/// Renders an update's release-notes Markdown in the update window. We parse the
/// notes into blocks (`ReleaseNotes.blocks`) and lay out the block structure —
/// heading, bullet list, paragraphs — ourselves; `Text` renders the inline
/// bold/code/links each block already carries. This stands in for a full
/// Markdown view library: the generated notes only use that small subset.
struct ReleaseNotesView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            ForEach(Array(ReleaseNotes.blocks(fromMarkdown: markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    Text(text)
                        .font(Self.headingFont(forLevel: level))
                        .padding(.top, DS.Spacing.sm)
                case .listItem(let text):
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                        Text(verbatim: "•")
                            .foregroundStyle(.secondary)
                        Text(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .paragraph(let text):
                    Text(text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .tint(DS.Palette.accent)
    }

    /// Heading sizes on the 13-pt control scale, matching the former
    /// swift-markdown-ui theme's 1.31 / 1.15 / 1.0 em steps. Notes in practice
    /// only ever use H2, but the full ladder keeps any hand-written heading sane.
    private static func headingFont(forLevel level: Int) -> Font {
        let base = NSFont.systemFontSize
        return switch level {
        case 1: .system(size: base * 1.31, weight: .bold)
        case 2: .system(size: base * 1.15, weight: .semibold)
        default: .system(size: base, weight: .semibold)
        }
    }
}
