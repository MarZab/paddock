import Foundation
import Testing
@testable import PaddockCore

struct AgentStatusKitTests {
    /// The merge and the plugin are JavaScript; they run in the sandbox's Node, so a machine without one skips them.
    static let hasNode: Bool = {
        (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .contains { FileManager.default.isExecutableFile(atPath: "\($0)/node") }
    }()

    // MARK: AgentState

    private let tabID = UUID(uuidString: "6D3F2C1E-1B2A-4C5D-8E9F-0A1B2C3D4E5F")

    @Test func parsesAStateLine() {
        let line = #"{"session":"abc-123","state":"waiting","agent":"claude","tab":"6D3F2C1E-1B2A-4C5D-8E9F-0A1B2C3D4E5F","time":1761400000}"#
        #expect(AgentState(line: line) == AgentState(session: "abc-123", kind: .waiting, agent: .claude, tab: tabID,
                                                     time: Date(timeIntervalSince1970: 1_761_400_000)))
    }

    @Test func parsesTheWatchersOwnOutput() throws {
        // Real paddock-agent-watch output from a Claude Code sandbox on the Mac (2026-10-31).
        let lines = String(decoding: try Fixture.data("agent", "watch.jsonl"), as: UTF8.self).split(separator: "\n").map(String.init)
        let states = lines.compactMap(AgentState.init(line:))
        #expect(states.count == lines.count)
        #expect(states[0] == AgentState(session: "a5a05f80-61bc-43cd-9fe0-7070da1adea8", kind: .idle, agent: .claude,
                                        tab: UUID(uuidString: "9F35E85C-DE44-47DC-8926-48490DE3A2B4"),
                                        time: Date(timeIntervalSince1970: 1_793_399_289)))
        #expect(states[1].kind == .working && states[1].agent == .claude && states[1].session == "f9f88357-edc4-4dea-b720-f5230e42b274")
    }

    /// PAD-61: a restarted watcher does not blank the marks; only sessions it no longer reports go.
    @Test func aRestartedWatcherKeepsTheStatesItReportsAgain() {
        let tab = UUID()
        var states = AgentStates()
        states.apply(line: #"{"session":"a","state":"working","agent":"claude","tab":"\#(tab.uuidString)","time":5}"#)
        states.apply(line: #"{"session":"b","state":"idle","agent":"claude","tab":"","time":4}"#)
        states.beginResync()
        #expect(states.activity(ofTab: tab) == .working)
        states.apply(line: #"{"session":"a","state":"working","agent":"claude","tab":"\#(tab.uuidString)","time":5}"#)
        #expect(states.sessions.count == 2)
        states.endResync()
        #expect(Set(states.sessions.keys) == ["a"])
        #expect(states.activity(ofTab: tab) == .working)
        // Closed: later lines apply as usual.
        states.endResync()
        states.apply(line: #"{"session":"c","state":"waiting","agent":"claude","tab":"","time":6}"#)
        #expect(states.overall == .waiting && states.sessions.count == 2)
    }

    @Test func aMissingTabOrAgentIsKeptAsNone() {
        let state = AgentState(line: #"{"session":"s","state":"idle","agent":"something else","tab":"","time":1}"#)
        #expect(state?.agent == nil && state?.tab == nil)
    }

    @Test func dropsAnythingThatIsNotExactlyAState() {
        #expect(AgentState(line: #"{"session":"s","state":"rm -rf","agent":"claude","tab":"","time":1}"#) == nil)
        #expect(AgentState(line: #"{"session":"s","state":"idle","agent":"claude","tab":"","time":-1}"#) == nil)
        #expect(AgentState(line: #"{"session":"a b","state":"idle","agent":"claude","tab":"","time":1}"#) == nil)
        #expect(AgentState(line: #"{"session":"","state":"idle","agent":"claude","tab":"","time":1}"#) == nil)
        #expect(AgentState(line: #"{"state":"idle","agent":"claude","time":1}"#) == nil)
        #expect(AgentState(line: "not json") == nil)
        let padded = #"{"session":"s","state":"idle","agent":"claude","tab":"","time":1,"x":""# + String(repeating: "a", count: 600) + #""}"#
        #expect(AgentState(line: padded) == nil)
    }

    @Test func eachTabShowsItsOwnSession() {
        let other = UUID()
        var states = AgentStates()
        let first = #"{"session":"one","state":"working","agent":"claude","tab":"\#(tabID?.uuidString ?? "")","time":10}"#
        states.apply(line: first)
        states.apply(line: #"{"session":"two","state":"waiting","agent":"claude","tab":"\#(other.uuidString)","time":11}"#)
        #expect(states.state(ofTab: tabID ?? UUID())?.kind == .working)
        #expect(states.state(ofTab: other)?.kind == .waiting)
        // an ended session is forgotten, and a tab nobody reported for has no state
        states.apply(line: #"{"session":"one","state":"ended","agent":"claude","tab":"\#(tabID?.uuidString ?? "")","time":12}"#)
        #expect(states.state(ofTab: tabID ?? UUID()) == nil)
        states.apply(line: "garbage")
        #expect(states.sessions.count == 1)
    }

    @Test func theProjectShowsTheMostPressingSession() {
        var states = AgentStates()
        #expect(states.overall == .none)
        states.apply(line: #"{"session":"a","state":"idle","agent":"claude","tab":"","time":1}"#)
        #expect(states.overall == .none)
        states.apply(line: #"{"session":"b","state":"working","agent":"claude","tab":"","time":2}"#)
        #expect(states.overall == .working)
        states.apply(line: #"{"session":"c","state":"waiting","agent":"claude","tab":"","time":3}"#)
        #expect(states.overall == .waiting)
        states.apply(line: #"{"session":"c","state":"ended","agent":"claude","tab":"","time":4}"#)
        #expect(states.overall == .working)
    }

    @Test func aTabsActivityFollowsItsSession() {
        let mine = UUID()
        var states = AgentStates()
        #expect(states.activity(ofTab: mine) == .none)
        states.apply(line: #"{"session":"a","state":"waiting","agent":"claude","tab":"\#(mine.uuidString)","time":1}"#)
        states.apply(line: #"{"session":"b","state":"working","agent":"claude","tab":"","time":2}"#)
        #expect(states.activity(ofTab: mine) == .waiting)
        states.apply(line: #"{"session":"a","state":"idle","agent":"claude","tab":"\#(mine.uuidString)","time":3}"#)
        #expect(states.activity(ofTab: mine) == .none)
    }

    // MARK: Claude Code hooks

    @Test func claudeHooksMapEventsToStates() throws {
        let hooks = try #require(JSONSerialization.jsonObject(with: Data(AgentStatusKit.claudeHooksJSON.utf8)) as? [String: [[String: Any]]])
        func commands(_ event: String) -> [String] {
            (hooks[event] ?? []).flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        }
        #expect(commands("UserPromptSubmit") == ["paddock-agent-state working claude"])
        #expect(commands("PermissionRequest") == ["paddock-agent-state waiting claude"])
        #expect(commands("Stop") == ["paddock-agent-state idle claude"])
        #expect(commands("StopFailure") == ["paddock-agent-state idle claude"])
        #expect(commands("SessionEnd") == ["paddock-agent-state ended claude"])
        #expect(commands("PostToolUse") == ["paddock-agent-state working claude"])
        // a tool that asks the operator something is waiting, any other tool is working
        #expect(commands("PreToolUse") == ["paddock-agent-state working claude", "paddock-agent-state waiting claude"])
        let matchers = (hooks["PreToolUse"] ?? []).compactMap { $0["matcher"] as? String }
        #expect(matchers == ["^(?!(AskUserQuestion|ExitPlanMode)$)", "AskUserQuestion|ExitPlanMode"])
        // the permission_prompt notification arrives after about six seconds; PermissionRequest is used instead
        #expect((hooks["Notification"] ?? []).compactMap { $0["matcher"] as? String } == ["elicitation_dialog|elicitation_url_dialog"])
    }

    @Test func everyHookHasATimeoutAndOnlyCallsTheHelper() throws {
        let hooks = try #require(JSONSerialization.jsonObject(with: Data(AgentStatusKit.claudeHooksJSON.utf8)) as? [String: [[String: Any]]])
        for group in hooks.values.joined() {
            for hook in group["hooks"] as? [[String: Any]] ?? [] {
                #expect(hook["type"] as? String == "command")
                #expect(hook["timeout"] as? Int == 5)
                #expect((hook["command"] as? String)?.hasPrefix("paddock-agent-state ") == true)
            }
        }
    }

    // MARK: Scripts, run for real

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-status-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String], environment: [String: String], stdin: String = "") throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test func theStateScriptKeepsOneFilePerSession() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("paddock-agent-state")
        try AgentStatusKit.stateScript.write(to: script, atomically: true, encoding: .utf8)
        let agentDir = dir.appendingPathComponent("state-dir").path
        let tab = "6D3F2C1E-1B2A-4C5D-8E9F-0A1B2C3D4E5F"
        let env = ["PADDOCK_AGENT_DIR": agentDir, "PADDOCK_TAB": tab]
        func line(_ session: String) throws -> AgentState? {
            let file = URL(fileURLWithPath: agentDir + "/sessions/\(session).json")
            return AgentState(line: try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // the session comes from the hook's JSON on stdin; nothing is printed
        let json = #"{"session_id":"sess-1","cwd":"/x","tool_input":{"session_id":"nested"},"hook_event_name":"Stop"}"#
        let printed = try run("/bin/sh", [script.path, "waiting", "claude"], environment: env, stdin: json)
        #expect(printed.isEmpty)
        try run("/bin/sh", [script.path, "working", "claude"], environment: env, stdin: #"{"session_id":"sess-2"}"#)
        #expect(try line("sess-1")?.kind == .waiting)
        #expect(try line("sess-1")?.tab == UUID(uuidString: tab))
        #expect(try line("sess-2")?.kind == .working)

        // a session given as an argument, and the same state again leaves the file alone
        try run("/bin/sh", [script.path, "idle", "opencode", "oc-tab"], environment: env)
        let before = try line("oc-tab")?.time
        try run("/bin/sh", [script.path, "idle", "opencode", "oc-tab"], environment: env)
        #expect(try line("oc-tab")?.kind == .idle && line("oc-tab")?.time == before)
        #expect(try line("oc-tab")?.agent == .opencode)

        // unknown states, odd session names, and a bad tab are not written as given
        try run("/bin/sh", [script.path, "bogus", "claude", "sess-3"], environment: env)
        #expect(!FileManager.default.fileExists(atPath: agentDir + "/sessions/sess-3.json"))
        try run("/bin/sh", [script.path, "idle", "claude", "../escape"], environment: ["PADDOCK_AGENT_DIR": agentDir, "PADDOCK_TAB": "x\"y"])
        #expect(try line("default")?.tab == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("escape.json").path))
    }

    @Test func theWatcherPrintsEachSessionOnceAndForgetsTheEnded() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let state = dir.appendingPathComponent("paddock-agent-state")
        let watch = dir.appendingPathComponent("paddock-agent-watch")
        try AgentStatusKit.stateScript.write(to: state, atomically: true, encoding: .utf8)
        try AgentStatusKit.watchScript.write(to: watch, atomically: true, encoding: .utf8)
        let env = ["PADDOCK_AGENT_DIR": dir.appendingPathComponent("d").path]
        try run("/bin/sh", [state.path, "working", "claude", "a"], environment: env)
        try run("/bin/sh", [state.path, "idle", "claude", "b"], environment: env)
        try run("/bin/sh", [state.path, "ended", "claude", "b"], environment: env)
        let output = try run("/usr/bin/env", ["timeout", "2", "sh", watch.path], environment: env)
        let states = output.split(separator: "\n").compactMap { AgentState(line: String($0)) }
        #expect(states.map(\.session).sorted() == ["a", "b"])
        #expect(states.first { $0.session == "b" }?.kind == .ended)
        // the ended session's file is gone, so a second watcher starts with the live one only
        let again = try run("/usr/bin/env", ["timeout", "2", "sh", watch.path], environment: env)
        #expect(again.split(separator: "\n").compactMap { AgentState(line: String($0)) }.map(\.session) == ["a"])
    }

    /// PAD-64: an agent that dies without a SessionEnd (killed, its terminal closed) is reported
    /// ended once its process is gone, and forgotten. The state script runs under python3 here,
    /// which stands in for the agent and exits right after.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/proc/self/stat")
        && FileManager.default.fileExists(atPath: "/usr/bin/python3")))
    func aSessionWhoseAgentIsGoneEnds() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let state = dir.appendingPathComponent("paddock-agent-state")
        let watch = dir.appendingPathComponent("paddock-agent-watch")
        try AgentStatusKit.stateScript.write(to: state, atomically: true, encoding: .utf8)
        try AgentStatusKit.watchScript.write(to: watch, atomically: true, encoding: .utf8)
        let agentDir = dir.appendingPathComponent("d").path
        let env = ["PADDOCK_AGENT_DIR": agentDir]
        // Through a shell, as Claude Code runs its hooks: the pid is python's, not the shell's.
        try run("/usr/bin/python3", ["-c", "import subprocess, sys; subprocess.run(['/bin/sh', '-c', sys.argv[1] + ' working claude gone; true'])",
                                     "/bin/sh " + state.path], environment: env)
        // This one's agent is the test runner, which lives on.
        try run("/bin/sh", [state.path, "waiting", "claude", "alive"], environment: env)
        let written = try String(contentsOfFile: agentDir + "/sessions/gone.json", encoding: .utf8)
        #expect(!written.contains(#""pid":0,"#) && written.contains(#""pid":"#))
        let parsed = AgentState(line: written.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(parsed?.kind == .working && (parsed?.pid ?? 0) > 1)

        let output = try run("/usr/bin/env", ["timeout", "2", "sh", watch.path], environment: env)
        let states = output.split(separator: "\n").compactMap { AgentState(line: String($0)) }
        #expect(states.first { $0.session == "gone" }?.kind == .ended)
        #expect(states.first { $0.session == "alive" }?.kind == .waiting)
        #expect(!FileManager.default.fileExists(atPath: agentDir + "/sessions/gone.json"))
        #expect(FileManager.default.fileExists(atPath: agentDir + "/sessions/alive.json"))
    }

    @Test(.enabled(if: hasNode)) func theMergeKeepsWhatIsThereAndDoesNotAddTwice() throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let script = home.appendingPathComponent("merge.js")
        try AgentStatusKit.claudeMergeScript.write(to: script, atomically: true, encoding: .utf8)
        let claude = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let existing = #"{"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"mine"}]}]}}"#
        try existing.write(to: claude.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        let hooks = Data(AgentStatusKit.claudeHooksJSON.utf8).base64EncodedString()

        try run("/usr/bin/env", ["node", script.path, hooks], environment: ["HOME": home.path])
        try run("/usr/bin/env", ["node", script.path, hooks], environment: ["HOME": home.path])

        let data = try Data(contentsOf: claude.appendingPathComponent("settings.json"))
        let settings = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(settings["model"] as? String == "x")
        let installed = try #require(settings["hooks"] as? [String: [[String: Any]]])
        #expect(installed["Stop"]?.count == 2)
        #expect(installed["PreToolUse"]?.count == 2)
        #expect(installed["SessionEnd"]?.count == 1)
    }

    @Test(.enabled(if: hasNode)) func aSettingsFileThatCannotBeReadIsLeftAlone() throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let script = home.appendingPathComponent("merge.js")
        try AgentStatusKit.claudeMergeScript.write(to: script, atomically: true, encoding: .utf8)
        let claude = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let broken = claude.appendingPathComponent("settings.json")
        try "{ not json".write(to: broken, atomically: true, encoding: .utf8)
        try run("/usr/bin/env", ["node", script.path, Data("{}".utf8).base64EncodedString()], environment: ["HOME": home.path])
        #expect(try String(contentsOf: broken, encoding: .utf8) == "{ not json")
    }

    @Test(.enabled(if: hasNode)) func theOpenCodePluginCombinesSessions() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        // a stand-in for the helper that records its arguments
        let bin = dir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let helper = bin.appendingPathComponent("paddock-agent-state")
        try "#!/bin/sh\necho \"$1 $2\" >> \"$CALLS\"\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let plugin = dir.appendingPathComponent("plugin.mjs")
        try AgentStatusKit.opencodePlugin.write(to: plugin, atomically: true, encoding: .utf8)
        let driver = dir.appendingPathComponent("driver.mjs")
        try """
        import { PaddockStatus } from "./plugin.mjs"
        const hooks = await PaddockStatus()
        const send = (type, properties) => hooks.event({ event: { type, properties } })
        await send("session.status", { sessionID: "a", status: { type: "busy" } })
        await send("session.status", { sessionID: "child", status: { type: "busy" } })
        await send("session.status", { sessionID: "child", status: { type: "idle" } })
        await send("permission.asked", { sessionID: "a", id: "p1" })
        await send("permission.replied", { sessionID: "a", requestID: "p1", reply: "once" })
        await send("session.idle", { sessionID: "a" })
        await send("question.asked", { sessionID: "a", id: "q1" })
        await send("question.rejected", { sessionID: "a", requestID: "q1" })
        await send("message.updated", { sessionID: "a" })
        await new Promise((done) => setTimeout(done, 300))
        """.write(to: driver, atomically: true, encoding: .utf8)
        let calls = dir.appendingPathComponent("calls.txt")
        try run("/usr/bin/env", ["node", driver.path], environment: ["PATH": bin.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? ""),
                                                             "CALLS": calls.path])
        // idle at load; the child going idle does not hide the parent; a reply does not end the turn; idle at the end
        let lines = try String(contentsOf: calls, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines == ["idle opencode", "working opencode", "waiting opencode", "working opencode", "idle opencode",
                          "waiting opencode", "idle opencode"])
    }

    @Test func theKitIsWrittenOnceAndHoldsEveryPiece() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = PaddockPaths(configDirectory: dir.path)
        let kit = try AgentStatusKit.install(in: paths)
        #expect(kit == dir.path + "/kits/paddock-status")
        let spec = try String(contentsOfFile: KitFile.file(in: kit), encoding: .utf8)
        #expect(spec.contains("provides: [paddock-status]") && spec.contains("kind: mixin"))
        #expect(spec.contains("/home/agent/.config/opencode/plugins/paddock-status.js"))
        #expect(spec.contains(Data(AgentStatusKit.stateScript.utf8).base64EncodedString()))
        #expect(spec.contains(Data(AgentStatusKit.opencodePlugin.utf8).base64EncodedString()))
        // the project guide (PAD-71): an agent-context whose every line sits under `content: |`
        let guide = try #require(spec.components(separatedBy: "      content: |\n").last)
        #expect(spec.contains("com.docker.sandbox/agent-context@1") && guide.contains("### What Paddock refuses"))
        // blank lines stay empty on purpose (YAML allows it); every other line is indented
        #expect(guide.split(separator: "\n").allSatisfy { $0.hasPrefix("                ") })
        #expect(AgentStatusKit.watchArguments(sandbox: "paddock-app")
                == ["exec", "-i", "paddock-app", "sh", "-c", SandboxWatchers.replaceScript, "paddock-watch", "paddock-agent-watch", SandboxWatchers.owner])
    }
}
