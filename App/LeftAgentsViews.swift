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

extension AppModel {
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
