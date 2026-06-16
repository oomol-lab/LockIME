import Foundation
import Testing

@testable import LockIMEKit

@MainActor
@Suite("LockController")
struct LockControllerTests {
    private let us: InputSourceID = "com.apple.keylayout.US"
    private let abc: InputSourceID = "com.apple.keylayout.ABC"
    private let pinyin: InputSourceID = "com.apple.inputmethod.SCIM.ITABC"

    private func make(
        current: InputSourceID,
        enabled: Bool = false
    ) -> (LockController, MockInputSourceProvider, FakeUptime) {
        let provider = MockInputSourceProvider(
            current: current,
            sources: [.stub(us.rawValue), .stub(abc.rawValue), .stub(pinyin.rawValue, cjkv: true)]
        )
        let uptime = FakeUptime()
        let controller = LockController(
            provider: provider,
            isEnabled: enabled,
            uptime: uptime.read
        )
        return (controller, provider, uptime)
    }

    @Test("commandSwitch with no active lock takes effect and sticks")
    func commandSwitchNoLock() {
        let (controller, provider, _) = make(current: us) // disabled (no lock)
        controller.commandSwitch(abc)
        #expect(provider.current == abc)
        #expect(controller.activationCount == 1)
        controller.selectedSourceDidChange() // nothing reverts while disabled
        #expect(provider.current == abc)
    }

    @Test("commandSwitch is a no-op when already on the source")
    func commandSwitchAlreadyThere() {
        let (controller, provider, _) = make(current: abc)
        controller.commandSwitch(abc)
        #expect(provider.selectCalls.isEmpty)
        #expect(controller.activationCount == 0)
    }

    @Test("commandSwitch yields to an active lock even inside the suppression window")
    func commandSwitchYieldsToActiveLock() {
        let (controller, provider, uptime) = make(current: us, enabled: true)
        controller.setTarget(abc)          // lock to abc: forces us→abc, opens the 0.30s settle window
        #expect(provider.current == abc)
        uptime.advance(by: 0.10)           // still inside the window
        controller.commandSwitch(pinyin)   // transient API switch
        #expect(provider.current == pinyin) // it took effect…
        controller.selectedSourceDidChange() // …and the system posts the change
        #expect(provider.current == abc)   // the lock reverted it (cleared settle window)
        #expect(controller.target == abc)  // lock target untouched
    }

    @Test("a failed commandSwitch select changes nothing and is not counted")
    func commandSwitchFailedSelectNotCounted() {
        let (controller, provider, _) = make(current: us) // disabled (no lock)
        provider.selectSucceeds[abc] = false
        var events: [ActivationEvent] = []
        controller.onActivation = { events.append($0) }
        controller.commandSwitch(abc)
        #expect(provider.selectCalls == [abc]) // attempted once…
        #expect(provider.current == us)        // …but it did not take
        #expect(controller.activationCount == 0)
        #expect(events.isEmpty)                // no event on a failed switch
    }

    @Test("commandSwitch emits one .apiCommand event with from-source and no rule context")
    func commandSwitchEmitsApiCommandEvent() {
        let (controller, _, _) = make(current: us) // disabled (no lock)
        var events: [ActivationEvent] = []
        controller.onActivation = { events.append($0) }
        controller.commandSwitch(abc)
        #expect(events.count == 1)
        #expect(events.first?.reason == .apiCommand)
        #expect(events.first?.inputSource == abc)
        #expect(events.first?.fromSourceName == us.rawValue) // stub name == id
        // A command switch belongs to no rule, so it carries no app/rule context.
        #expect(events.first?.triggeringBundleID == nil)
        #expect(events.first?.ruleSource == nil)
        #expect(events.first?.matchedHost == nil)
        #expect((events.first?.durationMs ?? -1) >= 0)
    }

    @Test("disabled controller never forces a switch")
    func disabledDoesNothing() {
        let (controller, provider, _) = make(current: abc)
        controller.setTarget(us)
        controller.selectedSourceDidChange()
        #expect(provider.selectCalls.isEmpty)
        #expect(controller.activationCount == 0)
    }

    @Test("enabled with no target does nothing")
    func noTargetDoesNothing() {
        let (controller, provider, _) = make(current: abc, enabled: true)
        controller.selectedSourceDidChange()
        #expect(provider.selectCalls.isEmpty)
    }

    @Test("setTarget forces immediately when current differs")
    func setTargetForcesWhenMismatched() {
        let (controller, provider, _) = make(current: abc, enabled: true)
        controller.setTarget(us)
        #expect(provider.selectCalls == [us])
        #expect(provider.current == us)
        #expect(controller.activationCount == 1)
    }

    @Test("setTarget does not force when already on target")
    func setTargetNoForceWhenMatched() {
        let (controller, provider, _) = make(current: us, enabled: true)
        controller.setTarget(us)
        #expect(provider.selectCalls.isEmpty)
        #expect(controller.activationCount == 0)
    }

    @Test("a switch away is reverted to the target")
    func revertsSwitchAway() {
        let (controller, provider, uptime) = make(current: us, enabled: true)
        controller.setTarget(us)
        #expect(provider.selectCalls.isEmpty) // already on target

        // user switches away…
        provider.current = abc
        uptime.advance(by: 1.0) // outside any window
        controller.selectedSourceDidChange()

        #expect(provider.selectCalls == [us])
        #expect(provider.current == us)
        #expect(controller.activationCount == 1)
    }

    @Test("the echo of our own forced switch is ignored (idempotent)")
    func idempotentOnTargetEcho() {
        let (controller, provider, uptime) = make(current: us, enabled: true)
        controller.setTarget(us)
        provider.current = abc
        uptime.advance(by: 1.0)
        controller.selectedSourceDidChange() // forces back to us, current == us now

        let callsAfterForce = provider.selectCalls.count
        // the system posts a change notification for our own switch:
        controller.selectedSourceDidChange()
        #expect(provider.selectCalls.count == callsAfterForce) // no extra force
    }

    @Test("within the suppression window, a lingering mismatch is not re-forced")
    func suppressionWindowHoldsOff() {
        let (controller, provider, uptime) = make(current: us, enabled: true)
        controller.setTarget(us)

        // a switch the force doesn't immediately reflect (no-op select)
        provider.selectIsNoOp = true
        provider.current = abc
        uptime.advance(by: 1.0)
        controller.selectedSourceDidChange() // attempts force, but select is a no-op
        #expect(provider.selectCalls == [us])

        // still mismatched, but we are inside the 0.30s settle window
        uptime.advance(by: 0.1)
        controller.selectedSourceDidChange()
        #expect(provider.selectCalls == [us]) // held off — no second force
    }

    @Test("after the suppression window, a persistent mismatch is re-forced")
    func reForcesAfterWindow() {
        let (controller, provider, uptime) = make(current: us, enabled: true)
        controller.setTarget(us)

        provider.selectIsNoOp = true
        provider.current = abc
        uptime.advance(by: 1.0)
        controller.selectedSourceDidChange()
        #expect(provider.selectCalls.count == 1)

        // window elapses, still wrong → re-force
        uptime.advance(by: LockController.suppressionWindow + 0.01)
        controller.selectedSourceDidChange()
        #expect(provider.selectCalls.count == 2)
    }

    @Test("changing the target supersedes the suppression window")
    func targetChangeBypassesWindow() {
        let (controller, provider, uptime) = make(current: us, enabled: true)
        controller.setTarget(us)
        provider.current = abc
        uptime.advance(by: 1.0)
        controller.selectedSourceDidChange() // forces back to us; opens settle window
        let calls = provider.selectCalls.count

        // Within the window, a NEW target must still be enforced immediately.
        controller.setTarget(abc)
        #expect(provider.selectCalls.count == calls + 1)
        #expect(provider.current == abc)
    }

    @Test("enabling while mismatched engages the lock")
    func enableEngagesLock() {
        let (controller, provider, _) = make(current: abc, enabled: false)
        controller.setTarget(us) // sets target but disabled → no force
        #expect(provider.selectCalls.isEmpty)

        controller.setEnabled(true)
        #expect(provider.selectCalls == [us])
        #expect(controller.activationCount == 1)
    }

    @Test("activation events carry source, reason, and non-negative duration")
    func emitsActivationEvents() {
        let (controller, _, _) = make(current: abc, enabled: true)
        var events: [ActivationEvent] = []
        controller.onActivation = { events.append($0) }

        controller.setTarget(us, reason: .lockEngaged)
        #expect(events.count == 1)
        #expect(events.first?.inputSource == us)
        #expect(events.first?.reason == .lockEngaged)
        #expect((events.first?.durationMs ?? -1) >= 0)
    }

    @Test("setEnabled attributes the engaging force with the given reason")
    func setEnabledReason() {
        let (controller, _, _) = make(current: abc, enabled: false)
        var events: [ActivationEvent] = []
        controller.onActivation = { events.append($0) }
        controller.setTarget(us) // disabled → no force yet
        #expect(events.isEmpty)
        controller.setEnabled(true, reason: .startupApplied)
        #expect(events.first?.reason == .startupApplied)
    }

    @Test("events carry the from-source and the target's app/rule context")
    func emitsContextFields() {
        let (controller, provider, uptime) = make(current: abc, enabled: true)
        var events: [ActivationEvent] = []
        controller.onActivation = { events.append($0) }

        // Forcing abc → us records where it came from and the target's context.
        controller.setTarget(us, reason: .appActivated, bundleID: "com.foo.Bar", ruleSource: .appRule)
        #expect(events.count == 1)
        #expect(events.first?.fromSourceName == abc.rawValue) // stub name == id
        #expect(events.first?.triggeringBundleID == "com.foo.Bar")
        #expect(events.first?.ruleSource == .appRule)

        // A later revert keeps the target's context but carries its own reason
        // and the source it drifted to as the from-source.
        provider.current = pinyin
        uptime.advance(by: 1.0)
        controller.selectedSourceDidChange()
        #expect(events.count == 2)
        #expect(events.last?.reason == .revertedSwitch)
        #expect(events.last?.triggeringBundleID == "com.foo.Bar")
        #expect(events.last?.fromSourceName == pinyin.rawValue)
    }

    @Test("a failed select does not count as an activation")
    func failedSelectNotCounted() {
        let (controller, provider, _) = make(current: abc, enabled: true)
        provider.selectSucceeds[us] = false
        controller.setTarget(us)
        #expect(provider.selectCalls == [us])
        #expect(controller.activationCount == 0)
    }

    // MARK: - One-shot switch

    @Test("switchOnce switches once and installs NO standing target")
    func switchOnceSwitchesAndLeavesNoTarget() {
        let (controller, provider, _) = make(current: abc, enabled: true)
        controller.switchOnce(us, reason: .appActivated)
        #expect(provider.selectCalls == [us])
        #expect(provider.current == us)
        #expect(controller.activationCount == 1)
        #expect(controller.target == nil) // crucial: no standing lock
    }

    @Test("switchOnce is a no-op when already on the target")
    func switchOnceNoOpWhenOnTarget() {
        let (controller, provider, _) = make(current: us, enabled: true)
        controller.switchOnce(us)
        #expect(provider.selectCalls.isEmpty)
        #expect(controller.activationCount == 0)
        #expect(controller.target == nil)
    }

    @Test("switchOnce is a no-op (no crash) when the current source is unknown")
    func switchOnceNoOpWhenCurrentNil() {
        let provider = MockInputSourceProvider(current: nil, sources: [.stub(us.rawValue)])
        let controller = LockController(provider: provider, isEnabled: true)
        controller.switchOnce(us)
        #expect(provider.selectCalls.isEmpty)
        #expect(controller.activationCount == 0)
        #expect(controller.target == nil)
    }

    @Test("after switchOnce a later source change is never reverted")
    func switchOnceDoesNotRevert() {
        let (controller, provider, uptime) = make(current: abc, enabled: true)
        controller.switchOnce(us)
        #expect(provider.selectCalls == [us])

        // User switches away, well outside any settle window.
        provider.current = abc
        uptime.advance(by: 1.0)
        controller.selectedSourceDidChange()
        #expect(provider.selectCalls == [us]) // no revert — the user keeps abc
        #expect(provider.current == abc)
    }

    @Test("switchOnce ignores controller.isEnabled (the engine gates on config)")
    func switchOnceForcesWhileControllerDisabled() {
        // The enable path re-resolves before the controller flips on, so the
        // one-shot must fire regardless of the controller's own isEnabled.
        let (controller, provider, _) = make(current: abc, enabled: false)
        controller.switchOnce(us)
        #expect(provider.selectCalls == [us])
        #expect(controller.activationCount == 1)
    }

    @Test("a failed switchOnce select does not count")
    func switchOnceFailedSelectNotCounted() {
        let (controller, provider, _) = make(current: abc, enabled: true)
        provider.selectSucceeds[us] = false
        controller.switchOnce(us)
        #expect(provider.selectCalls == [us])
        #expect(controller.activationCount == 0)
    }

    @Test("switchOnce emits one event with the rule context and given reason")
    func switchOnceEmitsContext() {
        let (controller, _, _) = make(current: abc, enabled: true)
        var events: [ActivationEvent] = []
        controller.onActivation = { events.append($0) }
        controller.switchOnce(us, reason: .urlMatched, bundleID: "com.foo.Bar", ruleSource: .urlRule, matchedHost: "github.com")
        #expect(events.count == 1)
        #expect(events.first?.inputSource == us)
        #expect(events.first?.reason == .urlMatched)
        #expect(events.first?.ruleSource == .urlRule)
        #expect(events.first?.triggeringBundleID == "com.foo.Bar")
        #expect(events.first?.matchedHost == "github.com")
        #expect(events.first?.fromSourceName == abc.rawValue)
    }
}
