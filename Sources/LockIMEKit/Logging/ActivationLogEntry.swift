import Foundation
import SwiftData

/// A persisted record of one forced input-source switch. Kept for 24 hours.
@Model
public final class ActivationLogEntry {
    public var timestamp: Date
    public var inputSourceID: String
    public var inputSourceName: String
    /// `ActivationReason.rawValue` (stored as a string for SwiftData simplicity).
    public var reasonRaw: String
    /// Wall time the switch took, in milliseconds.
    public var durationMs: Double
    // The fields below are optional so SwiftData's automatic lightweight
    // migration can open an older on-disk store (rows written before they
    // existed simply carry `nil`). Do NOT make any of them non-optional.
    /// Localized name of the source switched away from, when known.
    public var fromSourceName: String?
    /// Bundle ID of the app/launcher the rule resolved against.
    public var triggeringBundleID: String?
    /// Display name resolved from `triggeringBundleID` at record time (the app
    /// may have quit by the time the row is viewed).
    public var triggeringAppName: String?
    /// `RuleSource.rawValue` — which rule branch produced the target.
    public var ruleSourceRaw: String?
    /// The matched URL rule's host pattern, for `urlMatched` rows.
    public var matchedHost: String?

    public init(
        timestamp: Date,
        inputSourceID: String,
        inputSourceName: String,
        reasonRaw: String,
        durationMs: Double,
        fromSourceName: String? = nil,
        triggeringBundleID: String? = nil,
        triggeringAppName: String? = nil,
        ruleSourceRaw: String? = nil,
        matchedHost: String? = nil
    ) {
        self.timestamp = timestamp
        self.inputSourceID = inputSourceID
        self.inputSourceName = inputSourceName
        self.reasonRaw = reasonRaw
        self.durationMs = durationMs
        self.fromSourceName = fromSourceName
        self.triggeringBundleID = triggeringBundleID
        self.triggeringAppName = triggeringAppName
        self.ruleSourceRaw = ruleSourceRaw
        self.matchedHost = matchedHost
    }

    /// Build a row from an event. `triggeringAppName` is resolved by the caller
    /// (it needs `NSWorkspace`, kept out of the non-UI kit) and injected here.
    public convenience init(_ event: ActivationEvent, triggeringAppName: String? = nil) {
        self.init(
            timestamp: event.timestamp,
            inputSourceID: event.inputSource.rawValue,
            inputSourceName: event.inputSourceName,
            reasonRaw: event.reason.rawValue,
            durationMs: event.durationMs,
            fromSourceName: event.fromSourceName,
            triggeringBundleID: event.triggeringBundleID,
            triggeringAppName: triggeringAppName,
            ruleSourceRaw: event.ruleSource?.rawValue,
            matchedHost: event.matchedHost
        )
    }

    public var reason: ActivationReason? { ActivationReason(rawValue: reasonRaw) }
    public var ruleSource: RuleSource? { ruleSourceRaw.flatMap(RuleSource.init(rawValue:)) }
}
