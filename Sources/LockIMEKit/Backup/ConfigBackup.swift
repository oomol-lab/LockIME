import Foundation

/// A URL rule as stored in a backup file. Unlike `URLRule` it carries no UUID:
/// the runtime identity is per-device and not portable, so backups key URL rules
/// solely by their `hostPattern` (the same key the import diff matches on).
public struct BackupURLRule: Codable, Equatable, Sendable {
    public var hostPattern: String
    public var lockedSourceID: InputSourceID
    /// Whether a matched URL locks to the source or just switches to it once.
    public var action: RuleAction
    /// How `hostPattern` is matched against the browser's current URL.
    public var matchType: URLMatchType

    public init(
        hostPattern: String,
        lockedSourceID: InputSourceID,
        action: RuleAction = .lock,
        matchType: URLMatchType = .domainSuffix
    ) {
        self.hostPattern = hostPattern
        self.lockedSourceID = lockedSourceID
        self.action = action
        self.matchType = matchType
    }

    private enum CodingKeys: String, CodingKey {
        case hostPattern, lockedSourceID, action, matchType
    }

    // Lenient: a backup written before the lock/switch distinction carries no
    // `action` → default `.lock`, and one written before match types carries no
    // `matchType` → default `.domainSuffix` (the original host-suffix behavior).
    // `action`/`matchType` are decoded as raw *strings* and mapped, so an
    // *unrecognized* value (a newer LockIME wrote a match type this build doesn't
    // know) also falls back to the default rather than throwing — otherwise that
    // throw propagates through `decodeIfPresent([BackupURLRule].self)` and the
    // whole backup mis-reports as `.damaged`. Keeps reading robust even though the
    // .lockime format itself is pre-release.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostPattern = try container.decode(String.self, forKey: .hostPattern)
        lockedSourceID = try container.decode(InputSourceID.self, forKey: .lockedSourceID)
        let rawAction = try container.decodeIfPresent(String.self, forKey: .action)
        action = rawAction.flatMap(RuleAction.init(rawValue:)) ?? .lock
        let rawMatchType = try container.decodeIfPresent(String.self, forKey: .matchType)
        matchType = rawMatchType.flatMap(URLMatchType.init(rawValue:)) ?? .domainSuffix
    }
}

/// The portable part of a `LockConfiguration` — the "rules and binding intent"
/// a backup carries between machines: the global default source (and its
/// lock/switch action), per-app rules, and per-URL rules. Per-device *runtime*
/// state (the master lock, enhanced mode, language preference, the login item)
/// is deliberately **not** here, so importing never flips those on someone
/// else's machine.
///
/// `sourceNames` is a display-name catalog (input-source identifier → its name
/// at export time) so a target machine that is missing an input source can
/// still show a human-readable label instead of a bare identifier.
public struct BackupPayload: Codable, Equatable, Sendable {
    public var defaultSourceID: InputSourceID?
    /// The global default's lock/switch behavior; travels with `defaultSourceID`
    /// on import. Default `.lock` (fully backward compatible). Mirrors
    /// `LockConfiguration.defaultAction`.
    public var defaultAction: RuleAction
    public var appRules: [AppRule]
    public var urlRules: [BackupURLRule]
    public var sourceNames: [String: String]

    public init(
        defaultSourceID: InputSourceID? = nil,
        defaultAction: RuleAction = .lock,
        appRules: [AppRule] = [],
        urlRules: [BackupURLRule] = [],
        sourceNames: [String: String] = [:]
    ) {
        self.defaultSourceID = defaultSourceID
        self.defaultAction = defaultAction
        self.appRules = appRules
        self.urlRules = urlRules
        self.sourceNames = sourceNames
    }

    // Forward/backward-compatible decoding: a newer file may add fields (ignored
    // by `Decoder` automatically) and an older/partial file may omit some — every
    // key falls back to an empty default so reading stays lenient.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultSourceID = try container.decodeIfPresent(InputSourceID.self, forKey: .defaultSourceID)
        // Decode the action as a raw *string* and map it (same rationale as
        // `BackupURLRule.action`): a missing key (a backup written before the
        // global default carried an action) OR an unrecognized value both fall
        // back to `.lock` rather than throwing and mis-reporting the file.
        let rawDefaultAction = try container.decodeIfPresent(String.self, forKey: .defaultAction)
        defaultAction = rawDefaultAction.flatMap(RuleAction.init(rawValue:)) ?? .lock
        appRules = try container.decodeIfPresent([AppRule].self, forKey: .appRules) ?? []
        urlRules = try container.decodeIfPresent([BackupURLRule].self, forKey: .urlRules) ?? []
        sourceNames = try container.decodeIfPresent([String: String].self, forKey: .sourceNames) ?? [:]
    }
}

/// A versioned, file-level configuration backup (`.lockime` JSON).
///
/// The envelope is built to evolve safely:
/// - `format` is a fixed identifier — a file without it isn't one of ours.
/// - `schemaVersion` is the integer schema this file was written against.
/// - `minReader` is the **lowest** reader capability that can safely read it; a
///   file whose `minReader` exceeds this build's `readerVersion` is cleanly
///   rejected ("please update LockIME"), shown via the human `appVersion` string
///   — never the raw integer.
/// - `appVersion` is the human-readable version that wrote the file.
///
/// Evolution rule: only ever add *optional* fields, so older readers keep
/// loading newer files (and bump `minReader` only on a genuinely breaking
/// change).
public struct ConfigBackup: Codable, Equatable, Sendable {
    public var format: String
    public var schemaVersion: Int
    public var minReader: Int
    public var appVersion: String
    public var payload: BackupPayload

    public init(
        format: String = ConfigBackup.formatIdentifier,
        schemaVersion: Int = ConfigBackup.writerSchemaVersion,
        minReader: Int = ConfigBackup.writerMinReader,
        appVersion: String,
        payload: BackupPayload
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.minReader = minReader
        self.appVersion = appVersion
        self.payload = payload
    }

    // Lenient envelope decoding: tolerate a compatible file that omits an
    // envelope field (defaulting it) rather than rejecting it as damaged. Only
    // `payload` is genuinely required; `read(_:)` has already verified `format`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? ConfigBackup.formatIdentifier
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? ConfigBackup.writerSchemaVersion
        minReader = try container.decodeIfPresent(Int.self, forKey: .minReader) ?? ConfigBackup.writerMinReader
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        payload = try container.decode(BackupPayload.self, forKey: .payload)
    }
}

public extension ConfigBackup {
    /// Marks a file as a LockIME backup; a file lacking it isn't ours.
    static let formatIdentifier = "com.oomol.LockIME.backup"
    /// The schema version this build writes.
    static let writerSchemaVersion = 1
    /// The `minReader` this build stamps into files it writes — i.e. the lowest
    /// reader capability that can safely read today's files.
    static let writerMinReader = 1
    /// This build's reading capability. A file is rejected as too new when its
    /// `minReader` exceeds this value.
    static let readerVersion = 1

    /// The conventional file extension for exported backups.
    static let fileExtension = "lockime"

    /// The fixed, brand prefix every exported backup's default filename carries
    /// (before the timestamp). ASCII and **unlocalized on purpose**: it keeps a
    /// folder of exports grouped and sortable regardless of the app's display
    /// language, and "LockIME" is the brand (never translated).
    static let fileNamePrefix = "LockIME Backup"

    /// The default export filename **without** the extension — the value the
    /// export `NSSavePanel` should put in its name field. The panel appends the
    /// single, correct `.lockime` from its `allowedContentTypes`; see
    /// `suggestedFileName` for why the extension is *not* embedded here.
    ///
    /// The stem is the brand prefix plus a wall-clock timestamp built from
    /// calendar components in a fixed, locale-independent layout
    /// (`yyyy-MM-dd HH-mm-ss`) — deliberately *not* a localized `DateFormatter`
    /// string, which would (a) leak the **system** locale into a name the app's
    /// language override is meant to govern and (b) risk filename-illegal
    /// separators (a `:` is reserved on macOS). Time fields use `-`, never `.`,
    /// so the stem carries **no dots at all** — nothing `NSSavePanel` could
    /// mistake for an existing extension. The ASCII layout sorts chronologically
    /// by name.
    ///
    /// - Parameters:
    ///   - date: the moment to stamp (the caller passes `Date()` at export time).
    ///   - timeZone: the zone the wall-clock time is rendered in; defaults to the
    ///     user's current zone, injectable for deterministic tests.
    static func suggestedFileNameStem(date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(
            format: "%04d-%02d-%02d %02d-%02d-%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
        return "\(fileNamePrefix) \(stamp)"
    }

    /// The full default export filename, `<stem>.lockime`, for contexts that
    /// need a complete name (logging, non-panel saves).
    ///
    /// The export panel does **not** use this — it feeds `suggestedFileNameStem`
    /// and lets `allowedContentTypes` append the extension. Embedding the
    /// extension in `NSSavePanel.nameFieldStringValue` risks a doubled
    /// `….lockime.lockime`: the panel ensures the saved file carries an allowed
    /// extension, and if its own extension-detection doesn't cleanly match the
    /// embedded one (notably when the stem contains dots, e.g. a `23.15.28`
    /// time), it appends `.lockime` a second time. Letting the panel own the
    /// extension sidesteps that entirely.
    static func suggestedFileName(date: Date, timeZone: TimeZone = .current) -> String {
        "\(suggestedFileNameStem(date: date, timeZone: timeZone)).\(fileExtension)"
    }

    /// Build a backup envelope from a live configuration, dropping the per-device
    /// runtime state and capturing a display-name catalog for every referenced
    /// input source whose name is known.
    static func make(
        from config: LockConfiguration,
        appVersion: String,
        sourceNames: [InputSourceID: String]
    ) -> ConfigBackup {
        // Only source-pinning app rules (lock/switch) carry a source; the
        // ignore/use-default modes don't.
        let appRuleSources = config.appRules.compactMap { rule in
            rule.mode.pinsSource ? rule.lockedSourceID : nil
        }
        let referenced: [InputSourceID] =
            ([config.defaultSourceID].compactMap { $0 })
            + appRuleSources
            + config.urlRules.map(\.lockedSourceID)

        var catalog: [String: String] = [:]
        for id in referenced where catalog[id.rawValue] == nil {
            if let name = sourceNames[id] { catalog[id.rawValue] = name }
        }

        let payload = BackupPayload(
            defaultSourceID: config.defaultSourceID,
            defaultAction: config.defaultAction,
            appRules: config.appRules,
            urlRules: config.urlRules.map { BackupURLRule(hostPattern: $0.hostPattern, lockedSourceID: $0.lockedSourceID, action: $0.action, matchType: $0.matchType) },
            sourceNames: catalog
        )
        return ConfigBackup(appVersion: appVersion, payload: payload)
    }

    /// Encode to pretty-printed, key-sorted JSON so the file is human-readable.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Parse and version-gate a backup file's bytes.
    ///
    /// The gate runs *before* fully decoding the payload, so a file written by a
    /// newer LockIME (whose payload this build may not understand) still reports
    /// `incompatibleVersion` rather than a confusing `damaged`. The original
    /// parse error is never surfaced to the user — callers map the returned
    /// category to a catalog key (see the i18n rules), the same shape as
    /// `UpdateFailure`.
    static func read(_ data: Data) -> Result<ConfigBackup, BackupReadError> {
        // 1) Must be a JSON object. (Bytes that don't parse aren't one of ours;
        //    a genuine I/O failure to *read* the file is `.unreadable`, raised by
        //    the caller before it ever gets here.)
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let top = object as? [String: Any]
        else {
            return .failure(.notABackup)
        }
        // 2) Must carry our format identifier.
        guard let format = top["format"] as? String, format == formatIdentifier else {
            return .failure(.notABackup)
        }
        // 3) Version gate, reading only the envelope fields. A missing/invalid
        //    `minReader` is treated as the writer minimum (lenient — these are
        //    our own files), so it never spuriously rejects.
        let minReader = (top["minReader"] as? Int) ?? writerMinReader
        if minReader > readerVersion {
            let appVersion = (top["appVersion"] as? String) ?? ""
            return .failure(.incompatibleVersion(appVersion: appVersion))
        }
        // 4) Compatible: decode in full (lenient payload). A structural failure
        //    here means the file is damaged.
        guard let backup = try? JSONDecoder().decode(ConfigBackup.self, from: data) else {
            return .failure(.damaged)
        }
        return .success(backup)
    }
}

/// A semantic category of failure when reading a backup file, mirroring
/// `UpdateFailure`: surfaces carry this value and resolve a catalog key at
/// render time, so the message follows the in-app language override instead of
/// leaking a system-localized `error.localizedDescription`.
public enum BackupReadError: Error, Equatable, Sendable {
    /// The file's bytes couldn't be read at all (I/O, permissions). Raised by the
    /// caller that loads the file, not by `read(_:)`.
    case unreadable
    /// The bytes were read fine, but it isn't a LockIME backup — not JSON, or
    /// missing/wrong format identifier.
    case notABackup
    /// A LockIME backup whose contents are structurally broken.
    case damaged
    /// Written by a newer LockIME than this build can read. Carries the
    /// human-readable `appVersion` for the "please update" message — never the
    /// raw schema integer.
    case incompatibleVersion(appVersion: String)
}
