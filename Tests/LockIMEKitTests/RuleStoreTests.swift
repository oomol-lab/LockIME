import Foundation
import Testing

@testable import LockIMEKit

@Suite("RuleStore")
struct RuleStoreTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "lockime.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("missing data loads the default configuration")
    func loadsDefault() {
        let store = RuleStore(defaults: freshDefaults())
        #expect(store.load() == LockConfiguration.default)
    }

    @Test("save then load round-trips the configuration")
    func roundTrip() {
        let store = RuleStore(defaults: freshDefaults())
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: "com.apple.keylayout.US",
            appRules: [
                AppRule(bundleID: "com.apple.Terminal", mode: .locked, lockedSourceID: "com.apple.keylayout.ABC"),
                AppRule(bundleID: "com.switch.App", mode: .switched, lockedSourceID: "com.apple.keylayout.US"),
                AppRule(bundleID: "com.game.App", mode: .ignored),
                AppRule(bundleID: "com.foo.App", mode: .useDefault),
            ],
            enhancedModeEnabled: true,
            urlRules: [
                URLRule(hostPattern: "github.com", lockedSourceID: "com.apple.keylayout.ABC", action: .switchOnce),
                URLRule(hostPattern: "example.com", lockedSourceID: "com.apple.keylayout.US", action: .lock),
            ]
        )
        store.save(config)
        #expect(store.load() == config)
    }

    // The single most important back-compat test: write v1.x bytes (URL rules
    // with NO `action` key) straight into UserDefaults, bypassing save(), and
    // assert load() returns the rules with `.lock` — NOT `.default`. Without the
    // lenient URLRule decoder, the per-element throw would propagate out of
    // `decodeIfPresent([URLRule])`, RuleStore.load()'s `try?` would swallow it,
    // and the upgrading user would silently lose EVERY rule.
    @Test("legacy v1.x bytes without a URL action load with .lock, never .default")
    func loadsLegacyBytesWithoutAction() {
        let defaults = freshDefaults()
        let store = RuleStore(defaults: defaults)
        let json = """
        {"isEnabled": true, "defaultSourceID": "com.apple.keylayout.US",
         "appRules": [{"bundleID": "com.a", "mode": "locked", "lockedSourceID": "com.apple.keylayout.ABC"}],
         "enhancedModeEnabled": true,
         "urlRules": [{"id": "\(UUID().uuidString)", "hostPattern": "github.com", "lockedSourceID": "com.apple.keylayout.ABC"}]}
        """
        defaults.set(Data(json.utf8), forKey: "lockConfiguration")
        let loaded = store.load()
        #expect(loaded != .default)                 // nothing was swallowed
        #expect(loaded.appRules.count == 1)
        #expect(loaded.urlRules.count == 1)
        #expect(loaded.urlRules.first?.action == .lock)
    }

    @Test("a later save overwrites an earlier one")
    func overwrite() {
        let defaults = freshDefaults()
        let store = RuleStore(defaults: defaults)
        store.save(LockConfiguration(isEnabled: true))
        store.save(LockConfiguration(isEnabled: false, defaultSourceID: "com.apple.keylayout.US"))
        let loaded = store.load()
        #expect(loaded.isEnabled == false)
        #expect(loaded.defaultSourceID == "com.apple.keylayout.US")
    }
}
