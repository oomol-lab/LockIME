import Foundation
import Testing

@testable import LockIMEKit

@Suite("ConfigBackup envelope & codec")
struct ConfigBackupTests {
    private func sampleConfig() -> LockConfiguration {
        LockConfiguration(
            isEnabled: true,
            defaultSourceID: "com.apple.keylayout.US",
            appRules: [
                AppRule(bundleID: "com.apple.Terminal", mode: .locked, lockedSourceID: "com.apple.keylayout.ABC"),
                AppRule(bundleID: "com.game.App", mode: .ignored),
                AppRule(bundleID: "com.other.App", mode: .useDefault),
            ],
            enhancedModeEnabled: true,
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: "com.apple.inputmethod.SCIM.ITABC")]
        )
    }

    private let names: [InputSourceID: String] = [
        "com.apple.keylayout.US": "U.S.",
        "com.apple.keylayout.ABC": "ABC",
        "com.apple.inputmethod.SCIM.ITABC": "Pinyin - Simplified",
    ]

    @Test("make() captures rules and binding intent, dropping per-device runtime state")
    func makeDropsRuntimeState() {
        let backup = ConfigBackup.make(from: sampleConfig(), appVersion: "1.2.3", sourceNames: names)
        #expect(backup.format == ConfigBackup.formatIdentifier)
        #expect(backup.schemaVersion == ConfigBackup.writerSchemaVersion)
        #expect(backup.minReader == ConfigBackup.writerMinReader)
        #expect(backup.appVersion == "1.2.3")
        #expect(backup.payload.defaultSourceID == "com.apple.keylayout.US")
        #expect(backup.payload.appRules.count == 3)
        #expect(backup.payload.urlRules == [BackupURLRule(hostPattern: "github.com", lockedSourceID: "com.apple.inputmethod.SCIM.ITABC")])
    }

    @Test("make() catalogs only referenced sources with known names")
    func makeBuildsNameCatalog() {
        let backup = ConfigBackup.make(from: sampleConfig(), appVersion: "1", sourceNames: names)
        // US (default), ABC (locked app rule), and the URL rule's source — but
        // not the ignored/useDefault app rules (they pin no source).
        #expect(backup.payload.sourceNames == [
            "com.apple.keylayout.US": "U.S.",
            "com.apple.keylayout.ABC": "ABC",
            "com.apple.inputmethod.SCIM.ITABC": "Pinyin - Simplified",
        ])
    }

    @Test("make() omits catalog entries for sources without a known name")
    func makeOmitsUnknownNames() {
        let config = LockConfiguration(defaultSourceID: "com.unknown.source")
        let backup = ConfigBackup.make(from: config, appVersion: "1", sourceNames: [:])
        #expect(backup.payload.sourceNames.isEmpty)
        #expect(backup.payload.defaultSourceID == "com.unknown.source")
    }

    @Test("encoded() round-trips through read()")
    func roundTrip() throws {
        let backup = ConfigBackup.make(from: sampleConfig(), appVersion: "1.2.3", sourceNames: names)
        let data = try backup.encoded()
        let result = ConfigBackup.read(data)
        #expect(try result.get() == backup)
    }

    @Test("switch rules (app .switched, url .switchOnce) survive make→encode→read")
    func switchRulesRoundTrip() throws {
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: "com.apple.keylayout.US",
            appRules: [AppRule(bundleID: "com.apple.Terminal", mode: .switched, lockedSourceID: "com.apple.keylayout.ABC")],
            enhancedModeEnabled: true,
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: "com.apple.inputmethod.SCIM.ITABC", action: .switchOnce)]
        )
        let backup = ConfigBackup.make(from: config, appVersion: "1", sourceNames: names)
        let decoded = try ConfigBackup.read(backup.encoded()).get()
        #expect(decoded.payload.appRules.first?.mode == .switched)
        #expect(decoded.payload.urlRules.first?.action == .switchOnce)
        // A switched app rule pins a source, so it is catalogued like a lock.
        #expect(decoded.payload.sourceNames["com.apple.keylayout.ABC"] == "ABC")
    }

    @Test("the global default's action round-trips through make→encode→read")
    func defaultActionRoundTrips() throws {
        // make() defaults to lock when the config's action is lock.
        let lockBackup = ConfigBackup.make(from: sampleConfig(), appVersion: "1", sourceNames: names)
        #expect(lockBackup.payload.defaultAction == .lock)

        // A switch-action default survives export→read.
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: "com.apple.keylayout.US",
            defaultAction: .switchOnce
        )
        let decoded = try ConfigBackup.read(ConfigBackup.make(from: config, appVersion: "1", sourceNames: names).encoded()).get()
        #expect(decoded.payload.defaultSourceID == "com.apple.keylayout.US")
        #expect(decoded.payload.defaultAction == .switchOnce)
    }

    @Test("a backup missing defaultAction reads as .lock (lenient)")
    func defaultActionMissingDecodesAsLock() throws {
        let json = """
        {"format": "\(ConfigBackup.formatIdentifier)", "minReader": 1, "appVersion": "1",
         "payload": {"defaultSourceID": "com.apple.keylayout.US"}}
        """
        let backup = try ConfigBackup.read(Data(json.utf8)).get()
        #expect(backup.payload.defaultAction == .lock)
        // An unknown value likewise degrades to lock rather than mis-reporting the file.
        let unknown = """
        {"format": "\(ConfigBackup.formatIdentifier)", "minReader": 1, "appVersion": "1",
         "payload": {"defaultSourceID": "com.apple.keylayout.US", "defaultAction": "teleport"}}
        """
        #expect(try ConfigBackup.read(Data(unknown.utf8)).get().payload.defaultAction == .lock)
    }

    @Test("a .lockime URL rule without an action decodes to .lock (lenient)")
    func urlRuleWithoutActionDecodesAsLock() throws {
        let json = """
        {"format": "\(ConfigBackup.formatIdentifier)", "minReader": 1, "appVersion": "1",
         "payload": {"urlRules": [{"hostPattern": "github.com", "lockedSourceID": "com.apple.keylayout.ABC"}]}}
        """
        let backup = try ConfigBackup.read(Data(json.utf8)).get()
        #expect(backup.payload.urlRules.first?.action == .lock)
        // A backup that predates match types likewise decodes to the original
        // suffix behavior — old .lockime files keep loading unchanged.
        #expect(backup.payload.urlRules.first?.matchType == .domainSuffix)
    }

    @Test("a backup with an unknown matchType/action degrades it, not the whole read")
    func unknownEnumValuesDecodeLeniently() throws {
        // A backup from a newer LockIME may carry a matchType/action value this
        // build doesn't know. A non-lenient decoder would throw, propagate through
        // the urlRules array decode, and mis-report the whole file as `.damaged`.
        // Each unknown value must degrade to its default while the rest reads fine.
        let json = """
        {"format": "\(ConfigBackup.formatIdentifier)", "minReader": 1, "appVersion": "9",
         "payload": {"defaultSourceID": "com.apple.keylayout.US", "urlRules": [
            {"hostPattern": "github.com", "lockedSourceID": "com.apple.keylayout.ABC", "action": "warp", "matchType": "telepathy"},
            {"hostPattern": "example.com", "lockedSourceID": "com.apple.keylayout.US", "action": "switchOnce", "matchType": "domain"}
         ]}}
        """
        let backup = try ConfigBackup.read(Data(json.utf8)).get()   // NOT .damaged
        #expect(backup.payload.urlRules.count == 2)
        #expect(backup.payload.defaultSourceID == "com.apple.keylayout.US")
        let gh = try #require(backup.payload.urlRules.first { $0.hostPattern == "github.com" })
        #expect(gh.action == .lock)
        #expect(gh.matchType == .domainSuffix)
        let ex = try #require(backup.payload.urlRules.first { $0.hostPattern == "example.com" })
        #expect(ex.action == .switchOnce)
        #expect(ex.matchType == .domain)
    }

    @Test("URL-rule match types survive make→encode→read")
    func matchTypesRoundTrip() throws {
        let config = LockConfiguration(
            enhancedModeEnabled: true,
            urlRules: [
                URLRule(hostPattern: "github.com", lockedSourceID: "com.apple.keylayout.US", matchType: .domain),
                URLRule(hostPattern: "google", lockedSourceID: "com.apple.keylayout.ABC", matchType: .domainKeyword),
                URLRule(hostPattern: "/pull/", lockedSourceID: "com.apple.inputmethod.SCIM.ITABC", action: .switchOnce, matchType: .urlRegex),
            ]
        )
        let decoded = try ConfigBackup.read(ConfigBackup.make(from: config, appVersion: "1", sourceNames: names).encoded()).get()
        #expect(decoded.payload.urlRules.map(\.matchType) == [.domain, .domainKeyword, .urlRegex])
        // Order is priority and must survive the round-trip (a JSON array preserves it).
        #expect(decoded.payload.urlRules.map(\.hostPattern) == ["github.com", "google", "/pull/"])
        #expect(decoded.payload.urlRules.last?.action == .switchOnce)
    }

    @Test("encoded() is human-readable pretty JSON with unescaped slashes")
    func prettyEncoding() throws {
        let backup = ConfigBackup.make(from: sampleConfig(), appVersion: "1", sourceNames: names)
        let text = try #require(String(data: backup.encoded(), encoding: .utf8))
        #expect(text.contains("\n"))
        #expect(text.contains("com.oomol.LockIME.backup"))
        // .withoutEscapingSlashes keeps bundle IDs readable.
        #expect(!text.contains("\\/"))
    }

    @Test("read() rejects non-JSON bytes as not-a-backup")
    func readsNonJSON() {
        #expect(ConfigBackup.read(Data("not json".utf8)) == .failure(.notABackup))
    }

    @Test("read() rejects valid JSON that isn't a LockIME backup")
    func readsWrongFormat() {
        let json = #"{"format": "com.someone.else", "payload": {}}"#
        #expect(ConfigBackup.read(Data(json.utf8)) == .failure(.notABackup))
        // Also a JSON object with no format at all.
        #expect(ConfigBackup.read(Data("{}".utf8)) == .failure(.notABackup))
    }

    @Test("read() rejects a file whose minReader exceeds this build")
    func readsTooNew() {
        let json = """
        {"format": "\(ConfigBackup.formatIdentifier)", "schemaVersion": 99, \
        "minReader": \(ConfigBackup.readerVersion + 1), "appVersion": "9.9.9", \
        "payload": {"appRules": [], "urlRules": []}}
        """
        #expect(ConfigBackup.read(Data(json.utf8)) == .failure(.incompatibleVersion(appVersion: "9.9.9")))
    }

    @Test("version gate fires before payload decoding (unparseable future payload)")
    func gateBeforeDecode() {
        // A future file we can't decode must still report incompatibleVersion,
        // never damaged — that's what tells the user to update.
        let json = """
        {"format": "\(ConfigBackup.formatIdentifier)", \
        "minReader": \(ConfigBackup.readerVersion + 5), "appVersion": "10.0", \
        "payload": {"appRules": "this is not an array"}}
        """
        #expect(ConfigBackup.read(Data(json.utf8)) == .failure(.incompatibleVersion(appVersion: "10.0")))
    }

    @Test("too-new file with no appVersion still reports an empty version")
    func tooNewMissingAppVersion() {
        let json = """
        {"format": "\(ConfigBackup.formatIdentifier)", \
        "minReader": \(ConfigBackup.readerVersion + 1), "payload": {}}
        """
        #expect(ConfigBackup.read(Data(json.utf8)) == .failure(.incompatibleVersion(appVersion: "")))
    }

    @Test("read() reports a compatible-but-broken file as damaged")
    func readsDamaged() {
        // Correct format + compatible version, but the payload is the wrong type.
        let json = #"{"format": "com.oomol.LockIME.backup", "minReader": 1, "payload": "broken"}"#
        #expect(ConfigBackup.read(Data(json.utf8)) == .failure(.damaged))
    }

    @Test("read() defaults a missing minReader to the writer minimum (lenient)")
    func readsMissingMinReader() throws {
        let json = """
        {"format": "\(ConfigBackup.formatIdentifier)", \
        "payload": {"defaultSourceID": "com.apple.keylayout.US"}}
        """
        let backup = try ConfigBackup.read(Data(json.utf8)).get()
        #expect(backup.minReader == ConfigBackup.writerMinReader)
        #expect(backup.payload.defaultSourceID == "com.apple.keylayout.US")
    }

    @Test("read() ignores unknown fields and defaults absent payload arrays")
    func forwardCompatibleDecode() throws {
        let json = """
        {"format": "\(ConfigBackup.formatIdentifier)", "schemaVersion": 1, "minReader": 1, \
        "appVersion": "2.0", "futureFlag": true, \
        "payload": {"defaultSourceID": "com.apple.keylayout.US", "futureRules": [1,2,3]}}
        """
        let backup = try ConfigBackup.read(Data(json.utf8)).get()
        #expect(backup.payload.defaultSourceID == "com.apple.keylayout.US")
        #expect(backup.payload.appRules.isEmpty)
        #expect(backup.payload.urlRules.isEmpty)
        #expect(backup.payload.sourceNames.isEmpty)
    }

    @Test("a backup carrying per-device runtime fields ignores them (only rules are read)")
    func ignoresRuntimeFields() throws {
        // The portable format has no place for isEnabled / enhancedModeEnabled /
        // language, so a file that smuggles them in is read as if they weren't
        // there — import can never flip per-device runtime state.
        let json = """
        {"format": "\(ConfigBackup.formatIdentifier)", "minReader": 1, "appVersion": "1", "isEnabled": true,
         "payload": {"defaultSourceID": "com.apple.keylayout.US",
                     "appRules": [{"bundleID": "com.a", "mode": "locked", "lockedSourceID": "com.apple.keylayout.ABC"}],
                     "urlRules": [], "enhancedModeEnabled": true, "isEnabled": true, "languagePreference": "ja"}}
        """
        let backup = try ConfigBackup.read(Data(json.utf8)).get()
        #expect(backup.payload.defaultSourceID == "com.apple.keylayout.US")
        #expect(backup.payload.appRules.count == 1)
        // BackupPayload simply has no isEnabled / enhancedModeEnabled / language
        // members — the smuggled keys decode to nothing.
    }

    @Test("BackupPayload decodes an empty object to all-empty defaults")
    func payloadEmptyDefaults() throws {
        let payload = try JSONDecoder().decode(BackupPayload.self, from: Data("{}".utf8))
        #expect(payload.defaultSourceID == nil)
        #expect(payload.defaultAction == .lock)
        #expect(payload.appRules.isEmpty)
        #expect(payload.urlRules.isEmpty)
        #expect(payload.sourceNames.isEmpty)
    }

    // MARK: - Suggested export filename

    /// A `Date` at the given wall-clock components in a fixed zone, so the
    /// expected filename is deterministic regardless of the test host's zone.
    private func date(
        _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int,
        in timeZone: TimeZone
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute, c.second) = (y, mo, d, h, mi, s)
        return calendar.date(from: c)!
    }

    @Test("suggestedFileNameStem is the panel name field value — no extension, no dots")
    func suggestedFileNameStemHasNoDots() {
        // The export panel feeds this to NSSavePanel and lets allowedContentTypes
        // append the extension. The stem must carry NO dots — a dot would look
        // like an extension to the panel and risk a doubled `.lockime.lockime`.
        let tz = TimeZone(identifier: "America/New_York")!
        let stem = ConfigBackup.suggestedFileNameStem(date: date(2026, 6, 22, 23, 15, 28, in: tz), timeZone: tz)
        #expect(stem == "LockIME Backup 2026-06-22 23-15-28")
        #expect(!stem.contains("."))
        #expect((stem as NSString).pathExtension.isEmpty)
    }

    @Test("suggestedFileName is the stem plus exactly the .lockime extension")
    func suggestedFileNameIsStemPlusExtension() {
        let tz = TimeZone(identifier: "UTC")!
        let date = date(2026, 6, 22, 23, 15, 28, in: tz)
        let stem = ConfigBackup.suggestedFileNameStem(date: date, timeZone: tz)
        let full = ConfigBackup.suggestedFileName(date: date, timeZone: tz)
        #expect(full == "\(stem).\(ConfigBackup.fileExtension)")
    }

    @Test("suggestedFileName stamps a fixed yyyy-MM-dd HH-mm-ss layout")
    func suggestedFileNameLayout() {
        let tz = TimeZone(identifier: "America/New_York")!
        let name = ConfigBackup.suggestedFileName(date: date(2026, 6, 22, 14, 30, 15, in: tz), timeZone: tz)
        #expect(name == "LockIME Backup 2026-06-22 14-30-15.lockime")
    }

    @Test("suggestedFileName zero-pads every component")
    func suggestedFileNameZeroPads() {
        let tz = TimeZone(identifier: "UTC")!
        let name = ConfigBackup.suggestedFileName(date: date(2026, 1, 2, 3, 4, 5, in: tz), timeZone: tz)
        #expect(name == "LockIME Backup 2026-01-02 03-04-05.lockime")
    }

    @Test("suggestedFileName renders wall-clock time in the given zone")
    func suggestedFileNameHonorsZone() {
        // The same instant reads as different wall-clock times per zone, so the
        // stamp must reflect the zone passed in — not the host's.
        let instant = date(2026, 6, 22, 12, 0, 0, in: TimeZone(identifier: "UTC")!)
        let tokyo = ConfigBackup.suggestedFileName(date: instant, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        let utc = ConfigBackup.suggestedFileName(date: instant, timeZone: TimeZone(identifier: "UTC")!)
        #expect(tokyo == "LockIME Backup 2026-06-22 21-00-00.lockime")
        #expect(utc == "LockIME Backup 2026-06-22 12-00-00.lockime")
    }

    @Test("suggestedFileName carries the brand prefix and the backup extension")
    func suggestedFileNamePrefixAndExtension() {
        let tz = TimeZone(identifier: "UTC")!
        let name = ConfigBackup.suggestedFileName(date: date(2026, 6, 22, 9, 8, 7, in: tz), timeZone: tz)
        #expect(name.hasPrefix(ConfigBackup.fileNamePrefix + " "))
        #expect(name.hasSuffix("." + ConfigBackup.fileExtension))
    }

    @Test("suggestedFileName produces a filename-legal name (no reserved separators)")
    func suggestedFileNameIsLegal() {
        let tz = TimeZone(identifier: "UTC")!
        let name = ConfigBackup.suggestedFileName(date: date(2026, 6, 22, 14, 30, 15, in: tz), timeZone: tz)
        // `:` is reserved on macOS (and `/` is the path separator); the stamp
        // must avoid both — that's why the time uses `-`.
        #expect(!name.contains(":"))
        #expect(!name.contains("/"))
    }

    @Test("suggestedFileName contains exactly one dot — the extension separator")
    func suggestedFileNameHasSingleDot() {
        // Regression guard: a timestamp with interior dots (e.g. `…23.15.28`)
        // gives the name a multi-part trailing extension that fools NSSavePanel
        // into appending `.lockime` a second time → `….lockime.lockime`. The only
        // `.` in the name must be the one before the extension.
        let tz = TimeZone(identifier: "UTC")!
        let name = ConfigBackup.suggestedFileName(date: date(2026, 6, 22, 23, 15, 28, in: tz), timeZone: tz)
        #expect(name.filter { $0 == "." }.count == 1)
        #expect((name as NSString).pathExtension == ConfigBackup.fileExtension)
    }

    @Test("suggestedFileName defaults to the current zone (the production call site)")
    func suggestedFileNameDefaultsToCurrentZone() {
        // The export panel calls `suggestedFileName(date:)` with no zone, leaning
        // on the `timeZone = .current` default. Exercise that default path without
        // hardcoding a host-zone-dependent expected string: it must equal the same
        // call made with `.current` passed explicitly.
        let instant = date(2026, 6, 22, 12, 0, 0, in: TimeZone(identifier: "UTC")!)
        #expect(ConfigBackup.suggestedFileName(date: instant)
            == ConfigBackup.suggestedFileName(date: instant, timeZone: .current))
    }

    @Test("suggestedFileName names later exports so they sort after earlier ones")
    func suggestedFileNameSortsChronologically() {
        let tz = TimeZone(identifier: "UTC")!
        // The distinguishability goal: distinct moments give distinct names, and
        // lexicographic order matches chronological order (sortable in Finder).
        let earlier = ConfigBackup.suggestedFileName(date: date(2026, 6, 22, 9, 0, 0, in: tz), timeZone: tz)
        let later = ConfigBackup.suggestedFileName(date: date(2026, 6, 22, 9, 0, 1, in: tz), timeZone: tz)
        #expect(earlier != later)
        #expect(earlier < later)
    }
}
