import Foundation
import Testing

@testable import LockIMEKit

@Suite("ReleaseNotes markdown parsing")
struct ReleaseNotesTests {
    @Test("empty or whitespace-only input yields no blocks")
    func emptyInput() {
        #expect(ReleaseNotes.blocks(fromMarkdown: "").isEmpty)
        #expect(ReleaseNotes.blocks(fromMarkdown: "   \n\n\t").isEmpty)
    }

    @Test("an H2 heading parses with its level and trimmed text")
    func heading() throws {
        let blocks = ReleaseNotes.blocks(fromMarkdown: "## What's Changed")
        #expect(blocks.count == 1)
        guard case .heading(let level, let text) = try #require(blocks.first) else {
            Issue.record("expected a heading, got \(String(describing: blocks.first))")
            return
        }
        #expect(level == 2)
        #expect(String(text.characters) == "What's Changed")
    }

    @Test("an unordered list becomes one listItem per bullet")
    func unorderedList() {
        let blocks = ReleaseNotes.blocks(fromMarkdown: "* one\n* two\n* three")
        #expect(blocks.count == 3)
        #expect(blocks.allSatisfy { if case .listItem = $0 { true } else { false } })
        if case .listItem(let first) = blocks.first {
            #expect(String(first.characters) == "one")
        }
    }

    @Test("inline bold and links survive on the block's text")
    func inlineFormatting() throws {
        let blocks = ReleaseNotes.blocks(fromMarkdown: "**bold** then <https://example.com>")
        guard case .paragraph(let text) = try #require(blocks.first) else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(text.runs.contains { $0.link != nil })
    }

    @Test("real GitHub-generated notes → heading + bullets + closing paragraph")
    func realWorldSample() throws {
        let notes = """
        ## What's Changed
        * test: add CI-safe coverage by @octocat in https://github.com/o/r/pull/10
        * feat: detect overlays by @octocat in https://github.com/o/r/pull/11

        **Full Changelog**: https://github.com/o/r/compare/v1.2.1...v1.2.2
        """
        let blocks = ReleaseNotes.blocks(fromMarkdown: notes)
        #expect(blocks.count == 4)
        guard case .heading(2, _) = blocks[0] else {
            Issue.record("block 0 should be an H2 heading")
            return
        }
        #expect({ if case .listItem = blocks[1] { true } else { false } }())
        #expect({ if case .listItem = blocks[2] { true } else { false } }())
        guard case .paragraph(let last) = blocks[3] else {
            Issue.record("block 3 should be the Full Changelog paragraph")
            return
        }
        // The bare compare URL is auto-linked, and "Full Changelog" is bold.
        #expect(last.runs.contains { $0.link != nil })
        #expect(last.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    @Test("block kinds outside the generated subset degrade to readable text")
    func gracefulDegradation() {
        // A fenced code block never appears in generated notes; it must still
        // surface its contents rather than vanish or crash.
        let markdown = """
        ## Heading
        ```
        let answer = 42
        ```
        """
        let blocks = ReleaseNotes.blocks(fromMarkdown: markdown)
        #expect(!blocks.isEmpty)
        let everything = blocks.map { block -> String in
            switch block {
            case .heading(_, let text), .listItem(let text), .paragraph(let text):
                String(text.characters)
            }
        }.joined(separator: "\n")
        #expect(everything.contains("let answer = 42"))
    }

    @Test("@mentions link to the GitHub profile, keeping the @name text")
    func mentionsLinkified() throws {
        let blocks = ReleaseNotes.blocks(fromMarkdown: "* fix by @BlackHole1 in https://github.com/o/r/pull/10")
        guard case .listItem(let text) = try #require(blocks.first) else {
            Issue.record("expected a list item")
            return
        }
        let mention = try #require(text.runs.first { $0.link?.absoluteString == "https://github.com/BlackHole1" })
        #expect(String(text[mention.range].characters) == "@BlackHole1")
    }

    @Test("PR and compare URLs shrink to #N / the ref range, keeping the link")
    func compactGitHubLinks() throws {
        let pr = ReleaseNotes.blocks(fromMarkdown: "* landed in https://github.com/o/r/pull/42")
        guard case .listItem(let prText) = try #require(pr.first) else {
            Issue.record("expected a list item")
            return
        }
        #expect(String(prText.characters).contains("#42"))
        #expect(!String(prText.characters).contains("/pull/42"))
        #expect(prText.runs.contains { $0.link?.absoluteString == "https://github.com/o/r/pull/42" })

        let cmp = ReleaseNotes.blocks(fromMarkdown: "**Full Changelog**: https://github.com/o/r/compare/v1.2.1...v1.2.2")
        guard case .paragraph(let cmpText) = try #require(cmp.first) else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(String(cmpText.characters).contains("v1.2.1...v1.2.2"))
        #expect(!String(cmpText.characters).contains("/compare/"))
        #expect(cmpText.runs.contains { $0.link?.absoluteString.contains("/compare/") == true })
    }

    @Test("an email local part is not mistaken for an @mention")
    func emailIsNotAMention() throws {
        let blocks = ReleaseNotes.blocks(fromMarkdown: "reach me at someone@example.com today")
        guard case .paragraph(let text) = try #require(blocks.first) else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(!text.runs.contains { $0.link?.absoluteString == "https://github.com/example" })
    }

    @Test("a @name inside an inline code span is left literal, not linkified")
    func mentionInsideCodeNotLinkified() throws {
        let blocks = ReleaseNotes.blocks(fromMarkdown: "handle the `@retroactive` attribute")
        guard case .paragraph(let text) = try #require(blocks.first) else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(!text.runs.contains { $0.link?.absoluteString == "https://github.com/retroactive" })
    }
}
