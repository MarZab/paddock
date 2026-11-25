import PaddockCore
import SwiftUI

/// Agents Paddock left running (PAD-153; backlog doc UI, Agents left running): an agent whose tab
/// this app opened and no longer has (Paddock quit, or the tab closed) still runs in the sandbox
/// with no terminal. Each shows as a tab of its own and a sidebar row; opening it offers to take it
/// over (stop it, then a new agent tab that resumes its conversation) or to stop it, and closing
/// the tab stops it.
struct LeftAgentView: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let state: AgentState

    var body: some View {
        let name = SidebarAgents.name(state.agent)
        let working = AgentActivity(state.kind) == .working
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("\(name) is still running").font(.title2)
            Text("""
                Paddock opened this agent in a tab that is gone (the tab was closed, or Paddock quit). It still runs in the \
                sandbox, with no terminal: sbx cannot attach to it again. Take it over to go on with its conversation in a new tab.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(stateText(now: context.date)).monospacedDigit()
            }
            Text("Session \(state.session)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if working {
                Label("It is working now: taking over or stopping ends what it is doing.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Button("Take Over") { model.takeOverLeftAgent(state, of: project) }
                    .buttonStyle(.borderedProminent)
                    .help("Stops it, then opens a new agent tab that resumes its conversation (\(name) \(LeftAgents.resumeArguments(state).joined(separator: " ")))")
                Button("Stop") { model.stopLeftAgent(state, of: project) }
                    .help("Stops it; its conversation stays, and claude --resume in an agent tab can pick it up later")
            }
            .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stateText(now: Date) -> String {
        let time = SidebarAgents.elapsed(now.timeIntervalSince(state.time))
        switch AgentActivity(state.kind) {
        case .working: return "Working for \(time)"
        case .waiting: return "Waiting for you for \(time)"
        case .none: return "Idle for \(time)"
        }
    }
}

extension ProjectTerminals {
    /// The agents this app left running in the sandbox, except the ones being stopped.
    var leftAgents: [AgentState] {
        let open = Set((tabs.tabs + rightTabs.tabs).map(\.id))
        return LeftAgents.find(states: agents, openTabs: open, opened: opened, project: sandbox)
            .filter { !leftStopping.contains($0.session) }
    }

    /// One half's tabs for them, in the order `leftAgents` gives.
    func leftAgentHostTabs(_ half: Half) -> [TerminalTabs.HostTab] {
        leftAgents.compactMap { state in
            let tab = LeftAgents.hostTab(state)
            guard self.half(of: tab) == half else { return nil }
            let name = SidebarAgents.name(state.agent)
            let activity: TerminalTabs.HostTab.Activity = switch AgentActivity(state.kind) {
            case .working: .busy
            case .waiting: .attention
            case .none: .none
            }
            return TerminalTabs.HostTab(
                id: tab, title: "\(name) (left running)", systemImage: "clock.arrow.circlepath",
                help: "\(name) still runs in the sandbox, with no terminal: open this tab to take it over or stop it; closing the tab stops it",
                style: .standard, closable: true, activity: activity, actions: [])
        }
    }

    /// Places a tab for each new left-running agent, and lets go of the ones that ended.
    func placeLeftAgents() {
        let now = Set(leftAgents.map(LeftAgents.hostTab))
        for tab in now.subtracting(leftPlaced).sorted() { place(tab) }
        for tab in leftPlaced.subtracting(now) {
            deselect(tab)
            hostHalves[tab] = nil
        }
        leftPlaced = now
        // A session that ended is no longer being stopped.
        let sessions = Set(agents.sessions.keys)
        leftStopping = leftStopping.filter { sessions.contains($0) }
    }

    /// Shows a host tab in its half (a left-running agent's, from the sidebar).
    func showHostTab(_ tab: String) {
        var bar = tabs(half(of: tab))
        bar.selectHost(tab)
        setTabs(bar, half(of: tab))
    }

    /// Hides a left-running agent's tab while it is being stopped, or shows it again when that failed.
    func setStopping(_ session: String, _ stopping: Bool) {
        if stopping { leftStopping.insert(session) } else { leftStopping.remove(session) }
        placeLeftAgents()
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

/// Every agent in every running sandbox (System > Processes, PAD-153): where it is, what it does,
/// and Stop or Take Over for the ones this Paddock opened.
struct AgentSessionsTable: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<String> = []
    @State private var toStop: [AgentSessionRow] = []

    var body: some View {
        let rows = model.agentSessionRows()
        VStack(alignment: .leading, spacing: 0) {
            Text("Agents in sandboxes").font(.headline).padding(.horizontal, 12).padding(.vertical, 8)
            Table(rows, selection: $selection) {
                TableColumn("Project") { row in Text(row.project.name).lineLimit(1) }
                    .width(min: 100, ideal: 140)
                TableColumn("Agent") { row in Text(row.name) }
                    .width(70)
                TableColumn("State") { row in
                    Text(row.stateText)
                        .foregroundStyle(AgentActivity(row.state.kind) == .waiting ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                }
                .width(90)
                TableColumn("Where") { row in
                    Text(row.place.title)
                        .foregroundStyle(row.place == .leftRunning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                .width(min: 110, ideal: 150)
                TableColumn("For") { row in
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Text(SidebarAgents.elapsed(context.date.timeIntervalSince(row.state.time))).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .width(50)
                TableColumn("Session") { row in
                    Text(row.state.session).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        .help(row.state.session)
                }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                let chosen = rows.filter { ids.contains($0.id) }
                if chosen.count == 1, let row = chosen.first {
                    Button("Show") { model.show(row) }
                        .disabled(row.place == .otherApp || row.place == .outside)
                    if row.place == .leftRunning {
                        Button("Take Over") { model.takeOverLeftAgent(row.state, of: row.project) }
                    }
                }
                let stoppable = chosen.filter(\.isStoppable)
                Button(stoppable.count > 1 ? "Stop \(stoppable.count)..." : "Stop...") { toStop = stoppable }
                    .disabled(stoppable.isEmpty)
            }
            .overlay {
                if rows.isEmpty { ContentUnavailableView("No agents in running sandboxes", systemImage: "person.crop.circle.badge.questionmark") }
            }
            Text("Only agents this Paddock opened can be stopped here; one in another Paddock's tab or started outside Paddock is left alone.")
                .font(.caption).foregroundStyle(.secondary).padding(8)
        }
        .confirmationDialog("Stop \(toStop.count) agent\(toStop.count == 1 ? "" : "s")?",
                            isPresented: Binding(get: { !toStop.isEmpty }, set: { if !$0 { toStop = [] } })) {
            Button("Stop", role: .destructive) {
                let chosen = toStop
                toStop = []
                for row in chosen { model.stopLeftAgent(row.state, of: row.project) }
            }
        } message: {
            Text("What they are doing ends; their conversations stay, and claude --resume can pick them up:\n"
                 + toStop.map { "\($0.project.name): \($0.name), \($0.stateText.lowercased())" }.joined(separator: "\n"))
        }
    }
}

extension AgentSessionRow {
    /// Only an agent this Paddock opened, whose process the kit knows.
    var isStoppable: Bool { (place == .tab || place == .leftRunning) && state.pid != nil && state.tab != nil }
}

extension AppModel {
    /// Every agent session the running sandboxes report, by project, then oldest state first.
    func agentSessionRows() -> [AgentSessionRow] {
        projects.projects.sorted { $0.name < $1.name }.flatMap { project -> [AgentSessionRow] in
            guard let terminals = terminals[project.name] else { return [] }
            let open = Set((terminals.tabs.tabs + terminals.rightTabs.tabs).map(\.id))
            return terminals.agents.sessions.values
                .filter { $0.kind != .ended && !terminals.leftStopping.contains($0.session) }
                .sorted { ($0.time, $0.session) < ($1.time, $1.session) }
                .map { AgentSessionRow(project: project, state: $0,
                                       place: LeftAgents.place(of: $0, openTabs: open, opened: openedTabs, project: project.name)) }
        }
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
        case .leftRunning:
            requestedSelection = .leftAgent(row.project.name, LeftAgents.hostTab(row.state))
        case .otherApp, .outside:
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
