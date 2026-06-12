import Foundation
import Testing

@testable import LockIMEKit

@MainActor
@Suite("LogStore retention")
struct LogStoreTests {
    private func event(ageHours: Double, now: Date) -> ActivationEvent {
        ActivationEvent(
            timestamp: now.addingTimeInterval(-ageHours * 3600),
            inputSource: "com.apple.keylayout.US",
            inputSourceName: "ABC",
            reason: .revertedSwitch,
            durationMs: 1.5
        )
    }

    @Test("records persist")
    func records() {
        let store = LogStore(inMemory: true)
        store.record(event(ageHours: 0, now: .now))
        store.record(event(ageHours: 0, now: .now))
        #expect(store.count() == 2)
    }

    @Test("entries older than 24h are purged, newer kept")
    func purges() {
        let store = LogStore(inMemory: true)
        let now = Date(timeIntervalSince1970: 1_000_000)
        store.record(event(ageHours: 25, now: now)) // expired
        store.record(event(ageHours: 23.9, now: now)) // kept
        store.record(event(ageHours: 1, now: now)) // kept
        #expect(store.count() == 3)

        store.purgeExpired(now: now)
        #expect(store.count() == 2)
    }

    @Test("purge with nothing expired is a no-op")
    func purgeNoOp() {
        let store = LogStore(inMemory: true)
        let now = Date(timeIntervalSince1970: 1_000_000)
        store.record(event(ageHours: 1, now: now))
        store.purgeExpired(now: now)
        #expect(store.count() == 1)
    }

    @Test("an unusable directory falls back to a working in-memory store")
    func fallsBackWhenDiskStoreFails() throws {
        // A regular file standing where the store directory should be: the
        // on-disk ModelContainer can't be created beneath it, so init must
        // take the in-memory fallback branch.
        let badPath = FileManager.default.temporaryDirectory
            .appending(path: "lockime-badstore-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: badPath)
        defer { try? FileManager.default.removeItem(at: badPath) }

        let store = LogStore(directoryOverride: badPath)
        #expect(store.count() == 0)            // usable despite the bad path
        store.record(event(ageHours: 0, now: .now))
        #expect(store.count() == 1)            // records work (in-memory)

        // A second store over the same bad path does NOT see the first's
        // record — proof the fallback is a fresh in-memory store, not a
        // shared on-disk one.
        let second = LogStore(directoryOverride: badPath)
        #expect(second.count() == 0)
    }

    @Test("disk store persists across container instances")
    func diskPersists() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "lockime-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = LogStore(directoryOverride: directory)
        store.record(event(ageHours: 0, now: .now))
        store.record(event(ageHours: 0, now: .now))
        #expect(store.count() == 2)

        // A fresh store over the same on-disk file sees the persisted entries.
        let reopened = LogStore(directoryOverride: directory)
        #expect(reopened.count() == 2)
    }
}
