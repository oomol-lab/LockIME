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
}
