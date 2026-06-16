import AppKit
import LockIMEKit
import SwiftUI
import UniformTypeIdentifiers

/// What the editor sheet is editing — a brand-new rule, or an existing one.
/// Drives `.sheet(item:)`.
private enum EditorTarget: Identifiable {
    case add
    case edit(URLRule)
    var id: String {
        switch self {
        case .add: "add" // i18n-exempt: a sheet-identity token, not a UI string
        case .edit(let rule): rule.id.uuidString
        }
    }
}

/// Per-URL rules, gated behind the Accessibility-powered "enhanced mode". Each
/// rule is a read-only **summary row** (drag to reorder by priority); adding and
/// editing happen in a dedicated `URLRuleEditor` sheet, so a row never crams a
/// type picker, a text field, and two more pickers onto one line.
struct URLRulesSettingsPane: View {
    @Environment(AppState.self) private var state

    @State private var sheetTarget: EditorTarget?
    /// The UUID string of the rule currently being dragged, shared with each row's
    /// drop delegate so the list can reorder live as the row is dragged over others.
    @State private var draggingID: String?
    /// While a drag is in progress, the reordered list shown to the user. Kept
    /// view-local — the live drag never mutates `config`, so a cancelled drag (a
    /// release that lands on no drop target) persists and re-applies nothing; only
    /// a committed drop calls `state.reorderURLRules`. `nil` when not dragging.
    @State private var draftOrder: [URLRule]?

    var body: some View {
        let enhancedBinding = Binding(
            get: { state.config.enhancedModeEnabled },
            set: { state.setEnhancedMode($0) }
        )

        Form {
            enhancedSection(enhancedBinding)
            rulesSection
        }
        .formStyle(.grouped)
        // Fallback reorder drop for the whole pane: a drag released *not* on a row
        // (section chrome, the Add button, empty Form space) still commits, instead
        // of leaving the draft order shown-but-unpersisted. Rows handle their own
        // drop (deeper target wins); this only catches the off-row release.
        .onDrop(of: [.text], delegate: PaneDropDelegate(draggingID: $draggingID, onCommit: { commitReorder() }))
        .navigationTitle(state.loc("URL Rules"))
        .onAppear { state.refreshAccessibilityStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshAccessibilityStatus()
        }
        .sheet(item: $sheetTarget) { target in
            // A sheet bridges into its own AppKit window, which doesn't reliably
            // inherit the app's in-app language override — re-inject it (and
            // rebuild on language change) so the editor isn't resolved against the
            // system language. Same pattern as the import Review sheet.
            sheetEditor(target)
                .environment(\.locale, state.locale)
                .id(state.localeIdentifier)
        }
    }

    // MARK: Enhanced-mode section

    @ViewBuilder
    private func enhancedSection(_ enhancedBinding: Binding<Bool>) -> some View {
        Section {
            Toggle("Enhanced mode (per-URL rules)", isOn: enhancedBinding)
                .disabled(!state.accessibilityGranted)

            if !state.accessibilityGranted {
                AccessibilityRequiredNote("Enhanced mode requires Accessibility")
            }

            // After an import, URL rules can exist while enhanced mode is still
            // off (import never flips per-device runtime state) — a light, one-line
            // hint, no prompt or multi-step guidance.
            if !state.config.enhancedModeEnabled, !state.config.urlRules.isEmpty {
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("Enhanced mode is off, so your URL rules aren't active yet. Turn it on for them to take effect.")
                        .font(DS.Font.sectionFooter)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Spacing.xxs)
            }
        } header: {
            Text("Enhanced mode")
        } footer: {
            SectionFooter("Enhanced mode reads the active browser URL via Accessibility to apply per-URL rules. The core lock needs no permissions.")
        }
    }

    // MARK: Rules section

    @ViewBuilder
    private var rulesSection: some View {
        Section {
            if !state.config.urlRules.isEmpty {
                // Order is priority (first match wins), so surface the reordering
                // affordance once there's more than one rule.
                if state.config.urlRules.count > 1 { reorderCaption }
                ForEach(displayedRules) { rule in
                    URLRuleSummaryRow(
                        rule: rule,
                        active: state.config.enhancedModeEnabled,
                        draggingID: $draggingID,
                        onBeginDrag: { beginDrag(rule.id) },
                        onEdit: { clearDrag(); sheetTarget = .edit(rule) },
                        onReorderOver: { draggedID in reorder(draggedID: draggedID, over: rule.id) },
                        onDropCommit: { commitReorder() }
                    )
                }
            } else if state.config.enhancedModeEnabled {
                emptyState
            } else {
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: "lock").foregroundStyle(.secondary)
                    Text("Enable enhanced mode to add per-URL rules.").foregroundStyle(.secondary)
                }
                .padding(.vertical, DS.Spacing.xxs)
            }

            if state.config.enhancedModeEnabled {
                Button { clearDrag(); sheetTarget = .add } label: { Label("Add Rule…", systemImage: "plus") }
            }
        } header: {
            Text("URL rules")
        } footer: {
            SectionFooter("Per-URL rules work in Safari, Firefox, and Chromium-based browsers (Chrome, Edge, Brave, Arc, Vivaldi, Opera).")
        }
    }

    private var reorderCaption: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "arrow.up.arrow.down").foregroundStyle(.secondary)
            Text("Checked top to bottom — the first match wins. Drag to reorder.")
                .font(DS.Font.sectionFooter)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.xxs)
    }

    private var emptyState: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "globe").foregroundStyle(.secondary)
            Text("No URL rules yet.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Spacing.xxs)
    }

    // MARK: Editor sheet

    @ViewBuilder
    private func sheetEditor(_ target: EditorTarget) -> some View {
        Group {
            switch target {
            case .add:
                URLRuleEditor(add: state.config.defaultSourceID, onCommit: { commit($0) }, onClose: { sheetTarget = nil })
            case .edit(let rule):
                URLRuleEditor(edit: rule, onCommit: { commit($0) }, onRemove: { remove(rule) }, onClose: { sheetTarget = nil })
            }
        }
        .padding(DS.Spacing.xl)
        .frame(width: 400)
    }

    private func commit(_ rule: URLRule) {
        withAnimation(DS.Motion.list) { state.upsertURLRule(rule) }
        sheetTarget = nil
    }

    private func remove(_ rule: URLRule) {
        withAnimation(DS.Motion.list) { state.removeURLRule(id: rule.id) }
        sheetTarget = nil
    }

    /// The rows to show: the in-progress drag's local draft while dragging, else
    /// the live (committed) order. The draft never touches `config`, so a cancelled
    /// drag persists and re-applies nothing.
    ///
    /// The draft is shown only while it's a genuine permutation of the live rules
    /// (same id set). If `config` changed underneath an in-progress drag (an
    /// external `lockime://set-url-rule`/remove) or the draft is otherwise stale, we
    /// fall back to the committed order so an external edit is never masked by a
    /// stuck draft. A drag released off every drop target leaves the draft set with
    /// no commit; it self-heals on the next drag or edit (which re-snapshots or
    /// clears it) — `config` is never mutated mid-drag, so nothing is lost.
    private var displayedRules: [URLRule] {
        guard draggingID != nil, let draft = draftOrder,
              Set(draft.map(\.id)) == Set(state.config.urlRules.map(\.id))
        else { return state.config.urlRules }
        return draft
    }

    /// Start of a drag: snapshot the current order into the view-local draft and
    /// mark which rule is moving. (Snapshotting here also discards any stale draft
    /// left by a previous drag that was released off-target.)
    private func beginDrag(_ id: UUID) {
        draftOrder = state.config.urlRules
        draggingID = id.uuidString
    }

    /// Live reorder: while a rule is dragged over `target`, move it into the
    /// target's slot *in the draft* so the rows part to show where it will land
    /// (what-you-see-is-what-you-get — no separate insertion line). In-memory and
    /// view-local; nothing is persisted or re-applied until the drop commits.
    private func reorder(draggedID: String, over target: UUID) {
        guard draggedID != target.uuidString else { return }
        var draft = draftOrder ?? state.config.urlRules
        guard let from = draft.firstIndex(where: { $0.id.uuidString == draggedID }),
              let to = draft.firstIndex(where: { $0.id == target }), from != to
        else { return }
        let moved = draft.remove(at: from)
        draft.insert(moved, at: to)
        withAnimation(DS.Motion.list) { draftOrder = draft }
    }

    /// End of a drag: commit the draft order (one save + engine apply, a no-op if
    /// unchanged or not a permutation) and clear the drag state. Reached from a
    /// drop on a row or anywhere else in the pane — never left half-applied.
    private func commitReorder() {
        let draft = draftOrder
        clearDrag()
        if let draft { state.reorderURLRules(draft) }
    }

    /// Drop the in-progress drag's view-local state without committing.
    private func clearDrag() {
        draftOrder = nil
        draggingID = nil
    }
}

// MARK: - Summary row

/// A read-only summary of one rule — `[grab] [icon] pattern  ·  [type badge]  ·
/// binding`. Click the content to edit; drag the grab handle to reorder.
///
/// Reorder uses `.onDrag` (from the handle) + a `DropDelegate` returning
/// `DropProposal(operation: .move)` — which suppresses the copy "+" badge that
/// `.dropDestination` shows — and reorders *live* as the row passes over others
/// (the rows part to show the landing spot; on release it is already in place).
/// `.onMove` isn't usable here because this list lives in a grouped `Form`.
private struct URLRuleSummaryRow: View {
    @Environment(AppState.self) private var state
    let rule: URLRule
    let active: Bool
    @Binding var draggingID: String?
    let onBeginDrag: () -> Void
    let onEdit: () -> Void
    let onReorderOver: (String) -> Void
    let onDropCommit: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "line.3.horizontal")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 24)
                .contentShape(.rect)
                .help("Drag to reorder")
                .onDrag {
                    onBeginDrag()
                    return NSItemProvider(object: rule.id.uuidString as NSString)
                } preview: {
                    dragPreview
                }

            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "globe").foregroundStyle(.secondary)

                Text(verbatim: rule.hostPattern)
                    .foregroundStyle(active ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: DS.Spacing.md)

                typeBadge
                bindingText
                    .font(DS.Font.rowSubtitle)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
            .onTapGesture { onEdit() }
        }
        .padding(.vertical, DS.Spacing.xs)
        .onDrop(
            of: [.text],
            delegate: RuleDropDelegate(
                targetID: rule.id,
                draggingID: $draggingID,
                onReorderOver: onReorderOver,
                onDropCommit: onDropCommit
            )
        )
    }

    /// A compact "lifted row" card that floats under the cursor while dragging —
    /// a solid card (the system already renders the drag image translucent, so a
    /// material here would double up into a muddy blob) sized to its content.
    private var dragPreview: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "globe").foregroundStyle(.secondary)
            Text(verbatim: rule.hostPattern).foregroundStyle(.primary)
            typeBadge
        }
        .fixedSize()
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: DS.Radius.row))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.row).strokeBorder(.separator, lineWidth: 1)
        )
    }

    private var typeBadge: some View {
        Text(rule.matchType.pickerLabel)
            .font(DS.Font.rowSubtitle)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var bindingText: Text {
        let name = state.sourceDisplayName(for: rule.lockedSourceID) ?? rule.lockedSourceID.rawValue
        return rule.action == .switchOnce ? Text("Switch to \(name)") : Text("Lock to \(name)")
    }
}

/// Drop delegate for a live, "+"-free reorder. `dropEntered` moves the dragged
/// rule into this row's slot (so rows part to reveal the landing spot);
/// `dropUpdated` returns `.move` to suppress the copy badge; `performDrop`
/// persists the final order.
private struct RuleDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggingID: String?
    let onReorderOver: (String) -> Void
    let onDropCommit: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let id = draggingID, id != targetID.uuidString else { return }
        onReorderOver(id)
    }

    func performDrop(info: DropInfo) -> Bool {
        onDropCommit()
        return true
    }
}

/// Pane-wide fallback drop target so a reorder drag released *off* any row still
/// commits the draft order (rather than leaving it shown-but-unpersisted). Only
/// participates while a rule drag is in progress, so it never intercepts an
/// unrelated text drop.
private struct PaneDropDelegate: DropDelegate {
    @Binding var draggingID: String?
    let onCommit: () -> Void

    func validateDrop(info: DropInfo) -> Bool { draggingID != nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        draggingID != nil ? DropProposal(operation: .move) : nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggingID != nil else { return false }
        onCommit()
        return true
    }
}

// MARK: - The shared editor

/// The rule editor, shown in a sheet for both adding and editing. Edits a local
/// draft and commits on Add/Done — dismissing without committing discards, the
/// standard editor contract.
private struct URLRuleEditor: View {
    @Environment(AppState.self) private var state

    private let isAdd: Bool
    private let ruleID: UUID
    @State private var pattern: String
    @State private var matchType: URLMatchType
    @State private var action: RuleAction
    @State private var source: InputSourceID?
    private let onCommit: (URLRule) -> Void
    private let onRemove: (() -> Void)?
    private let onClose: () -> Void

    init(add defaultSource: InputSourceID?, onCommit: @escaping (URLRule) -> Void, onClose: @escaping () -> Void) {
        self.isAdd = true
        self.ruleID = UUID()
        _pattern = State(initialValue: "")
        _matchType = State(initialValue: .domainSuffix)
        _action = State(initialValue: .lock)
        _source = State(initialValue: nil)
        self.onCommit = onCommit
        self.onRemove = nil
        self.onClose = onClose
    }

    init(edit rule: URLRule, onCommit: @escaping (URLRule) -> Void, onRemove: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.isAdd = false
        self.ruleID = rule.id
        _pattern = State(initialValue: rule.hostPattern)
        _matchType = State(initialValue: rule.matchType)
        _action = State(initialValue: rule.action)
        _source = State(initialValue: rule.lockedSourceID)
        self.onCommit = onCommit
        self.onRemove = onRemove
        self.onClose = onClose
    }

    private var trimmed: String { pattern.trimmingCharacters(in: .whitespaces) }
    private var resolvedSource: InputSourceID? { source ?? state.config.defaultSourceID }
    private var regexInvalid: Bool { matchType == .urlRegex && !trimmed.isEmpty && !URLMatcher.isValidRegex(trimmed) }
    /// Whether the typed pattern already belongs to a *different* rule. The pattern
    /// is a rule's portable identity (match-type-independent — backups/import key on
    /// `hostPattern` alone), so two rules sharing one would silently collapse on the
    /// next export→import. Block it here (with feedback) rather than letting the save
    /// quietly overwrite the other rule or mint a duplicate.
    private var patternCollides: Bool {
        !trimmed.isEmpty && state.config.urlRules.contains { $0.id != ruleID && $0.hasSamePattern(as: trimmed) }
    }
    private var canCommit: Bool { !trimmed.isEmpty && resolvedSource != nil && !regexInvalid && !patternCollides }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            Text(isAdd ? "Add URL Rule" : "Edit URL Rule")
                .font(.headline)

            // Match type
            HStack(spacing: DS.Spacing.md) {
                Text("Match type").foregroundStyle(.secondary)
                Spacer(minLength: DS.Spacing.md)
                Picker("", selection: $matchType) {
                    ForEach(URLMatchType.allCases) { type in Text(type.pickerLabel).tag(type) }
                }
                .labelsHidden()
                .fixedSize()
            }

            // Pattern + per-type hint / regex error (the placeholder names the
            // field, so it needs no separate label).
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                TextField("", text: $pattern, prompt: Text(matchType.patternPlaceholder))
                    .textFieldStyle(.roundedBorder)
                if regexInvalid {
                    Label("Invalid regular expression", systemImage: "exclamationmark.triangle")
                        .font(DS.Font.sectionFooter)
                        .foregroundStyle(DS.Palette.warning)
                } else if patternCollides {
                    Label("A rule with this pattern already exists.", systemImage: "exclamationmark.triangle")
                        .font(DS.Font.sectionFooter)
                        .foregroundStyle(DS.Palette.warning)
                } else {
                    Text(matchType.helpText)
                        .font(DS.Font.sectionFooter)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Lock vs switch — the two segments are self-describing, so no label.
            Picker("", selection: $action) {
                Text("Lock to").tag(RuleAction.lock)
                Text("Switch to").tag(RuleAction.switchOnce)
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            // Target input source
            HStack(spacing: DS.Spacing.md) {
                Text("Input source").foregroundStyle(.secondary)
                Spacer(minLength: DS.Spacing.md)
                Picker("", selection: $source) {
                    Text("Default").tag(InputSourceID?.none)
                    ForEach(state.availableSources) { src in
                        Text(src.localizedName).tag(InputSourceID?.some(src.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            footer
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Spacing.md) {
            if let onRemove {
                Button(role: .destructive) { onRemove() } label: { Text("Remove") }
            }
            Spacer()
            Button("Cancel") { onClose() }
                .keyboardShortcut(.cancelAction)
            Button(isAdd ? "Add" : "Done") { commit() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canCommit)
        }
    }

    private func commit() {
        guard let src = resolvedSource, !trimmed.isEmpty, !regexInvalid, !patternCollides else { return }
        onCommit(URLRule(id: ruleID, hostPattern: trimmed, lockedSourceID: src, action: action, matchType: matchType))
    }
}

// MARK: - Match-type display

private extension URLMatchType {
    /// The picker label / row badge. Literal keys so they stay in the catalog.
    var pickerLabel: LocalizedStringKey {
        switch self {
        case .domainSuffix: "Domain suffix"
        case .domain: "Exact domain"
        case .domainKeyword: "Domain keyword"
        case .urlRegex: "URL regex"
        }
    }

    var patternPlaceholder: LocalizedStringKey {
        switch self {
        case .domainSuffix, .domain: "Host (e.g. github.com)"
        case .domainKeyword: "Keyword (e.g. google)"
        case .urlRegex: "Regex (e.g. /pull/)"
        }
    }

    var helpText: LocalizedStringKey {
        switch self {
        case .domainSuffix: "Matches the domain and all its subdomains."
        case .domain: "Matches only this exact domain, not its subdomains."
        case .domainKeyword: "Matches any domain that contains this text."
        case .urlRegex: "Matches the full URL with a regular expression. Be specific so it doesn't match unrelated pages."
        }
    }
}
