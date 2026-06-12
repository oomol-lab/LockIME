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
            RuleResolver.resolve(config: config, frontmostBundleID: "com.apple.Safari", urlMatch: pinyin)
                == .lock(pinyin, .urlRule)
        )
    }
}
