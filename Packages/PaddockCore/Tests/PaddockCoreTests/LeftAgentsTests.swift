import Foundation
@testable import PaddockCore
import Testing

/// PAD-153.1: agents Paddock left running in a sandbox, found from the status kit's sessions
/// (`Fixtures/agent/left-running.jsonl`: two real sessions from one sandbox, an idle claude whose tab
/// was gone and the working one in an open tab).
@Suite("Agents left running")
struct LeftAgentsTests {
    static let leftTab = UUID(uuidString: "91B60AE5-4A3B-4D96-BAD2-FCF2358A24D9")!
    static let openTab = UUID(uuidString: "1DFCD0D0-F2D9-4658-91D8-AB4A4E8CA2EC")!
    static let now = Date(timeIntervalSince1970: 1_795_596_000)

    func states() throws -> AgentStates {
        var states = AgentStates()
        let text = String(decoding: try Fixture.data("agent", "left-running.jsonl"), as: UTF8.self)
        for line in text.split(separator: "\n") { states.apply(line: String(line)) }
        #expect(states.sessions.count == 2)
        return states
    }

    func opened(_ tabs: UUID...) -> OpenedTabs {
        var opened = OpenedTabs()
        for tab in tabs { opened.add(tab, in: "paddock", at: Self.now) }
        return opened
    }

    @Test func anAgentWhoseTabThisAppOpenedAndClosedIsLeftRunning() throws {
        let left = LeftAgents.find(states: try states(), openTabs: [Self.openTab], opened: opened(Self.leftTab, Self.openTab), project: "paddock")
        #expect(left.map(\.session) == ["59fd5a55-8be1-411c-b27f-9fb066a30387"])
        #expect(left.first?.pid == 37856)
    }

    /// Paddock Dev and the installed Paddock share sandboxes: a tab the other app opened is not ours
    /// to stop, and neither is an agent started outside Paddock.
    @Test func anotherAppsTabsAreNotOurs() throws {
        #expect(LeftAgents.find(states: try states(), openTabs: [], opened: OpenedTabs(), project: "paddock").isEmpty)
        #expect(LeftAgents.find(states: try states(), openTabs: [], opened: opened(Self.leftTab), project: "other").isEmpty)
        var states = AgentStates()
        states.apply(line: #"{"session":"s1","state":"idle","agent":"claude","tab":"","pid":40,"time":1795593159}"#)
        // A kit before PAD-64 records no process: the watcher cannot end it, so it is not offered.
        states.apply(line: #"{"session":"s2","state":"idle","agent":"claude","tab":"91B60AE5-4A3B-4D96-BAD2-FCF2358A24D9","time":1795593159}"#)
        #expect(LeftAgents.find(states: states, openTabs: [], opened: opened(Self.leftTab), project: "paddock").isEmpty)
    }

    @Test func takingOverResumesTheSameConversation() throws {
        let left = try #require(LeftAgents.find(states: try states(), openTabs: [], opened: opened(Self.leftTab), project: "paddock").first)
        #expect(LeftAgents.resumeArguments(left) == ["--resume", "59fd5a55-8be1-411c-b27f-9fb066a30387"])
        let notAUUID = AgentState(session: "--dangerously-skip-permissions", kind: .idle, agent: .claude, tab: Self.leftTab, pid: 40, time: Self.now)
        #expect(LeftAgents.resumeArguments(notAUUID) == ["--continue"])
        let openCode = AgentState(session: "oc-91B60AE5", kind: .idle, agent: .opencode, tab: Self.leftTab, pid: 40, time: Self.now)
        #expect(LeftAgents.resumeArguments(openCode) == ["--continue"])
        let unknown = AgentState(session: "x", kind: .idle, agent: nil, tab: Self.leftTab, pid: 40, time: Self.now)
        #expect(LeftAgents.resumeArguments(unknown).isEmpty)
    }

    @Test func stopsOnlyThatSessionsProcess() throws {
        let left = try #require(LeftAgents.find(states: try states(), openTabs: [], opened: opened(Self.leftTab), project: "paddock").first)
        #expect(LeftAgents.stopCommand(sandbox: "paddock", state: left)
            == ["exec", "paddock", "sh", "-c", LeftAgents.stopScript, "paddock-stop", "37856", "tab", Self.leftTab.uuidString])
        let noTab = AgentState(session: "s", kind: .idle, agent: .claude, tab: nil, pid: 40, time: Self.now)
        #expect(LeftAgents.stopCommand(sandbox: "paddock", state: noTab) == nil)
        let init1 = AgentState(session: "s", kind: .idle, agent: .claude, tab: Self.leftTab, pid: 1, time: Self.now)
        #expect(LeftAgents.stopCommand(sandbox: "paddock", state: init1) == nil)
        #expect(LeftAgents.stopProcessCommand(sandbox: "paddock", pid: 1, name: "sh") == nil)
        #expect(LeftAgents.stopProcessCommand(sandbox: "paddock", pid: 40, name: "") == nil)
        #expect(LeftAgents.stopProcessCommand(sandbox: "paddock", pid: 40, name: "a\nb") == nil)
        #expect(LeftAgents.stopProcessCommand(sandbox: "paddock", pid: 40, name: "node")?.suffix(3) == ["40", "name", "node"])
    }

    /// The sidebar lists a left-running agent after the open tabs; its row opens its host tab.
    @Test func theSidebarListsItAfterTheTabs() throws {
        let states = try states()
        let left = LeftAgents.find(states: states, openTabs: [Self.openTab], opened: opened(Self.leftTab, Self.openTab), project: "paddock")
        let tabs = [SidebarAgents.Tab(id: Self.openTab, title: "agent", isAgent: true)]
        let rows = SidebarAgents.rows(tabs: tabs, marks: { _ in .none }, states: states, left: left, now: Self.now)
        #expect(rows.map(\.place) == [.agentTab, .leftRunning])
        let row = try #require(rows.last)
        #expect(row.tab == nil && row.hostTab == "left:59fd5a55-8be1-411c-b27f-9fb066a30387" && row.title == "claude")
        #expect(LeftAgents.session(ofHostTab: try #require(row.hostTab)) == "59fd5a55-8be1-411c-b27f-9fb066a30387")
        #expect(LeftAgents.session(ofHostTab: "show:tab-a1b2") == nil)
        #expect(SidebarAgents.help(row, now: Self.now).contains("left running"))
    }

    @Test func theRunnerStopsThroughSbx() async throws {
        let fake = FakeRunner()
        fake.succeedByDefault = true
        let runner = ProjectRunner(sbx: SbxService(runner: fake, sbx: URL(fileURLWithPath: "/sbx")), paths: PaddockPaths(configDirectory: "/tmp/p"))
        let project = Project(name: "paddock", folder: "/Users/op/paddock")
        let left = try #require(LeftAgents.find(states: try states(), openTabs: [], opened: opened(Self.leftTab), project: "paddock").first)
        try await runner.stopLeftAgent(left, of: project)
        try await runner.stopSandboxProcess(pid: 40, name: "node", of: project)
        #expect(fake.calls.map { Array($0.prefix(4)) } == [["exec", "paddock", "sh", "-c"], ["exec", "paddock", "sh", "-c"]])
        #expect(fake.calls.last?.suffix(3) == ["40", "name", "node"])
        await #expect(throws: ProjectRunError.cannotStop("process 1")) {
            try await runner.stopSandboxProcess(pid: 1, name: "sh", of: project)
        }
    }

    @Test func remembersItsTabsPerAppAndForgetsOldOnes() throws {
        let paths = PaddockPaths(configDirectory: "/c", dataDirectory: "/d")
        #expect(OpenedTabs.path(in: paths, bundleID: "net.zabreznik.paddock.dev") == "/d/tabs/net.zabreznik.paddock.dev.json")
        for bad in ["", "../x", "a/b", ".hidden", "a..b"] {
            #expect(OpenedTabs.path(in: paths, bundleID: bad) == nil, "\(bad)")
        }
        var tabs = opened(Self.leftTab, Self.openTab)
        let old = UUID()
        tabs.add(old, in: "paddock", at: Self.now.addingTimeInterval(-OpenedTabs.kept - 60))
        tabs.add(UUID(), in: "gone", at: Self.now)
        // Old and not reported: forgotten. Reported: kept however old.
        tabs.prune(project: "paddock", reported: [], now: Self.now)
        #expect(!tabs.contains(old, in: "paddock") && tabs.contains(Self.leftTab, in: "paddock"))
        var reported = tabs
        reported.add(old, in: "paddock", at: Self.now.addingTimeInterval(-OpenedTabs.kept - 60))
        reported.prune(project: "paddock", reported: [old], now: Self.now)
        #expect(reported.contains(old, in: "paddock"))
        tabs.keepOnly(projects: ["paddock"])
        #expect(tabs.projects.keys.sorted() == ["paddock"])

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("opened-tabs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("tabs/app.json").path
        try tabs.save(to: file)
        #expect(OpenedTabs.load(from: file) == tabs)
        let mode = try FileManager.default.attributesOfItem(atPath: file)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(OpenedTabs.load(from: folder.appendingPathComponent("missing.json").path) == OpenedTabs())
    }

    #if os(Linux)
    /// The stop script, run for real: a process with the tab's environment stops; one whose pid now
    /// belongs to something else does not. A process the test starts ignores TERM (it inherits the
    /// runner's blocked signals), so it ends by KILL after a short grace.
    @Test func theStopScriptChecksBeforeItStops() throws {
        let tab = UUID().uuidString
        func spawn(_ environment: [String: String]) throws -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["30"]
            process.environment = environment
            try process.run()
            return process
        }
        func stop(_ arguments: [String]) throws -> (Int32, String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", LeftAgents.stopScript, "paddock-stop"] + arguments
            let out = Pipe()
            process.standardOutput = out
            process.standardError = out
            try process.run()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        let other = try spawn(["PADDOCK_TAB": UUID().uuidString])
        defer { other.terminate() }
        let (refused, why) = try stop([String(other.processIdentifier), "tab", tab])
        #expect(refused == 3 && why.contains("another session"))
        #expect(other.isRunning)
        let (wrongName, _) = try stop([String(other.processIdentifier), "name", "node"])
        #expect(wrongName == 3 && other.isRunning)

        let agent = try spawn(["PADDOCK_TAB": tab])
        let (stopped, said) = try stop([String(agent.processIdentifier), "tab", tab, "5"])
        agent.waitUntilExit()
        #expect(stopped == 0 && said.contains("stopped") && !agent.isRunning)
        let (byName, _) = try stop([String(other.processIdentifier), "name", "sleep", "5"])
        other.waitUntilExit()
        #expect(byName == 0 && !other.isRunning)
        let (gone, saidGone) = try stop([String(agent.processIdentifier), "tab", tab])
        #expect(gone == 0 && saidGone.contains("gone"))
        #expect(try stop(["1", "name", "sh"]).0 == 2)
    }
    #endif
}
