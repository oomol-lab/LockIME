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
        #expect(AppRuleMode.switched.id == "switched")
        #expect(AppRuleMode.ignored.id == "ignored")
        #expect(AppRuleMode.useDefault.id == "useDefault")
    }

    @Test("only .locked and .switched pin a source")
    func appRuleModePinsSource() {
        #expect(AppRuleMode.locked.pinsSource)
        #expect(AppRuleMode.switched.pinsSource)
        #expect(!AppRuleMode.ignored.pinsSource)
        #expect(!AppRuleMode.useDefault.pinsSource)
    }

    @Test("RuleAction.id is its raw value")
    func ruleActionID() {
        #expect(RuleAction.lock.id == "lock")
        #expect(RuleAction.switchOnce.id == "switchOnce")
        #expect(RuleAction.allCases.allSatisfy { $0.id == $0.rawValue })
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

    @Test("a configuration with switch rules round-trips through Codable")
    func roundTripsSwitch() throws {
        let original = LockConfiguration(
            isEnabled: true,
            defaultSourceID: "com.apple.keylayout.US",
            appRules: [
                AppRule(bundleID: "com.apple.Terminal", mode: .switched, lockedSourceID: "com.apple.keylayout.ABC"),
                AppRule(bundleID: "com.apple.Safari", mode: .locked, lockedSourceID: "com.apple.keylayout.US"),
            ],
            enhancedModeEnabled: true,
            urlRules: [
                URLRule(hostPattern: "github.com", lockedSourceID: "com.apple.inputmethod.SCIM.ITABC", action: .switchOnce),
                URLRule(hostPattern: "example.com", lockedSourceID: "com.apple.keylayout.US", action: .lock),
            ]
        )
        let decoded = try JSONDecoder().decode(LockConfiguration.self, from: try JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.rule(for: "com.apple.Terminal")?.mode == .switched)
        #expect(decoded.urlRules.first(where: { $0.hostPattern == "github.com" })?.action == .switchOnce)
    }

    // The killer back-compat path: a v1.x LockConfiguration blob whose appRules /
    // urlRules ARRAYS contain elements with NO `action` key. `init(from:)` decodes
    // each array with `decodeIfPresent`, which *propagates* a per-element throw —
    // so without the lenient URLRule decoder a single legacy URL rule would abort
    // the whole load and silently drop every rule (see RuleStore's `try?`).
    @Test("legacy config whose rule arrays omit action decodes every rule as .lock")
    func decodesLegacyArraysWithoutAction() throws {
        let json = """
        {"isEnabled": true, "defaultSourceID": "com.apple.keylayout.US",
         "appRules": [
            {"bundleID": "com.a", "mode": "locked", "lockedSourceID": "com.apple.keylayout.ABC"},
            {"bundleID": "com.b", "mode": "ignored"}
         ],
         "enhancedModeEnabled": true,
         "urlRules": [
            {"id": "\(UUID().uuidString)", "hostPattern": "github.com", "lockedSourceID": "com.apple.keylayout.ABC"},
            {"id": "\(UUID().uuidString)", "hostPattern": "example.com", "lockedSourceID": "com.apple.keylayout.US"}
         ]}
        """
        let config = try JSONDecoder().decode(LockConfiguration.self, from: Data(json.utf8))
        #expect(config.appRules.count == 2)            // nothing dropped
        #expect(config.urlRules.count == 2)            // nothing dropped
        #expect(config.urlRules.allSatisfy { $0.action == .lock })
        #expect(config.rule(for: "com.a")?.mode == .locked)
    }
}
