import Foundation
import Testing

@testable import LockIMEKit

@MainActor
@Suite("LockEngine")
struct LockEngineTests {
    private let us: InputSourceID = "com.apple.keylayout.US"
    private let abc: InputSourceID = "com.apple.keylayout.ABC"

    private func makeEngine(
        current: InputSourceID,
        frontmost: String?
    ) -> (LockEngine, MockInputSourceProvider, MockFrontmostMonitor) {
        let provider = MockInputSourceProvider(
            current: current,
            sources: [.stub(us.rawValue), .stub(abc.rawValue)]
        )
        let monitor = MockFrontmostMonitor(bundleID: frontmost)
        let engine = LockEngine(provider: provider, appMonitor: monitor)
        engine.start()
        return (engine, provider, monitor)
    }

    @Test("applying an enabled global default enforces it")
    func appliesDefault() {
        let (engine, provider, _) = makeEngine(current: abc, frontmost: "com.foo.App")
        engine.apply(LockConfiguration(isEnabled: true, defaultSourceID: us))
        #expect(provider.selectCalls == [us])
        #expect(provider.current == us)
    }

    @Test("a disabled configuration enforces nothing")
    func disabledDoesNothing() {
        let (engine, provider, _) = makeEngine(current: abc, frontmost: "com.foo.App")
        engine.apply(LockConfiguration(isEnabled: false, defaultSourceID: us))
        #expect(provider.selectCalls.isEmpty)
        #expect(provider.current == abc)
    }

    @Test("a frontmost-app change retargets to that app's rule")
    func frontmostRetargets() {
        let (engine, provider, monitor) = makeEngine(current: us, frontmost: "com.foo.App")
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.apple.Terminal", mode: .locked, lockedSourceID: abc)]
        ))
        #expect(provider.current == us) // foo app → default

        monitor.activate("com.apple.Terminal")
        #expect(provider.current == abc) // retargeted to Terminal's rule
    }

    @Test("enhanced URL rule overrides the app rule when matched")
    func enhancedURLOverrides() {
        let pinyin: InputSourceID = "com.apple.inputmethod.SCIM.ITABC"
        let provider = MockInputSourceProvider(
            current: us,
            sources: [.stub(us.rawValue), .stub(abc.rawValue), .stub(pinyin.rawValue, cjkv: true)]
        )
        let monitor = MockFrontmostMonitor(bundleID: "com.apple.Safari")
        let urls = MockBrowserURLProvider(url: "https://github.com/x")
        let engine = LockEngine(provider: provider, appMonitor: monitor, urlProvider: urls)
        engine.start()

        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.apple.Safari", mode: .locked, lockedSourceID: abc)],
            enhancedModeEnabled: true,
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: pinyin)]
        ))
        #expect(provider.current == pinyin) // URL rule wins over the app rule
    }

    @Test("re-resolving after the URL changes switches to the new rule")
    func urlChangeReResolves() {
        let pinyin: InputSourceID = "com.apple.inputmethod.SCIM.ITABC"
        let provider = MockInputSourceProvider(
            current: us,
            sources: [.stub(us.rawValue), .stub(abc.rawValue), .stub(pinyin.rawValue, cjkv: true)]
        )
        let monitor = MockFrontmostMonitor(bundleID: "com.apple.Safari")
        let urls = MockBrowserURLProvider(url: "https://github.com/x")
        let engine = LockEngine(provider: provider, appMonitor: monitor, urlProvider: urls)
        engine.start()
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            enhancedModeEnabled: true,
            urlRules: [
                URLRule(hostPattern: "github.com", lockedSourceID: abc),
                URLRule(hostPattern: "translate.google.com", lockedSourceID: pinyin),
            ]
        ))
        #expect(provider.current == abc) // github rule

        // Navigate to a different URL; the engine re-reads it on re-activation
        // (the same path the URL poll uses).
        urls.url = "https://translate.google.com/?sl=en"
        monitor.activate("com.apple.Safari")
        #expect(provider.current == pinyin) // re-resolved to the google rule
    }

    @Test("URL rules are ignored when enhanced mode is off")
    func enhancedDisabledIgnoresURL() {
        let pinyin: InputSourceID = "com.apple.inputmethod.SCIM.ITABC"
        let provider = MockInputSourceProvider(
            current: us,
            sources: [.stub(us.rawValue), .stub(abc.rawValue), .stub(pinyin.rawValue, cjkv: true)]
        )
        let monitor = MockFrontmostMonitor(bundleID: "com.apple.Safari")
        let urls = MockBrowserURLProvider(url: "https://github.com/x")
        let engine = LockEngine(provider: provider, appMonitor: monitor, urlProvider: urls)
        engine.start()

        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.apple.Safari", mode: .locked, lockedSourceID: abc)],
            enhancedModeEnabled: false,
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: pinyin)]
        ))
        #expect(provider.current == abc) // app rule applies; URL rule ignored
    }

    @Test("activating an ignored app disengages locking")
    func ignoredAppDisengages() {
        let (engine, provider, monitor) = makeEngine(current: abc, frontmost: "com.game.App")
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.game.App", mode: .ignored)]
        ))
        // game app is ignored → no enforcement, current untouched
        #expect(provider.selectCalls.isEmpty)
        #expect(provider.current == abc)

        // switching to a normal app re-engages the default
        monitor.activate("com.other.App")
        #expect(provider.current == us)
    }
}

@MainActor
@Suite("LockEngine launcher overlays")
struct LockEngineLauncherTests {
    private let us: InputSourceID = "com.apple.keylayout.US"
    private let abc: InputSourceID = "com.apple.keylayout.ABC"
    private let pinyin: InputSourceID = "com.apple.inputmethod.SCIM.ITABC"
    private let spotlight = "com.apple.Spotlight"

    private func makeEngine(
        current: InputSourceID,
        frontmost: String?
    ) -> (LockEngine, MockInputSourceProvider, MockFloatingMonitor) {
        let provider = MockInputSourceProvider(
            current: current,
            sources: [.stub(us.rawValue), .stub(abc.rawValue), .stub(pinyin.rawValue, cjkv: true)]
        )
        let floating = MockFloatingMonitor()
        let engine = LockEngine(
            provider: provider,
            appMonitor: MockFrontmostMonitor(bundleID: frontmost),
            floatingAppMonitor: floating
        )
        engine.start()
        return (engine, provider, floating)
    }

    @Test("a launcher overlay retargets to its own rule, and dismissing it reverts")
    func launcherRetargetsAndReverts() {
        let (engine, provider, floating) = makeEngine(current: us, frontmost: "com.foo.App")
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: spotlight, mode: .locked, lockedSourceID: abc)]
        ))
        #expect(provider.current == us) // foo app → default

        floating.setLauncher(spotlight)
        #expect(provider.current == abc) // Spotlight's own rule applies

        floating.setLauncher(nil)
        #expect(provider.current == us) // dismissed → back to foo's default
    }

    // The reported bug (issue #9): with the overlay focused, `NSWorkspace`
    // still reports the underlying app, so its CJKV lock used to leak into the
    // search field. The overlay must resolve as *itself* — no Spotlight rule
    // means the global default, not the underlying app's pinyin lock.
    @Test("a launcher overlay does not inherit the underlying app's lock")
    func launcherDoesNotInheritUnderlyingLock() {
        let (engine, provider, floating) = makeEngine(current: pinyin, frontmost: "com.cjkv.App")
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.cjkv.App", mode: .locked, lockedSourceID: pinyin)]
        ))
        #expect(provider.current == pinyin) // the CJKV app is pinned to pinyin

        floating.setLauncher(spotlight)
        #expect(provider.current == us) // Spotlight → global default, NOT pinyin

        floating.setLauncher(nil)
        #expect(provider.current == pinyin) // dismissed → underlying lock returns
    }

    @Test("a launcher rule wins even when the underlying app is ignored")
    func launcherRuleBeatsIgnoredUnderlyingApp() {
        let (engine, provider, floating) = makeEngine(current: us, frontmost: "com.foo.App")
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [
                AppRule(bundleID: "com.foo.App", mode: .ignored),
                AppRule(bundleID: spotlight, mode: .locked, lockedSourceID: abc),
            ]
        ))
        #expect(provider.selectCalls.isEmpty) // foo is ignored → nothing forced
        #expect(provider.current == us)

        floating.setLauncher(spotlight)
        #expect(provider.current == abc) // Spotlight's lock applies over the overlay
    }

    @Test("an ignored launcher overlay enforces nothing")
    func ignoredLauncherDisengages() {
        // Underlying app is also ignored, so nothing is forced up front; the
        // contrast with `launcherRuleBeatsIgnoredUnderlyingApp` (same setup, a
        // *locked* overlay forces abc) isolates the overlay's own ignore.
        let (engine, provider, floating) = makeEngine(current: abc, frontmost: "com.foo.App")
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [
                AppRule(bundleID: "com.foo.App", mode: .ignored),
                AppRule(bundleID: spotlight, mode: .ignored),
            ]
        ))
        #expect(provider.selectCalls.isEmpty) // foo ignored → nothing forced
        #expect(provider.current == abc)

        floating.setLauncher(spotlight)
        #expect(provider.selectCalls.isEmpty) // ignored overlay → still nothing forced
        #expect(provider.current == abc)
    }

    @Test("a launcher overlay over a browser drops the URL-rule context")
    func launcherDropsBrowserURLContext() {
        let provider = MockInputSourceProvider(
            current: us,
            sources: [.stub(us.rawValue), .stub(abc.rawValue), .stub(pinyin.rawValue, cjkv: true)]
        )
        let floating = MockFloatingMonitor()
        let urls = BundleAwareURLProvider(url: "https://github.com/x", forBundleID: "com.apple.Safari")
        let engine = LockEngine(
            provider: provider,
            appMonitor: MockFrontmostMonitor(bundleID: "com.apple.Safari"),
            floatingAppMonitor: floating,
            urlProvider: urls
        )
        engine.start()
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            enhancedModeEnabled: true,
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: pinyin)]
        ))
        #expect(provider.current == pinyin) // Safari on github → URL rule

        floating.setLauncher(spotlight)
        #expect(provider.current == us) // overlay isn't the browser → default, not the URL rule

        floating.setLauncher(nil)
        #expect(provider.current == pinyin) // dismissed → URL rule applies again
    }

    @Test("accessibilityDidChange asks the floating monitor to re-attach")
    func accessibilityRefreshesMonitor() {
        let (engine, _, floating) = makeEngine(current: us, frontmost: "com.foo.App")
        #expect(floating.refreshCount == 0)
        engine.accessibilityDidChange()
        #expect(floating.refreshCount == 1)
    }

    @Test("revoking Accessibility clears a stale launcher attribution")
    func revokeClearsLauncherAttribution() {
        let (engine, provider, floating) = makeEngine(current: us, frontmost: "com.foo.App")
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: spotlight, mode: .locked, lockedSourceID: abc)]
        ))
        floating.setLauncher(spotlight)
        #expect(provider.current == abc) // overlay attributed to Spotlight's rule

        // Revoking access refreshes the monitor; with trust gone it can no longer
        // read focus, so it reports "no launcher" — the engine must revert to the
        // frontmost app rather than stay pinned to the stale overlay.
        floating.refreshClearsLauncher = true
        engine.accessibilityDidChange()
        #expect(provider.current == us) // reverted to foo's default
    }
}

/// A URL provider that, like the real Accessibility reader, only yields a URL
/// for the matching browser bundle — so a launcher overlay (a different bundle)
/// reads no URL.
@MainActor
private final class BundleAwareURLProvider: BrowserURLProviding {
    let url: String
    let bundleID: String
    init(url: String, forBundleID bundleID: String) {
        self.url = url
        self.bundleID = bundleID
    }
    func currentURL(forBundleID bundleID: String?) -> String? {
        bundleID == self.bundleID ? url : nil
    }
}

@MainActor
@Suite("LockEngine accessors & lifecycle")
struct LockEngineSurfaceTests {
    private let us: InputSourceID = "com.apple.keylayout.US"
    private let abc: InputSourceID = "com.apple.keylayout.ABC"

    @Test("activationCount counts forced switches")
    func activationCount() {
        let provider = MockInputSourceProvider(
            current: abc,
            sources: [.stub(us.rawValue), .stub(abc.rawValue)]
        )
        let engine = LockEngine(provider: provider, appMonitor: MockFrontmostMonitor(bundleID: "com.foo.App"))
        engine.start()
        #expect(engine.activationCount == 0)

        engine.apply(LockConfiguration(isEnabled: true, defaultSourceID: us))
        #expect(provider.current == us)
        #expect(engine.activationCount == 1)
    }

    @Test("stop detaches the frontmost monitor so later activations are ignored")
    func stopDetaches() {
        let provider = MockInputSourceProvider(
            current: us,
            sources: [.stub(us.rawValue), .stub(abc.rawValue)]
        )
        let monitor = MockFrontmostMonitor(bundleID: "com.foo.App")
        let engine = LockEngine(provider: provider, appMonitor: monitor)
        engine.start()
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.apple.Terminal", mode: .locked, lockedSourceID: abc)]
        ))
        #expect(provider.current == us) // foo → default
        let callsBeforeStop = provider.selectCalls.count

        engine.stop()
        monitor.activate("com.apple.Terminal") // would retarget to abc if still attached

        #expect(provider.current == us) // unchanged: the monitor was detached
        #expect(provider.selectCalls.count == callsBeforeStop)
    }

    @Test("currentSourceName prefers the localized name, then the raw id, then a dash")
    func currentSourceName() {
        // Localized name present.
        let named = MockInputSourceProvider(
            current: us,
            sources: [InputSource(id: us, localizedName: "U.S.", isSelectCapable: true, isEnabled: true, isCJKV: false)]
        )
        let namedEngine = LockEngine(provider: named, appMonitor: MockFrontmostMonitor())
        #expect(namedEngine.currentSourceName() == "U.S.")

        // Current id not among the known sources → fall back to the raw id.
        let unknown = MockInputSourceProvider(current: "com.unknown.X", sources: [.stub(us.rawValue)])
        let unknownEngine = LockEngine(provider: unknown, appMonitor: MockFrontmostMonitor())
        #expect(unknownEngine.currentSourceName() == "com.unknown.X")

        // No current source → em dash.
        let none = MockInputSourceProvider(current: nil, sources: [])
        let noneEngine = LockEngine(provider: none, appMonitor: MockFrontmostMonitor())
        #expect(noneEngine.currentSourceName() == "—")
    }

    @Test("selectableSources and currentSourceID delegate to the provider")
    func delegatesToProvider() {
        let provider = MockInputSourceProvider(
            current: abc,
            sources: [.stub(us.rawValue), .stub(abc.rawValue)]
        )
        let engine = LockEngine(provider: provider, appMonitor: MockFrontmostMonitor())
        #expect(engine.currentSourceID() == abc)
        #expect(engine.selectableSources() == provider.selectableSources())
        #expect(engine.selectableSources().map(\.id) == [us, abc])
    }
}

@MainActor
@Suite("LockEngine activation reasons")
struct LockEngineReasonTests {
    private let us: InputSourceID = "com.apple.keylayout.US"
    private let abc: InputSourceID = "com.apple.keylayout.ABC"
    private let pinyin: InputSourceID = "com.apple.inputmethod.SCIM.ITABC"
    private let spotlight = "com.apple.Spotlight"

    @Test("a frontmost-app switch is logged as appActivated with the app's context")
    func appActivatedContext() {
        let provider = MockInputSourceProvider(
            current: us,
            sources: [.stub(us.rawValue), .stub(abc.rawValue)]
        )
        let monitor = MockFrontmostMonitor(bundleID: "com.foo.App")
        let engine = LockEngine(provider: provider, appMonitor: monitor)
        var events: [ActivationEvent] = []
        engine.onActivation = { events.append($0) }
        engine.start()
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: "com.apple.Terminal", mode: .locked, lockedSourceID: abc)]
        ), reason: .startupApplied)

        monitor.activate("com.apple.Terminal")
        #expect(events.last?.reason == .appActivated)
        #expect(events.last?.ruleSource == .appRule)
        #expect(events.last?.triggeringBundleID == "com.apple.Terminal")
        #expect(events.last?.inputSource == abc)
    }

    @Test("a launcher overlay is logged focused, then dismissed")
    func launcherReasons() {
        let provider = MockInputSourceProvider(
            current: us,
            sources: [.stub(us.rawValue), .stub(abc.rawValue)]
        )
        let floating = MockFloatingMonitor()
        let engine = LockEngine(
            provider: provider,
            appMonitor: MockFrontmostMonitor(bundleID: "com.foo.App"),
            floatingAppMonitor: floating
        )
        var events: [ActivationEvent] = []
        engine.onActivation = { events.append($0) }
        engine.start()
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            appRules: [AppRule(bundleID: spotlight, mode: .locked, lockedSourceID: abc)]
        ))

        floating.setLauncher(spotlight)
        #expect(events.last?.reason == .launcherFocused)
        #expect(events.last?.triggeringBundleID == spotlight)

        floating.setLauncher(nil)
        #expect(events.last?.reason == .launcherDismissed)
    }

    // The enabling force at apply() time is attributed to the apply reason (the
    // lock engaging), with the URL provenance carried by `ruleSource`. The
    // dedicated `.urlMatched` reason fires only once already locked, when a URL
    // change re-resolves the target — the trigger *is* the URL.
    @Test("a URL change re-resolved while locked is logged as urlMatched with the host")
    func urlMatchedHost() {
        let provider = MockInputSourceProvider(
            current: us,
            sources: [.stub(us.rawValue), .stub(abc.rawValue), .stub(pinyin.rawValue, cjkv: true)]
        )
        let urls = MockBrowserURLProvider(url: "https://github.com/x")
        let monitor = MockFrontmostMonitor(bundleID: "com.apple.Safari")
        let engine = LockEngine(provider: provider, appMonitor: monitor, urlProvider: urls)
        var events: [ActivationEvent] = []
        engine.onActivation = { events.append($0) }
        engine.start()
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            enhancedModeEnabled: true,
            urlRules: [
                URLRule(hostPattern: "github.com", lockedSourceID: abc),
                URLRule(hostPattern: "translate.google.com", lockedSourceID: pinyin),
            ]
        ), reason: .startupApplied)
        #expect(provider.current == abc) // enabling forced the github rule

        // Navigate to the google rule and re-activate while already locked.
        urls.url = "https://translate.google.com/?sl=en"
        monitor.activate("com.apple.Safari")
        #expect(events.last?.reason == .urlMatched)
        #expect(events.last?.ruleSource == .urlRule)
        #expect(events.last?.matchedHost == "translate.google.com")
        #expect(events.last?.inputSource == pinyin)
    }

    // Editing a URL rule while already locked is a config edit — the trigger is
    // the edit, not a navigation — so it keeps .configChanged and carries the
    // URL provenance in ruleSource rather than masquerading as .urlMatched.
    @Test("an apply-driven URL resolution keeps its reason, not urlMatched")
    func applyReasonOutranksURLMatch() {
        let provider = MockInputSourceProvider(
            current: us,
            sources: [.stub(us.rawValue), .stub(abc.rawValue), .stub(pinyin.rawValue, cjkv: true)]
        )
        let urls = MockBrowserURLProvider(url: "https://github.com/x")
        let engine = LockEngine(
            provider: provider,
            appMonitor: MockFrontmostMonitor(bundleID: "com.apple.Safari"),
            urlProvider: urls
        )
        var events: [ActivationEvent] = []
        engine.onActivation = { events.append($0) }
        engine.start()
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            enhancedModeEnabled: true,
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: abc)]
        ), reason: .startupApplied)
        #expect(provider.current == abc)

        // Re-point the github rule while locked (a config edit, already enabled).
        engine.apply(LockConfiguration(
            isEnabled: true,
            defaultSourceID: us,
            enhancedModeEnabled: true,
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: pinyin)]
        ), reason: .configChanged)
        #expect(provider.current == pinyin)
        #expect(events.last?.reason == .configChanged) // not .urlMatched
        #expect(events.last?.ruleSource == .urlRule)   // provenance kept
        #expect(events.last?.matchedHost == "github.com")
    }

    // Turning the lock off must never force a switch: if the source has drifted
    // off target, disabling should leave it where the user put it, not yank it
    // back one last time. Enabling while already on target sets no settle
    // window, so the disable path is the only thing that could force here.
    @Test("disabling the lock is side-effect free")
    func disablingForcesNothing() {
        let provider = MockInputSourceProvider(
            current: abc,
            sources: [.stub(us.rawValue), .stub(abc.rawValue)]
        )
        let engine = LockEngine(provider: provider, appMonitor: MockFrontmostMonitor(bundleID: "com.foo.App"))
        var events: [ActivationEvent] = []
        engine.onActivation = { events.append($0) }
        engine.start()
        engine.apply(LockConfiguration(isEnabled: true, defaultSourceID: abc), reason: .lockEngaged)
        #expect(events.isEmpty) // already on target → locked without forcing

        provider.current = us // the source drifts off target
        engine.apply(LockConfiguration(isEnabled: false, defaultSourceID: abc), reason: .lockEngaged)
        #expect(events.isEmpty)         // disabling forced nothing
        #expect(provider.current == us) // left where the user put it
    }
}
