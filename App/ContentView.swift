import PaddockCore
import SwiftUI

/// What the sidebar selects: the projects overview, one project, or a System pane.
enum SidebarSelection: Hashable {
    case overview
    case project(String)
    /// An agent's row under its project: selecting it shows the project with that tab (PAD-63).
    case agent(String, UUID)
    /// An agent Paddock left running: selecting it shows the project with its host tab (PAD-153).
    case leftAgent(String, String)
    case models
    case network
    case filesystem
    case processes
    case templates
    case log
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarSelection? = .overview
    @State private var blockingHost = false
    /// How each project group shows, by section id; every group starts open (PAD-145).
    @State private var folds: [String: ProjectGroups.Fold] = [:]

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $selection) {
                    let sections = ProjectGroups.sections(model.allProjects)
                    // No project has a group: the one Projects section, as before groups.
                    let ungrouped = sections.count == 1 && sections.first?.group == nil
                    ForEach(sections) { section in
                        let fold: ProjectGroups.Fold = ungrouped ? .open : folds[section.id, default: .open]
                        Section {
                            ForEach(fold.shown(section.projects, isRunning: isRunning)) { project in
                                projectRows(project)
                            }
                        } header: {
                            if ungrouped {
                                projectsHeader
                            } else {
                                GroupHeader(title: section.group ?? ProjectGroups.otherTitle, fold: fold,
                                            running: section.projects.count(where: isRunning),
                                            total: section.projects.count,
                                            problemCount: section.id == sections.first?.id ? problemCount : 0,
                                            toggle: { folds[section.id] = fold.next },
                                            showOverview: { selection = .overview })
                            }
                        }
                    }
                    Section {
                        Label("Models", systemImage: "cpu").tag(SidebarSelection.models)
                        NetworkSidebarLabel().tag(SidebarSelection.network)
                        Label("Filesystem", systemImage: "folder.badge.gearshape").tag(SidebarSelection.filesystem)
                        Label("Processes", systemImage: "list.bullet.rectangle").tag(SidebarSelection.processes)
                            .help("sbx's processes on this Mac, and the ones whose terminal is gone")
                        Label("Templates", systemImage: "shippingbox").tag(SidebarSelection.templates)
                            .help("sbx's images, what uses them, and removing them")
                        LogSidebarLabel().tag(SidebarSelection.log)
                    } header: {
                        // A line keeps System apart from the projects' groups (PAD-145).
                        VStack(alignment: .leading, spacing: 8) {
                            Divider()
                            Text("System")
                        }
                        .padding(.top, 8)
                    }
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
                // Below the list, not in the sidebar's title bar: next to the window controls and
                // the sidebar toggle there, even one item overflows into a >> menu.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack(spacing: 8) {
                        StatusButton()
                        VersionLabel()
                        if let source = model.status?.sbxReadSource, !source.isSocket {
                            Image(systemName: "tortoise")
                                .foregroundStyle(.secondary)
                                .help("Reading sbx through its CLI, which is slower; the status checks say why")
                        }
                        Spacer()
                        Button("New Project", systemImage: "plus") { model.showsNewProject = true }
                            .labelStyle(.iconOnly)
                            .help("New Project")
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            } detail: {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The breadcrumb is the title; the plain title text is hidden.
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Breadcrumb(items: breadcrumb)
                                .padding(.leading, 8)
                        }
                        .withoutSharedBackground()
                        // In the detail's title bar, not the sidebar's: two items there overflow into a » menu.
                        // Not on a project's page, whose title bar holds its own actions.
                        if !isProjectPage {
                            TrailingEdge()
                            if selection == .network {
                                ToolbarItem(placement: .automatic) {
                                    Button("Block a Host", systemImage: "plus") { blockingHost = true }
                                        .help("Block a host for every sandbox or for one")
                                        .popover(isPresented: $blockingHost, arrowEdge: .bottom) {
                                            // Running sandboxes only: a sandbox deny needs the sandbox.
                                            let names = Set(model.networkRows(for: nil).compactMap(\.sandbox))
                                                .filter { model.state(ofSandbox: $0) != nil }.sorted()
                                            BlockHostPopover(model: model, sandboxes: names, scope: model.networkSandbox) {
                                                blockingHost = false
                                            }
                                        }
                                }
                            }
                            ToolbarItem(placement: .automatic) {
                                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.reloadAll() } }
                                    .help("Read the project files and sbx's sandboxes again")
                                    .disabled(model.isRefreshing)
                            }
                        }
                    }
                    .toolbar(removing: .title)
            }
        }
        .onChange(of: selection, initial: true) { _, selected in
            model.logIsShown = selected == .log
            switch selected {
            case .agent(let name, let tab)?:
                model.shownProject = name
                model.showAgentTab(tab, of: name)
            case .leftAgent(let name, let tab)?:
                model.shownProject = name
                model.terminals[name]?.showHostTab(tab)
            case .project(let name)?:
                model.shownProject = name
            default:
                model.shownProject = nil
            }
        }
        // The sidebar follows the tab bar: a tab with an agent row highlights that row, any other
        // tab (Info, a shell without an agent, a browser tab) the project.
        .onChange(of: model.shownTab) { _, tab in
            guard let name = model.shownProject, let project = model.project(named: name) else { return }
            let hasRow = tab.map { tab in model.agentRows(of: project, now: Date()).contains { $0.tab == tab } } ?? false
            let wanted: SidebarSelection = if let tab, hasRow { .agent(name, tab) } else { .project(name) }
            if selection != wanted { selection = wanted }
        }
        .onChange(of: model.requestedSelection) { _, requested in
            guard let requested else { return }
            selection = requested
            model.requestedSelection = nil
        }
        .sheet(item: $model.confirmation) { confirmation in
            ConfigConfirmSheet(confirmation: confirmation)
        }
        .sheet(isPresented: $model.showsNewProject) {
            NewProjectSheet { name in selection = .project(name) }
        }
    }

    private func isRunning(_ project: Project) -> Bool { model.state(of: project) == .running }

    /// A project's row and, under it, its agents, each with its own state, in tab order (PAD-63).
    @ViewBuilder private func projectRows(_ project: Project) -> some View {
        ProjectRow(project: project, badge: model.badge(of: project), help: model.badgeHelp(of: project))
            .tag(SidebarSelection.project(project.name))
        let now = Date()
        ForEach(model.agentRows(of: project, now: now)) { row in
            if let tab = row.tab {
                AgentRow(row: row, now: now).tag(SidebarSelection.agent(project.name, tab))
            } else if let hostTab = row.hostTab {
                AgentRow(row: row, now: now).tag(SidebarSelection.leftAgent(project.name, hostTab))
            } else {
                // In no open tab: nothing to show, so not selectable (no tag).
                AgentRow(row: row, now: now)
            }
        }
    }

    /// The heading while no project has a group: it opens the projects overview, like the breadcrumb.
    private var projectsHeader: some View {
        Button { selection = .overview } label: {
            HStack(spacing: 4) {
                Text("Projects")
                if problemCount > 0 {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .help("\(problemCount) problem(s); open Projects to see them")
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private var isProjectPage: Bool {
        switch selection {
        case .project?, .agent?, .leftAgent?: true
        default: false
        }
    }

    private var problemCount: Int { model.projectProblems.count + model.configProblems.count }

    /// Projects › name, or the System pane's name. Earlier items are clickable.
    private var breadcrumb: [Breadcrumb.Item] {
        let projects = Breadcrumb.Item(title: "Projects") { selection = .overview }
        switch selection {
        case .project(let name), .agent(let name, _), .leftAgent(let name, _): return [projects, Breadcrumb.Item(title: name, action: nil)]
        case .models: return system("Models")
        case .network: return system("Network")
        case .filesystem: return system("Filesystem")
        case .processes: return system("Processes")
        case .templates: return system("Templates")
        case .log: return system("Log")
        case .overview, nil: return [Breadcrumb.Item(title: "Projects", action: nil)]
        }
    }

    private func system(_ page: String) -> [Breadcrumb.Item] {
        [Breadcrumb.Item(title: "System", action: nil), Breadcrumb.Item(title: page, action: nil)]
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .project(let name), .agent(let name, _), .leftAgent(let name, _):
            if let project = model.project(named: name) {
                ProjectDetailView(project: project)
            } else {
                ContentUnavailableView("Project not found", systemImage: "folder.badge.questionmark")
            }
        case .models:
            ModelsView(health: model.status?.llmman)
        case .network:
            NetworkRulesPage()
        case .filesystem:
            FilesystemPage()
        case .processes:
            SbxProcessesView()
        case .templates:
            TemplatesView()
        case .log:
            ErrorLogView()
        case .overview, nil:
            ProjectsOverview { selection = .project($0) }
        }
    }
}

/// The Models pane (backlog doc UI): llmman's own web UI, which loads only while every hardening
/// check is green. The checks themselves are behind the status button.
struct ModelsView: View {
    let health: LlmmanHealth?

    var body: some View {
        if let health {
            if health.allowsLocalModels {
                LlmmanWebView()
            } else {
                ContentUnavailableView {
                    Label("llmman's UI is off", systemImage: "lock.shield")
                } description: {
                    Text(health.checks.filter { $0.status == .red }.map(\.detail).joined(separator: "\n"))
                }
            }
        } else {
            ProgressView("Checking llmman")
        }
    }
}

extension LlmmanHealth.Kind {
    var title: String {
        switch self {
        case .reachable: "llmman answers"
        case .shellOff: "Web shell off"
        case .loopbackOnly: "Loopback only"
        case .expectedPort: "Port denied to sandboxes"
        case .promptHistory: "Prompt history"
        }
    }
}

/// The window title as a path. Items with an action are links; the last item is where you are.
struct Breadcrumb: View {
    struct Item {
        let title: String
        let action: (() -> Void)?
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                // The same Text either way, so the title does not shift when an item turns into a
                // link (the link button style lays text out differently).
                if let action = item.action {
                    Step(title: item.title, action: action)
                } else {
                    Text(item.title).foregroundStyle(index == items.count - 1 ? .primary : .secondary)
                        .lineLimit(1)
                }
            }
        }
        .font(.headline)
    }

    /// An earlier step of the path: gray like the rest of the path, not the accent color, and
    /// darker under the pointer, which turns into a hand.
    private struct Step: View {
        let title: String
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Text(title).lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(hovering ? .primary : .secondary)
            .onHover { hovering = $0 }
            .pointerStyle(.link)
        }
    }
}

/// Pushes the toolbar items after it to the window's right edge (macOS 26's flexible toolbar
/// spacer; earlier systems place them as they do).
struct TrailingEdge: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible)
        }
    }
}

extension ToolbarContent {
    /// macOS 26 draws a glass background behind toolbar items; the breadcrumb is a title, not a control.
    @ToolbarContentBuilder
    func withoutSharedBackground() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// A project group's heading (PAD-145): clicking its title goes from open (every project) to
/// folded (the running ones) to closed (no rows) and back. On the right, in every fold: running of all its
/// projects, running in green.
/// The projects overview is in its context menu, and behind the problems mark of the first group.
private struct GroupHeader: View {
    let title: String
    let fold: ProjectGroups.Fold
    let running: Int
    let total: Int
    let problemCount: Int
    let toggle: () -> Void
    let showOverview: () -> Void
    /// How much further in from the header's trailing edge a row's badge sits.
    private static let badgeInset: CGFloat = 16

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                Text(title).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            if problemCount > 0 {
                Button(action: showOverview) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("\(problemCount) problem(s); open Projects to see them")
            }
            // Small and regular, where a row's badge sits (the Network item's count): a header
            // takes no `.badge`, so its font and distance from the edge are set by hand.
            // Running (green, like a running project's mark; muted when none) out of all its projects.
            Text("\(Text("\(running)").foregroundStyle(running > 0 ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary)))/\(total)")
                .font(.caption).fontWeight(.regular).monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.trailing, Self.badgeInset)
                .help("\(running) of \(total) running")
        }
        .padding(.top, 8)
        .contextMenu {
            Button("Show All Projects", action: showOverview)
        }
    }

    private var help: String {
        switch fold {
        case .open: "Click to show only the running projects"
        case .running: "Only the running projects show; click to close the group"
        case .closed: "Click to show every project of the group"
        }
    }
}

/// The sidebar's Network item, with the number of denies Paddock suggests (none when zero; PAD-123).
/// A view of its own, so only this label follows the rules, not the whole window.
private struct NetworkSidebarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let suggested = model.suggestedDenyCount
        Label("Network", systemImage: "network")
            .badge(suggested)
            .help(suggested == 0 ? "Every network rule, with what sandboxes connected to"
                : "Every network rule, with what sandboxes connected to; Paddock suggests \(suggested) to deny")
    }
}

/// The sidebar's Log item, with a red dot while an error came since the Log was last shown (PAD-122).
private struct LogSidebarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let unseen = model.logHasUnseenErrors
        Label {
            HStack(spacing: 6) {
                Text("Log")
                if unseen {
                    Circle().fill(.red).frame(width: 7, height: 7)
                        .accessibilityLabel("New errors")
                }
            }
        } icon: {
            Image(systemName: "text.alignleft")
        }
        .help(unseen ? "An error came since the Log was last shown" : "Errors, sandbox setup and activity, and voice, by category")
    }
}
