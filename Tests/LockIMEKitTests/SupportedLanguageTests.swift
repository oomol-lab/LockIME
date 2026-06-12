import Testing

@testable import LockIMEKit

@Suite("SupportedLanguage.resolve")
struct SupportedLanguageTests {
    @Test("exact and language-only matches", arguments: [
        ("en", SupportedLanguage.english),
        ("en-US", .english),
        ("ja", .japanese),
        ("ja-JP", .japanese),
        ("fr-CA", .french),
        ("de-DE", .german),
        ("es-419", .spanish),
        ("pt-BR", .portuguese),
        ("ru-RU", .russian),
    ])
    func basic(code: String, expected: SupportedLanguage) {
        #expect(SupportedLanguage.resolve(preferredLanguages: [code]) == expected)
    }

    @Test("Chinese script inference", arguments: [
        ("zh-Hans", SupportedLanguage.simplifiedChinese),
        ("zh-Hans-CN", .simplifiedChinese),
        ("zh-CN", .simplifiedChinese),
        ("zh-SG", .simplifiedChinese),
        ("zh-Hant", .traditionalChinese),
        ("zh-Hant-TW", .traditionalChinese),
        ("zh-TW", .traditionalChinese),
        ("zh-HK", .traditionalChinese),
        ("zh-MO", .traditionalChinese),
    ])
    func chinese(code: String, expected: SupportedLanguage) {
        #expect(SupportedLanguage.resolve(preferredLanguages: [code]) == expected)
    }

    @Test("falls back to English for unsupported languages")
    func fallback() {
        #expect(SupportedLanguage.resolve(preferredLanguages: ["ko", "ar", "th"]) == .english)
        #expect(SupportedLanguage.resolve(preferredLanguages: []) == .english)
    }

    @Test("picks the first supported language in preference order")
    func order() {
        #expect(SupportedLanguage.resolve(preferredLanguages: ["ko", "ja", "en"]) == .japanese)
        #expect(SupportedLanguage.resolve(preferredLanguages: ["ar", "fr-FR", "de"]) == .french)
    }

    @Test("preferredLocalization matches regional variants in third-party bundles")
    func preferredLocalization() {
        // The lproj list KeyboardShortcuts ships — regional names, not ours.
        let available = [
            "ar", "cs", "de", "en", "es", "fr", "hu", "ja", "ko", "nl",
            "pt-BR", "ru", "sk", "zh-Hans", "zh-TW",
        ]
        #expect(SupportedLanguage.english.preferredLocalization(from: available) == "en")
        #expect(SupportedLanguage.simplifiedChinese.preferredLocalization(from: available) == "zh-Hans")
        #expect(SupportedLanguage.traditionalChinese.preferredLocalization(from: available) == "zh-TW")
        #expect(SupportedLanguage.portuguese.preferredLocalization(from: available) == "pt-BR")
        #expect(SupportedLanguage.japanese.preferredLocalization(from: ["ja-JP"]) == "ja-JP")
        #expect(SupportedLanguage.russian.preferredLocalization(from: ["en", "de"]) == nil)
    }
}

@Suite("SupportedLanguage identity & endonyms")
struct SupportedLanguageIdentityTests {
    @Test("id and localeIdentifier are the raw locale code")
    func identifiers() {
        for language in SupportedLanguage.allCases {
            #expect(language.id == language.rawValue)
            #expect(language.localeIdentifier == language.rawValue)
        }
    }

    @Test("nativeName is the language's own endonym", arguments: [
        (SupportedLanguage.english, "English"),
        (.simplifiedChinese, "简体中文"),
        (.traditionalChinese, "繁體中文"),
        (.japanese, "日本語"),
        (.french, "Français"),
        (.german, "Deutsch"),
        (.spanish, "Español"),
        (.portuguese, "Português"),
        (.russian, "Русский"),
    ])
    func nativeName(language: SupportedLanguage, expected: String) {
        #expect(language.nativeName == expected)
    }

    @Test("every case has a distinct, non-empty endonym")
    func endonymsAreDistinct() {
        let names = SupportedLanguage.allCases.map(\.nativeName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }
}
