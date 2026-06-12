import Carbon
import Testing

@testable import LockIMEKit

@Suite("InputSourceChangeObserver")
struct InputSourceChangeObserverTests {
    @Test("each event maps to its Text Input Source notification name")
    func notificationNames() {
        #expect(
            InputSourceEvent.selectionChanged.notificationName as String
                == kTISNotifySelectedKeyboardInputSourceChanged as String
        )
        #expect(
            InputSourceEvent.enabledSourcesChanged.notificationName as String
                == kTISNotifyEnabledKeyboardInputSourcesChanged as String
        )
        // The two events must address distinct notifications, or the engine
        // would conflate "selection changed" with "enabled list changed".
        #expect(
            InputSourceEvent.selectionChanged.notificationName as String
                != InputSourceEvent.enabledSourcesChanged.notificationName as String
        )
    }
}
