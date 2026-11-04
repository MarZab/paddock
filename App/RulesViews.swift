import PaddockCore
import SwiftUI

extension RuleRow.Kind {
    var title: String {
        switch self {
        case .network: "Network"
        case .http: "HTTP"
        case .filesystemRead: "Read"
        case .filesystemWrite: "Write"
        case .mount: "Mount"
        }
    }
}

extension RuleRow.Source {
    var title: String {
        switch self {
        case .sbxDefault: "sbx default"
        case .kit: "kit"
        case .added: "added"
        case .approval: "approval"
        case .organization: "organization"
        case .paddockPlan: "Paddock"
        case .workspace: "workspace"
        case .unruled: "no rule"
        case .paddockSuggestion: "suggested by Paddock"
        }
    }

    var help: String {
        switch self {
        case .sbxDefault: "One of sbx's defaults"
        case .kit: "Added by the sandbox's kits: the agent's, the project's sbxenv.yaml kits, and Paddock's"
        case .added: "Added by you or Paddock"
        case .approval: "Saved from an sbx approval prompt"
        case .organization: "Organization policy; it cannot be changed here"
        case .paddockPlan: "Paddock's deny protecting its own services: llmman's port, or another project's gateway port"
        case .workspace: "A folder sbx mounts into the sandbox"
        case .unruled: "The sandbox connected to this host (or tried); no rule names it, so sbx's default decided"
        case .paddockSuggestion: "Paddock suggests denying this; nothing is denied until you do"
        }
    }
}

extension SbxApproval.Option {
    /// The icon for one of sbx's answers to an approval request, in the icon-only action columns.
    var systemImage: String {
        switch id {
        case "allow": "checkmark.circle"
        case "dismiss": "xmark.circle"
        default: "questionmark.circle"
        }
    }
}

extension RuleFilter.Seen {
    var title: String {
        switch self {
        case .all: "Any activity"
        case .seen: "Seen"
        case .blocked: "Blocked"
        }
    }
}

extension RuleFilter.Decision {
    var title: String {
        switch self {
        case .all: "All"
        case .allow: "Allowed"
        case .deny: "Denied"
        case .suggested: "Suggested"
        }
    }
}

/// The rules table with its search and filters: the Network
/// Rules and Filesystem pages show every row, a project's Info the rows that apply to its sandbox.
/// One row per host or path, in sections by scope (every sandbox first).
struct RulesPanel: View {
    let model: AppModel
    let rows: [RuleRow]
    /// As tall as its rows, scrolling with its page instead of inside itself (a project's Info).
    var fitsRows = false
    /// Network rows carry the log's activity; filesystem rows do not.
    var showsActivity = true
    /// The Network page's sandbox picker: the sandboxes to choose from, and the choice (nil for all).
    var sandboxes: [String] = []
    var sandbox: Binding<String?>?
    @State private var filter = RuleFilter()

    init(model: AppModel, rows: [RuleRow], fitsRows: Bool = false, showsActivity: Bool = true,
         sandboxes: [String] = [], sandbox: Binding<String?>? = nil) {
        self.model = model
        self.rows = rows
        self.fitsRows = fitsRows
        self.showsActivity = showsActivity
        self.sandboxes = sandboxes
        self.sandbox = sandbox
    }

    var body: some View {
        let shown = filter.apply(rows)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let sandbox {
                    Picker("Sandbox", selection: sandbox) {
                        Text("All sandboxes").tag(String?.none)
                        Divider()
                        ForEach(sandboxes, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help("Show one sandbox's rules (with the ones for every sandbox) and activity, or all")
                }
                TextField("Search", text: $filter.query, prompt: Text("Host, path, sandbox, or rule"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Picker("Decision", selection: $filter.decision) {
                    ForEach(RuleFilter.Decision.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if showsActivity {
                    Picker("Activity", selection: $filter.seen) {
                        ForEach(RuleFilter.Seen.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer()
            }
            // A chosen sandbox's own rules on top, then the ones for every sandbox.
            let sections = RulesTable.sections(shown, selected: sandbox?.wrappedValue)
            // In scope order (the chosen sandbox, then every sandbox's, then the others); the Sandbox
            // column says which.
            let ordered = sections.flatMap(\.rows)
            if fitsRows {
                RuleRowsTable(model: model, rows: ordered, showsActivity: showsActivity, context: sandbox?.wrappedValue)
                    .scrollDisabled(true)
                    .frame(height: Self.height(rows: ordered.count))
            } else {
                RuleRowsTable(model: model, rows: ordered, showsActivity: showsActivity, context: sandbox?.wrappedValue)
            }
            if showsActivity && !model.hasNetworkLog {
                Text("Reading the network log (sbx policy log)...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension RulesPanel {
    /// A table's height for its rows and column header.
    static func height(rows: Int) -> CGFloat {
        CGFloat(rows) * 24 + 32
    }
}

/// The table itself. Takes the model directly (Table cells, see `PortActions`).
struct RuleRowsTable: View {
    let model: AppModel
    let rows: [RuleRow]
    var showsActivity = true
    /// The sandbox the table is filtered to, for actions on rows that apply to every sandbox.
    var context: String? = nil
    /// The row under the pointer, slightly highlighted (every cell of it).
    @State private var hovered: String?

    /// A row and whether the pointer is on it. The hover is part of the row's data: a table redraws
    /// a row's cells only when its data changes.
    struct Shown: Identifiable, Equatable {
        let row: RuleRow
        let hovered: Bool
        var id: String { row.id }
    }

    var body: some View {
        Table(rows.map { Shown(row: $0, hovered: $0.id == hovered) }) {
            TableColumn("Decision") { shown in
                cell(shown) {
                    let row = shown.row
                    // A suggestion is shown disabled until it is applied.
                    Text(row.decision).foregroundStyle(row.isSuggestion ? Color.secondary : (row.decision == "deny" ? Color.red : Color.green))
                }
            }
            .width(min: 40, ideal: 48, max: 64)
            TableColumn("Sandbox") { shown in
                cell(shown) {
                    let row = shown.row
                    // Whom the rule applies to: one sandbox, or all of them.
                    Text(row.sandbox ?? "all").foregroundStyle(row.sandbox == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .width(min: 50, ideal: 90, max: 140)
            TableColumn("Target") { shown in
                cell(shown) {
                    let row = shown.row
                    Text(row.target)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(row.target)
                        .textSelection(.enabled)
                        .foregroundStyle(row.active && !row.isSuggestion ? .primary : .secondary)
                }
            }
            .width(min: 120, ideal: 220)
            TableColumn("Kind") { shown in cell(shown) { Text(shown.row.kind.title).foregroundStyle(.secondary) } }
                .width(min: 36, ideal: 48, max: 64)
            TableColumn("Source") { shown in
                cell(shown) {
                    let row = shown.row
                    Text(row.source.title)
                        .foregroundStyle(row.isSuggestion ? Color.yellow : Color.secondary)
                        .help(row.source.help)
                }
            }
            .width(min: 56, ideal: 84, max: 110)
            TableColumn("Seen") { shown in
                cell(shown) {
                    let row = shown.row
                    // "just now" stands out for a few seconds, orange when the row has blocked connections.
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        if let seen = row.activity?.lastSeen, context.date.timeIntervalSince(seen) < Self.justNow {
                            Text("just now").fontWeight(.semibold)
                                .foregroundStyle((row.activity?.blocked ?? 0) > 0 ? Color.orange : Color.green)
                        } else {
                            Text(row.activity?.lastSeen.map { $0.formatted(.relative(presentation: .named)) } ?? (row.activity == nil ? "" : "seen"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .width(min: 44, ideal: 64, max: 90)
            .defaultVisibility(showsActivity ? .visible : .hidden)
            TableColumn("Connections") { shown in
                cell(shown) {
                    let row = shown.row
                    Text(connectionsText(row.activity))
                        .foregroundStyle((row.activity?.blocked ?? 0) > 0 ? Color.orange : Color.secondary)
                }
            }
            .width(min: 44, ideal: 72, max: 110)
            .defaultVisibility(showsActivity ? .visible : .hidden)
            TableColumn("Rule") { shown in
                cell(shown) {
                    let row = shown.row
                    Text(ruleText(row))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(row.ruleResources.count > 1 ? row.ruleResources.joined(separator: "\n") : (row.ruleName ?? ""))
                }
            }
            .width(min: 50, ideal: 90)
            TableColumn("") { shown in cell(shown) { RuleActions(model: model, row: shown.row, context: context) } }
                .width(min: 68, ideal: 70, max: 76)
        }
    }

    /// How long a connection counts as "just now" in the Seen column.
    private static let justNow: TimeInterval = 10

    /// How far a hovered row's tint reaches past each cell, to close the gaps between cells.
    private static let cellGap: CGFloat = 8

    /// A cell filling its space, tinted while its row is under the pointer.
    private func cell(_ shown: Shown, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Past the cell's edges into the gaps between cells, so the whole row reads as one band.
            .background {
                if shown.hovered {
                    Color.accentColor.opacity(0.15)
                        .padding(.horizontal, -Self.cellGap)
                        .padding(.vertical, -4)
                }
            }
            .onHover { inside in
                if inside {
                    hovered = shown.id
                } else if hovered == shown.id {
                    hovered = nil
                }
            }
    }

    private func connectionsText(_ activity: HostActivity?) -> String {
        guard let activity else { return "" }
        switch (activity.allowed, activity.blocked) {
        case (_, 0): return "\(activity.allowed)"
        case (0, _): return "\(activity.blocked) blocked"
        default: return "\(activity.allowed), \(activity.blocked) blocked"
        }
    }

    /// The rule a row belongs to, and how many hosts it names when more than one.
    private func ruleText(_ row: RuleRow) -> String {
        guard let name = row.ruleName else { return "" }
        let short = name.count > 24 && UUID(uuidString: name) != nil ? String(name.prefix(8)) : name
        return row.ruleResources.count > 1 ? "\(short) (\(row.ruleResources.count))" : short
    }
}

/// Every action sbx allows for a row: allow, deny, or remove a sandbox's own rules; apply
/// Paddock's suggestions; answer approval requests; deny a global, kit,
/// or default allow for one sandbox (a sandbox deny beats any allow); host services for this Mac's
/// ports; remove a global rule. None for Paddock's own service denies, the gateway's HTTP rules,
/// global denies (no sandbox allow beats them), and filesystem rows.
struct RuleActions: View {
    let model: AppModel
    let row: RuleRow
    /// The sandbox the table is filtered to: global rows act for it.
    let context: String?

    /// One action: its slot keeps every kind of action in the same column on every row.
    struct Action {
        enum Slot: Int, CaseIterable {
            /// Allow, Apply, an approval's Allow.
            case allow
            /// Deny, Deny for a sandbox, an approval's Dismiss.
            case deny
            /// Remove.
            case remove
        }

        let slot: Slot
        let title: String
        let icon: String
        let help: String
        var disabled = false
        let perform: () -> Void
    }

    var body: some View {
        let actions = self.actions
        // A grid: one fixed slot per kind, left-aligned, empty slots keeping their place.
        HStack(spacing: 6) {
            ForEach(Action.Slot.allCases, id: \.self) { slot in
                if let action = actions.first(where: { $0.slot == slot }) {
                    Button(action.title, systemImage: action.icon, action: action.perform)
                        .help(action.help)
                        .disabled(action.disabled)
                        .frame(width: Self.slotWidth)
                } else {
                    Color.clear.frame(width: Self.slotWidth, height: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    private static let slotWidth: CGFloat = 18

    private var actions: [Action] {
        // The sandbox a row's actions are for: its own, or the one the table shows.
        let project = (row.sandbox ?? context).flatMap { model.project(named: $0) }.flatMap { model.state(of: $0) != nil ? $0 : nil }
        var actions: [Action] = []
        if let project, row.kind == .network {
            actions += sandboxActions(for: project)
        }
        // `sbx policy rm network`: network and HTTP rules only.
        if row.sandbox == nil, row.removable, !row.kind.isFilesystem, let id = row.ruleID {
            let resources = row.ruleResources
            actions.append(Action(slot: .remove, title: "Remove", icon: "trash",
                                  help: resources.count > 1 ? "Remove for all (\(resources.count) hosts)" : "Remove for all") {
                model.pendingGlobalRuleRemoval = SbxRuleReference(id: id, resources: resources, removable: true)
            })
        }
        return actions
    }

    private func sandboxActions(for project: Project) -> [Action] {
        let ownRule = row.sandbox != nil && (row.source == .added || row.source == .approval)
        let port = Ports.hostServicePort(row.target, app: model.appConfig)
        let name = project.name
        let row = self.row
        let model = self.model
        switch row.source {
        case .paddockSuggestion:
            return [Action(slot: .deny, title: "Deny", icon: "hand.raised", help: "Deny for \(name)") {
                model.deny(row.ruleResources, on: project, summary: row.target)
            }]
        case .unruled:
            // A pending sbx approval for the host is answered as such; otherwise a rule.
            if let request = model.approvalRequests(for: project).first(where: { $0.host == row.target }) {
                return request.options.map { option in
                    Action(slot: option.id == "allow" ? .allow : .deny, title: option.label, icon: option.systemImage,
                           help: "\(option.label) request", disabled: model.answering.contains(request.id)) {
                        model.respond(to: request, with: option, for: project)
                    }
                }
            }
            if let port {
                return [Action(slot: .allow, title: "Allow", icon: "checkmark.circle", help: "Allow port \(port)") {
                    model.addHostService(port, to: project)
                }]
            }
            guard let host = row.host else { return [] }
            return [
                Action(slot: .allow, title: "Allow", icon: "checkmark.circle", help: "Allow for \(name)") {
                    model.setHostRule(.allow, for: host, on: project)
                },
                Action(slot: .deny, title: "Deny", icon: "hand.raised", help: "Deny for \(name)") {
                    model.setHostRule(.deny, for: host, on: project)
                },
            ]
        case .paddockPlan, .workspace:
            return []
        case .sbxDefault, .kit, .organization, .added, .approval:
            if let port {
                // This Mac's ports are host services.
                if ownRule && row.decision == "deny" {
                    return [Action(slot: .allow, title: "Allow", icon: "checkmark.circle", help: "Allow port \(port)") {
                        model.addHostService(port, to: project)
                    }]
                }
                guard row.decision == "allow" else { return [] }
                return [ownRule
                    ? Action(slot: .remove, title: "Remove", icon: "trash", help: "Remove port \(port)") { model.removeHostService(port, from: project) }
                    : Action(slot: .deny, title: "Deny", icon: "hand.raised", help: "Deny for \(name)") { model.removeHostService(port, from: project) }]
            }
            guard let host = row.host else { return [] }
            if ownRule {
                let flip = row.decision == "allow"
                    ? Action(slot: .deny, title: "Deny", icon: "hand.raised", help: "Deny host") { model.setHostRule(.deny, for: host, on: project) }
                    : Action(slot: .allow, title: "Allow", icon: "checkmark.circle", help: "Allow host") { model.setHostRule(.allow, for: host, on: project) }
                return [flip, Action(slot: .remove, title: "Remove", icon: "trash", help: "Remove rule") { model.setHostRule(nil, for: host, on: project) }]
            }
            // A sandbox deny beats any allow: the global, kit, or default rule stays as it is.
            guard row.decision == "allow" else { return [] }
            return [Action(slot: .deny, title: "Deny", icon: "hand.raised", help: "Deny for \(name)") {
                model.setHostRule(.deny, for: host, on: project)
            }]
        }
    }
}

/// Block a host: for one sandbox (a sandbox deny, as a host rule), or for every sandbox (a global
/// sbx deny, confirmed first).
struct BlockHostPopover: View {
    let model: AppModel
    /// The sandboxes to choose from.
    let sandboxes: [String]
    let done: () -> Void
    /// Nil for every sandbox.
    @State private var scope: String?
    @State private var host = ""

    init(model: AppModel, sandboxes: [String], scope: String?, done: @escaping () -> Void) {
        self.model = model
        self.sandboxes = sandboxes
        self.done = done
        _scope = State(initialValue: scope)
    }

    var body: some View {
        let empty = host.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(alignment: .leading, spacing: 8) {
            Text("Block a host").font(.headline)
            Picker("For", selection: $scope) {
                Text("Every sandbox").tag(String?.none)
                Divider()
                ForEach(sandboxes, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .fixedSize()
            HStack(spacing: 8) {
                TextField("Host", text: $host, prompt: Text("example.com or *.example.com:443"))
                    .frame(width: 260)
                    .onSubmit(block)
                Button("Block", action: block)
                    .keyboardShortcut(.defaultAction)
                    .disabled(empty)
            }
        }
        .padding(12)
    }

    private func block() {
        let text = host.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if let scope {
            if let project = model.project(named: scope) { model.setHostRule(.deny, for: text, on: project) }
        } else {
            model.requestGlobalDeny(text)
        }
        done()
    }
}

/// Confirms changing sbx's global rules (they apply to every sandbox): removing one, or blocking a host.
struct GlobalRuleRemoval: ViewModifier {
    @Bindable var model: AppModel

    func body(content: Content) -> some View {
        content
        .confirmationDialog("Block \(model.pendingGlobalDeny ?? "") for every sandbox?",
                            isPresented: Binding(get: { model.pendingGlobalDeny != nil }, set: { if !$0 { model.pendingGlobalDeny = nil } }),
                            presenting: model.pendingGlobalDeny) { host in
            Button("Block for Every Sandbox", role: .destructive) { model.addGlobalDeny(host) }
        } message: { host in
            Text("Adds a global sbx deny for \(host). It applies to all sandboxes at once, including ones Paddock does not manage.")
        }
        .confirmationDialog("Remove this sbx rule for every sandbox?",
                                   isPresented: Binding(get: { model.pendingGlobalRuleRemoval != nil },
                                                        set: { if !$0 { model.pendingGlobalRuleRemoval = nil } }),
                                   presenting: model.pendingGlobalRuleRemoval) { rule in
            Button("Remove", role: .destructive) { model.removeGlobalRule(rule) }
        } message: { rule in
            Text(rule.resources.count > 1
                 ? "The rule names \(rule.resources.count) hosts, and sbx removes them all: \(rule.resources.joined(separator: ", ")). It applies to all sandboxes, including ones Paddock does not manage."
                 : "It applies to \(rule.resources.joined(separator: ", ")) for all sandboxes, including ones Paddock does not manage.")
        }
    }
}

/// Network (sidebar): every network and HTTP rule, global and per sandbox, with the network log
/// merged in: what each rule let through or
/// blocked, and the hosts no rule names.
struct NetworkRulesPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let all = model.networkRows(for: nil)
        let names = Set(all.compactMap(\.sandbox)).sorted()
        // One sandbox, or all (nil); the other sandboxes' sections are hidden. A sandbox that went
        // away falls back to all.
        let shown = model.networkSandbox.flatMap { names.contains($0) ? $0 : nil }
        RulesPanel(model: model, rows: shown.map { model.networkRows(for: $0) } ?? all, sandboxes: names,
                   sandbox: $model.networkSandbox)

            .padding(12)
            .navigationTitle("Network")
            .modifier(GlobalRuleRemoval(model: model))
            .task { await model.refreshAllSnapshots() }
    }
}

/// Filesystem (sidebar): sbx's filesystem rules and every sandbox's mounts.
struct FilesystemPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let all = model.filesystemRows(for: nil)
        let names = Set(all.compactMap(\.sandbox)).sorted()
        // As on the Network page: one sandbox (its section and the rules for every sandbox), or all.
        let shown = model.filesystemSandbox.flatMap { names.contains($0) ? $0 : nil }
        RulesPanel(model: model, rows: shown.map { model.filesystemRows(for: $0) } ?? all, showsActivity: false,
                   sandboxes: names, sandbox: $model.filesystemSandbox)
            .padding(12)
            .navigationTitle("Filesystem")
            .modifier(GlobalRuleRemoval(model: model))
            .task { await model.refreshAllSnapshots() }
    }
}
