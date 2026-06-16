import Foundation
import SwiftData
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

    @Test("the from-source, app, and rule context round-trips into a stored row")
    func recordsContextFields() throws {
        let store = LogStore(inMemory: true)
        store.record(
            ActivationEvent(
                timestamp: .now,
                inputSource: "com.apple.keylayout.US",
                inputSourceName: "U.S.",
                reason: .revertedSwitch,
                durationMs: 2.0,
                fromSourceName: "Pinyin",
                triggeringBundleID: "com.apple.Safari",
                ruleSource: .appRule,
                matchedHost: nil
            ),
            triggeringAppName: "Safari"
        )

        let rows = try store.container.mainContext.fetch(FetchDescriptor<ActivationLogEntry>())
        let row = try #require(rows.first)
        #expect(row.fromSourceName == "Pinyin")
        #expect(row.triggeringBundleID == "com.apple.Safari")
        #expect(row.triggeringAppName == "Safari")
        #expect(row.ruleSource == .appRule)
        #expect(row.reason == .revertedSwitch)
    }

    @Test("records persist")
    func records() {
        let store = LogStore(inMemory: true)
        store.record(event(ageHours: 0, now: .now))
        store.record(event(ageHours: 0, now: .now))
        #expect(store.count() == 2)
    }

    @Test("recent() returns within-window entries newest-first and honors limit")
    func recentNewestFirst() throws {
        let store = LogStore(inMemory: true)
        let now = Date.now
        store.record(event(ageHours: 0.1, now: now))   // newest, in window
        store.record(event(ageHours: 1, now: now))      // in window
        store.record(event(ageHours: 5, now: now))      // in window
        store.record(event(ageHours: 30, now: now))     // older than 24h → excluded

        let recent = store.recent(now: now)
        #expect(recent.count == 3)
        let first = try #require(recent.first)
        let last = try #require(recent.last)
        #expect(first.timestamp > last.timestamp)                 // newest first
        #expect(store.recent(now: now, limit: 2).count == 2)      // limit caps
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
        //
        // EXPECTED NOISE: this deliberately-broken path makes CoreData/SwiftData
        // print diagnostics to stderr before the Swift error is thrown ("Store
        // failed to load", "errno 20 / Not a directory", NSCocoaError 258). That
        // stderr is below the `try?` layer and can't be swallowed; CI log parsers
        // surface it as red annotations. It is not a regression — the test
        // asserts the fallback succeeds.
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

    @Test("default disk directory preserves release storage and isolates dev builds")
    func defaultDirectoryUsesBundleIdentity() {
        let support = URL.applicationSupportDirectory
        let releaseDirectory = support.appending(path: "LockIME", directoryHint: .isDirectory).path
        let devDirectory = support.appending(path: "com.oomol.LockIME.dev", directoryHint: .isDirectory).path

        #expect(LogStore.defaultDirectory(for: "com.oomol.LockIME").path == releaseDirectory)
        #expect(LogStore.defaultDirectory(for: "com.oomol.LockIME.dev").path == devDirectory)
        #expect(LogStore.defaultDirectory(for: nil).path == releaseDirectory)
    }
}
