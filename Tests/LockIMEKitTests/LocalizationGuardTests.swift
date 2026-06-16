import Foundation
import Testing

@testable import LockIMEKit

/// Anchor for locating the test bundle's embedded resources.
private final class BundleToken {}

/// Repo-wide i18n guards.
///
/// The app renders in an in-app language override, so two failure classes only
/// ever show up at runtime, in a language the developer isn't running: strings
/// localized by *someone else's* bundle (e.g. Sparkle's
/// `error.localizedDescription`, which follows the system language) leaking
/// into UI, and catalog keys that are missing or only partially translated.
/// These tests scan the app sources and the string catalog instead of waiting
/// for a mixed-language screenshot. `LockIMEKit` itself is non-UI, so only
/// `Sources/LockIME` is scanned.
@Suite("Localization guards")
struct LocalizationGuardTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // LockIMEKitTests/
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent()

    private static let appSources = repoRoot.appending(path: "Sources/LockIME")
    private static let catalog = appSources.appending(path: "Localizable.xcstrings")

    private static func appSwiftFiles() throws -> [(name: String, text: String)] {
        let enumerator = try #require(
            FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil)
        )
        var files: [(String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        #expect(!files.isEmpty, "no Swift sources found under \(appSources.path)")
        return files
    }

    private static func catalogStrings() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: catalog)
        let doc = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(doc["strings"] as? [String: [String: Any]])
    }

    @Test("UI layer never displays system-localized error text")
    func noLocalizedDescriptionInAppLayer() throws {
        // `localizedDescription` resolves against the *system* language, not
        // the in-app override — display would mix languages. Map the error to
        // a catalog key instead (see `UpdateFailure`) and log the original.
        // A deliberate non-UI use can opt out with an `i18n-exempt` comment.
        for (name, text) in try Self.appSwiftFiles() {
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                // Comments may mention the API; only flag code.
                let code = line.prefix(upTo: line.firstRange(of: "//")?.lowerBound ?? line.endIndex)
                if code.contains("localizedDescription"), !line.contains("i18n-exempt") {
                    Issue.record(
                        "\(name):\(index + 1) uses localizedDescription — map the error to a catalog key (see UpdateFailure)"
                    )
                }
            }
        }
    }

    @Test("string catalog is fully translated for every supported language")
    func catalogIsComplete() throws {
        // English is the source language: its catalog entries are implicit
        // (the key *is* the string), so every other SupportedLanguage must
        // carry an explicit, finished translation.
        let required = SupportedLanguage.allCases.filter { $0 != .english }.map(\.localeIdentifier)
        for (key, entry) in try Self.catalogStrings() {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in required {
                guard let unit = localizations[language]?["stringUnit"] as? [String: Any],
                      unit["state"] as? String == "translated"
                else {
                    Issue.record("catalog key \"\(key)\" is missing a finished \(language) translation")
                    continue
                }
            }
        }
    }

    @Test("window titles are never bridged from a LocalizedStringKey")
    func noLiteralNavigationTitles() throws {
        // `.navigationTitle("Key")` looks localized, but when SwiftUI bridges
        // the title to the AppKit window it resolves the key against the
        // *system* language, not the injected `\.locale` — the title ends up
        // in a different language than the content. Pass a pre-resolved
        // string instead: `.navigationTitle(state.loc("Key"))`.
        for (name, text) in try Self.appSwiftFiles() {
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.prefix(upTo: line.firstRange(of: "//")?.lowerBound ?? line.endIndex)
                if code.contains(".navigationTitle(\""), !line.contains("i18n-exempt") {
                    Issue.record(
                        "\(name):\(index + 1) bridges a LocalizedStringKey into the window title — use .navigationTitle(state.loc(...))"
                    )
                }
            }
        }
    }

    @Test("KeyboardShortcuts recorder titles are never bare string literals")
    func recorderTitlesAreLocalized() throws {
        // `KeyboardShortcuts.Recorder` exposes both a `String` and a
        // `LocalizedStringKey` initializer. A bare string literal binds to the
        // `String` one (concrete literal default), which renders verbatim and
        // bypasses the app's language override — a mixed-language Shortcuts
        // pane. Force the localized overload with `LocalizedStringKey("…")`.
        for (name, text) in try Self.appSwiftFiles() {
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.prefix(upTo: line.firstRange(of: "//")?.lowerBound ?? line.endIndex)
                if code.contains(".Recorder(\""), !line.contains("i18n-exempt") {
                    Issue.record(
                        "\(name):\(index + 1) passes a bare string to KeyboardShortcuts.Recorder — wrap it in LocalizedStringKey(\"…\")"
                    )
                }
            }
        }
    }

    @Test("redirected third-party bundles exist and cover every supported language")
    func thirdPartyBundlesCoverAllLanguages() throws {
        // `ThirdPartyBundleLocalization` redirects each listed package
        // resource bundle to the in-app language. Both of its assumptions can
        // silently break on a package bump: the SPM bundle name
        // ("<package>_<target>") and the per-language `.lproj` coverage that
        // `preferredLocalization(from:)` resolves. The packages are also test
        // dependencies, so the very bundles the app ships are checked here.
        let source = try String(
            contentsOf: Self.appSources.appending(path: "Localization/ThirdPartyBundleLocalization.swift"),
            encoding: .utf8
        )
        let names = source.matches(of: try Regex<(Substring, Substring)>(#""([A-Za-z0-9]+_[A-Za-z0-9]+)""#))
            .map { String($0.1) }
        try #require(!names.isEmpty, "no redirected bundle names found in ThirdPartyBundleLocalization.swift")

        for name in names {
            guard let url = Bundle(for: BundleToken.self).url(forResource: name, withExtension: "bundle"),
                  let bundle = Bundle(url: url)
            else {
                Issue.record("resource bundle \"\(name)\" not found — SPM bundle renamed on a package bump?")
                continue
            }
            for language in SupportedLanguage.allCases
            where language.preferredLocalization(from: bundle.localizations) == nil {
                Issue.record(
                    "\(name).bundle ships no \(language.localeIdentifier) localization — its UI would fall back to English"
                )
            }
        }
    }

    @Test("keys resolved outside SwiftUI exist in the catalog")
    func dynamicKeysExistInCatalog() throws {
        // Keys that reach the catalog outside SwiftUI's literal extraction are
        // invisible to Xcode's string extractor — a typo silently falls back to
        // English. Three such entry points are scanned: `loc(...)` /
        // `AppKitStrings.string(...)` / `.help(...)` calls; `UpdateFailure`'s bare
        // full-line `messageKey` literals; and `LocalizedStringKey`-returning enum
        // `switch` arms (e.g. `URLMatchType.pickerLabel`/`helpText`, the import
        // sheet's mode/match-type labels). Every literal at those points must be a
        // real catalog key. A `case` arm that returns a non-localized identity
        // token (not a UI string) opts out with an `i18n-exempt` comment.
        let keys = Set(try Self.catalogStrings().keys)
        let callPattern = try Regex<(Substring, Substring)>(
            #"(?:\bloc\(|AppKitStrings\.string\(|\.help\()\s*"((?:[^"\\]|\\.)+)""#
        )
        let literalLinePattern = try Regex<(Substring, Substring)>(#"(?m)^\s*"((?:[^"\\]|\\.)+)"$"#)
        // A `case <patterns>: "literal"` line — the shape of a computed property
        // returning a `LocalizedStringKey` per enum case (the literal is the whole
        // arm body, so the line ends in the closing quote).
        let caseArmPattern = try Regex<(Substring, Substring)>(
            #"^\s*case\s+\.[^:"]*:\s*"((?:[^"\\]|\\.)+)"\s*$"#
        )

        for (name, text) in try Self.appSwiftFiles() {
            var referenced = text.matches(of: callPattern).map { String($0.1) }
            if name == "UpdateFailure.swift" {
                // `messageKey` returns bare full-line literals from a switch.
                referenced += text.matches(of: literalLinePattern).map { String($0.1) }
            }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false)
            where !line.contains("i18n-exempt") {
                if let match = String(line).firstMatch(of: caseArmPattern) {
                    referenced.append(String(match.1))
                }
            }
            for key in referenced where !keys.contains(key) {
                Issue.record("\(name) resolves \"\(key)\" but Localizable.xcstrings has no such key")
            }
        }
    }

    @Test("every .sheet re-injects the in-app locale override")
    func sheetsReinjectLocale() throws {
        // A `.sheet` (like `.navigationTitle`) bridges into its own AppKit window,
        // which resets `\.locale` to the *system* language — so a sheet whose
        // content uses string literals renders against the system locale, not the
        // app's in-app override, producing a half-translated screen. The fix is to
        // re-inject `.environment(\.locale, state.locale)` at the call site (see
        // BackupSettingsPane). This guards that every sheet does so — and that it
        // injects the app's *own* locale, not some other value: matching only
        // `.environment(\.locale` would pass `.environment(\.locale, .current)`,
        // which still bridges in the system language.
        let reinjection = try Regex(#"\.environment\(\s*\\\.locale\s*,\s*(?:appState|state)\.locale\s*\)"#)
        for (name, text) in try Self.appSwiftFiles() {
            let lines = Array(text.split(separator: "\n", omittingEmptySubsequences: false))
            for (index, line) in lines.enumerated() {
                // Skip comments (e.g. a doc comment mentioning `.sheet(...)`).
                let code = line.prefix(upTo: line.firstRange(of: "//")?.lowerBound ?? line.endIndex)
                guard code.contains(".sheet(") else { continue }
                // The re-injection lives inside the sheet's content closure, a few
                // lines down — scan a generous window, stripping each line's comment
                // so a commented-out modifier can't satisfy the guard.
                let window = lines[index..<min(index + 20, lines.count)].map { windowLine in
                    String(windowLine.prefix(upTo: windowLine.firstRange(of: "//")?.lowerBound ?? windowLine.endIndex))
                }.joined(separator: "\n")
                if window.firstMatch(of: reinjection) == nil {
                    Issue.record(
                        "\(name):\(index + 1) presents a .sheet without re-injecting \\.locale — add .environment(\\.locale, state.locale) so it follows the in-app language override (see BackupSettingsPane)"
                    )
                }
            }
        }
    }
}
