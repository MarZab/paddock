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
                                            badge: model.badge(of: project), help: model.badgeHelp(of: project),
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
    /// The mark in words (state and approval requests), as the sidebar row's tooltip says it.
    let help: String
    let provider: AppConfig.Provider?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(project.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                // The state stays short beside the name; the tooltip adds the approval requests.
                HStack(spacing: 6) {
                    ProjectBadgeView(badge: badge, help: help)
                    Text(SandboxStateText.describe(state)).font(.callout).foregroundStyle(.secondary)
                }
                .help(help)
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
    /// Recreate waiting for the operator's confirmation.
    @State private var confirmsRecreate = false

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
            info
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
        .confirmationDialog("Recreate \(project.name)'s sandbox?", isPresented: $confirmsRecreate) {
            Button("Recreate", role: .destructive) { model.recreateSandbox(project) }
        } message: {
            Text("The sandbox is removed and created again with what the project names now: its folders, kits, and settings. "
                 + "Its terminals close, and everything inside it that is not in the project folder or an extra folder is lost"
                 + (project.keepsClaudeSessions ? ", except Claude's kept sessions." : ", Claude's sessions too."))
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
            .help(model.activity(of: project) ?? model.badgeHelp(of: project))
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
                // Always there with a sandbox, not only when Sync finds a difference.
                if state != nil {
                    Button("Recreate", systemImage: "arrow.triangle.2.circlepath") { confirmsRecreate = true }
                        .disabled(model.appConfig.agents[project.agent] == nil)
                        .help(model.appConfig.agents[project.agent] == nil
                              ? "Paddock cannot create this sandbox: its agent is not a paddock.yaml agent entry"
                              : "Remove the sandbox and create it again with what the project names now")
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
            .menuIndicator(steps.count > 1 || offersRecreate ? .visible : .hidden)
            .contextMenu { teardownItems(steps) }
            .help(steps.count > 1 ? "\(main.title); the arrow or a right click offers \(steps.dropFirst().map(\.title).joined(separator: " and "))"
                                  : main.title)
        }
    }

    @ViewBuilder
    private func teardownItems(_ steps: [AppModel.Teardown]) -> some View {
        ForEach(steps.filter { $0 == .stop }) { step in
            Button(step.title, systemImage: step.systemImage) { request(step) }
        }
        // Recreate here too (PAD-132), between stopping and removing.
        if offersRecreate {
            Button("Recreate...", systemImage: "arrow.triangle.2.circlepath") { confirmsRecreate = true }
                .disabled(model.appConfig.agents[project.agent] == nil)
            Divider()
        }
        ForEach(steps.filter { $0 != .stop }) { step in
            Button(step.title, systemImage: step.systemImage, role: .destructive) { request(step) }
        }
    }

    /// A sandbox exists, so it can be recreated.
    private var offersRecreate: Bool { model.state(of: project) != nil }

    /// The Info tab, one page of cards in two columns (backlog doc UI, Project Info): a third on
    /// the left: Agent, Status (with the sandbox's resources), Network, Ports; two thirds
    /// on the right: the notices, only when there is one (attention, Paddock's suggestions, sbx's
    /// approval requests), Folders, Kits, Recent Activity. In a narrow window the narrow column
    /// comes first.
    /// Hosts are allowed and denied on the Network page.
    private var info: some View {
        let network = model.networkRows(for: project.name)
        return ScrollView {
            InfoColumns {
                // The notices first (only when there is one), then the wide cards.
                VStack(alignment: .leading, spacing: 12) {
                    AttentionSections(project: project)
                    serviceDenyRow
                    approvalRows
                    ProjectFoldersCard(project: project)
                    if model.appConfig.agents[project.agent] != nil {
                        ProjectKitsCard(project: project)
                    }
                    RecentActivity(entries: model.timeline[project.name])
                }
                VStack(alignment: .leading, spacing: 12) {
                    ProjectAgentCard(project: project)
                    ProjectStatusCard(project: project)
                    networkCard(network)
                    ProjectPortsSections(project: project)
                }
            }
            .padding(16)
        }
    }

    /// The sandbox's rules and activity live on the Network page; here, counts and the way there.
    private func networkCard(_ rules: [RuleRow]) -> some View {
        let blocked = rules.filter { ($0.activity?.blocked ?? 0) > 0 }.count
        let suggested = rules.filter(\.isSuggestion).count
        return InfoCard("Network", systemImage: "network") {
            HStack(spacing: 6) {
                Text("\(rules.count) rules")
                if blocked > 0 {
                    Text("· \(blocked) blocked").foregroundStyle(.orange)
                        .help("Rules or hosts with blocked connections")
                }
                if suggested > 0 {
                    Text("· \(suggested) suggested").foregroundStyle(.yellow)
                }
            }
        } actions: {
            Button("Open in Network", systemImage: "arrow.right.circle") { model.showNetwork(for: project.name) }
                .help("The rules for this sandbox, with what it connected to, on the Network page")
        }
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
            InfoCard("Recent Activity", systemImage: "clock") {
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
            } actions: {
                if entries.count > Self.shortList {
                    Button(showsAll ? "Show Less" : "Show All \(entries.count)") { showsAll.toggle() }
                        .buttonStyle(.link)
                }
            }
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

/// The project's folders as a table (PAD-124), in Info and New Project alike: in Info first the
/// project folder (always writable; Show in Finder and Config), then one row per extra folder (its
/// path, a mark when it is another project's folder, Read-only, Show in Finder, Remove), and a last
/// row with the field to add one (`ExtraFolderField`), shown and hidden by the header's plus
/// button. A folder inside ~/Library/Logs stays read-only.
struct FoldersTable: View {
    @Environment(AppModel.self) private var model
    let folders: [Project.ExtraFolder]
    /// The project's folder; nil until New Project has one.
    let projectFolder: String?
    /// The project's name: its own folder is no other project's; nil in New Project.
    var sandbox: String?
    var showsInFinder = false
    /// The project folder as the first row (Info; New Project chooses it above the table).
    var showsProjectFolder = false
    /// Config in the project folder's row: edit its sbxenv.yaml.
    var editConfig: (() -> Void)?
    let setReadOnly: (String, Bool) -> Void
    let remove: (String) -> Void
    let add: (String) -> Void
    @State private var adding = false

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 0) {
            GridRow {
                Text("Folder")
                Text("Read-only").gridColumnAlignment(.center)
                Button(adding ? "Close" : "Add Folder", systemImage: adding ? "xmark.circle" : "plus.circle") { adding.toggle() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help(adding ? "Hide the field to add a folder" : "Add a folder: paste or type its path, choose it, or drop it")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
            Divider()
            if showsProjectFolder, let projectFolder {
                projectRow(projectFolder)
                Divider()
            } else if folders.isEmpty && !adding {
                GridRow {
                    Text("None").foregroundStyle(.secondary).gridCellColumns(3)
                }
                .padding(.vertical, 4)
            }
            ForEach(folders, id: \.path) { folder in
                row(folder)
                Divider()
            }
            if adding {
                GridRow {
                    ExtraFolderField(projectFolder: projectFolder, extraFolders: folders.map(\.path), sandbox: sandbox,
                                     otherProject: otherProject, add: add)
                        .gridCellColumns(3)
                }
                .padding(.top, 6)
            }
        }
    }

    /// The project folder: mounted writable, never removed here.
    private func projectRow(_ folder: String) -> some View {
        GridRow(alignment: .center) {
            HStack(spacing: 6) {
                Text((folder as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(folder)
                Text("project").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("Read-only", isOn: .constant(false))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(true)
                .help("The project folder is always writable: the agent works in it")
            HStack(spacing: 6) {
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
                }
                .help("Show the project folder in Finder")
                if let editConfig {
                    Button("Config", systemImage: "doc.text", action: editConfig)
                        .help("Edit sbxenv.yaml in the project folder; Paddock writes one, with a kit for the project, when there is none")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func row(_ folder: Project.ExtraFolder) -> some View {
        let logs = model.folderPolicy.isInsideLogs(folder.path)
        return GridRow(alignment: .center) {
            HStack(spacing: 4) {
                Text((folder.path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(folder.path)
                if let other = otherProject(folder.path) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .help("This is project \(other)'s folder: writable, this agent could change that project's files")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("Read-only", isOn: Binding(get: { folder.readOnly || logs }, set: { setReadOnly(folder.path, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(logs)
                .help(logs ? "Inside ~/Library/Logs: always read-only" : "Off: the agent can change this folder's files too")
            HStack(spacing: 6) {
                if showsInFinder {
                    Button("Show in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)])
                    }
                    .help("Show in Finder")
                }
                Button("Remove", systemImage: "minus.circle") { remove(folder.path) }
                    .help("Stop mounting this folder (at the sandbox's next create)")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func otherProject(_ path: String) -> String? {
        ExtraFolders.otherProject(path, in: model.allProjects, except: sandbox ?? "")
    }
}

/// Where an extra folder is added (PAD-124), in Info and New Project alike: paste or type a path
/// (`ExtraFolders.path(fromInput:)`), checked as it is typed with the checks it gets when added
/// (`ExtraFolders.check`), Return or Add adds it; Choose... opens the Open panel at the nearest
/// folder of what was typed; folders dropped from Finder are added, each checked. `add` gets the
/// checked path; it checks again (backlog doc Security rules).
struct ExtraFolderField: View {
    @Environment(AppModel.self) private var model
    /// The project's folder; nil until New Project has one.
    let projectFolder: String?
    let extraFolders: [String]
    /// For the Open panel's message.
    var sandbox: String?
    /// The project whose folder this is, if another's (a warning, not a refusal).
    var otherProject: (String) -> String? = { _ in nil }
    let add: (String) -> Void
    @State private var text = ""
    @State private var dropTargeted = false

    /// What was typed, as a checked path or why not.
    private enum Verdict {
        case empty
        case ok(String)
        case problem(String)
    }

    private var verdict: Verdict { verdict(for: text) }

    private func verdict(for input: String) -> Verdict {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        guard let path = ExtraFolders.path(fromInput: input, home: NSHomeDirectory()) else {
            return .problem("Not a full path: start with / or ~/")
        }
        guard let projectFolder else { return .problem("Choose the project folder first") }
        let policy = model.folderPolicy
        do throws(ExtraFolderProblem) {
            return .ok(try ExtraFolders.check(path, projectFolder: projectFolder, extraFolders: extraFolders, policy: policy))
        } catch {
            return .problem(error.description.prefix(1).uppercased() + error.description.dropFirst())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                TextField("Extra folder", text: $text, prompt: Text("Paste or type a folder path, or drop a folder here"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .onSubmit(addTyped)
                Button("Add", action: addTyped)
                    .disabled({ if case .ok = verdict { false } else { true } }())
                    .help("Mount this folder in the sandbox, read-only unless you switch it (at its next create)")
                Button("Choose...", action: choose)
                    .help("Pick the folder in the Open panel")
            }
            switch verdict {
            case .empty:
                EmptyView()
            case .ok(let path):
                if model.folderPolicy.isInsideLogs(path) {
                    Label("Inside ~/Library/Logs: mounted read-only, and it may hold other apps' logs", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if let other = otherProject(path) {
                    Label("This is project \(other)'s folder; writable, this agent could change its files", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Label((path as NSString).abbreviatingWithTildeInPath, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            case .problem(let problem):
                Label(problem, systemImage: "xmark.circle").foregroundStyle(.red)
            }
        }
        .font(.callout)
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: dropTargeted ? 2 : 0))
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter(\.isFileURL)
            for url in folders { addChecked(url.path) }
            return !folders.isEmpty
        } isTargeted: { dropTargeted = $0 }
    }

    private func addTyped() {
        guard case .ok(let path) = verdict else { return }
        add(path)
        text = ""
    }

    /// A dropped or chosen folder: added when it passes, else shown in the field with why not.
    private func addChecked(_ path: String) {
        if case .ok(let checked) = verdict(for: path) {
            add(checked)
        } else {
            text = path
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = sandbox.map { "A folder to mount in \($0)'s sandbox, read-only" } ?? "A folder to mount in the sandbox, read-only"
        // Start at what was typed, or the nearest folder above it that exists.
        if var start = ExtraFolders.path(fromInput: text, home: NSHomeDirectory()) {
            var isFolder: ObjCBool = false
            while start != "/", !(FileManager.default.fileExists(atPath: start, isDirectory: &isFolder) && isFolder.boolValue) {
                start = (start as NSString).deletingLastPathComponent
            }
            panel.directoryURL = URL(fileURLWithPath: start, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addChecked(url.path)
    }
}

/// Claude's sessions in Info's Agent card (PAD-127), on one line: Keep (on this Mac, across
/// recreates; it applies at the sandbox's next create), how many there are and their size, and
/// Show in Finder and Clear (confirmed) once there is a folder.
struct ClaudeSessionsLine: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var confirmsClear = false

    var body: some View {
        let summary = model.claudeSessionsSummary(of: project)
        HStack(spacing: 6) {
            Toggle("Keep", isOn: Binding(get: { project.keepsClaudeSessions },
                                         set: { model.setKeepsClaudeSessions($0, for: project) }))
                .toggleStyle(.checkbox)
                .help(project.keepsClaudeSessions
                      ? "Claude's sessions (claude --resume) are kept on this Mac and survive recreating the sandbox"
                      : "Keep Claude's sessions (claude --resume) on this Mac, so recreating the sandbox does not lose them")
            if let summary {
                Text("\(summary.sessions) · \(ByteCountFormatter.string(fromByteCount: summary.bytes, countStyle: .file))")
                    .foregroundStyle(.secondary)
                    .help("\(summary.sessions) session\(summary.sessions == 1 ? "" : "s") kept on this Mac")
                Group {
                    Button("Show in Finder", systemImage: "folder") { model.revealClaudeSessions(of: project) }
                        .help("Show the sessions folder in Finder")
                    Button("Clear Sessions...", systemImage: "trash") { confirmsClear = true }
                        .disabled(summary.sessions == 0 && summary.bytes == 0)
                        .help("Remove every kept session of this project")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        .confirmationDialog("Clear \(project.name)'s Claude sessions?", isPresented: $confirmsClear) {
            Button("Clear Sessions", role: .destructive) { model.clearClaudeSessions(of: project) }
        } message: {
            Text(model.state(of: project) == .running
                ? "Every kept session of this project is removed, the one the agent is in now too. This cannot be undone."
                : "Every kept session of this project is removed. This cannot be undone.")
        }
    }
}

/// Info's Status card: titled with the sandbox's state and what asks for the operator; its CPU,
/// memory, disk, and load while it runs (Processes in the card's actions); when it was created and
/// used, and the gateway (backlog doc UI, Project Info). Ports are in their own card.
struct ProjectStatusCard: View {
    @Environment(AppModel.self) private var model
    let project: Project

    var body: some View {
        let sandbox = model.sandboxes.first { $0.name == project.name }
        // The card's title is the state and what asks for the operator, as the tooltip says it.
        InfoCard {
            HStack(spacing: 6) {
                ProjectBadgeView(badge: model.badge(of: project), help: model.badgeHelp(of: project))
                let words = model.badgeHelp(of: project)
                Text(words.prefix(1).uppercased() + words.dropFirst()).lineLimit(2)
            }
        } content: {
            VStack(alignment: .leading, spacing: CardMetrics.lineSpacing) {
                SandboxResourcesMeters(project: project)
                CardFacts {
                    CardFact("Created") {
                        Text(sandbox?.createdAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "-")
                    }
                    CardFact("Last used") {
                        Text(sandbox?.lastUsedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "-")
                    }
                    if let port = project.gatewayPort {
                        CardFact("Gateway") {
                            Text(model.gatewayPorts[project.name] == nil ? "port \(port), not listening" : "port \(port)")
                        }
                    }
                    if project.cloneMode {
                        CardFact("Clone mode") { Text("the agent works on its own clone") }
                    }
                }
            }
            // One label column for the meters and the facts.
            .environment(\.cardLabelWidth, 72)
        } actions: {
            Button("Processes", systemImage: "cpu") { model.openProcesses(of: project) }
                .disabled(!model.mayPoll(project))
                .help("What runs in the sandbox, by app, in a tab of its own")
        }
    }
}

/// Info's Agent card: the agent and its model, the terminals' colors, and Claude's sessions.
struct ProjectAgentCard: View {
    @Environment(AppModel.self) private var model
    let project: Project

    var body: some View {
        InfoCard("Agent", systemImage: "sparkles") {
            CardFacts {
                CardFact("Agent") { Text(project.agent) }
                CardFact("Model") { Text(providerSummary).truncationMode(.middle) }
                CardFact("Terminal") { themePicker }
                if model.appConfig.agents[project.agent] == .claudeCode {
                    CardFact("Sessions") { ClaudeSessionsLine(project: project) }
                }
            }
        }
    }

    /// So this project's terminals look unlike other projects' (kept in its project file).
    private var themePicker: some View {
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

    private var providerSummary: String {
        model.appConfig.provider(named: project.provider)?.summary ?? "\(project.provider) (not defined)"
    }
}

/// Info's Folders card: one table of the project folder and the extra folders, with the field to
/// add one, Create for an sbxenv.yaml when there is none, and the way to the Filesystem page. A
/// change applies at the sandbox's next create.
struct ProjectFoldersCard: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var confirmsFiles = false

    var body: some View {
        let hasEnvironment = model.environment(of: project) != nil
        InfoCard("Folders", systemImage: "folder") {
            VStack(alignment: .leading, spacing: 8) {
                FoldersTable(folders: project.extraFolders, projectFolder: project.folder, sandbox: project.name,
                             showsInFinder: true, showsProjectFolder: true,
                             editConfig: { model.openProjectConfig(project) },
                             setReadOnly: { model.setExtraFolder($0, readOnly: $1, in: project) },
                             remove: { model.removeExtraFolder($0, from: project) },
                             add: { model.addExtraFolder($0, to: project) })
                if !hasEnvironment {
                    HStack(spacing: 6) {
                        Text("No sbxenv.yaml").foregroundStyle(.secondary)
                        Button("Create...") { confirmsFiles = true }
                            .buttonStyle(.link)
                            .help("Write sbxenv.yaml and a kit for this project into its folder, to run it with `sbx env run` too")
                    }
                }
            }
        } actions: {
            Button("Open in Filesystem", systemImage: "arrow.right.circle") { model.showFilesystem(for: project.name) }
                .help("The filesystem rules and mounts for this sandbox, on the Filesystem page")
        }
        .confirmationDialog("Create sbxenv.yaml for \(project.name)?", isPresented: $confirmsFiles) {
            Button("Create") { model.createSandboxFiles(for: project) }
        } message: {
            Text("Writes sbxenv.yaml, tools/sandbox/\(SandboxFiles.kitName(for: project.name)) and tools/sandbox/run.sh into the project folder. Existing files are never replaced.")
        }
    }
}

/// Info's Kits card: Paddock's kits for the sandbox (Edit Kits) and, with an sbxenv.yaml, the
/// project's own (Review): each is changed in its own place (backlog doc Kits).
struct ProjectKitsCard: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var editsKits = false

    var body: some View {
        let environment = model.environment(of: project)
        InfoCard("Kits", systemImage: "puzzlepiece.extension") {
            CardFacts {
                CardFact(environment == nil ? "Paddock" : "Paddock's") {
                    let kits = project.chosenKits(model.appConfig)
                    Text(kits.isEmpty ? "none" : kits.joined(separator: ", "))
                        .truncationMode(.tail)
                        .help(kits.joined(separator: ", "))
                }
                if let environment {
                    CardFact("Project's") {
                        let kits = environment.kits.map(\.source)
                        Text(kits.isEmpty ? "none" : kits.joined(separator: ", "))
                            .truncationMode(.tail)
                            .help("From sbxenv.yaml: " + (kits.isEmpty ? "none" : kits.joined(separator: ", ")))
                    }
                }
            }
        } actions: {
            if environment != nil {
                Button("Review", systemImage: "checklist") { model.confirmation = .init(project: project.name, then: .nothing) }
                    .help("Review sbxenv.yaml: its kits and hosts, and which hosts the agent may reach")
            }
            Button("Edit Kits", systemImage: "slider.horizontal.3") { editsKits = true }
                .help("Choose the sbx kits the sandbox is created with")
        }
        .sheet(isPresented: $editsKits) { KitsSheet(project: project) }
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
                    if model.appConfig.agents[binding.wrappedValue.agent] == .claudeCode {
                        Section {
                            Toggle("Keep Claude's sessions on this Mac", isOn: binding.keepsClaudeSessions)
                        } footer: {
                            Text("Sessions (claude --resume) go to a folder of this project in Paddock's data folder and survive recreating the sandbox. Clear them in the project's Info.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        FoldersTable(folders: binding.wrappedValue.extraFolders, projectFolder: binding.wrappedValue.folder,
                                     setReadOnly: { path, readOnly in
                                              if let index = binding.wrappedValue.extraFolders.firstIndex(where: { $0.path == path }) {
                                                  binding.wrappedValue.extraFolders[index].readOnly = readOnly
                                              }
                                          },
                                          remove: { path in binding.wrappedValue.extraFolders.removeAll { $0.path == path } },
                                          add: { path in binding.wrappedValue.extraFolders.append(Project.ExtraFolder(path: path)) })
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
