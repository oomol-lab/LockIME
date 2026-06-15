import Foundation
import Testing

@testable import LockIMEKit

@Suite("ImportPlan diff, resolve & summary")
struct ImportPlanTests {
    // MARK: fixtures

    private func source(_ id: InputSourceID, _ name: String) -> InputSource {
        InputSource(id: id, localizedName: name, isSelectCapable: true, isEnabled: true, isCJKV: false)
    }

    /// US and ABC are installed; "Missing" never is.
    private var installed: [InputSource] {
        [source("US", "U.S."), source("ABC", "ABC")]
    }

    private func backup(
        defaultSourceID: InputSourceID? = nil,
        appRules: [AppRule] = [],
        urlRules: [BackupURLRule] = [],
        sourceNames: [String: String] = [:]
    ) -> ConfigBackup {
        ConfigBackup(appVersion: "1", payload: BackupPayload(
            defaultSourceID: defaultSourceID, appRules: appRules, urlRules: urlRules, sourceNames: sourceNames
        ))
    }

    private func item(_ plan: ImportPlan, _ id: String) -> ImportItem? {
        plan.items.first { $0.id == id }
    }

    // MARK: - Builder categorization

    @Test("an empty local config makes every file binding a new item")
    func allNewWhenLocalEmpty() {
        let plan = ImportPlan(
            current: .default,
            backup: backup(
                defaultSourceID: "US",
                appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "ABC")],
                urlRules: [BackupURLRule(hostPattern: "github.com", lockedSourceID: "US")]
            ),
            installedSources: installed
        )
        #expect(plan.items.count == 3)
        #expect(plan.items.allSatisfy { $0.status == .new })
        #expect(plan.newItems.count == 3)
        #expect(plan.conflictItems.isEmpty)
    }

    @Test("identical bindings produce unchanged items, shown in neither edit section")
    func identicalBindingsUnchanged() {
        let current = LockConfiguration(
            defaultSourceID: "US",
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "ABC")],
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: "US")]
        )
        let plan = ImportPlan(current: current, backup: backup(
            defaultSourceID: "US",
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "ABC")],
            urlRules: [BackupURLRule(hostPattern: "github.com", lockedSourceID: "US")]
        ), installedSources: installed)
        #expect(plan.items.allSatisfy { $0.status == .unchanged })
        #expect(plan.newItems.isEmpty)
        #expect(plan.conflictItems.isEmpty)
        // An all-identical merge is a pure no-op.
        #expect(plan.resolvedConfiguration() == current)
        #expect(!plan.summary().hasEffect)
    }

    @Test("Replace re-asserts an unchanged rule whose source went missing")
    func replaceUnchangedMissingSurfaces() {
        // File and local agree, but the pinned source isn't installed here.
        let current = LockConfiguration(appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "Missing")])
        var plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "Missing")]
        ), installedSources: installed)
        // Merge: unchanged is a no-op, not surfaced as missing.
        #expect(plan.missingItems.isEmpty)
        // Replace: the rule is re-asserted from the file → surfaced as missing.
        plan.mode = .replace
        #expect(plan.missingItems.count == 1)
        // Removing it drops the rule entirely.
        plan.items[0].missingDisposition = .remove
        #expect(plan.resolvedConfiguration().appRules.isEmpty)
    }

    @Test("a differing default is a conflict; a differing app source is a conflict")
    func conflictsDetected() {
        let current = LockConfiguration(
            defaultSourceID: "US",
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US")]
        )
        let plan = ImportPlan(current: current, backup: backup(
            defaultSourceID: "ABC",
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "ABC")]
        ), installedSources: installed)
        #expect(item(plan, "default")?.status == .conflict)
        #expect(item(plan, "default")?.localSource == "US")
        #expect(item(plan, "default")?.fileSource == "ABC")
        #expect(item(plan, "app:com.a")?.status == .conflict)
    }

    @Test("an app rule differing only in mode is a conflict")
    func appModeConflict() {
        let current = LockConfiguration(appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "ABC")])
        let plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .ignored)]
        ), installedSources: installed)
        let conflict = item(plan, "app:com.a")
        #expect(conflict?.status == .conflict)
        #expect(conflict?.fileMode == .ignored)
        #expect(conflict?.fileSource == nil)
        #expect(conflict?.localMode == .locked)
        #expect(conflict?.localSource == "ABC")
    }

    @Test("local-only rule counts are tracked for Replace")
    func localOnlyCounts() {
        let current = LockConfiguration(
            appRules: [
                AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US"),
                AppRule(bundleID: "com.localonly", mode: .locked, lockedSourceID: "US"),
            ],
            urlRules: [
                URLRule(hostPattern: "a.com", lockedSourceID: "US"),
                URLRule(hostPattern: "localonly.com", lockedSourceID: "US"),
            ]
        )
        let plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US")],
            urlRules: [BackupURLRule(hostPattern: "a.com", lockedSourceID: "US")]
        ), installedSources: installed)
        #expect(plan.localOnlyAppRuleCount == 1)
        #expect(plan.localOnlyURLRuleCount == 1)
    }

    // MARK: - Merge resolution

    @Test("merge keeps local rules and adds new ones")
    func mergeAddsAndKeeps() {
        let current = LockConfiguration(appRules: [AppRule(bundleID: "com.local", mode: .locked, lockedSourceID: "US")])
        let plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.new", mode: .locked, lockedSourceID: "ABC")]
        ), installedSources: installed)
        let resolved = plan.resolvedConfiguration()
        #expect(resolved.appRules.map(\.bundleID) == ["com.local", "com.new"])
    }

    @Test("merge conflict defaults to keeping the local binding")
    func mergeConflictDefaultsKeepLocal() {
        let current = LockConfiguration(appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US")])
        let plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "ABC")]
        ), installedSources: installed)
        #expect(plan.resolvedConfiguration().rule(for: "com.a")?.lockedSourceID == "US")
    }

    @Test("merge conflict set to useFile takes the file binding")
    func mergeConflictUseFile() {
        let current = LockConfiguration(appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US")])
        var plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "ABC")]
        ), installedSources: installed)
        plan.items[0].resolution = .useFile
        #expect(plan.resolvedConfiguration().rule(for: "com.a")?.lockedSourceID == "ABC")
    }

    @Test("a new rule excluded via include is not imported")
    func excludedNewRuleNotImported() {
        var plan = ImportPlan(current: .default, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US")]
        ), installedSources: installed)
        plan.items[0].include = false
        #expect(plan.resolvedConfiguration().appRules.isEmpty)
    }

    @Test("merge preserves the local default and a local-only rule")
    func mergePreservesDefaultAndLocalOnly() {
        let current = LockConfiguration(
            defaultSourceID: "US",
            appRules: [AppRule(bundleID: "com.localonly", mode: .locked, lockedSourceID: "ABC")]
        )
        let plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.new", mode: .locked, lockedSourceID: "US")]
        ), installedSources: installed)
        let resolved = plan.resolvedConfiguration()
        #expect(resolved.defaultSourceID == "US")
        #expect(resolved.appRules.map(\.bundleID) == ["com.localonly", "com.new"])
    }

    // MARK: - Replace resolution

    @Test("replace drops local-only rules and lets the file win conflicts")
    func replaceDropsLocalOnlyAndFileWins() {
        let current = LockConfiguration(
            appRules: [
                AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US"),
                AppRule(bundleID: "com.localonly", mode: .locked, lockedSourceID: "US"),
            ]
        )
        var plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "ABC")]
        ), installedSources: installed)
        plan.mode = .replace
        let resolved = plan.resolvedConfiguration()
        #expect(resolved.appRules.map(\.bundleID) == ["com.a"])
        #expect(resolved.rule(for: "com.a")?.lockedSourceID == "ABC")
    }

    @Test("replace preserves the local default when the file specifies none")
    func replaceKeepsDefaultWhenFileHasNone() {
        let current = LockConfiguration(defaultSourceID: "US")
        var plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "ABC")]
        ), installedSources: installed)
        plan.mode = .replace
        #expect(plan.resolvedConfiguration().defaultSourceID == "US")
    }

    @Test("replace sets the file's default when it specifies one")
    func replaceSetsFileDefault() {
        let current = LockConfiguration(defaultSourceID: "US")
        var plan = ImportPlan(current: current, backup: backup(defaultSourceID: "ABC"), installedSources: installed)
        plan.mode = .replace
        #expect(plan.resolvedConfiguration().defaultSourceID == "ABC")
    }

    @Test("import never touches the per-device runtime flags")
    func runtimeFlagsPreserved() {
        let current = LockConfiguration(isEnabled: true, defaultSourceID: "US", enhancedModeEnabled: true)
        var plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "ABC")]
        ), installedSources: installed)
        plan.mode = .replace
        let resolved = plan.resolvedConfiguration()
        #expect(resolved.isEnabled == true)
        #expect(resolved.enhancedModeEnabled == true)
    }

    // MARK: - Missing sources

    @Test("a new rule targeting an uninstalled source is flagged missing")
    func newMissingFlagged() {
        let plan = ImportPlan(current: .default, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "Missing")]
        ), installedSources: installed)
        #expect(plan.missingItems.count == 1)
        #expect(plan.effectiveFileSourceIsMissing(plan.items[0]))
    }

    @Test("an app rule pinning no source is never missing")
    func nonLockingRuleNeverMissing() {
        let plan = ImportPlan(current: .default, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .ignored)]
        ), installedSources: installed)
        #expect(plan.missingItems.isEmpty)
    }

    @Test("a kept-local conflict is not missing even if the file source is absent")
    func keepLocalConflictNotMissing() {
        let current = LockConfiguration(appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US")])
        let plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "Missing")]
        ), installedSources: installed)
        // Default resolution is keepLocal → effective source is US (installed).
        #expect(plan.missingItems.isEmpty)
    }

    @Test("a merge conflict on a missing file source stays in the conflict section")
    func useFileConflictStaysInConflictSection() {
        // In Merge a conflict keeps its keep-local escape hatch, so it stays in
        // the conflict section (with an inline warning) rather than moving to the
        // missing section. The predicate still reports the source as missing.
        let current = LockConfiguration(appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US")])
        var plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "Missing")]
        ), installedSources: installed)
        plan.items[0].resolution = .useFile
        #expect(plan.effectiveFileSourceIsMissing(plan.items[0]))
        #expect(plan.missingItems.isEmpty)
        #expect(plan.conflictItems.count == 1)
    }

    @Test("replace surfaces a conflict's missing file source (file always wins)")
    func replaceConflictMissing() {
        let current = LockConfiguration(appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US")])
        var plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "Missing")]
        ), installedSources: installed)
        plan.mode = .replace
        #expect(plan.missingItems.count == 1)
    }

    @Test("keep disposition leaves a missing rule in the config (inactive)")
    func missingKeptStaysInConfig() {
        let plan = ImportPlan(current: .default, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "Missing")]
        ), installedSources: installed)
        // default disposition is keep.
        #expect(plan.resolvedConfiguration().rule(for: "com.a")?.lockedSourceID == "Missing")
    }

    @Test("remove disposition drops a missing new rule entirely")
    func missingRemovedDropsRule() {
        var plan = ImportPlan(current: .default, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "Missing")]
        ), installedSources: installed)
        plan.items[0].missingDisposition = .remove
        #expect(plan.resolvedConfiguration().appRules.isEmpty)
    }

    @Test("useFile + missing + remove deletes the rule (neither binding survives)")
    func useFileMissingRemoveDeletes() {
        let current = LockConfiguration(appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US")])
        var plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "Missing")]
        ), installedSources: installed)
        plan.items[0].resolution = .useFile
        plan.items[0].missingDisposition = .remove
        #expect(plan.resolvedConfiguration().appRules.isEmpty)
    }

    @Test("a missing URL rule kept stays; removed drops")
    func missingURLDisposition() {
        var plan = ImportPlan(current: .default, backup: backup(
            urlRules: [BackupURLRule(hostPattern: "x.com", lockedSourceID: "Missing")]
        ), installedSources: installed)
        #expect(plan.resolvedConfiguration().urlRules.count == 1)
        plan.items[0].missingDisposition = .remove
        #expect(plan.resolvedConfiguration().urlRules.isEmpty)
    }

    @Test("a missing global default kept is set; removed falls back to local")
    func missingDefaultDisposition() {
        let current = LockConfiguration(defaultSourceID: "US")
        var plan = ImportPlan(current: current, backup: backup(defaultSourceID: "Missing"), installedSources: installed)
        // Conflict; flip to useFile so the missing file default is effective.
        plan.items[0].resolution = .useFile
        #expect(plan.resolvedConfiguration().defaultSourceID == "Missing")
        plan.items[0].missingDisposition = .remove
        #expect(plan.resolvedConfiguration().defaultSourceID == "US")
    }

    // MARK: - Summary & outcome

    @Test("summary tallies added, updated, kept, removed and inactive")
    func summaryCounts() {
        let current = LockConfiguration(
            appRules: [
                AppRule(bundleID: "com.conflict", mode: .locked, lockedSourceID: "US"),
                AppRule(bundleID: "com.localonly", mode: .locked, lockedSourceID: "US"),
            ]
        )
        var plan = ImportPlan(current: current, backup: backup(
            appRules: [
                AppRule(bundleID: "com.conflict", mode: .locked, lockedSourceID: "ABC"),
                AppRule(bundleID: "com.new", mode: .locked, lockedSourceID: "Missing"),
            ]
        ), installedSources: installed)
        // Merge, conflict→useFile so it counts as an update.
        if let i = plan.items.firstIndex(where: { $0.id == "app:com.conflict" }) {
            plan.items[i].resolution = .useFile
        }
        let s = plan.summary()
        #expect(s.added == 1)        // com.new (kept though missing → still added)
        #expect(s.updated == 1)      // com.conflict rebound to file
        #expect(s.kept == 0)         // the only conflict was set to useFile
        #expect(s.removed == 0)      // merge keeps local-only
        #expect(s.inactive == 1)     // com.new targets the missing source
        #expect(s.hasEffect)
    }

    @Test("a conflict left at keepLocal counts as kept and is a no-op")
    func keepLocalIsNoOp() {
        let current = LockConfiguration(appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US")])
        let plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "ABC")]
        ), installedSources: installed)
        let s = plan.summary()
        #expect(s.kept == 1)
        #expect(s.added == 0 && s.updated == 0 && s.removed == 0)
        #expect(!s.hasEffect)
    }

    @Test("replace counts local-only rules as removed")
    func replaceRemovedCount() {
        let current = LockConfiguration(appRules: [
            AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US"),
            AppRule(bundleID: "com.localonly", mode: .locked, lockedSourceID: "US"),
        ])
        var plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US")]
        ), installedSources: installed)
        plan.mode = .replace
        let s = plan.summary()
        #expect(s.removed == 1)
        #expect(s.hasEffect)
    }

    @Test("a pre-existing local rule on a missing source isn't counted as imported-inactive")
    func preExistingInactiveNotCounted() {
        // Local already pins a rule to an uninstalled source; the import only adds
        // a new, installed rule. The receipt must attribute inactivity solely to
        // imported rules, not the carried-over local one.
        let current = LockConfiguration(appRules: [AppRule(bundleID: "com.old", mode: .locked, lockedSourceID: "Missing")])
        let plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.new", mode: .locked, lockedSourceID: "US")]
        ), installedSources: installed)
        let outcome = plan.outcome()
        #expect(outcome.imported == 1)
        #expect(outcome.inactive == 0)
        #expect(plan.summary().inactive == 0)
    }

    @Test("Replace re-asserting an unchanged missing rule isn't counted as imported-inactive")
    func replaceUnchangedMissingNotImportedInactive() {
        let current = LockConfiguration(appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "Missing")])
        var plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "Missing")]
        ), installedSources: installed)
        plan.mode = .replace
        let s = plan.summary()
        #expect(s.added == 0 && s.updated == 0)  // file == local: nothing imported
        #expect(s.inactive == 0)                 // so nothing imported-inactive
    }

    @Test("outcome reports imported and inactive counts")
    func outcomeReceipt() {
        var plan = ImportPlan(current: .default, backup: backup(
            appRules: [
                AppRule(bundleID: "com.ok", mode: .locked, lockedSourceID: "US"),
                AppRule(bundleID: "com.missing", mode: .locked, lockedSourceID: "Missing"),
            ]
        ), installedSources: installed)
        let outcome = plan.outcome()
        #expect(outcome.imported == 2)
        #expect(outcome.inactive == 1)
    }

    // MARK: - Display names

    @Test("displayName prefers the local name, then the file catalog, then the raw id")
    func displayNamePrecedence() {
        let plan = ImportPlan(current: .default, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "Missing")],
            sourceNames: ["US": "米国", "Missing": "Zhuyin"]
        ), installedSources: installed)
        #expect(plan.displayName(for: "US") == "U.S.")       // installed name wins
        #expect(plan.displayName(for: "Missing") == "Zhuyin") // from file catalog
        #expect(plan.displayName(for: "Unknown") == "Unknown") // raw fallback
    }

    // MARK: - Coverage for manual review-screen scenarios

    @Test("an empty backup yields no items and no effect")
    func emptyBackupNoEffect() {
        let plan = ImportPlan(current: LockConfiguration(defaultSourceID: "US"), backup: backup(), installedSources: installed)
        #expect(plan.items.isEmpty)
        #expect(plan.newItems.isEmpty && plan.conflictItems.isEmpty && plan.missingItems.isEmpty)
        #expect(!plan.summary().hasEffect)
    }

    @Test("merge global-default conflict keeps local by default, takes file when chosen")
    func mergeDefaultConflict() {
        let current = LockConfiguration(defaultSourceID: "US")
        var plan = ImportPlan(current: current, backup: backup(defaultSourceID: "ABC"), installedSources: installed)
        #expect(item(plan, "default")?.status == .conflict)
        #expect(plan.resolvedConfiguration().defaultSourceID == "US")   // default: keep local
        plan.items[0].resolution = .useFile
        #expect(plan.resolvedConfiguration().defaultSourceID == "ABC")  // chosen: use file
    }

    @Test("new, conflict and missing items coexist as distinct sections")
    func mixedSectionsCoexist() {
        let current = LockConfiguration(appRules: [AppRule(bundleID: "com.conflict", mode: .locked, lockedSourceID: "US")])
        let plan = ImportPlan(current: current, backup: backup(
            appRules: [
                AppRule(bundleID: "com.conflict", mode: .locked, lockedSourceID: "ABC"),   // conflict
                AppRule(bundleID: "com.new", mode: .locked, lockedSourceID: "US"),          // new (installed)
                AppRule(bundleID: "com.missing", mode: .locked, lockedSourceID: "Missing"), // missing
            ],
            urlRules: [BackupURLRule(hostPattern: "github.com", lockedSourceID: "US")]      // new URL
        ), installedSources: installed)
        #expect(plan.newItems.count == 2)       // com.new + github.com
        #expect(plan.conflictItems.count == 1)  // com.conflict
        #expect(plan.missingItems.count == 1)   // com.missing
    }

    @Test("imported ignore / use-default rules resolve with their mode and no source")
    func importedNonLockingModes() {
        let plan = ImportPlan(current: .default, backup: backup(
            appRules: [AppRule(bundleID: "com.ig", mode: .ignored), AppRule(bundleID: "com.def", mode: .useDefault)]
        ), installedSources: installed)
        let resolved = plan.resolvedConfiguration()
        #expect(resolved.rule(for: "com.ig")?.mode == .ignored)
        #expect(resolved.rule(for: "com.ig")?.lockedSourceID == nil)
        #expect(resolved.rule(for: "com.def")?.mode == .useDefault)
        #expect(plan.missingItems.isEmpty)   // non-locking rules pin no source
    }

    @Test("round-trip: exporting a config then importing it yields no changes")
    func exportImportRoundTrip() {
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: "US",
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "ABC"),
                       AppRule(bundleID: "com.b", mode: .ignored)],
            enhancedModeEnabled: true,
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: "US")]
        )
        let exported = ConfigBackup.make(from: config, appVersion: "1", sourceNames: ["US": "U.S.", "ABC": "ABC"])
        let plan = ImportPlan(current: config, backup: exported, installedSources: installed)
        #expect(plan.newItems.isEmpty && plan.conflictItems.isEmpty && plan.missingItems.isEmpty)
        #expect(!plan.summary().hasEffect)
        #expect(plan.resolvedConfiguration() == config)
    }

    // MARK: - Switch action

    @Test("a new switched app rule carries its mode and source")
    func switchedAppRuleIsNew() {
        let plan = ImportPlan(current: .default, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .switched, lockedSourceID: "ABC")]
        ), installedSources: installed)
        let item = item(plan, "app:com.a")
        #expect(item?.status == .new)
        #expect(item?.fileMode == .switched)
        #expect(item?.fileSource == "ABC")
        #expect(plan.resolvedConfiguration().rule(for: "com.a")?.mode == .switched)
    }

    @Test("lock vs switch on the same app source is a conflict")
    func lockVsSwitchAppIsConflict() {
        let current = LockConfiguration(appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "ABC")])
        let plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .switched, lockedSourceID: "ABC")] // same source, different action
        ), installedSources: installed)
        let conflict = item(plan, "app:com.a")
        #expect(conflict?.status == .conflict)
        #expect(conflict?.localMode == .locked)
        #expect(conflict?.fileMode == .switched)
    }

    @Test("a new switch URL rule carries its action; lock vs switch is a URL conflict")
    func switchURLRuleNewAndConflict() {
        // New switch URL rule.
        let newPlan = ImportPlan(current: .default, backup: backup(
            urlRules: [BackupURLRule(hostPattern: "github.com", lockedSourceID: "US", action: .switchOnce)]
        ), installedSources: installed)
        let newItem = item(newPlan, "url:github.com")
        #expect(newItem?.status == .new)
        #expect(newItem?.fileAction == .switchOnce)
        #expect(newPlan.resolvedConfiguration().urlRules.first?.action == .switchOnce)

        // Same host + same source but different action → conflict.
        let current = LockConfiguration(urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: "US", action: .lock)])
        let conflictPlan = ImportPlan(current: current, backup: backup(
            urlRules: [BackupURLRule(hostPattern: "github.com", lockedSourceID: "US", action: .switchOnce)]
        ), installedSources: installed)
        let conflict = item(conflictPlan, "url:github.com")
        #expect(conflict?.status == .conflict)
        #expect(conflict?.localAction == .lock)
        #expect(conflict?.fileAction == .switchOnce)
    }

    @Test("Replace preserves the file's switch action for app and URL rules")
    func replacePreservesSwitchAction() {
        let current = LockConfiguration(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "US")],
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: "US", action: .lock)]
        )
        var plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .switched, lockedSourceID: "ABC")],
            urlRules: [BackupURLRule(hostPattern: "github.com", lockedSourceID: "ABC", action: .switchOnce)]
        ), installedSources: installed)
        plan.mode = .replace
        let resolved = plan.resolvedConfiguration()
        #expect(resolved.rule(for: "com.a")?.mode == .switched)
        #expect(resolved.rule(for: "com.a")?.lockedSourceID == "ABC")
        #expect(resolved.urlRules.first?.action == .switchOnce)
        #expect(resolved.urlRules.first?.lockedSourceID == "ABC")
    }

    @Test("a lock→switch change tallies as updated, not added")
    func lockToSwitchTalliesAsUpdated() {
        let current = LockConfiguration(
            appRules: [AppRule(bundleID: "com.a", mode: .locked, lockedSourceID: "ABC")],
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: "US", action: .lock)]
        )
        var plan = ImportPlan(current: current, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .switched, lockedSourceID: "ABC")],
            urlRules: [BackupURLRule(hostPattern: "github.com", lockedSourceID: "US", action: .switchOnce)]
        ), installedSources: installed)
        plan.mode = .replace
        let summary = plan.summary()
        #expect(summary.updated == 2) // app + url rebind
        #expect(summary.added == 0)
    }

    @Test("a missing source on a switched app rule surfaces like a lock")
    func switchedMissingSourceSurfaces() {
        let plan = ImportPlan(current: .default, backup: backup(
            appRules: [AppRule(bundleID: "com.a", mode: .switched, lockedSourceID: "Missing")]
        ), installedSources: installed)
        #expect(plan.missingItems.count == 1)
        #expect(plan.summary().inactive == 1)
    }

    @Test("round-trip of a switch config is a pure no-op (action survives every path)")
    func switchExportImportRoundTrip() {
        let config = LockConfiguration(
            isEnabled: true,
            defaultSourceID: "US",
            appRules: [AppRule(bundleID: "com.a", mode: .switched, lockedSourceID: "ABC")],
            enhancedModeEnabled: true,
            urlRules: [URLRule(hostPattern: "github.com", lockedSourceID: "US", action: .switchOnce)]
        )
        let exported = ConfigBackup.make(from: config, appVersion: "1", sourceNames: ["US": "U.S.", "ABC": "ABC"])
        var plan = ImportPlan(current: config, backup: exported, installedSources: installed)
        #expect(!plan.summary().hasEffect)
        // Merge keeps the local rules verbatim (including the URL rule's id).
        #expect(plan.resolvedConfiguration() == config)
        // Replace re-asserts the file's rules; it regenerates URL ids (the runtime
        // identity isn't portable — see BackupURLRule), so compare the portable
        // fields rather than full equality. The switch action must survive.
        plan.mode = .replace
        let replaced = plan.resolvedConfiguration()
        #expect(replaced.rule(for: "com.a")?.mode == .switched)
        #expect(replaced.urlRules.first?.action == .switchOnce)
        #expect(replaced.urlRules.first?.lockedSourceID == "US")
    }
}
