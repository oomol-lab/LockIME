import Foundation
import Testing

@testable import LockIMEKit

@Suite("LockConfiguration model")
struct LockConfigurationTests {
    @Test("AppRuleMode.id is its raw value for every case")
    func appRuleModeID() {
        for mode in AppRuleMode.allCases {
            #expect(mode.id == mode.rawValue)
        }
        #expect(AppRuleMode.locked.id == "locked")
        #expect(AppRuleMode.ignored.id == "ignored")
        #expect(AppRuleMode.useDefault.id == "useDefault")
    }

    @Test("AppRule.id is its bundle identifier")
    func appRuleID() {
        let rule = AppRule(bundleID: "com.apple.Terminal", mode: .locked, lockedSourceID: "com.apple.keylayout.ABC")
        #expect(rule.id == "com.apple.Terminal")
    }

    @Test("URLRule.id defaults to a fresh UUID and is preserved when given")
    func urlRuleID() {
        let explicit = UUID()
        let pinned = URLRule(id: explicit, hostPattern: "github.com", lockedSourceID: "x")
        #expect(pinned.id == explicit)

        // Two default-constructed rules get distinct identities.
        let a = URLRule(hostPattern: "a.com", lockedSourceID: "x")
        let b = URLRule(hostPattern: "a.com", lockedSourceID: "x")
        #expect(a.id != b.id)
    }

    @Test("rule(for:) returns the matching app rule or nil")
    func ruleLookup() {
        let config = LockConfiguration(appRules: [
            AppRule(bundleID: "com.apple.Terminal", mode: .locked, lockedSourceID: "com.apple.keylayout.ABC"),
            AppRule(bundleID: "com.game.App", mode: .ignored),
        ])
        #expect(config.rule(for: "com.apple.Terminal")?.mode == .locked)
        #expect(config.rule(for: "com.game.App")?.mode == .ignored)
        #expect(config.rule(for: "com.absent.App") == nil)
    }

    @Test("decoding an empty object falls back to every default")
    func decodesEmptyToDefaults() throws {
        let config = try JSONDecoder().decode(LockConfiguration.self, from: Data("{}".utf8))
        #expect(config == LockConfiguration.default)
        #expect(config.isEnabled == false)
        #expect(config.defaultSourceID == nil)
        #expect(config.appRules.isEmpty)
        #expect(config.enhancedModeEnabled == false)
        #expect(config.urlRules.isEmpty)
    }

    @Test("decoding a partial object keeps present keys and defaults the rest")
    func decodesPartial() throws {
        let json = #"{"isEnabled": true, "defaultSourceID": "com.apple.keylayout.US"}"#
        let config = try JSONDecoder().decode(LockConfiguration.self, from: Data(json.utf8))
        #expect(config.isEnabled == true)
        #expect(config.defaultSourceID == "com.apple.keylayout.US")
        // Absent keys still fall back to their defaults.
        #expect(config.appRules.isEmpty)
        #expect(config.enhancedModeEnabled == false)
        #expect(config.urlRules.isEmpty)
    }

    @Test("a fully-specified configuration round-trips through Codable")
    func roundTrips() throws {
        let original = LockConfiguration(
            isEnabled: true,
            defaultSourceID: "com.apple.keylayout.US",
            appRules: [AppRule(bundleID: "com.apple.Terminal", mode: .locked, lockedSourceID: "com.apple.keylayout.ABC")],
            enhancedModeEnabled: true,
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: "com.apple.inputmethod.SCIM.ITABC")]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LockConfiguration.self, from: data)
        #expect(decoded == original)
    }
}
