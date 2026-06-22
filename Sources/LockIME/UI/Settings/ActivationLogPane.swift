import LockIMEKit
import SwiftData
import SwiftUI

struct ActivationLogPane: View {
    @Environment(AppState.self) private var state
    @Query private var entries: [ActivationLogEntry]

    init() {
        let cutoff = Date.now.addingTimeInterval(-LogStore.retention)
        _entries = Query(
            filter: #Predicate<ActivationLogEntry> { $0.timestamp > cutoff },
            sort: \ActivationLogEntry.timestamp,
            order: .reverse
        )
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Forced input-source switches from the last 24 hours appear here.")
                )
            } else {
                Table(entries) {
                    TableColumn("Time") { entry in
                        Text(entry.timestamp, format: .dateTime.hour().minute().second())
                            .monospacedDigit()
                    }
                    TableColumn("Input source") { entry in
                        // Show "from → to" when the prior source is known and
                        // differs; the arrow is a verbatim glyph, never localized.
                        if let from = entry.fromSourceName, from != entry.inputSourceName {
                            Text(verbatim: "\(from) → \(entry.inputSourceName)")
                        } else {
                            Text(entry.inputSourceName)
                        }
                    }
                    TableColumn("App") { entry in
                        // App/bundle names are identifiers, shown verbatim.
                        Text(verbatim: entry.triggeringAppName ?? entry.triggeringBundleID ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Reason") { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Self.reasonLabel(entry.reasonRaw))
                            Group {
                                if entry.reason == .urlMatched, let host = entry.matchedHost {
                                    Text(verbatim: host)
                                } else if let raw = entry.ruleSourceRaw,
                                          let label = Self.ruleSourceLabel(raw) {
                                    Text(label)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    TableColumn("Duration") { entry in
                        // " ms" stays verbatim (a unit, never localized); the
                        // number formats in the app's chosen language, not the
                        // system locale.
                        Text(verbatim: "\(entry.durationMs.formatted(.number.precision(.fractionLength(1)).locale(state.locale))) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(state.loc("Activation Log"))
        .onAppear { state.purgeLog() }
    }

    static func reasonLabel(_ raw: String) -> LocalizedStringKey {
        switch ActivationReason(rawValue: raw) {
        case .revertedSwitch: "Reverted switch"
        case .appActivated: "App activated"
        case .launcherFocused: "Launcher opened"
        case .launcherDismissed: "Launcher closed"
        case .urlPolled: "URL re-checked"
        case .urlMatched: "URL matched"
        case .addressBarFocused: "Address bar focused"
        case .addressBarBlurred: "Address bar blurred"
        case .lockEngaged: "Lock engaged"
        case .configChanged: "Settings changed"
        case .startupApplied: "Lock restored"
        case .apiCommand: "API command"
        case nil: LocalizedStringKey(raw)
        }
    }

    /// The rule branch behind a forced switch, shown as a dimmed subtitle.
    /// `nil` for an unrecognized raw value (e.g. a legacy row with no branch).
    static func ruleSourceLabel(_ raw: String) -> LocalizedStringKey? {
        switch RuleSource(rawValue: raw) {
        case .appRule: return "App rule"
        case .globalDefault: return "Default rule"
        case .urlRule: return "URL rule"
        case .addressBarRule: return "Address-bar rule"
        case nil: return nil
        }
    }
}
