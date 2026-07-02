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
    /// File-side URL-rule action — lock vs one-shot switch (`nil` for the global
    /// default and app rules, whose lock/switch distinction rides in the mode).
    public let fileAction: RuleAction?
    /// File-side URL-rule match type (`nil` for the global default and app rules).
    public let fileMatchType: URLMatchType?
    /// Local-side mode/source, populated only for `.conflict` items.
    public let localMode: AppRuleMode?
    public let localSource: InputSourceID?
    /// Local-side URL-rule action, populated only for URL `.conflict` items.
    public let localAction: RuleAction?
    /// Local-side URL-rule match type, populated only for URL `.conflict` items.
    public let localMatchType: URLMatchType?

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
        missingDisposition: MissingSourceDisposition,
        fileAction: RuleAction? = nil,
        localAction: RuleAction? = nil,
        fileMatchType: URLMatchType? = nil,
        localMatchType: URLMatchType? = nil
    ) {
        self.id = id
        self.subject = subject
        self.status = status
        self.fileMode = fileMode
        self.fileSource = fileSource
        self.fileAction = fileAction
        self.fileMatchType = fileMatchType
        self.localMode = localMode
        self.localSource = localSource
        self.localAction = localAction
        self.localMatchType = localMatchType
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
    /// Whether the file orders the URL rules it shares with the local config in a
    /// different priority sequence. Order is priority (first match wins), so when
    /// this is true the import surfaces a reviewable order choice. False when the
    /// two agree, or share fewer than two rules.
    public let urlOrderDiffers: Bool
    /// The user's **Merge-only** URL-rule order choice: `true` adopt the file's
    /// order, `false`/`nil` keep the local order (the default). Ignored under
    /// Replace, which always adopts the file's order.
    public var urlOrderUseFile: Bool?

    /// The effective URL-rule order. Replace adopts the file's order
    /// unconditionally — it makes the config *match* the file, order included — so
    /// the order choice is a Merge-only affordance: Merge keeps the local order
    /// unless the user opts into the file's.
    public var effectiveUseFileOrder: Bool { mode == .replace ? true : (urlOrderUseFile ?? false) }

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
            // Lock and switch both pin a source; only the mode (carried in full)
            // tells them apart, so a lock-vs-switch difference falls out of the
            // `local.mode == rule.mode` comparison as a conflict automatically.
            let fileSource = rule.mode.pinsSource ? rule.lockedSourceID : nil
            if let local = localByBundle[rule.bundleID] {
                let localSource = local.mode.pinsSource ? local.lockedSourceID : nil
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

        // URL rules (keyed by host pattern). The pattern is a URL rule's portable
        // identity — `ImportItem.id`, `localByHost`, and `urlMap` all key on it —
        // so two file rules sharing a pattern would mint colliding item ids and
        // break the Review list's `ForEach`/`firstIndex`. De-dupe the file's rules
        // by pattern up front (keep the first, preserve order), the same collapse
        // the resolver applies; the editor enforces one rule per pattern locally,
        // so this only guards a hand-authored or legacy file.
        let localByHost = Dictionary(
            current.urlRules.map { ($0.hostPattern, $0) }, uniquingKeysWith: { first, _ in first }
        )
        var seenFileHosts = Set<String>()
        let fileURLRules = backup.payload.urlRules.filter { seenFileHosts.insert($0.hostPattern).inserted }
        for rule in fileURLRules {
            if let local = localByHost[rule.hostPattern] {
                // A difference in source, lock-vs-switch, or match type on the
                // same pattern is a conflict.
                let status: ImportItem.Status =
                    (local.lockedSourceID == rule.lockedSourceID && local.action == rule.action
                        && local.matchType == rule.matchType)
                        ? .unchanged : .conflict
                items.append(ImportItem(
                    id: "url:\(rule.hostPattern)", subject: .url(hostPattern: rule.hostPattern), status: status,
                    fileMode: nil, fileSource: rule.lockedSourceID,
                    localMode: nil, localSource: local.lockedSourceID,
                    include: true, resolution: .keepLocal, missingDisposition: .keep,
                    fileAction: rule.action, localAction: local.action,
                    fileMatchType: rule.matchType, localMatchType: local.matchType
                ))
            } else {
                items.append(ImportItem(
                    id: "url:\(rule.hostPattern)", subject: .url(hostPattern: rule.hostPattern), status: .new,
                    fileMode: nil, fileSource: rule.lockedSourceID, localMode: nil, localSource: nil,
                    include: true, resolution: .keepLocal, missingDisposition: .keep,
                    fileAction: rule.action, fileMatchType: rule.matchType
                ))
            }
        }

        self.items = items

        let fileBundleIDs = Set(backup.payload.appRules.map(\.bundleID))
        let fileHosts = Set(backup.payload.urlRules.map(\.hostPattern))
        self.localOnlyAppRuleCount = current.appRules.filter { !fileBundleIDs.contains($0.bundleID) }.count
        self.localOnlyURLRuleCount = current.urlRules.filter { !fileHosts.contains($0.hostPattern) }.count

        // Order is priority; the order choice only matters (and is only surfaced)
        // when file and local share rules in a different relative order.
        self.urlOrderUseFile = nil
        let fileOrder = fileURLRules.map(\.hostPattern)
        let localOrder = current.urlRules.map(\.hostPattern)
        let common = Set(fileOrder).intersection(localOrder)
        self.urlOrderDiffers = fileOrder.filter(common.contains) != localOrder.filter(common.contains)
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
    /// flags (`isEnabled`, `enhancedModeEnabled`) are carried
    /// straight from the base config (via `var result = baseConfig` below) and
    /// never imported.
    public func resolvedConfiguration() -> LockConfiguration {
        var appRules: [String: AppRule]
        var defaultSource: InputSourceID?

        // URL rules carry an explicit user-controlled priority (first match wins),
        // so unlike app rules they are never alphabetized. `urlMap` holds the
        // binding per pattern; the final order is computed afterwards from the
        // order choice (`resolvedURLOrder`). (Duplicate host patterns collapse to
        // one — the import diff keys URL rules by pattern.)
        var urlMap: [String: URLRule]

        switch mode {
        case .merge:
            appRules = Dictionary(baseConfig.appRules.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
            urlMap = Dictionary(baseConfig.urlRules.map { ($0.hostPattern, $0) }, uniquingKeysWith: { first, _ in first })
            defaultSource = baseConfig.defaultSourceID
        case .replace:
            // Drop local-only rules. The global default is preserved unless the
            // file specifies one (a default item below) — a file without a
            // default never silently clears the user's.
            appRules = [:]
            urlMap = [:]
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
                    urlMap[host] = nil
                } else if let source = item.fileSource {
                    urlMap[host] = URLRule(
                        hostPattern: host,
                        lockedSourceID: source,
                        action: item.fileAction ?? .lock,
                        matchType: item.fileMatchType ?? .domainSuffix
                    )
                }
            }
        }

        var result = baseConfig
        result.appRules = appRules.values.sorted { $0.bundleID < $1.bundleID }
        result.urlRules = resolvedURLOrder(present: urlMap)
        result.defaultSourceID = defaultSource
        return result
    }

    /// The final URL-rule priority order over the surviving rules in `urlMap`,
    /// honoring the order choice. Use-file → the file's order first, then any rule
    /// present only locally (a Merge carry-over) appended in local order; keep-local
    /// → local order first, then file-only rules appended in file order. First
    /// occurrence wins; rules dropped from `urlMap` (missing-source removals) fall
    /// out via the `urlMap[$0] != nil` filter.
    private func resolvedURLOrder(present urlMap: [String: URLRule]) -> [URLRule] {
        let fileOrder = items.compactMap { item -> String? in
            if case .url(let host) = item.subject { return host } else { return nil }
        }
        let localOrder = orderedHostPatterns(baseConfig.urlRules)
        let primary = effectiveUseFileOrder ? fileOrder : localOrder
        let secondary = effectiveUseFileOrder ? localOrder : fileOrder
        var seen = Set<String>()
        return (primary + secondary)
            .filter { urlMap[$0] != nil && seen.insert($0).inserted }
            .compactMap { urlMap[$0] }
    }

    /// The host patterns of `rules` in order, first occurrence only.
    private func orderedHostPatterns(_ rules: [URLRule]) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for rule in rules where seen.insert(rule.hostPattern).inserted {
            order.append(rule.hostPattern)
        }
        return order
    }

    // MARK: - Summary

    /// A live tally of the import's effect under the current choices.
    public func summary() -> ImportSummary {
        let resolved = resolvedConfiguration()
        let base = baseConfig

        let baseKeys = bindingKeys(of: base, includeURLPosition: true)
        let resolvedKeys = bindingKeys(of: resolved, includeURLPosition: true)
        // Position-blind binding fingerprints — same keys, values without the
        // URL-rule index — so `inactive` can ask "did this rule's *binding* change"
        // separately from the position-aware "did anything change" that drives
        // `updated`/`hasEffect`.
        let baseBindings = bindingKeys(of: base, includeURLPosition: false)
        let resolvedBindings = bindingKeys(of: resolved, includeURLPosition: false)
        let resolvedSources = bindingSources(of: resolved)

        var added = 0, updated = 0, removed = 0, inactive = 0
        for (key, binding) in resolvedKeys {
            if let was = baseKeys[key] {
                if was != binding { updated += 1 }
            } else {
                added += 1
            }
            // "Inactive" is scoped to what the import actually added or *rebound* —
            // never a pre-existing local rule merely carried over or merely
            // reordered — so the receipt ("其中 M 条…未生效") stays a true subset of
            // the imported count. A pure reorder changes priority, not a source's
            // install status, so it tests the position-BLIND binding here.
            let rebound = baseBindings[key] == nil || baseBindings[key] != resolvedBindings[key]
            if rebound, let source = resolvedSources[key], !installedSourceIDs.contains(source) {
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
    private func bindingKeys(of config: LockConfiguration, includeURLPosition: Bool) -> [String: String] {
        var map: [String: String] = [:]
        if let def = config.defaultSourceID { map["default"] = def.rawValue }
        for rule in config.appRules {
            // The mode rawValue already separates lock from switch; only a
            // source-pinning mode contributes a source.
            let source = rule.mode.pinsSource ? (rule.lockedSourceID?.rawValue ?? "") : ""
            map["app:\(rule.bundleID)"] = "\(rule.mode.rawValue)|\(source)"
        }
        for (index, rule) in config.urlRules.enumerated() {
            // Order is priority for URL rules (first match wins), so a rule's
            // POSITION is part of its effective behavior: with `includeURLPosition`
            // the index is folded in so a backup that only reorders the same rules
            // reads as a change — flipping `hasEffect` on and tallying as an update
            // (a position-blind key reported "no changes" and left Apply disabled).
            // The position-BLIND form is used to decide `inactive`, which tracks a
            // rule's source-install status: a reorder doesn't change that, so it
            // must not inflate the inactive count.
            let position = includeURLPosition ? "\(index)|" : ""
            map["url:\(rule.hostPattern)"] = "\(position)\(rule.action.rawValue)|\(rule.matchType.rawValue)|\(rule.lockedSourceID.rawValue)"
        }
        return map
    }

    /// The pinned source per binding key, so an added/updated key can be tested
    /// for "source installed?" when tallying inactive imports. Keyed exactly like
    /// `bindingKeys`. A binding that pins no source contributes no entry.
    private func bindingSources(of config: LockConfiguration) -> [String: InputSourceID] {
        var map: [String: InputSourceID] = [:]
        if let def = config.defaultSourceID { map["default"] = def }
        for rule in config.appRules where rule.mode.pinsSource {
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
