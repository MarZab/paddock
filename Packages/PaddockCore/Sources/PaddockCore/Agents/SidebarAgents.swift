import Foundation

/// One agent under its project in the sidebar (backlog doc UI, Sidebar agents; PAD-63, PAD-64): an
/// agent tab, a shell tab an agent runs in, or a session Paddock did not open. Display only.
public struct SidebarAgentRow: Sendable, Equatable, Identifiable {
    public enum Place: Sendable, Equatable {
        /// An agent tab (`sbx run`): always a row, whatever its agent reported.
        case agentTab
        /// A shell tab an agent was started in (the shell carries the tab's `PADDOCK_TAB`).
        case shellTab
        /// A session in no open tab: started outside Paddock, or its tab is gone. Nothing to open.
        case elsewhere
    }

    /// The tab's UUID, or `session:` and the session for a row without a tab.
    public let id: String
    /// The tab to open; nil for `elsewhere`.
    public let tab: UUID?
    /// What the row says: the title the tab's program set (as the tab bar shows it), else the tab's
    /// own name, or the agent's name for a session in no tab.
    public let title: String
    /// The tab's own name ("agent 2", "shell"), for the tooltip; nil without a tab.
    public let tabName: String?
    public let place: Place
    public let mark: AgentTabMark
    /// When the agent's current state began, when it reported one.
    public let since: Date?

    public init(id: String, tab: UUID?, title: String, tabName: String? = nil, place: Place, mark: AgentTabMark, since: Date?) {
        self.id = id
        self.tab = tab
        self.title = title
        self.tabName = tabName
        self.place = place
        self.mark = mark
        self.since = since
    }
}

public enum SidebarAgents {
    /// A session tab of the project, in the order its tab bars show them (left half first).
    public struct Tab: Sendable, Equatable {
        public let id: UUID
        /// The tab's own name ("agent 2").
        public let title: String
        /// The title its program set, as the tab bar shows it (sanitized there), when it set one.
        public let label: String?
        public let isAgent: Bool

        public init(id: UUID, title: String, label: String? = nil, isAgent: Bool) {
            self.id = id
            self.title = title
            self.label = label.flatMap { $0.isEmpty ? nil : $0 }
            self.isAgent = isAgent
        }
    }

    /// A session in no open tab that has been idle this long is not shown: one whose agent died
    /// without saying so would otherwise stay (the kit's watcher ends those it can tell are gone).
    public static let idleElsewhereShownFor: TimeInterval = 3600

    /// The project's rows, in a stable order: its tabs in tab-bar order (every agent tab; a shell
    /// tab only while an agent in it reports), then the sessions started outside Paddock by session
    /// (`isShownElsewhere`).
    public static func rows(tabs: [Tab], marks: (UUID) -> AgentTabMark, states: AgentStates, now: Date) -> [SidebarAgentRow] {
        var rows: [SidebarAgentRow] = []
        for tab in tabs {
            let state = states.state(ofTab: tab.id)
            if tab.isAgent {
                rows.append(SidebarAgentRow(id: tab.id.uuidString, tab: tab.id, title: tab.label ?? tab.title, tabName: tab.title,
                                            place: .agentTab, mark: marks(tab.id), since: state?.time))
            } else if let state {
                // The agent in a shell sets the shell's title too.
                rows.append(SidebarAgentRow(id: tab.id.uuidString, tab: tab.id, title: tab.label ?? "\(name(state.agent)) in \(tab.title)",
                                            tabName: tab.title, place: .shellTab, mark: marks(tab.id), since: state.time))
            }
        }
        let elsewhere = states.sessions.values
            .filter(isShownElsewhere)
            .filter { state in !(AgentActivity(state.kind) == .none && now.timeIntervalSince(state.time) > idleElsewhereShownFor) }
            .sorted { $0.session < $1.session }
        for state in elsewhere {
            let mark: AgentTabMark = switch AgentActivity(state.kind) {
            case .working: .working
            case .waiting: .waiting
            case .none: .none
            }
            rows.append(SidebarAgentRow(id: "session:" + state.session, tab: nil, title: name(state.agent), place: .elsewhere,
                                        mark: mark, since: state.time))
        }
        return rows
    }

    /// Whether a session in no open tab gets a row: only one started outside Paddock (no tab) whose
    /// process the kit knows, so the watcher ends it when the agent goes. A session that names a tab
    /// Paddock no longer has (closed, or from an earlier launch) is not shown: Paddock opened it and
    /// it is gone from Paddock. Nor is one from a kit without the process (before PAD-64), which
    /// would stay for a day after its agent died.
    static func isShownElsewhere(_ state: AgentState) -> Bool {
        state.tab == nil && state.pid != nil
    }

    /// The agent's name for a row.
    static func name(_ agent: AgentState.Agent?) -> String {
        switch agent {
        case .claude: "claude"
        case .opencode: "opencode"
        case nil: "agent"
        }
    }

    /// The row's state and how long it has been in it: "waits 3m", "working 40s", "done 12m", "idle".
    public static func stateText(_ row: SidebarAgentRow, now: Date) -> String {
        let time = row.since.map { " " + elapsed(now.timeIntervalSince($0)) } ?? ""
        switch row.mark {
        case .waiting: return "waits" + time
        case .working: return "working" + time
        case .finished: return "done" + time
        case .none: return "idle"
        }
    }

    /// The row's tooltip.
    public static func help(_ row: SidebarAgentRow, now: Date) -> String {
        let state = switch row.mark {
        case .waiting: "waits for you"
        case .working: "is working"
        case .finished: "finished while you were elsewhere"
        case .none: "is idle"
        }
        let time = row.since.map { " (\(elapsed(now.timeIntervalSince($0))))" } ?? ""
        let place = switch row.place {
        case .agentTab, .shellTab: ""
        case .elsewhere: "; started outside Paddock or in a closed tab"
        }
        let tab = row.tabName.map { $0 == row.title ? "" : " (\($0))" } ?? ""
        return "\(row.title)\(tab) \(state)\(row.mark == .none ? "" : time)\(place)"
    }

    /// "40s", "3m", "2h", "1d": whole units, rounded down.
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        switch value {
        case ..<60: return "\(value)s"
        case ..<3600: return "\(value / 60)m"
        case ..<86_400: return "\(value / 3600)h"
        default: return "\(value / 86_400)d"
        }
    }
}
