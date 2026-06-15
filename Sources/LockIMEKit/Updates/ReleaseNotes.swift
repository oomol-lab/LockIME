import Foundation

/// A renderable block of an update's release notes, parsed from the appcast
/// item's Markdown.
///
/// We render notes ourselves rather than embedding a full Markdown view library:
/// the notes are GitHub's generated changelog, which only ever uses a tiny
/// subset — an `##` heading, a flat bullet list, paragraphs, and inline
/// bold/code/links — and `AttributedString(markdown:)` parses all of it.
/// SwiftUI's `Text` already renders the *inline* attributes (bold, code, links);
/// only the *block* layout (heading sizes, list bullets, paragraph spacing) is
/// ours to do, which is what these cases carry.
public enum ReleaseNoteBlock: Equatable, Sendable {
    /// A heading; `level` is the Markdown depth (`#` → 1, `##` → 2, …).
    case heading(level: Int, text: AttributedString)
    /// One bullet-list item. Ordered and unordered lists both render as bullets
    /// (generated notes only ever produce unordered lists).
    case listItem(AttributedString)
    /// A plain paragraph. Any block kind we don't special-case — a fenced code
    /// block, a block quote, a table cell — degrades to this, so notes that ever
    /// stray outside the generated subset stay readable instead of vanishing.
    case paragraph(AttributedString)
}

public enum ReleaseNotes {
    /// Parse release-notes Markdown into renderable blocks. Inline formatting
    /// (bold, code, links) is preserved on each block's `AttributedString` for
    /// `Text` to render; block structure is surfaced as the cases above.
    ///
    /// Never throws: malformed Markdown degrades to a single plain paragraph,
    /// and empty/whitespace input yields no blocks.
    public static func blocks(fromMarkdown markdown: String) -> [ReleaseNoteBlock] {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            let plain = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            return plain.isEmpty ? [] : [.paragraph(AttributedString(plain))]
        }

        var blocks: [ReleaseNoteBlock] = []
        var bufferKey: Int?
        var bufferComponents: [PresentationIntent.IntentType] = []
        var buffer = AttributedString()

        func flush() {
            let trimmed = trimmingWhitespace(buffer)
            if !trimmed.characters.isEmpty {
                blocks.append(classify(styledForGitHub(trimmed), components: bufferComponents))
            }
            buffer = AttributedString()
        }

        for run in parsed.runs {
            // `components` is ordered innermost-first, so its first element is the
            // smallest enclosing block — a distinct identity per paragraph, list
            // item, or heading. A change there marks a block boundary; top-level
            // text carries no intent (key -1).
            let components = run.presentationIntent?.components ?? []
            let key = components.first?.identity ?? -1
            if key != bufferKey {
                flush()
                bufferKey = key
                bufferComponents = components
            }
            buffer.append(parsed[run.range])
        }
        flush()
        return blocks
    }

    private static func classify(
        _ text: AttributedString,
        components: [PresentationIntent.IntentType]
    ) -> ReleaseNoteBlock {
        for component in components {
            if case .header(let level) = component.kind {
                return .heading(level: level, text: text)
            }
        }
        for component in components {
            if case .listItem = component.kind {
                return .listItem(text)
            }
        }
        return .paragraph(text)
    }

    /// Apply the reading conveniences GitHub layers on top of plain Markdown,
    /// which cmark — and so the old swift-markdown-ui path — left as literal
    /// text: link `@name` to its profile, and relabel `…/pull/N`, `…/issues/N`,
    /// and `…/compare/A...B` links as `#N` / `A...B` (the link target is kept).
    /// Applied per block, so it never disturbs the block split.
    private static func styledForGitHub(_ block: AttributedString) -> AttributedString {
        linkifyingMentions(in: shorteningGitHubLinks(block))
    }

    /// Relabel GitHub PR/issue/compare link runs to their short form, preserving
    /// the link target and any inline styling.
    private static func shorteningGitHubLinks(_ input: AttributedString) -> AttributedString {
        var result = AttributedString()
        for run in input.runs {
            guard let url = run.link, let label = compactGitHubLabel(for: url) else {
                result.append(input[run.range])
                continue
            }
            var replacement = AttributedString(label)
            replacement.link = url
            replacement.inlinePresentationIntent = run.inlinePresentationIntent
            result.append(replacement)
        }
        return result
    }

    /// `#N` for a pull/issue URL, the bare ref range for a compare URL, else nil.
    private static func compactGitHubLabel(for url: URL) -> String? {
        guard
            let host = url.host?.lowercased(),
            host == "github.com" || host.hasSuffix(".github.com")
        else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 4 else { return nil }
        switch parts[2] {
        case "pull", "issues": return "#\(parts[3])"
        case "compare": return parts[3]
        default: return nil
        }
    }

    /// Link every `@username` (GitHub's 1–39 char, no leading/trailing-hyphen
    /// rule) that isn't already inside a link — skipping email locals via the
    /// look-behind — to `https://github.com/<username>`.
    private static func linkifyingMentions(in input: AttributedString) -> AttributedString {
        var output = input
        let text = String(output.characters)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![A-Za-z0-9_@/.])@([A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?)"#
        ) else { return output }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text),
                  let name = Range(match.range(at: 1), in: text),
                  let url = URL(string: "https://github.com/\(text[name])") else { continue }
            let lower = output.index(output.startIndex, offsetByCharacters: text.distance(from: text.startIndex, to: whole.lowerBound))
            let upper = output.index(output.startIndex, offsetByCharacters: text.distance(from: text.startIndex, to: whole.upperBound))
            // Leave a `@name` that is already a link or sits inside an inline
            // code span (e.g. a PR title's `@retroactive`) untouched.
            let target = output[lower..<upper]
            let isCode = target.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true }
            if !isCode, target.runs.allSatisfy({ $0.link == nil }) {
                output[lower..<upper].link = url
            }
        }
        return output
    }

    /// Trim leading/trailing whitespace — including the newlines Markdown leaves
    /// at block edges — without disturbing inline attributes on the interior.
    private static func trimmingWhitespace(_ value: AttributedString) -> AttributedString {
        var value = value
        while let first = value.characters.first, first.isWhitespace {
            value.removeSubrange(value.startIndex ..< value.characters.index(after: value.startIndex))
        }
        while let last = value.characters.last, last.isWhitespace {
            value.removeSubrange(value.characters.index(before: value.endIndex) ..< value.endIndex)
        }
        return value
    }
}
