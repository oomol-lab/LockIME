import AppKit
import LockIMEKit
import SwiftUI

/// View model for the single Review Import screen. Wraps the pure `ImportPlan`
/// and adds the cosmetic "(default)" tracking — which rows still follow a
/// section-header default vs. ones the user overrode individually. All choices
/// stay in memory; nothing is persisted until `applyImport()`.
@MainActor
@Observable
final class ImportReviewModel: Identifiable {
    let id = UUID()
    var plan: ImportPlan

    private(set) var conflictOverrides: Set<String> = []
    private(set) var missingOverrides: Set<String> = []

    private let apply: (ImportPlan) -> ImportOutcome

    init(plan: ImportPlan, apply: @escaping (ImportPlan) -> ImportOutcome) {
        self.plan = plan
        self.apply = apply
    }

    // MARK: Derived (pure functions of the current choices)

    var mode: ImportMode { plan.mode }
    var newItems: [ImportItem] { plan.newItems }
    /// New App rules (and the global default, which conceptually belongs with the
    /// app side) — shown separately from URL rules per the New-rules split.
    var newAppItems: [ImportItem] {
        plan.newItems.filter { if case .url = $0.subject { return false }; return true }
    }
    /// New URL rules.
    var newURLItems: [ImportItem] {
        plan.newItems.filter { if case .url = $0.subject { return true }; return false }
    }
    var conflictItems: [ImportItem] { plan.conflictItems }
    var missingItems: [ImportItem] { plan.missingItems }
    var summary: ImportSummary { plan.summary() }
    /// Local rules Replace would remove (the visible destruction scope).
    var replaceRemovesCount: Int { plan.localOnlyAppRuleCount + plan.localOnlyURLRuleCount }

    func displayName(for id: InputSourceID) -> String { plan.displayName(for: id) }
    func item(_ itemID: String) -> ImportItem? { plan.items.first { $0.id == itemID } }
    /// Whether the item's chosen binding points at a source that isn't installed
    /// (drives the inline warning on a merge conflict that picked the file).
    func isEffectiveMissing(_ item: ImportItem) -> Bool { plan.effectiveFileSourceIsMissing(item) }

    // MARK: Mode

    func setMode(_ newMode: ImportMode) { plan.mode = newMode }

    // MARK: URL-rule order (shown only when the file's order differs)

    var urlOrderDiffers: Bool { plan.urlOrderDiffers }
    /// The effective order choice (the override, else the mode default).
    var urlOrderUseFile: Bool { plan.effectiveUseFileOrder }
    func setURLOrderUseFile(_ useFile: Bool) { plan.urlOrderUseFile = useFile }

    // MARK: New-rule inclusion

    func setInclude(_ itemID: String, _ on: Bool) { mutate(itemID) { $0.include = on } }
    /// Toggle inclusion for a specific set of new items (one section's rows).
    func setAllInclude(_ on: Bool, ids: [String]) {
        let set = Set(ids)
        for index in plan.items.indices where set.contains(plan.items[index].id) {
            plan.items[index].include = on
        }
    }

    // MARK: Conflict resolution (header default + per-row override)

    func resolution(_ itemID: String) -> ConflictResolution { item(itemID)?.resolution ?? .keepLocal }
    func isConflictDefault(_ itemID: String) -> Bool { !conflictOverrides.contains(itemID) }

    func setResolution(_ itemID: String, _ resolution: ConflictResolution) {
        mutate(itemID) { $0.resolution = resolution }
        conflictOverrides.insert(itemID)
    }

    func setAllConflicts(_ resolution: ConflictResolution) {
        for index in plan.items.indices { plan.items[index].resolution = resolution }
        conflictOverrides.removeAll()
    }

    // MARK: Missing-source disposition (header default + per-row override)

    func disposition(_ itemID: String) -> MissingSourceDisposition { item(itemID)?.missingDisposition ?? .keep }
    func isMissingDefault(_ itemID: String) -> Bool { !missingOverrides.contains(itemID) }

    func setDisposition(_ itemID: String, _ disposition: MissingSourceDisposition) {
        mutate(itemID) { $0.missingDisposition = disposition }
        missingOverrides.insert(itemID)
    }

    func setAllMissing(_ disposition: MissingSourceDisposition) {
        for index in plan.items.indices { plan.items[index].missingDisposition = disposition }
        missingOverrides.removeAll()
    }

    // MARK: Commit

    func applyImport() -> ImportOutcome { apply(plan) }

    // MARK: Private

    private func mutate(_ itemID: String, _ change: (inout ImportItem) -> Void) {
        guard let index = plan.items.firstIndex(where: { $0.id == itemID }) else { return }
        change(&plan.items[index])
    }
}

/// The **single** Review Import surface. Everything an import needs — Merge vs.
/// Replace, same-key conflicts, missing input sources, and the one Apply — folds
/// into this one sheet. No `NSAlert`, no `confirmationDialog`, no cascading
/// sheets: changing any control only recomputes this screen, and only Apply
/// mutates state. Cancel/Esc discards everything.
struct ImportReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ImportReviewModel
    /// Called with the receipt after Apply commits.
    let onApplied: (ImportOutcome) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                modeSection
                // Merge-only: Replace adopts the file's order wholesale, so there's
                // nothing to choose there.
                if model.mode == .merge, model.urlOrderDiffers { orderSection }
                if !model.newAppItems.isEmpty { newAppSection }
                if !model.newURLItems.isEmpty { newURLSection }
                if model.mode == .merge, !model.conflictItems.isEmpty { conflictSection }
                if !model.missingItems.isEmpty { missingSection }
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: 600, height: 620)
        .overlayScrollers()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Review Import")
                .font(DS.Font.windowTitle)
            Text("Nothing is changed until you apply.")
                .font(DS.Font.subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.xl)
    }

    // MARK: Mode

    private var modeSection: some View {
        Section {
            Picker("", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                Text("Merge").tag(ImportMode.merge)
                Text("Replace").tag(ImportMode.replace)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(model.mode == .merge
                 ? "Keeps your current rules and adds the file's. You decide each conflict below."
                 : "Makes your rules match the file. The file wins every conflict.")
                .font(DS.Font.sectionFooter)
                .foregroundStyle(.secondary)

            if model.mode == .replace, model.replaceRemovesCount > 0 {
                Label {
                    Text("Replace removes \(model.replaceRemovesCount) of your rules that aren't in the file.")
                } icon: {
                    Image(systemName: "trash")
                }
                .font(DS.Font.sectionFooter)
                .foregroundStyle(DS.Palette.warning)
            }
        } header: {
            Text("How to import")
        }
    }

    // MARK: URL-rule order

    /// Shown in Merge when the file orders the shared URL rules differently (Replace
    /// always adopts the file's order, so it offers no choice). Order is priority
    /// (first match wins), so this is a real, reviewable choice — keep the local
    /// arrangement or adopt the file's. Reuses the conflict picker's
    /// "Keep Local"/"Use File" labels.
    private var orderSection: some View {
        Section {
            Picker("", selection: Binding(get: { model.urlOrderUseFile }, set: { model.setURLOrderUseFile($0) })) {
                Text("Keep Local").tag(false)
                Text("Use File").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("URL rule order")
        } footer: {
            SectionFooter("The backup lists your URL rules in a different priority order. Order is priority — the first matching rule wins.")
        }
    }

    // MARK: New rules (App and URL split into their own sections)

    private var newAppSection: some View {
        Section {
            ForEach(model.newAppItems) { item in newRow(item) }
        } header: {
            newHeader(Text("New app rules (\(model.newAppItems.count))"), items: model.newAppItems)
        }
    }

    private var newURLSection: some View {
        Section {
            ForEach(model.newURLItems) { item in newRow(item) }
        } header: {
            newHeader(Text("New URL rules (\(model.newURLItems.count))"), items: model.newURLItems)
        }
    }

    private func newHeader(_ title: Text, items: [ImportItem]) -> some View {
        HStack {
            title
            Spacer()
            let ids = items.map(\.id)
            Button("Select All") { model.setAllInclude(true, ids: ids) }
            Button("Select None") { model.setAllInclude(false, ids: ids) }
        }
        .buttonStyle(.link)
        .font(DS.Font.sectionFooter)
    }

    private func newRow(_ item: ImportItem) -> some View {
        HStack(spacing: DS.Spacing.lg) {
            Toggle("", isOn: Binding(get: { item.include }, set: { model.setInclude(item.id, $0) }))
                .labelsHidden()
            subjectLabel(item)
            Spacer(minLength: DS.Spacing.md)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            fileBindingText(item)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DS.Spacing.xxs)
    }

    // MARK: Conflicts

    private var conflictSection: some View {
        Section {
            ForEach(model.conflictItems) { item in
                conflictRow(item)
            }
        } header: {
            HStack {
                Text("Conflicts (\(model.conflictItems.count))")
                Spacer()
                Picker("", selection: Binding(get: { model.allConflictHeader }, set: { model.setAllConflicts($0) })) {
                    Text("Keep Local").tag(ConflictResolution.keepLocal)
                    Text("Use File").tag(ConflictResolution.useFile)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .font(DS.Font.sectionFooter)
        } footer: {
            SectionFooter("Your bindings are kept unless you choose the file's.")
        }
    }

    private func conflictRow(_ item: ImportItem) -> some View {
        HStack(spacing: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                subjectLabel(item)
                bindingComparison(item)
                if model.isEffectiveMissing(item) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(DS.Palette.warning)
                        Text("Input source not installed")
                    }
                    .font(DS.Font.rowSubtitle)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: DS.Spacing.md)
            VStack(alignment: .trailing, spacing: DS.Spacing.xxs) {
                Picker("", selection: Binding(
                    get: { model.resolution(item.id) },
                    set: { model.setResolution(item.id, $0) }
                )) {
                    Text("Keep Local").tag(ConflictResolution.keepLocal)
                    Text("Use File").tag(ConflictResolution.useFile)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if model.isConflictDefault(item.id) {
                    Text("(default)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, DS.Spacing.xxs)
    }

    private func bindingComparison(_ item: ImportItem) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text("Local:").foregroundStyle(.secondary)
            localBindingText(item)
            Text(verbatim: "·").foregroundStyle(.tertiary)
            Text("File:").foregroundStyle(.secondary)
            fileBindingText(item)
        }
        .font(DS.Font.rowSubtitle)
    }

    // MARK: Missing input sources

    private var missingSection: some View {
        Section {
            ForEach(model.missingItems) { item in
                missingRow(item)
            }
        } header: {
            HStack {
                Text("Input source not installed (\(model.missingItems.count))")
                Spacer()
                Picker("", selection: Binding(get: { model.allMissingHeader }, set: { model.setAllMissing($0) })) {
                    Text("Keep").tag(MissingSourceDisposition.keep)
                    Text("Remove All").tag(MissingSourceDisposition.remove)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .font(DS.Font.sectionFooter)
        } footer: {
            SectionFooter("Rules aren't lost — they resume automatically once you install the matching input source.")
        }
    }

    private func missingRow(_ item: ImportItem) -> some View {
        HStack(spacing: DS.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(DS.Palette.warning)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                subjectLabel(item)
                    .foregroundStyle(.secondary)
                HStack(spacing: DS.Spacing.xs) {
                    fileBindingText(item)
                    Text(verbatim: "·").foregroundStyle(.tertiary)
                    Text("Input source not installed")
                }
                .font(DS.Font.rowSubtitle)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: DS.Spacing.md)
            VStack(alignment: .trailing, spacing: DS.Spacing.xxs) {
                Picker("", selection: Binding(
                    get: { model.disposition(item.id) },
                    set: { model.setDisposition(item.id, $0) }
                )) {
                    Text("Keep").tag(MissingSourceDisposition.keep)
                    Text("Remove").tag(MissingSourceDisposition.remove)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if model.isMissingDefault(item.id) {
                    Text("(default)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, DS.Spacing.xxs)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: DS.Spacing.lg) {
            summaryView
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Apply") {
                let outcome = model.applyImport()
                onApplied(outcome)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!model.summary.hasEffect)
        }
        .padding(DS.Spacing.xl)
    }

    private var summaryView: some View {
        let summary = model.summary
        return HStack(spacing: DS.Spacing.md) {
            summaryChip("Added", summary.added)
            summaryChip("Updated", summary.updated)
            summaryChip("Kept", summary.kept)
            summaryChip("Removed", summary.removed)
        }
        .font(DS.Font.rowSubtitle)
    }

    private func summaryChip(_ label: LocalizedStringKey, _ count: Int) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(label).foregroundStyle(.secondary)
            Text(count.formatted())
                .monospacedDigit()
                .foregroundStyle(count > 0 ? .primary : .tertiary)
        }
    }

    // MARK: Shared row pieces

    @ViewBuilder
    private func subjectLabel(_ item: ImportItem) -> some View {
        switch item.subject {
        case .globalDefault:
            Label {
                Text("Global default")
            } icon: {
                Image(systemName: "keyboard")
            }
        case .app(let bundleID):
            AppRowLabel(bundleID: bundleID)
        case .url(let host):
            Label {
                Text(verbatim: host)
            } icon: {
                Image(systemName: "globe").foregroundStyle(.secondary)
            }
        }
    }

    /// The file-side binding as composable `Text`. A source-pinning rule reads as
    /// "Lock to %@" / "Switch to %@" so lock and switch are visibly parallel (and
    /// a same-source lock-vs-switch conflict is distinguishable); a non-pinning
    /// app mode reads as its mode word; the global default now reads the same
    /// "Lock to"/"Switch to" way too (it carries a lock/switch action); a
    /// sourceless binding reads "Default".
    /// Returning `Text` keeps it recolorable inside `HStack`s while resolving
    /// catalog keys against the injected `\.locale`.
    private func fileBindingText(_ item: ImportItem) -> Text {
        bindingText(subject: item.subject, mode: item.fileMode, action: item.fileAction, source: item.fileSource, matchType: item.fileMatchType)
    }

    private func localBindingText(_ item: ImportItem) -> Text {
        bindingText(subject: item.subject, mode: item.localMode, action: item.localAction, source: item.localSource, matchType: item.localMatchType)
    }

    private func bindingText(
        subject: ImportItem.Subject,
        mode: AppRuleMode?,
        action: RuleAction?,
        source: InputSourceID?,
        matchType: URLMatchType?
    ) -> Text {
        switch subject {
        case .globalDefault:
            // The global default now carries a lock/switch action, so render it as
            // "Lock to %@" / "Switch to %@" too — parallel to app/URL rules, so a
            // same-source lock-vs-switch conflict stays distinguishable.
            guard let source else { return Text("Default") }
            return pinnedBindingText(isSwitch: action == .switchOnce, source: source)
        case .app:
            if let mode, !mode.pinsSource { return Text(modeKey(mode)) } // ignore / use default
            guard let source else { return Text("Default") }
            return pinnedBindingText(isSwitch: mode == .switched, source: source)
        case .url:
            guard let source else { return Text("Default") }
            let pinned = pinnedBindingText(isSwitch: action == .switchOnce, source: source)
            // Append the match type when it isn't the default so two same-source,
            // same-action rules that differ only by match type stay distinguishable.
            if let matchType, matchType != .domainSuffix {
                return pinned + Text(verbatim: " · ") + Text(matchType.importLabel)
            }
            return pinned
        }
    }

    /// A source-pinning binding: the localized "Lock to %@" / "Switch to %@"
    /// phrase with the source name interpolated (a verbatim proper noun).
    private func pinnedBindingText(isSwitch: Bool, source: InputSourceID) -> Text {
        let name = model.displayName(for: source)
        return Text(isSwitch ? "Switch to \(name)" : "Lock to \(name)")
    }

    private func modeKey(_ mode: AppRuleMode) -> LocalizedStringKey {
        switch mode {
        case .locked: "Lock to"
        case .switched: "Switch to"
        case .ignored: "Ignore"
        case .useDefault: "Use default"
        }
    }
}

private extension ImportReviewModel {
    /// The conflict section header's segmented value: the common resolution when
    /// all conflicts agree, defaulting to keep-local otherwise.
    var allConflictHeader: ConflictResolution {
        conflictItems.allSatisfy { $0.resolution == .useFile } && !conflictItems.isEmpty ? .useFile : .keepLocal
    }

    /// The missing section header's segmented value: remove only when every
    /// missing row is set to remove.
    var allMissingHeader: MissingSourceDisposition {
        missingItems.allSatisfy { $0.missingDisposition == .remove } && !missingItems.isEmpty ? .remove : .keep
    }
}

private extension URLMatchType {
    /// A compact label for the import comparison. Reuses the same catalog keys as
    /// the URL Rules editor (the default suffix type is never labelled — it's the
    /// unmarked, common case).
    var importLabel: LocalizedStringKey {
        switch self {
        case .domainSuffix: "Domain suffix"
        case .domain: "Exact domain"
        case .domainKeyword: "Domain keyword"
        case .urlRegex: "URL regex"
        }
    }
}
