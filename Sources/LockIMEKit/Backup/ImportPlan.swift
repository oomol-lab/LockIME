import Foundation

/// How an imported backup combines with the local configuration.
public enum ImportMode: String, Sendable, CaseIterable, Identifiable {
    /// Non-destructive: keep local rules, add the file's new ones, resolve
    /// conflicts per-row (defaulting to the local binding).
    case merge
    /// The file's rules win: local-only rules are dropped and every conflict
    /// takes the file's binding.
    case replace

    public var id: String { rawValue }
}

/// Per-conflict resolution. The vocabulary is LockIME's own ("keep local / use
/// file"), never "ours/theirs".
public enum ConflictResolution: String, Sendable, Equatable {
    case keepLocal
    case useFile
}

/// What to do with a rule whose target input source isn't installed on this
/// machine. "Not installed" is a *derived* state — there is no persisted flag —
/// so `keep` simply leaves the rule (it naturally stays inactive until the
/// source is installed) and `remove` deletes it. A missing source is **never**
/// silently substituted with another.
public enum MissingSourceDisposition: String, Sendable, Equatable {
    case keep
    case remove
}

/// One reviewable binding from an imported backup — the global default, an app
/// rule, or a URL rule — unified so the Review screen and the resolver treat
/// them identically.
public struct ImportItem: Identifiable, Sendable, Equatable {
    public enum Subject: Sendable, Equatable {
        case globalDefault
        case app(bundleID: String)
        case url(hostPattern: String)
    }

    public enum Status: Sendable, Equatable {
        /// Present in the file, absent locally.
        case new
        /// Present in both, with a different binding.
        case conflict
        /// Present in both with an identical binding. Invisible in Merge (a
        /// no-op), but in Replace the file's full rule set wins, so an
        /// unchanged rule is re-asserted (and can surface as missing/removable).
        case unchanged
    }

    public let id: String
    public let subject: Subject
    public let status: Status

    /// File-side app-rule mode (`nil` for the global default and URL rules).
    public let fileMode: AppRuleMode?
    /// The file-side effective locked source (`nil` when the file binding pins
    /// no source — e.g. an app rule in `.ignored`/`.useDefault`).
    public let fileSource: InputSourceID?
    /// Local-side mode/source, populated only for `.conflict` items.
    public let localMode: AppRuleMode?
    public let localSource: InputSourceID?

    // MARK: user choices

    /// Include this `.new` binding in the import (ignored for `.conflict`).
    public var include: Bool
    /// How to resolve a `.conflict` (ignored for `.new`).
    public var resolution: ConflictResolution
    /// What to do when the *effective* binding's source isn't installed.
    public var missingDisposition: MissingSourceDisposition

    init(
        id: String,
        subject: Subject,
        status: Status,
        fileMode: AppRuleMode?,
        fileSource: InputSourceID?,
        localMode: AppRuleMode?,
        localSource: InputSourceID?,
        include: Bool,
        resolution: ConflictResolution,
        missingDisposition: MissingSourceDisposition
    ) {
        self.id = id
        self.subject = subject
        self.status = status
        self.fileMode = fileMode
        self.fileSource = fileSource
        self.localMode = localMode
        self.localSource = localSource
        self.include = include
        self.resolution = resolution
        self.missingDisposition = missingDisposition
    }
}

/// A running tally of an import's effect, recomputed live as the user edits the
/// plan. `added`/`updated`/`removed` are derived by diffing the base config
/// against the resolved one; `kept` counts conflicts left at the local binding.
public struct ImportSummary: Equatable, Sendable {
    public var added: Int
    public var updated: Int
    public var kept: Int
    public var removed: Int
    /// Imported (added or rebound) rules whose source isn't installed — kept but
    /// inactive until it is. Scoped to what the import changed, never a
    /// pre-existing local rule that was merely carried over.
    public var inactive: Int

    /// Whether applying would change anything. A plan that only keeps local
    /// bindings (or imports nothing) is a no-op, so Apply is disabled.
    public var hasEffect: Bool { added > 0 || updated > 0 || removed > 0 }
}

/// The result of applying an import, for the post-Apply receipt.
public struct ImportOutcome: Equatable, Sendable {
    /// Rules added or rebound by the import.
    public var imported: Int
    /// Imported rules that won't take effect until their input source is
    /// installed.
    public var inactive: Int
}

/// An in-memory, editable staging plan for importing a backup. Building it and
/// resolving it are pure — **nothing is persisted until a caller takes
/// `resolvedConfiguration()` and saves it**. Toggling any choice (mode,
/// include, resolution, disposition) only mutates this value.
public struct ImportPlan: Sendable, Equatable {
    public var mode: ImportMode
    public var items: [ImportItem]

    /// The local configuration the import merges into / preserves runtime flags
    /// from. Held so `resolvedConfiguration()` can keep `isEnabled` and
    /// `enhancedModeEnabled` untouched.
    public let baseConfig: LockConfiguration
    /// Local app rules absent from the file — removed by Replace.
    public let localOnlyAppRuleCount: Int
    /// Local URL rules absent from the file — removed by Replace.
    public let localOnlyURLRuleCount: Int
    public let installedSourceIDs: Set<InputSourceID>
    /// Display names for every referenced source: the importing machine's own
    /// names take precedence, with the file's catalog filling in those it lacks
    /// (so a missing source still shows a human label).
    public let sourceNames: [InputSourceID: String]

    public init(
        current: LockConfiguration,
        backup: ConfigBackup,
        installedSources: [InputSource],
        mode: ImportMode = .merge
    ) {
        self.mode = mode
        self.baseConfig = current
        self.installedSourceIDs = Set(installedSources.map(\.id))

        var names: [InputSourceID: String] = [:]
        for (raw, name) in backup.payload.sourceNames {
            names[InputSourceID(raw)] = name
        }
        for source in installedSources {
            names[source.id] = source.localizedName
        }
        self.sourceNames = names

        var items: [ImportItem] = []

        // Global default.
        if let fileDefault = backup.payload.defaultSourceID {
            let status: ImportItem.Status
            if current.defaultSourceID == nil {
                status = .new
            } else if current.defaultSourceID == fileDefault {
                status = .unchanged
            } else {
                status = .conflict
            }
            items.append(ImportItem(
                id: "default", subject: .globalDefault, status: status,
                fileMode: nil, fileSource: fileDefault,
                localMode: nil, localSource: current.defaultSourceID,
                include: true, resolution: .keepLocal, missingDisposition: .keep
            ))
        }

        // App rules (keyed by bundle identifier).
        let localByBundle = Dictionary(
            current.appRules.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first }
        )
        for rule in backup.payload.appRules {
            let fileSource = rule.mode == .locked ? rule.lockedSourceID : nil
            if let local = localByBundle[rule.bundleID] {
                let localSource = local.mode == .locked ? local.lockedSourceID : nil
                let status: ImportItem.Status =
                    (local.mode == rule.mode && localSource == fileSource) ? .unchanged : .conflict
                items.append(ImportItem(
                    id: "app:\(rule.bundleID)", subject: .app(bundleID: rule.bundleID), status: status,
                    fileMode: rule.mode, fileSource: fileSource,
                    localMode: local.mode, localSource: localSource,
                    include: true, resolution: .keepLocal, missingDisposition: .keep
                ))
            } else {
                items.append(ImportItem(
                    id: "app:\(rule.bundleID)", subject: .app(bundleID: rule.bundleID), status: .new,
                    fileMode: rule.mode, fileSource: fileSource, localMode: nil, localSource: nil,
                    include: true, resolution: .keepLocal, missingDisposition: .keep
                ))
            }
        }

        // URL rules (keyed by host pattern).
        let localByHost = Dictionary(
            current.urlRules.map { ($0.hostPattern, $0) }, uniquingKeysWith: { first, _ in first }
        )
        for rule in backup.payload.urlRules {
            if let local = localByHost[rule.hostPattern] {
                let status: ImportItem.Status =
                    local.lockedSourceID == rule.lockedSourceID ? .unchanged : .conflict
                items.append(ImportItem(
                    id: "url:\(rule.hostPattern)", subject: .url(hostPattern: rule.hostPattern), status: status,
                    fileMode: nil, fileSource: rule.lockedSourceID,
                    localMode: nil, localSource: local.lockedSourceID,
                    include: true, resolution: .keepLocal, missingDisposition: .keep
                ))
            } else {
                items.append(ImportItem(
                    id: "url:\(rule.hostPattern)", subject: .url(hostPattern: rule.hostPattern), status: .new,
                    fileMode: nil, fileSource: rule.lockedSourceID, localMode: nil, localSource: nil,
                    include: true, resolution: .keepLocal, missingDisposition: .keep
                ))
            }
        }

        self.items = items

        let fileBundleIDs = Set(backup.payload.appRules.map(\.bundleID))
        let fileHosts = Set(backup.payload.urlRules.map(\.hostPattern))
        self.localOnlyAppRuleCount = current.appRules.filter { !fileBundleIDs.contains($0.bundleID) }.count
        self.localOnlyURLRuleCount = current.urlRules.filter { !fileHosts.contains($0.hostPattern) }.count
    }

    // MARK: - Derived sections (pure functions of the current choices)

    /// New bindings (the file has them, the local config doesn't), **excluding**
    /// any whose effective source is missing — for a brand-new rule the missing
    /// section's keep/remove already subsumes an include toggle, so it lives
    /// there instead and never appears twice.
    public var newItems: [ImportItem] {
        items.filter { $0.status == .new && !effectiveFileSourceIsMissing($0) }
    }

    /// Conflicting bindings (present in both, different). Shown only in Merge
    /// (Replace lets the file win silently). A conflict whose chosen binding
    /// targets a missing source stays here — its keep-local escape hatch must
    /// remain reachable — and the row carries an inline "not installed" warning
    /// instead of moving to the missing section.
    public var conflictItems: [ImportItem] {
        items.filter { $0.status == .conflict }
    }

    /// Items whose *effective* (file-sourced) binding targets a source that
    /// isn't installed, surfaced for a keep/remove decision. Merge conflicts are
    /// excluded (they keep their keep-local/use-file control in the conflict
    /// section); everything else — new rules, and in Replace every file-won
    /// binding — appears here.
    public var missingItems: [ImportItem] {
        items.filter { effectiveFileSourceIsMissing($0) && !($0.status == .conflict && mode == .merge) }
    }

    /// Whether `item`'s binding, under the current mode and choices, comes from
    /// the file (vs keeping the local one or being excluded).
    public func usesFileBinding(_ item: ImportItem) -> Bool {
        switch item.status {
        case .new:
            return item.include
        case .conflict:
            return mode == .replace || item.resolution == .useFile
        case .unchanged:
            // No-op in Merge (local already equals file); re-asserted in Replace
            // where the file's full rule set wins.
            return mode == .replace
        }
    }

    /// Whether `item`'s effective file binding pins a source that isn't
    /// installed locally. False whenever the effective binding is the local one,
    /// excluded, or pins no source.
    public func effectiveFileSourceIsMissing(_ item: ImportItem) -> Bool {
        guard usesFileBinding(item), let source = item.fileSource else { return false }
        return !installedSourceIDs.contains(source)
    }

    // MARK: - Resolution

    /// Fold the plan into a final configuration. Pure: the per-device runtime
    /// flags (`isEnabled`, `enhancedModeEnabled`) are carried straight from the
    /// base config and never imported.
    public func resolvedConfiguration() -> LockConfiguration {
        var appRules: [String: AppRule]
        var urlRules: [String: URLRule]
        var defaultSource: InputSourceID?

        switch mode {
        case .merge:
            appRules = Dictionary(baseConfig.appRules.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
            urlRules = Dictionary(baseConfig.urlRules.map { ($0.hostPattern, $0) }, uniquingKeysWith: { first, _ in first })
            defaultSource = baseConfig.defaultSourceID
        case .replace:
            // Drop local-only rules. The global default is preserved unless the
            // file specifies one (a default item below) — a file without a
            // default never silently clears the user's.
            appRules = [:]
            urlRules = [:]
            defaultSource = baseConfig.defaultSourceID
        }

        for item in items {
            guard usesFileBinding(item) else { continue }
            let drop = effectiveFileSourceIsMissing(item) && item.missingDisposition == .remove

            switch item.subject {
            case .globalDefault:
                // A missing default set to "remove" falls back to the local
                // default rather than clearing it (clearing the global default
                // would strip the lock's target — too destructive to do here).
                if !drop { defaultSource = item.fileSource }
            case .app(let bundleID):
                if drop {
                    appRules[bundleID] = nil
                } else {
                    appRules[bundleID] = AppRule(
                        bundleID: bundleID,
                        mode: item.fileMode ?? .locked,
                        lockedSourceID: item.fileSource
                    )
                }
            case .url(let host):
                if drop {
                    urlRules[host] = nil
                } else if let source = item.fileSource {
                    urlRules[host] = URLRule(hostPattern: host, lockedSourceID: source)
                }
            }
        }

        var result = baseConfig
        result.appRules = appRules.values.sorted { $0.bundleID < $1.bundleID }
        result.urlRules = urlRules.values.sorted { $0.hostPattern < $1.hostPattern }
        result.defaultSourceID = defaultSource
        return result
    }

    // MARK: - Summary

    /// A live tally of the import's effect under the current choices.
    public func summary() -> ImportSummary {
        let resolved = resolvedConfiguration()
        let base = baseConfig

        let baseKeys = bindingKeys(of: base)
        let resolvedKeys = bindingKeys(of: resolved)
        let resolvedSources = bindingSources(of: resolved)

        var added = 0, updated = 0, removed = 0, inactive = 0
        for (key, binding) in resolvedKeys {
            let changed: Bool
            if let was = baseKeys[key] {
                changed = was != binding
                if changed { updated += 1 }
            } else {
                changed = true
                added += 1
            }
            // "Inactive" is scoped to what the import actually added or rebound —
            // never a pre-existing local rule merely carried over — so the receipt
            // ("其中 M 条…未生效") stays a true subset of the imported count.
            if changed, let source = resolvedSources[key], !installedSourceIDs.contains(source) {
                inactive += 1
            }
        }
        for key in baseKeys.keys where resolvedKeys[key] == nil { removed += 1 }

        let kept = items.filter { $0.status == .conflict && !usesFileBinding($0) }.count

        return ImportSummary(added: added, updated: updated, kept: kept, removed: removed, inactive: inactive)
    }

    /// The receipt shown after Apply.
    public func outcome() -> ImportOutcome {
        let s = summary()
        return ImportOutcome(imported: s.added + s.updated, inactive: s.inactive)
    }

    // MARK: - Private helpers

    /// A comparable per-key binding snapshot of a configuration, so the same key
    /// in two configs can be diffed for "changed". The global default is keyed
    /// `"default"`; app rules `"app:<id>"`; URL rules `"url:<host>"`.
    private func bindingKeys(of config: LockConfiguration) -> [String: String] {
        var map: [String: String] = [:]
        if let def = config.defaultSourceID { map["default"] = def.rawValue }
        for rule in config.appRules {
            let source = rule.mode == .locked ? (rule.lockedSourceID?.rawValue ?? "") : ""
            map["app:\(rule.bundleID)"] = "\(rule.mode.rawValue)|\(source)"
        }
        for rule in config.urlRules {
            map["url:\(rule.hostPattern)"] = rule.lockedSourceID.rawValue
        }
        return map
    }

    /// The pinned source per binding key, so an added/updated key can be tested
    /// for "source installed?" when tallying inactive imports. Keyed exactly like
    /// `bindingKeys`. A binding that pins no source contributes no entry.
    private func bindingSources(of config: LockConfiguration) -> [String: InputSourceID] {
        var map: [String: InputSourceID] = [:]
        if let def = config.defaultSourceID { map["default"] = def }
        for rule in config.appRules where rule.mode == .locked {
            if let source = rule.lockedSourceID { map["app:\(rule.bundleID)"] = source }
        }
        for rule in config.urlRules { map["url:\(rule.hostPattern)"] = rule.lockedSourceID }
        return map
    }

    // MARK: - Display

    /// Best human-readable name for a source: the local name, then the file's
    /// captured name, falling back to the raw identifier.
    public func displayName(for id: InputSourceID) -> String {
        sourceNames[id] ?? id.rawValue
    }
}
