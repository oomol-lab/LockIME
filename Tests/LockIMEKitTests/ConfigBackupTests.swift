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

    @Test("a .lockime URL rule without an action decodes to .lock (lenient)")
    func urlRuleWithoutActionDecodesAsLock() throws {
        let json = """
        {"format": "\(ConfigBackup.formatIdentifier)", "minReader": 1, "appVersion": "1",
         "payload": {"urlRules": [{"hostPattern": "github.com", "lockedSourceID": "com.apple.keylayout.ABC"}]}}
        """
        let backup = try ConfigBackup.read(Data(json.utf8)).get()
        #expect(backup.payload.urlRules.first?.action == .lock)
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
        #expect(payload.appRules.isEmpty)
        #expect(payload.urlRules.isEmpty)
        #expect(payload.sourceNames.isEmpty)
    }
}
