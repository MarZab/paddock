import Foundation
import Testing
@testable import PaddockCore

/// PAD-63, PAD-64: the agents under each project in the sidebar.
@Suite("SidebarAgents")
struct SidebarAgentsTests {
    let now = Date(timeIntervalSince1970: 10_000)
    let agentOne = UUID(), agentTwo = UUID(), shell = UUID(), closed = UUID()

    func line(_ session: String, _ state: String, tab: UUID?, agent: String = "claude", pid: Int? = 42, time: Int) -> String {
        let pid = pid.map { #","pid":\#($0)"# } ?? ""
        return #"{"session":"\#(session)","state":"\#(state)","agent":"\#(agent)","tab":"\#(tab?.uuidString ?? "")"\#(pid),"time":\#(time)}"#
    }

    var tabs: [SidebarAgents.Tab] {
        [SidebarAgents.Tab(id: agentOne, title: "agent", isAgent: true),
         SidebarAgents.Tab(id: shell, title: "shell", isAgent: false),
         SidebarAgents.Tab(id: agentTwo, title: "agent 2", isAgent: true)]
    }

    @Test func rowsFollowTheTabsThenTheSessionsStartedOutside() {
        var states = AgentStates()
        states.apply(line: line("z-outside", "waiting", tab: nil, time: 9_900))
        states.apply(line: line("b-outside", "working", tab: nil, time: 9_950))
        states.apply(line: line("s1", "working", tab: agentTwo, time: 9_960))
        states.apply(line: line("s2", "idle", tab: shell, agent: "opencode", time: 9_000))
        let marks: [UUID: AgentTabMark] = [agentTwo: .working, agentOne: .finished]
        let rows = SidebarAgents.rows(tabs: tabs, marks: { marks[$0] ?? .none }, states: states, now: now)
        #expect(rows.map(\.title) == ["agent", "opencode in shell", "agent 2", "claude", "claude"])
        #expect(rows.map(\.place) == [.agentTab, .shellTab, .agentTab, .elsewhere, .elsewhere])
        #expect(rows.map(\.mark) == [.finished, .none, .working, .working, .waiting])
        #expect(rows[3].id == "session:b-outside" && rows[3].tab == nil)
        #expect(rows[2].since == Date(timeIntervalSince1970: 9_960))
        #expect(rows[0].since == nil)
    }

    /// The operator's report (2026-11-01): agents showed that had no tab. A session of a closed
    /// tab or an earlier launch, and one from a kit that cannot tell its agent died, get no row.
    @Test func sessionsOfTabsThatAreGoneAndOfTheOldKitAreNotShown() {
        var states = AgentStates()
        states.apply(line: line("closed-tab", "working", tab: closed, time: 9_950))
        states.apply(line: line("old-kit", "waiting", tab: nil, pid: nil, time: 9_950))
        states.apply(line: line("pid-zero", "waiting", tab: nil, pid: 0, time: 9_950))
        states.apply(line: line("outside", "waiting", tab: nil, time: 9_950))
        let rows = SidebarAgents.rows(tabs: tabs, marks: { _ in .none }, states: states, now: now)
        #expect(rows.map(\.id) == [agentOne.uuidString, agentTwo.uuidString, "session:outside"])
    }

    /// A row reads like its tab: the program's title when it set one, the tab's name otherwise.
    @Test func aRowShowsTheTabsTitle() {
        var states = AgentStates()
        states.apply(line: line("s2", "working", tab: shell, time: 9_990))
        let titled = [SidebarAgents.Tab(id: agentOne, title: "agent", label: "Fix the login bug", isAgent: true),
                      SidebarAgents.Tab(id: shell, title: "shell", label: "Claude Code", isAgent: false),
                      SidebarAgents.Tab(id: agentTwo, title: "agent 2", label: "", isAgent: true)]
        let rows = SidebarAgents.rows(tabs: titled, marks: { _ in .working }, states: states, now: now)
        #expect(rows.map(\.title) == ["Fix the login bug", "Claude Code", "agent 2"])
        #expect(rows.map(\.tabName) == ["agent", "shell", "agent 2"])
        #expect(SidebarAgents.help(rows[1], now: now) == "Claude Code (shell) is working (10s)")
        #expect(SidebarAgents.help(rows[2], now: now) == "agent 2 is working")
    }

    @Test func aShellTabWithoutAnAgentIsNoRow() {
        let rows = SidebarAgents.rows(tabs: tabs, marks: { _ in .none }, states: AgentStates(), now: now)
        #expect(rows.map(\.title) == ["agent", "agent 2"])
    }

    @Test func anIdleSessionElsewhereGoesAfterAnHour() {
        var states = AgentStates()
        states.apply(line: line("old-idle", "idle", tab: nil, time: Int(now.timeIntervalSince1970) - 3_601))
        states.apply(line: line("new-idle", "idle", tab: nil, time: Int(now.timeIntervalSince1970) - 60))
        states.apply(line: line("old-waiting", "waiting", tab: nil, time: 1))
        let rows = SidebarAgents.rows(tabs: [], marks: { _ in .none }, states: states, now: now)
        #expect(rows.map(\.id) == ["session:new-idle", "session:old-waiting"])
    }

    @Test func stateAndTimeInWords() {
        let row = SidebarAgentRow(id: "x", tab: nil, title: "agent 2", place: .agentTab, mark: .waiting,
                                  since: now.addingTimeInterval(-185))
        #expect(SidebarAgents.stateText(row, now: now) == "waits 3m")
        #expect(SidebarAgents.help(row, now: now) == "agent 2 waits for you (3m)")
        let idle = SidebarAgentRow(id: "y", tab: nil, title: "claude", place: .elsewhere, mark: .none, since: now)
        #expect(SidebarAgents.stateText(idle, now: now) == "idle")
        #expect(SidebarAgents.help(idle, now: now) == "claude is idle; started outside Paddock or in a closed tab")
        #expect(SidebarAgents.elapsed(40) == "40s" && SidebarAgents.elapsed(7_300) == "2h" && SidebarAgents.elapsed(90_000) == "1d")
        #expect(SidebarAgents.elapsed(-5) == "0s")
    }

    @Test func tabMarksAreReadBack() {
        var marks = AgentTabMarks()
        let tab = UUID()
        _ = marks.update(tab: tab, activity: .working, isShown: false)
        #expect(marks.mark(of: tab) == .working)
        _ = marks.update(tab: tab, activity: .none, isShown: false)
        #expect(marks.mark(of: tab) == .finished)
        marks.seen(tab)
        #expect(marks.mark(of: tab) == .none)
        #expect(marks.mark(of: UUID()) == .none)
    }
}
