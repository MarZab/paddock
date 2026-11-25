import PaddockCore
import PaddockShellCore
import SwiftUI

/// Agents Paddock left running (PAD-153; backlog doc UI, Agents left running): an agent whose tab
/// this app opened and no longer has (Paddock quit, or the tab closed) still runs in the sandbox
/// with no terminal, and so may one in another Paddock's tab. Info's Running Agents card lists them
/// with Take Over (stop it, then a new agent tab that resumes its conversation) and Stop; each has
/// a sidebar row that opens Info. No tab of their own.
extension ProjectTerminals {
    private var openTabIDs: Set<UUID> { Set((tabs.tabs + rightTabs.tabs).map(\.id)) }

    /// The agents this app left running in the sandbox, except the ones being stopped.
    var leftAgents: [AgentState] {
        LeftAgents.find(states: agents, openTabs: openTabIDs, opened: opened, project: sandbox)
            .filter { !leftStopping.contains($0.session) }
    }

    /// The agents in another Paddock's tabs (PAD-153.5), except the ones being stopped.
    var otherAgents: [AgentState] {
        LeftAgents.others(states: agents, openTabs: openTabIDs, opened: opened, project: sandbox)
            .filter { !leftStopping.contains($0.session) }
    }

    /// Every agent Info offers to take over: the ones left running, then other Paddocks'.
    var adriftAgents: [AgentState] { leftAgents + otherAgents }

    /// Where a session is (`LeftAgents.Place`).
    func place(of state: AgentState) -> LeftAgents.Place {
        LeftAgents.place(of: state, openTabs: openTabIDs, opened: opened, project: sandbox)
    }

    /// Shows Info, the left half's first tab.
    func showInfo() {
        var bar = tabs(.left)
        bar.selection = nil
        bar.selectHost(nil)
        setTabs(bar, .left)
    }

    /// Lets go of the sessions being stopped once they ended.
    func forgetStopped() {
        let sessions = Set(agents.sessions.keys)
        leftStopping = leftStopping.filter { sessions.contains($0) }
    }

    /// Hides a left-running agent's row while it is being stopped, or shows it again when that failed.
    func setStopping(_ session: String, _ stopping: Bool) {
        if stopping { leftStopping.insert(session) } else { leftStopping.remove(session) }
    }
}

/// One agent session in a running sandbox, for System > Processes (PAD-153).
struct AgentSessionRow: Identifiable {
    let project: Project
    let state: AgentState
    let place: LeftAgents.Place

    var id: String { project.name + "/" + state.session }
    var name: String { SidebarAgents.name(state.agent) }
    var stateText: String {
        switch AgentActivity(state.kind) {
        case .working: "Working"
        case .waiting: "Waits for you"
        case .none: "Idle"
        }
    }
}

/// Info's Running agents card (PAD-153.5): every agent session in the project's sandbox, what it
/// does, where it is (a tab, left running, another Paddock's tab, outside Paddock), and Show, Take
/// Over, and Stop where they apply.
struct ProjectAgentsCard: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var toStop: AgentSessionRow?
    /// A take-over that asks first: the agent works now, or another Paddock shows it.
    @State private var toTakeOver: AgentSessionRow?

    var body: some View {
        let rows = model.agentSessionRows(of: project)
        InfoCard("Running Agents", systemImage: "person.2") {
            if rows.isEmpty {
                Text(model.mayPoll(project) ? "No agent reports from the sandbox" : "Shown while the sandbox runs")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: CardMetrics.lineSpacing) {
                    ForEach(rows) { row in line(row) }
                }
            }
        }
        .confirmationDialog("Stop \(toStop?.name ?? "the agent")?", isPresented: Binding(get: { toStop != nil }, set: { if !$0 { toStop = nil } })) {
            Button("Stop", role: .destructive) {
                if let row = toStop { model.stopLeftAgent(row.state, of: row.project) }
                toStop = nil
            }
        } message: {
            Text(toStop?.place == .otherApp
                 ? "It runs in another Paddock's tab, which loses it. What it is doing ends; its conversation stays (claude --resume)."
                 : "What it is doing ends; its conversation stays, and claude --resume can pick it up.")
        }
        .confirmationDialog("Take over \(toTakeOver?.name ?? "the agent")?",
                            isPresented: Binding(get: { toTakeOver != nil }, set: { if !$0 { toTakeOver = nil } })) {
            Button("Take Over") {
                if let row = toTakeOver { model.takeOverLeftAgent(row.state, of: row.project) }
                toTakeOver = nil
            }
        } message: {
            Text([toTakeOver.map { AgentActivity($0.state.kind) == .none ? nil : "It is \($0.stateText.lowercased()) now: that ends." } ?? nil,
                  toTakeOver?.place == .otherApp ? "It runs in another Paddock's tab, which loses it." : nil,
                  "Paddock stops it, then opens an agent tab that goes on with its conversation."]
                .compactMap { $0 }.joined(separator: " "))
        }
    }

    private func line(_ row: AgentSessionRow) -> some View {
        HStack(spacing: 8) {
            AgentMarkView(mark: SidebarAgents.mark(row.state))
            Text(row.name)
            Text(row.stateText).foregroundStyle(AgentActivity(row.state.kind) == .waiting ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(SidebarAgents.elapsed(context.date.timeIntervalSince(row.state.time))).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(row.place.title)
                .foregroundStyle(row.place == .leftRunning || row.place == .otherApp ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            Spacer(minLength: 4)
            Group {
                if row.place == .tab {
                    Button("Show", systemImage: "arrow.up.forward.square") { model.show(row) }
                        .help("Show its tab")
                }
                if row.place == .leftRunning || row.place == .otherApp {
                    Button("Take Over", systemImage: "arrow.triangle.2.circlepath") {
                        if AgentActivity(row.state.kind) == .none && row.place == .leftRunning {
                            model.takeOverLeftAgent(row.state, of: row.project)
                        } else {
                            toTakeOver = row
                        }
                    }
                    .help("Stop it, then go on with its conversation in a new agent tab (\(row.name) \(LeftAgents.resumeArguments(row.state).joined(separator: " ")))")
                }
                if row.isStoppable {
                    Button("Stop", systemImage: "stop.circle") { toStop = row }
                        .help("Stop it in the sandbox")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .help("Session \(row.state.session)")
    }
}

/// Info's Processes card (PAD-153.5): the sandbox's processes by app, as its Processes tab shows
/// them, with Stop on a process.
struct ProjectProcessesCard: View {
    @Environment(AppModel.self) private var model
    let project: Project

    var body: some View {
        InfoCard("Processes", systemImage: "cpu") {
            SandboxProcessesTab(project: project, showsHeader: false)
                .frame(height: 260)
        } actions: {
            Button("Open in a Tab", systemImage: "arrow.up.forward.square") { model.openProcesses(of: project) }
                .disabled(!model.mayPoll(project))
                .help("What runs in the sandbox, by app, in a tab of its own")
        }
    }
}

extension AgentSessionRow {
    /// An agent in a Paddock tab (this one's or another's) whose process the kit knows; never one
    /// started outside Paddock.
    var isStoppable: Bool { place != .outside && state.pid != nil && state.tab != nil }
}

extension AppModel {
    /// Every agent session the project's sandbox reports, oldest state first.
    func agentSessionRows(of project: Project) -> [AgentSessionRow] {
        guard let terminals = terminals[project.name] else { return [] }
        return terminals.agents.sessions.values
            .filter { $0.kind != .ended && !terminals.leftStopping.contains($0.session) }
            .sorted { ($0.time, $0.session) < ($1.time, $1.session) }
            .map { AgentSessionRow(project: project, state: $0, place: terminals.place(of: $0)) }
    }

    /// Stops a process the operator picked in the sandbox's Processes tab (checked by pid and name).
    func stopSandboxProcess(pid: Int32, name: String, of project: Project) {
        Task {
            do {
                try await runner().stopSandboxProcess(pid: pid, name: name, of: project)
                appendLog("Stopped \(name) (\(pid)) in \(project.name)", source: project.name)
            } catch {
                fail("Could not stop \(name) (\(pid)) in \(project.name): \(String(describing: error))", in: project.name)
            }
        }
    }

    /// The agents running in this Paddock's tabs, per project, for the question before quitting:
    /// every agent tab whose session has not exited, and every shell tab an agent reports from.
    func runningAgents() -> [QuitWarning.Running] {
        terminals.compactMap { name, terminals in
            var agents = 0
            var busy = 0
            for tab in terminals.tabs.tabs + terminals.rightTabs.tabs where terminals.sessions[tab.id] != nil && terminals.exits[tab.id] == nil {
                let state = terminals.agents.state(ofTab: tab.id)
                guard tab.kind == .agent || (tab.kind == .shell && state.map { $0.kind != .ended } == true) else { continue }
                agents += 1
                if let state, AgentActivity(state.kind) != .none { busy += 1 }
            }
            return agents > 0 ? QuitWarning.Running(project: name, agents: agents, busy: busy) : nil
        }
    }

    /// Shows an agent's tab: its own, or its left-running one.
    func show(_ row: AgentSessionRow) {
        switch row.place {
        case .tab:
            if let tab = row.state.tab { requestedSelection = .agent(row.project.name, tab) }
        case .leftRunning, .otherApp, .outside:
            break
        }
    }

    /// Reads the tabs this app opened (`OpenedTabs`, one file per app), without projects that are
    /// gone and tabs too old to matter.
    func loadOpenedTabs() {
        guard let path = openedTabsPath else { return }
        var tabs = OpenedTabs.load(from: path)
        tabs.keepOnly(projects: Set(projects.projects.map(\.name)))
        for name in tabs.projects.keys { tabs.prune(project: name, reported: [], now: Date()) }
        openedTabs = tabs
        saveOpenedTabs()
    }

    private var openedTabsPath: String? {
        OpenedTabs.path(in: paths, bundleID: Bundle.main.bundleIdentifier ?? "net.zabreznik.paddock")
    }

    func recordOpenedTab(_ tab: UUID, in project: String) {
        openedTabs.add(tab, in: project, at: Date())
        terminals[project]?.opened = openedTabs
        saveOpenedTabs()
    }

    private func saveOpenedTabs() {
        guard let path = openedTabsPath else { return }
        do {
            try openedTabs.save(to: path)
        } catch {
            appendLog("Could not keep the tabs Paddock opened in \(path): \(error.localizedDescription)", isError: true)
        }
    }

    /// Stops an agent Paddock left running; its tab goes at once and comes back if that failed.
    func stopLeftAgent(_ state: AgentState, of project: Project) {
        terminals[project.name]?.setStopping(state.session, true)
        Task {
            do {
                try await runner().stopLeftAgent(state, of: project)
            } catch {
                terminals[project.name]?.setStopping(state.session, false)
                fail("Could not stop \(SidebarAgents.name(state.agent)) in \(project.name): \(String(describing: error))", in: project.name)
            }
        }
    }

    /// Takes a left-running agent over: stops it (so two agents never write one conversation), then
    /// opens an agent tab that resumes its conversation (`LeftAgents.resumeArguments`).
    func takeOverLeftAgent(_ state: AgentState, of project: Project) {
        guard let terminals = openTerminals(for: project) else { return }
        terminals.setStopping(state.session, true)
        Task {
            do {
                try await runner().stopLeftAgent(state, of: project)
                terminals.open(.agent, agentArguments: LeftAgents.resumeArguments(state))
            } catch {
                terminals.setStopping(state.session, false)
                fail("Could not take over \(SidebarAgents.name(state.agent)) in \(project.name): \(String(describing: error))", in: project.name)
            }
        }
    }
}
