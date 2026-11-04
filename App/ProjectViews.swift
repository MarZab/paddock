import AppKit
import PaddockCore
import PaddockShellCore
import SwiftUI

struct ProjectRow: View {
    let project: Project
    /// The project's one mark and its words (backlog doc UI, Status marks).
    let badge: ProjectBadge
    let help: String

    var body: some View {
        HStack(spacing: 6) {
            ProjectBadgeView(badge: badge, help: help)
            // The sandbox name, as sbx and the terminal show it.
            Text(project.name)
        }
        .help(help)
    }
}

/// An agent under its project in the sidebar (PAD-63): its own mark, its tab's title (up to three
/// lines), and how long it has been in its state. Idle agents and agents in no open tab are dimmed; the time moves on its own.
struct AgentRow: View {
    let row: SidebarAgentRow
    let now: Date

    var body: some View {
        // The mark and the time stay on the title's first line while it wraps.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            AgentMarkView(mark: row.mark)
            Text(row.title).lineLimit(3).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            TimelineView(.periodic(from: now, by: 15)) { context in
                Text(SidebarAgents.stateText(row, now: context.date))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
        }
        .padding(.leading, 19)
        .opacity(row.place == .elsewhere || row.mark == .none ? 0.6 : 1)
        .help(SidebarAgents.help(row, now: now))
        .accessibilityElement(children: .combine)
    }
}

/// An agent's mark, the same symbols as its tab (backlog doc UI, Status marks): orange exclamation
/// while it waits for the operator, green ellipsis while it works, a checkmark once it finished out
/// of view. Entering "waits" bounces it once; nothing pulses.
struct AgentMarkView: View {
    let mark: AgentTabMark
    @State private var bounces = 0

    var body: some View {
        symbol
            .frame(width: 13, height: 13)
            .symbolEffect(.bounce, value: bounces)
            .onChange(of: mark) { old, new in
                if new == .waiting, old != .waiting { bounces += 1 }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var symbol: some View {
        switch mark {
        case .waiting:
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 11)).foregroundStyle(.orange)
        case .working:
            Image(systemName: "ellipsis.circle.fill").font(.system(size: 11)).foregroundStyle(.green)
        case .finished:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.tint)
        case .none:
            Image(systemName: "circle").font(.system(size: 7)).foregroundStyle(.tertiary)
        }
    }
}

/// A project's mark (`ProjectBadge`): one static symbol per state, color only adds to it, so it
/// reads without watching it (PAD-33). Entering "needs you" bounces it once, nothing pulses.
struct ProjectBadgeView: View {
    let badge: ProjectBadge
    /// For VoiceOver; the views around it show it as a tooltip.
    var help = ""
    @State private var bounces = 0

    var body: some View {
        symbol
            .frame(width: 13, height: 13)
            .symbolEffect(.bounce, value: bounces)
            .onChange(of: badge) { old, new in
                if new == .needsYou, old != .needsYou { bounces += 1 }
            }
            .accessibilityElement()
            .accessibilityLabel(help)
            .accessibilityHidden(badge == .none)
    }

    @ViewBuilder private var symbol: some View {
        switch badge {
        case .needsYou:
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 11)).foregroundStyle(.orange)
        case .running:
            Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.green)
        case .changing:
            Image(systemName: "circle.lefthalf.filled").font(.system(size: 9)).foregroundStyle(.secondary)
        case .problem:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(.red)
        case .stopped:
            Image(systemName: "circle").font(.system(size: 8)).foregroundStyle(.secondary)
        case .none:
            Color.clear
        }
    }
}

enum SandboxStateText {
    static func describe(_ state: SandboxStates.State?) -> String {
        ProjectBadge.describe(state)
    }
}

extension AppConfig.Provider {
    var summary: String {
        switch self {
        case .agentDefault: "default provider"
        case .local(let model): "local model \(model)"
        }
    }
}

/// All projects as cards, plus any problems loading Paddock's config or project files.
struct ProjectsOverview: View {
    @Environment(AppModel.self) private var model
    let open: (String) -> Void

    init(open: @escaping (String) -> Void) {
        self.open = open
    }

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 16)]

    var body: some View {
        let problems = model.configProblems + model.projectProblems
        if model.allProjects.isEmpty && problems.isEmpty {
            ContentUnavailableView {
                Label("No projects yet", systemImage: "folder")
            } description: {
                Text("A project is one folder, run by one agent in its own sandbox.")
            } actions: {
                Button("New Project") { model.showsNewProject = true }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(model.allProjects) { project in
                            Button { open(project.name) } label: {
                                ProjectCard(project: project, state: model.state(of: project),
                                            badge: model.badge(of: project),
                                            provider: model.appConfig.provider(named: project.provider))
                            }
                            .buttonStyle(.plain)
                        }
                        Button { model.showsNewProject = true } label: { NewProjectCard() }
                            .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Projects")
        }
    }
}

struct ProjectCard: View {
    let project: Project
    let state: SandboxStates.State?
    let badge: ProjectBadge
    let provider: AppConfig.Provider?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(project.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                ProjectBadgeView(badge: badge, help: SandboxStateText.describe(state))
                Text(SandboxStateText.describe(state)).font(.callout).foregroundStyle(.secondary)
            }
            Label(project.agent, systemImage: "terminal")
            Label(provider?.summary ?? "\(project.provider) (not defined)", systemImage: "cpu")
                .lineLimit(1)
                .truncationMode(.middle)
            Label((project.folder as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct NewProjectCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus").font(.title2)
            Text("New Project")
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 120)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    let project: Project
    /// A remove step waiting for the operator's confirmation.
    @State private var confirming: AppModel.Teardown?

    init(project: Project) {
        self.project = project
    }

    var body: some View {
        let state = model.state(of: project)
        let changes = model.syncItems(for: project).filter { $0.apply != .create && !project.ignoredSuggestions.contains($0.id) }
        let pendingPorts = model.portRows().contains { $0.sandbox == project.name && $0.state.differs }
        let requests = !model.approvalRequests(for: project).isEmpty
        let needsAttention = pendingPorts || requests || !changes.isEmpty || model.needsConfirmation(for: project)
        ProjectTabs(project: project, needsAttention: needsAttention) {
            info(state)
        }
        .navigationTitle(project.name)
        .toolbar { actions(state) }
        .modifier(GlobalRuleRemoval(model: model))
        .task(id: project.name) { await model.refreshSnapshot(project.name) }
        .confirmationDialog(confirming.map { "\($0.title) \(project.name)?" } ?? "",
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            presenting: confirming) { step in
            Button(step.title, role: .destructive) { model.tearDown(project, to: step) }
        } message: { step in
            Text(teardownMessage(step, state: state))
        }
    }

    /// What a remove step does, including the steps it takes first.
    private func teardownMessage(_ step: AppModel.Teardown, state: SandboxStates.State?) -> String {
        let stopsFirst = state == .running ? "It is stopped first. " : ""
        let sandbox = "The sandbox and everything inside it that is not in the project folder are deleted."
        switch step {
        case .stop:
            return ""
        case .removeSandbox:
            return stopsFirst + sandbox + " The folder and Paddock's project stay."
        case .removeProject:
            let removesSandbox = state == nil ? "" : stopsFirst + sandbox + " Then "
            return removesSandbox + (state == nil ? "Deletes" : "deletes")
                + " its project file in ~/.config/paddock/projects. The folder and its files stay as they are."
        }
    }

    /// Stop runs at once; a remove step asks first.
    private func request(_ step: AppModel.Teardown) {
        if step == .stop {
            model.tearDown(project, to: .stop)
        } else {
            confirming = step
        }
    }

    /// The project's actions in the title bar, aligned right: its state, then start, stop, or
    /// create, and remove. Its config opens from the Info tab's folder row.
    @ToolbarContentBuilder
    private func actions(_ state: SandboxStates.State?) -> some ToolbarContent {
        TrailingEdge()
        ToolbarItemGroup(placement: .automatic) {
            // The state, always; while an action runs, its name ("Starting the sandbox") instead of
            // the state's, not a spinner.
            HStack(spacing: 6) {
                ProjectBadgeView(badge: model.badge(of: project), help: model.badgeHelp(of: project))
                Text(model.activity(of: project) ?? SandboxStateText.describe(state))
                    .foregroundStyle(.secondary)
            }
            // Clear of the toolbar group's rounded edge.
            .padding(.horizontal, 8)
            .help(model.activity(of: project) ?? SandboxStateText.describe(state))
            Group {
                switch state {
                case nil:
                    Button("Create Sandbox", systemImage: "plus.square") { model.createSandbox(project) }
                        .help("Create the sandbox")
                case .running?:
                    EmptyView()
                case .stopped?, .other?:
                    Button("Start", systemImage: "play.fill") { model.startSandbox(project) }
                        .help("Start the sandbox")
                }
                teardownButton
            }
            .disabled(model.isBusy(project))
            // Last: shells and the folder, in the operator's own apps. New tabs open from the tab bar's +.
            Menu {
                Section("Sandbox") {
                    Button("Sandbox Shell in Terminal", systemImage: "apple.terminal") { model.openExternalShell(for: project) }
                        .help("sbx exec -it \(project.name) bash, in your terminal app")
                }
                .disabled(state == nil || model.sbxPath == nil)
                Section("This Mac") {
                    Button("Shell on This Mac in Terminal", systemImage: "laptopcomputer") { model.openHostShell(for: project) }
                        .help("Your login shell on this Mac, in \(project.folder), not in the sandbox")
                    Button("Show in Finder", systemImage: "folder") { model.showInFinder(project) }
                }
            } label: {
                Label("Shells", systemImage: "apple.terminal")
            }
            .menuIndicator(.visible)
            .help("Shells in the sandbox or on this Mac in your terminal app, and the folder in Finder")
        }
    }

    /// Stop and remove in one button: a click takes the mildest step the project can take now
    /// (stop, else remove the sandbox, else remove the project); its menu, and a right click, offer
    /// every step, each taking the ones before it first.
    @ViewBuilder
    private var teardownButton: some View {
        let steps = model.teardownSteps(for: project)
        if let main = steps.first {
            Menu {
                teardownItems(steps)
            } label: {
                Label(main.title, systemImage: main.systemImage)
            } primaryAction: {
                request(main)
            }
            .menuIndicator(steps.count > 1 ? .visible : .hidden)
            .contextMenu { teardownItems(steps) }
            .help(steps.count > 1 ? "\(main.title); the arrow or a right click offers \(steps.dropFirst().map(\.title).joined(separator: " and "))"
                                  : main.title)
        }
    }

    @ViewBuilder
    private func teardownItems(_ steps: [AppModel.Teardown]) -> some View {
        ForEach(steps) { step in
            Button(step.title, systemImage: step.systemImage, role: step == .stop ? nil : .destructive) { request(step) }
        }
    }

    /// Wider than this, the Info tab shows its two columns side by side.
    private static let twoColumnWidth: CGFloat = 820

    /// The Info tab, one page in two columns (stacked when the window is narrow): on the left the
    /// project's details, what needs attention (only when something does), Paddock's suggestions,
    /// and shortcuts to its rules on the Network and Filesystem pages; on the right
    /// its ports. Hosts are allowed and denied on the Network page.
    private func info(_ state: SandboxStates.State?) -> some View {
        let network = model.networkRows(for: project.name)
        let filesystem = model.filesystemRows(for: project.name)
        let left = VStack(alignment: .leading, spacing: 14) {
            ProjectStatusHeader(project: project, state: state)
            SandboxResourcesSection(project: project)
            AttentionSections(project: project)
            serviceDenyRow
            approvalRows
            networkShortcut(network)
            filesystemShortcut(filesystem)
            RecentActivity(entries: model.timeline[project.name])
        }
        let right = VStack(alignment: .leading, spacing: 18) {
            ProjectPortsSections(project: project)
        }
        return GeometryReader { geometry in
            ScrollView {
                Group {
                    if geometry.size.width >= Self.twoColumnWidth {
                        HStack(alignment: .top, spacing: 24) {
                            left.frame(width: min(geometry.size.width * 0.45, 520))
                            Divider()
                            right.frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            left
                            right
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    /// The sandbox's rules and activity live on the Network page; here, a count and the way there.
    private func networkShortcut(_ rules: [RuleRow]) -> some View {
        let blocked = rules.filter { ($0.activity?.blocked ?? 0) > 0 }.count
        let suggested = rules.filter(\.isSuggestion).count
        return HStack(spacing: 6) {
            Image(systemName: "network").foregroundStyle(.secondary)
            Text("\(rules.count) rules")
            if blocked > 0 {
                Text("· \(blocked) blocked").foregroundStyle(.orange)
                    .help("Rules or hosts with blocked connections")
            }
            if suggested > 0 {
                Text("· \(suggested) suggested").foregroundStyle(.yellow)
            }
            Spacer()
            Button("Open in Network") { model.showNetwork(for: project.name) }
                .help("The rules for this sandbox, with what it connected to")
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// The sandbox's filesystem rules and mounts live on the Filesystem page; here, a count and the way there.
    private func filesystemShortcut(_ rules: [RuleRow]) -> some View {
        let mounts = rules.filter { $0.kind == .mount }.count
        return HStack(spacing: 6) {
            Image(systemName: "folder.badge.gearshape").foregroundStyle(.secondary)
            Text("\(mounts) mount\(mounts == 1 ? "" : "s") · \(rules.count - mounts) rules")
            Spacer()
            Button("Open in Filesystem") { model.showFilesystem(for: project.name) }
                .help("The filesystem rules and mounts for this sandbox")
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// Paddock's denies for its own services (llmman, other projects' gateways), missing from the
    /// sandbox: a suggestion with Apply, not a warning.
    @ViewBuilder
    private var serviceDenyRow: some View {
        if let item = model.syncItems(for: project).first(where: { $0.id == SyncItem.serviceDeniesID }),
           !project.ignoredSuggestions.contains(SyncItem.serviceDeniesID) {
            suggestionBlock("Deny the sandbox access to Paddock's services", action: "Apply", help: item.summary,
                            ignore: { model.ignoreSuggestion(SyncItem.serviceDeniesID, for: project) }) {
                model.apply(item, for: project)
            }
        }
    }

    /// sbx's approval requests: what the agent tried that no rule decided, newest first, each with
    /// the answers sbx offers (Allow, Dismiss).
    @ViewBuilder
    private var approvalRows: some View {
        ForEach(model.approvalRequests(for: project)) { request in
            NoticeRow(.request, "Wants to reach \(request.title)", help: request.detail) {
                // sbx's own options, in its order, the first (Allow) as the main one.
                ForEach(request.options.reversed()) { option in
                    Button(option.label) { model.respond(to: request, with: option, for: project) }
                    // Next to Dismiss: Dismiss only waves it off (sbx asks again), Block denies the host.
                    if option.id == "dismiss" {
                        Button("Block") { model.block(request, for: project) }
                            .help("Deny \(request.host) for \(project.name); the agent cannot reach it")
                    }
                }
            }
            .disabled(model.answering.contains(request.id))
        }
    }

    /// A suggestion: what it is, a button that applies it, and Ignore when it can be dismissed.
    private func suggestionBlock(_ text: String, action: String, help: String, ignore: (() -> Void)? = nil,
                                 apply: @escaping () -> Void) -> some View {
        NoticeRow(.suggestion, text) {
            if let ignore {
                Button("Ignore", action: ignore)
                    .help("Stop suggesting this for this project")
            }
            Button(action, action: apply)
                .help(help)
        }
        .disabled(model.isBusy(project))
    }
}

/// The newest approval request under a project's terminal: what the agent is waiting for, with
/// sbx's answers.
struct ApprovalBanner: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let request: SbxApproval
    let more: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("The agent wants to reach \(request.title)").lineLimit(1).truncationMode(.middle)
                if more > 0 {
                    Text("\(more) more in Info").font(.caption).foregroundStyle(.secondary)
                }
            }
            .help(request.detail)
            Spacer()
            ForEach(request.options.reversed()) { option in
                // No keyboard shortcut: Return belongs to the terminal above.
                Button(option.label) { model.respond(to: request, with: option, for: project) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
        .overlay(alignment: .top) { Divider() }
        .disabled(model.answering.contains(request.id))
    }
}

/// What happened in the sandbox while Paddock was watching: lifecycle, published ports, and each
/// host it reached or was blocked from for the first time. Kept in memory only.
struct RecentActivity: View {
    let entries: [ActivityTimeline.Entry]
    @State private var showsAll = false

    private static let shortList = 8

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Recent Activity").font(.headline)
                    Spacer()
                    if entries.count > Self.shortList {
                        Button(showsAll ? "Show Less" : "Show All \(entries.count)") { showsAll.toggle() }
                            .buttonStyle(.link)
                    }
                }
                ForEach(showsAll ? entries : Array(entries.prefix(Self.shortList))) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: Self.icon(entry.kind)).foregroundStyle(Self.color(entry.kind)).frame(width: 16)
                        Text(entry.text).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(entry.date, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    }
                    .help(Self.help(entry))
                }
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    static func icon(_ kind: ActivityTimeline.Entry.Kind) -> String {
        switch kind {
        case .lifecycle("started"): "play.fill"
        case .lifecycle("stopped"): "stop.fill"
        case .lifecycle: "shippingbox"
        case .ports: "point.3.connected.trianglepath.dotted"
        case .connected: "arrow.up.right"
        case .blocked: "hand.raised"
        }
    }

    static func color(_ kind: ActivityTimeline.Entry.Kind) -> Color {
        if case .blocked = kind { return .orange }
        return .secondary
    }

    static func help(_ entry: ActivityTimeline.Entry) -> String {
        let when = entry.date.formatted(date: .abbreviated, time: .standard)
        if case .blocked(_, let reason?) = entry.kind { return "\(when): \(reason)" }
        return when
    }
}

/// The folders mounted besides the project folder (PAD-73.5): read-only unless switched, each with
/// Show in Finder and Remove, and Add. A change applies at the sandbox's next create.
struct ExtraFoldersRow: View {
    @Environment(AppModel.self) private var model
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(project.extraFolders, id: \.path) { folder in
                HStack(spacing: 6) {
                    Text((folder.path as NSString).abbreviatingWithTildeInPath)
                        .truncationMode(.head)
                        .help(folder.path)
                    Toggle("Read-only", isOn: Binding(get: { folder.readOnly },
                                                      set: { model.setExtraFolder(folder.path, readOnly: $0, in: project) }))
                        .toggleStyle(.checkbox)
                        .help("Off: the agent can change this folder's files too")
                    if let other = ExtraFolders.otherProject(folder.path, in: model.allProjects, except: project.name) {
                        Label("project \(other)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help("This is \(other)'s folder: writable, this agent could change that project's files")
                    }
                    Button("Show in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)])
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                    Button("Remove", systemImage: "minus.circle") { model.removeExtraFolder(folder.path, from: project) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Stop mounting this folder (at the sandbox's next create)")
                }
            }
            HStack(spacing: 6) {
                if project.extraFolders.isEmpty { Text("none") }
                Button("Add Folder", systemImage: "plus.circle") { chooseFolder() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Mount another folder in the sandbox, read-only unless you switch it (at its next create)")
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "A folder to mount in \(project.name)'s sandbox, read-only"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addExtraFolder(url.path, to: project)
    }
}

/// The project's details at the top of its Info tab: what sbx and the project file say about it.
struct ProjectStatusHeader: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let state: SandboxStates.State?
    @State private var editsKits = false
    @State private var confirmsFiles = false

    var body: some View {
        let sandbox = model.sandboxes.first { $0.name == project.name }
        let ports = model.snapshots[project.name]?.ports.count
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
            row("Status") {
                HStack(spacing: 6) {
                    ProjectBadgeView(badge: model.badge(of: project), help: model.badgeHelp(of: project))
                    // The state and what asks for the operator, as the tooltip says it, first letter up.
                    let words = model.badgeHelp(of: project)
                    Text(words.prefix(1).uppercased() + words.dropFirst())
                }
            }
            row("Agent") { Text(project.agent) }
            row("Provider") { Text(providerSummary) }
            row("Terminal") {
                // So this project's terminals look unlike other projects' (kept in its project file).
                Picker("Terminal theme", selection: Binding(get: { project.terminalTheme },
                                                            set: { model.setTerminalTheme($0, for: project) })) {
                    Text("Default").tag(String?.none)
                    Divider()
                    ForEach(TerminalTheme.all) { theme in
                        Label {
                            Text(theme.name)
                        } icon: {
                            Image(systemName: "square.fill")
                                .foregroundStyle(Color(red: Double(theme.background.red) / 255,
                                                       green: Double(theme.background.green) / 255,
                                                       blue: Double(theme.background.blue) / 255))
                        }
                        .tag(Optional(theme.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help("The colors of this project's terminals in Paddock, to tell its sessions apart")
            }
            row("Folder") {
                HStack(spacing: 4) {
                    Text((project.folder as NSString).abbreviatingWithTildeInPath)
                        .truncationMode(.head)
                    Button("Show in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.folder)])
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                    Button("Config", systemImage: "doc.text") { model.openProjectConfig(project) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Edit sbxenv.yaml in the project folder; Paddock writes one, with a kit for the project, when there is none")
                }
            }
            if model.environment(of: project) == nil {
                row("sbxenv.yaml") {
                    HStack(spacing: 6) {
                        Text("none")
                        Button("Create...", systemImage: "doc.badge.plus") { confirmsFiles = true }
                            .buttonStyle(.borderless)
                            .help("Write sbxenv.yaml and a kit for this project into its folder, to run it with `sbx env run` too")
                    }
                    .confirmationDialog("Create sbxenv.yaml for \(project.name)?", isPresented: $confirmsFiles) {
                        Button("Create") { model.createSandboxFiles(for: project) }
                    } message: {
                        Text("Writes sbxenv.yaml, tools/sandbox/\(SandboxFiles.kitName(for: project.name)) and tools/sandbox/run.sh into the project folder. Existing files are never replaced.")
                    }
                }
            }
            row("Extra folders") {
                ExtraFoldersRow(project: project)
            }
            if let port = project.gatewayPort {
                row("Gateway") { Text(model.gatewayPorts[project.name] == nil ? "port \(port), not listening" : "port \(port)") }
            }
            if project.cloneMode {
                row("Clone mode") { Text("the agent works on its own clone") }
            }
            if model.appConfig.agents[project.agent] != nil {
                // The project file's kits (sbx's and its own) apart from Paddock's: each is changed
                // in its own place (backlog doc Kits).
                if let environment = model.environment(of: project) {
                    row("Project kits") {
                        HStack(spacing: 4) {
                            let kits = environment.kits.map(\.source)
                            Text(kits.isEmpty ? "none" : kits.joined(separator: ", "))
                                .truncationMode(.tail)
                                .help("From sbxenv.yaml: " + (kits.isEmpty ? "none" : kits.joined(separator: ", ")))
                            Button("Review", systemImage: "checklist") {
                                model.confirmation = .init(project: project.name, then: .nothing)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Review sbxenv.yaml: its kits and hosts, and which hosts the agent may reach")
                        }
                    }
                }
                row(model.environment(of: project) == nil ? "Kits" : "Paddock kits") {
                    HStack(spacing: 4) {
                        let kits = project.chosenKits(model.appConfig)
                        Text(kits.isEmpty ? "none" : kits.joined(separator: ", "))
                            .truncationMode(.tail)
                            .help(kits.joined(separator: ", "))
                        Button("Edit Kits", systemImage: "puzzlepiece.extension") { editsKits = true }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Choose the sbx kits the sandbox is created with")
                    }
                }
            }
            row("Published") { Text(ports.map { "\($0) port\($0 == 1 ? "" : "s")" } ?? "-") }
            row("Created") {
                Text(sandbox?.createdAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "-")
            }
            row("Last used") { Text(sandbox?.lastUsedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "-") }
        }
        .font(.callout)
        .lineLimit(1)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $editsKits) { KitsSheet(project: project) }
    }

    private func row(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value()
        }
    }

    private var providerSummary: String {
        model.appConfig.provider(named: project.provider)?.summary ?? "\(project.provider) (not defined)"
    }
}

/// New Project (backlog doc UI, Sheets). Every choice is a section the operator defined in paddock.yaml.
struct NewProjectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let created: (String) -> Void

    @State private var draft: ProjectDraft?
    @State private var configProblem: String?
    @State private var error: String?
    /// Write `sbxenv.yaml` and a kit for the project into its folder (`SandboxFiles`).
    @State private var writesFiles = false

    init(created: @escaping (String) -> Void) {
        self.created = created
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        Text(draft?.folder ?? "No folder chosen")
                            .foregroundStyle(draft == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(draft == nil ? "Choose Folder..." : "Change...") { chooseFolder() }
                    }
                } header: {
                    Text("New Project").font(.title3.bold())
                } footer: {
                    Text("Only this folder is mounted into the sandbox.")
                }
                if let binding = Binding($draft) {
                    Section {
                        TextField("Name", text: binding.name)
                        if !ProjectList.isValidSandboxName(binding.wrappedValue.name) {
                            Text("Letters, numbers, hyphens, and periods; starting with a letter or number.")
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                    } footer: {
                        Text("Also the sbx sandbox name.")
                    }
                    Section {
                        Picker("Agent", selection: binding.agent) {
                            ForEach(model.appConfig.agents.keys.sorted(), id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Provider", selection: binding.provider) {
                            ForEach(providerChoices, id: \.self) { name in
                                Text(providerLabel(name)).tag(name)
                            }
                        }
                        Toggle("Clone mode (the agent works on its own clone)", isOn: binding.cloneMode)
                            .disabled(!NewProject.supportsClone(binding.wrappedValue.folder))
                            .help(NewProject.supportsClone(binding.wrappedValue.folder)
                                ? "sbx clones the repository; your working tree stays untouched"
                                : "Needs a Git repository: this folder has no .git of its own")
                    }
                    if case .local(let name)? = model.appConfig.provider(named: binding.wrappedValue.provider),
                       let installed = model.installedModels, !installed.contains(name) {
                        Label("llmman does not have \(name) yet. Download it under Models first.", systemImage: "arrow.down.circle")
                            .foregroundStyle(.orange)
                    }
                    Section {
                        if hasEnvironmentFile(binding.wrappedValue.folder) {
                            Text("The folder has an sbxenv.yaml: Paddock uses it, and shows it for you to confirm before the first create.")
                        } else {
                            Toggle("Create sbxenv.yaml and a kit for this project", isOn: $writesFiles)
                                .help("Writes sbxenv.yaml and tools/sandbox/\(SandboxFiles.kitName(for: binding.wrappedValue.name)) into the folder")
                        }
                    } header: {
                        Text("Sandbox files")
                    } footer: {
                        Text("sbxenv.yaml is the project's own setup, which sbx env run uses without Paddock: its kits, hosts, and ports. Paddock adds its own part from a file of its own.")
                    }
                    Section {
                        let agent = model.appConfig.agents[binding.wrappedValue.agent]
                        KitPicker(app: model.appConfig, agent: agent, selection: binding.kits)
                    } header: {
                        Text("Kits")
                    } footer: {
                        KitsFootnote()
                    }
                    Section {
                        ForEach(binding.wrappedValue.extraFolders, id: \.path) { folder in
                            HStack(spacing: 6) {
                                Text((folder.path as NSString).abbreviatingWithTildeInPath).truncationMode(.head)
                                Spacer()
                                Toggle("Read-only", isOn: Binding(
                                    get: { folder.readOnly },
                                    set: { readOnly in
                                        if let index = binding.wrappedValue.extraFolders.firstIndex(where: { $0.path == folder.path }) {
                                            binding.wrappedValue.extraFolders[index].readOnly = readOnly
                                        }
                                    }))
                                    .toggleStyle(.checkbox)
                                Button("Remove", systemImage: "minus.circle") {
                                    binding.wrappedValue.extraFolders.removeAll { $0.path == folder.path }
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                            }
                        }
                        Button("Add Folder...") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Add"
                            guard panel.runModal() == .OK, let url = panel.url,
                                  !binding.wrappedValue.extraFolders.contains(where: { $0.path == url.path }) else { return }
                            binding.wrappedValue.extraFolders.append(Project.ExtraFolder(path: url.path))
                        }
                    } header: {
                        Text("Extra folders")
                    } footer: {
                        Text("Mounted besides the project folder at the same path, read-only unless you switch it. Each is checked like a project folder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let configProblem {
                    Label(configProblem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if let error {
                    Label(error, systemImage: "xmark.octagon").foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.map { !ProjectList.isValidSandboxName($0.name) } ?? true)
            }
            .padding(12)
        }
        .frame(width: 560, height: 640)
        .task {
            model.loadFiles()
            await model.loadInstalledModels()
        }
        // The kits offered and preselected depend on the agent.
        .onChange(of: draft?.agent) { draft?.agentChanged(app: model.appConfig) }
    }

    /// The `[providers]` sections, then every model in llmman's store that no section names.
    private var providerChoices: [String] {
        let sections = model.appConfig.providers
        let named = Set(sections.values.compactMap { if case .local(let model) = $0 { model } else { nil } })
        let installed = (model.installedModels ?? []).filter { !named.contains($0) }.sorted()
        var choices = sections.keys.sorted() + installed.map { AppConfig.localProviderName(model: $0) }
        // A draft's provider (a default from paddock.yaml, say) stays selectable even when it is not installed.
        if let current = draft?.provider, !choices.contains(current) { choices.append(current) }
        return choices
    }

    private func providerLabel(_ name: String) -> String {
        guard let provider = model.appConfig.provider(named: name) else { return name }
        if model.appConfig.providers[name] == nil, case .local(let installed) = provider {
            return "\(installed) (local model)"
        }
        return "\(name) (\(provider.summary))"
    }

    private func hasEnvironmentFile(_ folder: String) -> Bool {
        FileManager.default.fileExists(atPath: folder + "/" + SbxEnvFile.fileName)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let taken = Set(model.allProjects.map(\.name))
        let (next, problem) = NewProject.draft(folder: url.path, app: model.appConfig, taken: taken)
        draft = next
        configProblem = problem.map { "sbxenv.yaml does not read; its name and agent were not used: \($0.description)" }
        error = nil
    }

    private func create() {
        guard let draft else { return }
        do {
            try model.addProject(draft, writesFiles: writesFiles && !hasEnvironmentFile(draft.folder))
            created(draft.name)
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}
