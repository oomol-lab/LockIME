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

    // TODO(legacy-locking-migration): delete this test together with the
    // decode shim in LockConfiguration.init(from:).
    @Test("a legacy lockingEnabled=false migrates to a cleared global default")
    func legacyLockingOffClearsGlobalDefault() throws {
        // ≤1.5 shipped an "Enable locking" sub-toggle; off disabled every
        // continuous lock. The single-switch model expresses the global part as
        // a default of None, so the legacy key migrates there instead of
        // silently re-engaging the *global* lock on upgrade. Rule-level locks
        // (`.locked` app rules, `.lock` URL/address-bar rules) are deliberately
        // NOT demoted: rules now mean what they say, and rewriting the user's
        // rule modes on a heuristic would be more destructive than re-engaging
        // the locks they explicitly configured.
        let json = #"{"isEnabled": true, "lockingEnabled": false, "defaultSourceID": "com.apple.keylayout.US"}"#
        let config = try JSONDecoder().decode(LockConfiguration.self, from: Data(json.utf8))
        #expect(config.isEnabled == true)
        #expect(config.defaultSourceID == nil)
    }

    // TODO(legacy-locking-migration): delete this test together with the
    // decode shim in LockConfiguration.init(from:).
    @Test("a legacy lockingEnabled=true decodes with its global default intact")
    func legacyLockingOnKeepsGlobalDefault() throws {
        let json = #"{"isEnabled": true, "lockingEnabled": true, "defaultSourceID": "com.apple.keylayout.US"}"#
        let config = try JSONDecoder().decode(LockConfiguration.self, from: Data(json.utf8))
        #expect(config.defaultSourceID == "com.apple.keylayout.US")
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
        // The same lenient path applies to the newer matchType key: a legacy URL
        // rule that predates match types decodes to the original suffix behavior.
        #expect(config.urlRules.allSatisfy { $0.matchType == .domainSuffix })
        #expect(config.rule(for: "com.a")?.mode == .locked)
    }

    // The forward-compat sibling of the above: a config written by a *newer* build
    // can carry enum values this build doesn't know (a new matchType/action/mode
    // case), e.g. after a downgrade. A non-lenient decoder would throw on the
    // unknown value, propagate through the array decode, and silently wipe the
    // ENTIRE config to `.default`. Each unknown value must instead degrade to its
    // safe default while every other rule survives.
    @Test("unknown enum values degrade to defaults instead of wiping the config")
    func decodesUnknownEnumValuesLeniently() throws {
        let json = """
        {"isEnabled": true, "defaultSourceID": "com.apple.keylayout.US",
         "appRules": [
            {"bundleID": "com.a", "mode": "teleport", "lockedSourceID": "com.apple.keylayout.ABC"},
            {"bundleID": "com.b", "mode": "ignored"}
         ],
         "enhancedModeEnabled": true,
         "urlRules": [
            {"id": "\(UUID().uuidString)", "hostPattern": "github.com", "lockedSourceID": "com.apple.keylayout.ABC", "action": "warp", "matchType": "telepathy"},
            {"id": "\(UUID().uuidString)", "hostPattern": "example.com", "lockedSourceID": "com.apple.keylayout.US", "action": "switchOnce", "matchType": "domain"}
         ]}
        """
        let config = try JSONDecoder().decode(LockConfiguration.self, from: Data(json.utf8))
        // Nothing dropped: the unknown values did not abort the whole decode.
        #expect(config.appRules.count == 2)
        #expect(config.urlRules.count == 2)
        #expect(config.defaultSourceID == "com.apple.keylayout.US")
        // Unknown values degrade to their defaults…
        #expect(config.rule(for: "com.a")?.mode == .locked)
        let gh = try #require(config.urlRules.first { $0.hostPattern == "github.com" })
        #expect(gh.action == .lock)
        #expect(gh.matchType == .domainSuffix)
        // …while a rule with all-known values is unaffected.
        let ex = try #require(config.urlRules.first { $0.hostPattern == "example.com" })
        #expect(ex.action == .switchOnce)
        #expect(ex.matchType == .domain)
    }

    @Test("address-bar fields default off and round-trip through Codable")
    func addressBarRoundTrips() throws {
        // Defaults: off, switch action, no source, address bar outranks URL rules.
        let def = LockConfiguration.default
        #expect(def.addressBarFocusEnabled == false)
        #expect(def.addressBarAction == .switchOnce)
        #expect(def.addressBarSourceID == nil)
        #expect(def.addressBarOutranksURLRules == true)

        let original = LockConfiguration(
            isEnabled: true,
            defaultSourceID: "com.apple.keylayout.US",
            addressBarFocusEnabled: true,
            addressBarAction: .lock,
            addressBarSourceID: "com.apple.keylayout.ABC",
            addressBarOutranksURLRules: false // non-default, to prove it round-trips
        )
        let decoded = try JSONDecoder().decode(LockConfiguration.self, from: try JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.addressBarFocusEnabled)
        #expect(decoded.addressBarAction == .lock)
        #expect(decoded.addressBarSourceID == "com.apple.keylayout.ABC")
        #expect(decoded.addressBarOutranksURLRules == false)
    }

    @Test("a config predating the address-bar fields decodes to the off defaults")
    func decodesLegacyWithoutAddressBarFields() throws {
        let json = #"{"isEnabled": true, "defaultSourceID": "com.apple.keylayout.US", "enhancedModeEnabled": true}"#
        let config = try JSONDecoder().decode(LockConfiguration.self, from: Data(json.utf8))
        #expect(config.addressBarFocusEnabled == false)
        #expect(config.addressBarAction == .switchOnce)
        #expect(config.addressBarSourceID == nil)
        // A config predating this field defaults to the new address-bar-first behavior.
        #expect(config.addressBarOutranksURLRules == true)
    }

    @Test("an unknown address-bar action degrades to switchOnce instead of throwing")
    func decodesUnknownAddressBarAction() throws {
        // A newer build could write an action this one doesn't know; it must
        // degrade rather than abort the whole config decode.
        let json = #"{"addressBarFocusEnabled": true, "addressBarAction": "teleport", "addressBarSourceID": "com.apple.keylayout.ABC"}"#
        let config = try JSONDecoder().decode(LockConfiguration.self, from: Data(json.utf8))
        #expect(config.addressBarFocusEnabled)
        #expect(config.addressBarAction == .switchOnce)
        #expect(config.addressBarSourceID == "com.apple.keylayout.ABC")
    }

    @Test("URLMatchType.id is its raw value (the stable persisted token)")
    func urlMatchTypeID() {
        #expect(URLMatchType.domainSuffix.rawValue == "domain-suffix")
        #expect(URLMatchType.domain.rawValue == "domain")
        #expect(URLMatchType.domainKeyword.rawValue == "domain-keyword")
        #expect(URLMatchType.urlRegex.rawValue == "url-regex")
        #expect(URLMatchType.allCases.allSatisfy { $0.id == $0.rawValue })
    }

    @Test("a configuration with non-default match types round-trips through Codable")
    func roundTripsMatchType() throws {
        let original = LockConfiguration(
            enhancedModeEnabled: true,
            urlRules: [
                URLRule(hostPattern: "github.com", lockedSourceID: "x", matchType: .domain),
                URLRule(hostPattern: "google", lockedSourceID: "y", matchType: .domainKeyword),
                URLRule(hostPattern: "/pull/", lockedSourceID: "z", action: .switchOnce, matchType: .urlRegex),
            ]
        )
        let decoded = try JSONDecoder().decode(LockConfiguration.self, from: try JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.urlRules.map(\.matchType) == [.domain, .domainKeyword, .urlRegex])
    }
}
