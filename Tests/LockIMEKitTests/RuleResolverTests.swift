import Foundation
import Testing

@testable import LockIMEKit

@Suite("RuleResolver")
struct RuleResolverTests {
    private let us: InputSourceID = "com.apple.keylayout.US"
    private let abc: InputSourceID = "com.apple.keylayout.ABC"
    private let pinyin: InputSourceID = "com.apple.inputmethod.SCIM.ITABC"

    @Test("global default applies when no app rule matches")
    func globalDefault() {
        let config = LockConfiguration(isEnabled: true, defaultSourceID: us, appRules: [])
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.foo.Bar") == .lock(us, .globalDefault))
    }

    @Test("a switch-action global default yields a one-shot switch")
    func globalDefaultSwitch() {
        let config = LockConfiguration(
            isEnabled: true, defaultSourceID: us, defaultAction: .switchOnce, appRules: []
        )
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.foo.Bar") == .switchOnce(us, .globalDefault))
        // No frontmost app still resolves against the default.
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: nil) == .switchOnce(us, .globalDefault))
    }

    @Test("the default action defaults to lock (backward compatible)")
    func globalDefaultActionDefaultsToLock() {
        // Constructed without specifying defaultAction → the original lock behavior.
        let config = LockConfiguration(isEnabled: true, defaultSourceID: us)
        #expect(config.defaultAction == .lock)
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.foo.Bar") == .lock(us, .globalDefault))
    }

    @Test("a useDefault app rule honors the default's switch action")
    func useDefaultRuleHonorsSwitchDefault() {
        let config = LockConfiguration(
            isEnabled: true, defaultSourceID: us, defaultAction: .switchOnce,
            appRules: [AppRule(bundleID: "com.foo.App", mode: .useDefault)]
        )
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.foo.App") == .switchOnce(us, .globalDefault))
    }

    @Test("a sourceless locked/switched app rule falls through, honoring the switch default")
    func sourcelessRuleFallsThroughToSwitchDefault() {
        // A `.locked` rule with no source set falls through to the switch default.
        let lockedFallthrough = LockConfiguration(
            isEnabled: true, defaultSourceID: us, defaultAction: .switchOnce,
            appRules: [AppRule(bundleID: "com.foo.App", mode: .locked, lockedSourceID: nil)]
        )
        #expect(RuleResolver.resolve(config: lockedFallthrough, frontmostBundleID: "com.foo.App") == .switchOnce(us, .globalDefault))
        // Likewise a `.switched` rule with no source set.
        let switchedFallthrough = LockConfiguration(
            isEnabled: true, defaultSourceID: us, defaultAction: .switchOnce,
            appRules: [AppRule(bundleID: "com.foo.App", mode: .switched, lockedSourceID: nil)]
        )
        #expect(RuleResolver.resolve(config: switchedFallthrough, frontmostBundleID: "com.foo.App") == .switchOnce(us, .globalDefault))
    }

    @Test("an explicit app rule still overrides a switch-action global default")
    func appRuleOverridesSwitchDefault() {
        let config = LockConfiguration(
            isEnabled: true, defaultSourceID: us, defaultAction: .switchOnce,
            appRules: [AppRule(bundleID: "com.apple.Terminal", mode: .locked, lockedSourceID: abc)]
        )
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.apple.Terminal") == .lock(abc, .appRule))
        // A different app takes the switch default.
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.other.App") == .switchOnce(us, .globalDefault))
    }

    @Test("no default and no rule yields noTarget")
    func noTarget() {
        let config = LockConfiguration(isEnabled: true, defaultSourceID: nil, appRules: [])
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.foo.Bar") == .noTarget)
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: nil) == .noTarget)
    }

    @Test("a locked app rule overrides the global default")
    func appRuleOverridesDefault() {
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.apple.Terminal", mode: .locked, lockedSourceID: abc)]
        )
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.apple.Terminal") == .lock(abc, .appRule))
        // a different app still uses the default
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.other.App") == .lock(us, .globalDefault))
    }

    @Test("an ignored app rule disables locking for that app")
    func ignoredApp() {
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.game.App", mode: .ignored)]
        )
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.game.App") == .ignore)
    }

    @Test("useDefault rule falls back to the global default")
    func useDefaultRule() {
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.foo.App", mode: .useDefault)]
        )
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.foo.App") == .lock(us, .globalDefault))
    }

    @Test("locked rule with no source set falls back to the default")
    func lockedWithoutSourceFallsBack() {
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.foo.App", mode: .locked, lockedSourceID: nil)]
        )
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.foo.App") == .lock(us, .globalDefault))
    }

    @Test("an enhanced URL match wins over everything")
    func urlMatchWins() {
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.apple.Safari", mode: .locked, lockedSourceID: abc)]
        )
        #expect(
            RuleResolver.resolve(config: config, frontmostBundleID: "com.apple.Safari", urlMatch: (pinyin, .lock))
                == .lock(pinyin, .urlRule)
        )
        // A switch-action URL match yields a one-shot switch, still outranking the app lock.
        #expect(
            RuleResolver.resolve(config: config, frontmostBundleID: "com.apple.Safari", urlMatch: (pinyin, .switchOnce))
                == .switchOnce(pinyin, .urlRule)
        )
    }

    @Test("a switched app rule yields a one-shot switch")
    func switchedAppRule() {
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.apple.Terminal", mode: .switched, lockedSourceID: abc)]
        )
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.apple.Terminal") == .switchOnce(abc, .appRule))
        // A different app still uses the (lock-only) global default.
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.other.App") == .lock(us, .globalDefault))
    }

    @Test("a switched rule with no source set falls back to the default lock")
    func switchedWithoutSourceFallsBack() {
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.foo.App", mode: .switched, lockedSourceID: nil)]
        )
        #expect(RuleResolver.resolve(config: config, frontmostBundleID: "com.foo.App") == .lock(us, .globalDefault))
    }

    // MARK: - Address-bar focus rule

    @Test("address-bar focus locks its source over the app/default rule")
    func addressBarLocks() {
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.apple.Safari", mode: .locked, lockedSourceID: pinyin)],
            addressBarFocusEnabled: true,
            addressBarAction: .lock,
            addressBarSourceID: abc
        )
        #expect(
            RuleResolver.resolve(config: config, frontmostBundleID: "com.apple.Safari", addressBarFocused: true)
                == .lock(abc, .addressBarRule)
        )
        // Not focused → the app rule applies as usual.
        #expect(
            RuleResolver.resolve(config: config, frontmostBundleID: "com.apple.Safari", addressBarFocused: false)
                == .lock(pinyin, .appRule)
        )
    }

    @Test("address-bar focus with the switch action yields a one-shot switch")
    func addressBarSwitches() {
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            addressBarFocusEnabled: true,
            addressBarAction: .switchOnce,
            addressBarSourceID: abc
        )
        #expect(
            RuleResolver.resolve(config: config, frontmostBundleID: "com.apple.Safari", addressBarFocused: true)
                == .switchOnce(abc, .addressBarRule)
        )
    }

    @Test("by default the address bar outranks a URL rule; URL-first is an opt-out")
    func addressBarOutranksByDefault() {
        // New default: addressBarOutranksURLRules == true → the address bar wins
        // when both apply.
        let def = LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            addressBarFocusEnabled: true,
            addressBarAction: .lock,
            addressBarSourceID: abc
        )
        #expect(def.addressBarOutranksURLRules == true)
        #expect(
            RuleResolver.resolve(
                config: def, frontmostBundleID: "com.apple.Safari",
                urlMatch: (pinyin, .lock), addressBarFocused: true
            ) == .lock(abc, .addressBarRule)
        )

        // Opt out → URL rules win when the user flips the flag.
        var urlFirst = def
        urlFirst.addressBarOutranksURLRules = false
        #expect(
            RuleResolver.resolve(
                config: urlFirst, frontmostBundleID: "com.apple.Safari",
                urlMatch: (pinyin, .lock), addressBarFocused: true
            ) == .lock(pinyin, .urlRule)
        )
    }

    @Test("the priority flag only matters when the address bar is actually focused")
    func priorityOnlyWhenFocused() {
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            addressBarFocusEnabled: true,
            addressBarAction: .lock,
            addressBarSourceID: abc
            // addressBarOutranksURLRules defaults to true
        )
        // Bar not focused → the URL rule applies regardless of the priority flag.
        #expect(
            RuleResolver.resolve(
                config: config, frontmostBundleID: "com.apple.Safari",
                urlMatch: (pinyin, .lock), addressBarFocused: false
            ) == .lock(pinyin, .urlRule)
        )
        // No URL match, bar focused → the address bar applies.
        #expect(
            RuleResolver.resolve(config: config, frontmostBundleID: "com.apple.Safari", addressBarFocused: true)
                == .lock(abc, .addressBarRule)
        )
    }

    @Test("the winner's switch action is preserved when both browser-scoped rules apply")
    func switchActionPreservedForWinner() {
        // URL-first order (opt-out): a switch-action URL rule wins as a one-shot,
        // even though the address-bar rule is a lock.
        let urlFirst = LockConfiguration(
            isEnabled: true, defaultSourceID: us,
            addressBarFocusEnabled: true, addressBarAction: .lock, addressBarSourceID: abc,
            addressBarOutranksURLRules: false
        )
        #expect(
            RuleResolver.resolve(
                config: urlFirst, frontmostBundleID: "com.apple.Safari",
                urlMatch: (pinyin, .switchOnce), addressBarFocused: true
            ) == .switchOnce(pinyin, .urlRule)
        )

        // Address-bar first: a switch-action address-bar rule wins as a one-shot,
        // even though the URL rule is a lock.
        let barFirst = LockConfiguration(
            isEnabled: true, defaultSourceID: us,
            addressBarFocusEnabled: true, addressBarAction: .switchOnce, addressBarSourceID: abc,
            addressBarOutranksURLRules: true
        )
        #expect(
            RuleResolver.resolve(
                config: barFirst, frontmostBundleID: "com.apple.Safari",
                urlMatch: (pinyin, .lock), addressBarFocused: true
            ) == .switchOnce(abc, .addressBarRule)
        )
    }

    @Test("the address-bar rule is inert when disabled or unconfigured")
    func addressBarInertWhenOffOrUnset() {
        // Disabled → falls through to the default.
        let off = LockConfiguration(
            isEnabled: true, defaultSourceID: us,
            addressBarFocusEnabled: false, addressBarAction: .lock, addressBarSourceID: abc
        )
        #expect(RuleResolver.resolve(config: off, frontmostBundleID: "com.apple.Safari", addressBarFocused: true) == .lock(us, .globalDefault))

        // Enabled but no source set → falls through (never acts inert).
        let noSource = LockConfiguration(
            isEnabled: true, defaultSourceID: us,
            addressBarFocusEnabled: true, addressBarAction: .lock, addressBarSourceID: nil
        )
        #expect(RuleResolver.resolve(config: noSource, frontmostBundleID: "com.apple.Safari", addressBarFocused: true) == .lock(us, .globalDefault))
    }
}
