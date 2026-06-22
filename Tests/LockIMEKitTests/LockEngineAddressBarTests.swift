import Foundation
import Testing

@testable import LockIMEKit

@MainActor
@Suite("LockEngine address-bar rule")
struct LockEngineAddressBarTests {
    private let us: InputSourceID = "com.apple.keylayout.US"
    private let abc: InputSourceID = "com.apple.keylayout.ABC"
    private let pinyin: InputSourceID = "com.apple.inputmethod.SCIM.ITABC"
    private let safari = "com.apple.Safari"

    private func makeEngine(
        current: InputSourceID,
        frontmost: String?
    ) -> (LockEngine, MockInputSourceProvider, MockFrontmostMonitor, MockAddressBarMonitor) {
        let provider = MockInputSourceProvider(
            current: current,
            sources: [.stub(us.rawValue), .stub(abc.rawValue), .stub(pinyin.rawValue, cjkv: true)]
        )
        let monitor = MockFrontmostMonitor(bundleID: frontmost)
        let addressBar = MockAddressBarMonitor()
        let engine = LockEngine(provider: provider, appMonitor: monitor, addressBarMonitor: addressBar)
        engine.start()
        return (engine, provider, monitor, addressBar)
    }

    private func config(action: RuleAction, source: InputSourceID?, default def: InputSourceID? = nil, appRules: [AppRule] = []) -> LockConfiguration {
        LockConfiguration(
            isEnabled: true,
            defaultSourceID: def,
            appRules: appRules,
            addressBarFocusEnabled: true,
            addressBarAction: action,
            addressBarSourceID: source
        )
    }

    @Test("lock mode: focusing the address bar locks the source; blur falls back to the default")
    func lockModeFocusAndBlur() {
        let (engine, provider, _, ab) = makeEngine(current: us, frontmost: safari)
        engine.apply(config(action: .lock, source: abc, default: us))
        #expect(provider.current == us)                 // address bar not focused yet → default
        #expect(ab.observedBundleID == safari)          // observing the frontmost browser

        ab.setFocused(true)
        #expect(provider.current == abc)                // address-bar lock applied

        ab.setFocused(false)
        #expect(provider.current == us)                 // blur → back to the default lock
    }

    @Test("switch mode fires once on focus and re-arms after blur")
    func switchModeFiresOnceAndReArms() {
        let (engine, provider, _, ab) = makeEngine(current: us, frontmost: safari)
        engine.apply(config(action: .switchOnce, source: abc, default: us))
        #expect(provider.current == us)

        ab.setFocused(true)
        #expect(provider.current == abc)              // switched once
        #expect(provider.selectCalls == [abc])

        provider.current = us                         // user switches away — no standing lock reverts it
        ab.setFocused(false)                          // blur → default lock (us); already there, no switch
        #expect(provider.current == us)
        #expect(provider.selectCalls == [abc])

        ab.setFocused(true)                           // genuine re-entry → fires again
        #expect(provider.current == abc)
        #expect(provider.selectCalls == [abc, abc])
    }

    @Test("URL-first opt-out: a matched URL rule wins even while the address bar is focused")
    func urlFirstOptOutKeepsURLRule() {
        let provider = MockInputSourceProvider(
            current: us,
            sources: [.stub(us.rawValue), .stub(abc.rawValue), .stub(pinyin.rawValue, cjkv: true)]
        )
        let urls = MockBrowserURLProvider(url: "https://github.com/x")
        let ab = MockAddressBarMonitor()
        let engine = LockEngine(
            provider: provider,
            appMonitor: MockFrontmostMonitor(bundleID: safari),
            addressBarMonitor: ab,
            urlProvider: urls
        )
        engine.start()
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            enhancedModeEnabled: true,
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: pinyin)],
            addressBarFocusEnabled: true,
            addressBarAction: .lock,
            addressBarSourceID: abc,
            addressBarOutranksURLRules: false // opt out of the address-bar-first default
        ))
        #expect(provider.current == pinyin)   // github URL rule

        ab.setFocused(true)
        #expect(provider.current == pinyin)   // still the URL rule — opted into URL-first
    }

    @Test("with address-bar priority on, focusing the bar overrides the matched URL rule")
    func addressBarPriorityOverridesURL() {
        let provider = MockInputSourceProvider(
            current: us,
            sources: [.stub(us.rawValue), .stub(abc.rawValue), .stub(pinyin.rawValue, cjkv: true)]
        )
        let urls = MockBrowserURLProvider(url: "https://github.com/x")
        let ab = MockAddressBarMonitor()
        let engine = LockEngine(
            provider: provider,
            appMonitor: MockFrontmostMonitor(bundleID: safari),
            addressBarMonitor: ab,
            urlProvider: urls
        )
        engine.start()
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            enhancedModeEnabled: true,
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: pinyin)],
            addressBarFocusEnabled: true,
            addressBarAction: .lock,
            addressBarSourceID: abc,
            addressBarOutranksURLRules: true
        ))
        #expect(provider.current == pinyin)   // bar not focused → URL rule still applies

        ab.setFocused(true)
        #expect(provider.current == abc)       // focused → address bar overrides the URL rule

        ab.setFocused(false)
        #expect(provider.current == pinyin)    // blur → URL rule reclaims the page
    }

    @Test("override on + both switch actions: bar and URL one-shots dedup by context, re-firing on each transition")
    func overrideSwitchOnceDedupByContext() {
        let provider = MockInputSourceProvider(
            current: us,
            sources: [.stub(us.rawValue), .stub(abc.rawValue), .stub(pinyin.rawValue, cjkv: true)]
        )
        let urls = MockBrowserURLProvider(url: "https://github.com/x")
        let ab = MockAddressBarMonitor()
        let engine = LockEngine(
            provider: provider,
            appMonitor: MockFrontmostMonitor(bundleID: safari),
            addressBarMonitor: ab,
            urlProvider: urls
        )
        engine.start()
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            enhancedModeEnabled: true,
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: pinyin, action: .switchOnce)],
            addressBarFocusEnabled: true,
            addressBarAction: .switchOnce,
            addressBarSourceID: abc,
            addressBarOutranksURLRules: true
        ))
        #expect(provider.current == pinyin)                 // bar not focused → URL one-shot fired
        #expect(provider.selectCalls == [pinyin])

        ab.setFocused(true)
        #expect(provider.current == abc)                    // bar overrides → its own one-shot fires
        #expect(provider.selectCalls == [pinyin, abc])

        ab.setFocused(false)
        // Blur → the URL one-shot reclaims the page. Its SwitchKey (keyed on the
        // host pattern) differs from the address-bar key (keyed on the bundle),
        // so it is a genuine re-entry and re-fires — the documented one-shot
        // re-entry contract, now reachable via the address-bar excursion.
        #expect(provider.current == pinyin)
        #expect(provider.selectCalls == [pinyin, abc, pinyin])
    }

    @Test("no reverse restore: blur leaves the source where the rule put it when no rule reclaims it")
    func noReverseRestore() {
        let (engine, provider, _, ab) = makeEngine(current: us, frontmost: safari)
        // No default and no app rule, so nothing reclaims the source on blur.
        engine.apply(config(action: .lock, source: abc, default: nil))
        #expect(provider.current == us)       // nothing forced up front

        ab.setFocused(true)
        #expect(provider.current == abc)      // address-bar lock applied

        ab.setFocused(false)
        #expect(provider.current == abc)      // blur leaves it at abc — never restored to us
    }

    @Test("the feature is dormant when off: not observed, and a stray focus event does nothing")
    func dormantWhenOff() {
        let (engine, provider, _, ab) = makeEngine(current: us, frontmost: safari)
        engine.apply(LockConfiguration(
            isEnabled: true, defaultSourceID: us,
            addressBarFocusEnabled: false, addressBarAction: .lock, addressBarSourceID: abc
        ))
        #expect(ab.observedBundleID == nil)   // off → not observing

        ab.setFocused(true)                   // even a stray event resolves to nothing (config gate)
        #expect(provider.current == us)
    }

    @Test("the address bar is observed only while a browser is frontmost")
    func observedOnlyForBrowsers() {
        let (engine, _, monitor, ab) = makeEngine(current: us, frontmost: "com.foo.App")
        engine.apply(config(action: .switchOnce, source: abc, default: us))
        #expect(ab.observedBundleID == nil)   // a non-browser app → not observed

        monitor.activate(safari)
        #expect(ab.observedBundleID == safari)

        monitor.activate("com.foo.App")
        #expect(ab.observedBundleID == nil)   // left the browser → observation stops
    }

    @Test("a forced switch is logged as addressBarFocused with the address-bar rule branch")
    func logsReasonAndBranch() {
        let (engine, _, _, ab) = makeEngine(current: us, frontmost: safari)
        var events: [ActivationEvent] = []
        engine.onActivation = { events.append($0) }
        engine.apply(config(action: .lock, source: abc, default: us))

        ab.setFocused(true)
        #expect(events.last?.reason == .addressBarFocused)
        #expect(events.last?.ruleSource == .addressBarRule)
        #expect(events.last?.inputSource == abc)
    }

    @Test("accessibilityDidChange asks the address-bar monitor to re-attach")
    func accessibilityRefreshes() {
        let (engine, _, _, ab) = makeEngine(current: us, frontmost: safari)
        #expect(ab.refreshCount == 0)
        engine.accessibilityDidChange()
        #expect(ab.refreshCount == 1)
    }

    @Test("a launcher overlay over a browser suspends address-bar observation")
    func launcherSuspendsObservation() {
        let provider = MockInputSourceProvider(
            current: us,
            sources: [.stub(us.rawValue), .stub(abc.rawValue), .stub(pinyin.rawValue, cjkv: true)]
        )
        let floating = MockFloatingMonitor()
        let ab = MockAddressBarMonitor()
        let engine = LockEngine(
            provider: provider,
            appMonitor: MockFrontmostMonitor(bundleID: safari),
            floatingAppMonitor: floating,
            addressBarMonitor: ab
        )
        engine.start()
        engine.apply(config(action: .lock, source: abc, default: us))
        #expect(ab.observedBundleID == safari)

        floating.setLauncher("com.apple.Spotlight")
        #expect(ab.observedBundleID == nil)   // overlay isn't a browser → suspended

        floating.setLauncher(nil)
        #expect(ab.observedBundleID == safari) // dismissed → resumes
    }
}
