import Foundation
import Testing
@testable import PaddockCore

struct VoiceKitTests {
    private let tab = "6D3F2C1E-1B2A-4C5D-8E9F-0A1B2C3D4E5F"

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-voice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func run(_ arguments: [String], environment: [String: String], stdin: String = "") throws -> (out: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
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
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }

    /// The kit's two programs in `dir`, and the environment they run with there.
    private func install(in dir: URL) throws -> (tool: String, watch: String, env: [String: String]) {
        let tool = dir.appendingPathComponent("paddock-voice")
        let watch = dir.appendingPathComponent("paddock-voice-watch")
        try VoiceKit.script.write(to: tool, atomically: true, encoding: .utf8)
        try VoiceKit.watchScript.write(to: watch, atomically: true, encoding: .utf8)
        return (tool.path, watch.path, ["PADDOCK_VOICE_DIR": dir.appendingPathComponent("d").path, "PADDOCK_TAB": tab])
    }

    private func watched(_ watch: String, env: [String: String]) throws -> [VoiceMessage] {
        try run(["timeout", "2", "sh", watch], environment: env).out.split(separator: "\n").compactMap { VoiceMessage(line: String($0)) }
    }

    @Test(.enabled(if: AgentStatusKitTests.hasNode)) func whatTheAgentSaysReachesTheWatcherOnce() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let kit = try install(in: dir)
        try set(VoiceSettings(voice: true, voiceReply: true), kit)
        #expect(try run(["node", kit.tool, "words", "add", "PolicyPlanner", "sbx"], environment: kit.env).status == 0)
        #expect(try run(["node", kit.tool, "say", "Tests", "pass."], environment: kit.env).status == 0)
        let messages = try watched(kit.watch, env: kit.env)
        #expect(messages.map(\.kind) == [.words(["PolicyPlanner", "sbx"]), .say(text: "Tests pass.")])
        #expect(messages.last?.tab == UUID(uuidString: tab))
        // a second watcher gets the words again (state), not the say (an event, printed once)
        #expect(try watched(kit.watch, env: kit.env).map(\.kind) == [.words(["PolicyPlanner", "sbx"])])
    }

    @Test(.enabled(if: AgentStatusKitTests.hasNode)) func aQuestionGetsPaddocksAnswer() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let kit = try install(in: dir)
        try set(VoiceSettings(voice: true, voiceReply: true), kit)
        let asking = Task.detached { [kit] in
            try run(["node", kit.tool, "ask", "Which target?", "--choice", "staging", "--choice", "production", "--timeout", "20"],
                    environment: kit.env).out
        }
        // the question shows up, and Paddock answers it on standard input
        var question: VoiceMessage?
        for _ in 0..<20 where question == nil {
            question = try watched(kit.watch, env: kit.env).first { if case .ask = $0.kind { true } else { false } }
        }
        let message = try #require(question)
        #expect(message.kind == .ask(question: "Which target?", choices: ["staging", "production"], deadline: message.time.addingTimeInterval(20)))
        let answer = try #require(VoiceAnswer.to(choices: ["staging", "production"], answer: "the second one"))
        try run(["node", kit.tool, "--answer", message.id], environment: kit.env, stdin: answer.line)
        #expect(try await asking.value == "choice: production\n")
    }

    @Test(.enabled(if: AgentStatusKitTests.hasNode)) func aQuestionNobodyAnswersIsTakenBack() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let kit = try install(in: dir)
        try set(VoiceSettings(voice: true, voiceReply: true), kit)
        #expect(try run(["node", kit.tool, "ask", "Still there?", "--timeout", "5"], environment: kit.env).out == "timeout\n")
        let messages = try watched(kit.watch, env: kit.env)
        #expect(messages.count == 2 && messages.last?.kind == .cancel && messages.first?.id == messages.last?.id)
    }

    @Test(.enabled(if: AgentStatusKitTests.hasNode)) func theKitRefusesWhatPaddockWouldDrop() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let kit = try install(in: dir)
        try set(VoiceSettings(voice: true, voiceReply: true), kit)
        #expect(try run(["node", kit.tool, "words", "add", "$(id)"], environment: kit.env).status == 2)
        #expect(try run(["node", kit.tool, "say", String(repeating: "a", count: 601)], environment: kit.env).status == 2)
        #expect(try run(["node", kit.tool, "ask", "q", "--choice", "a", "--choice", "A"], environment: kit.env).status == 2)
        #expect(try run(["node", kit.tool, "ask", "q", "--timeout", "99999"], environment: kit.env).status == 2)
        // answers only for a question that waits, and only in the answer shapes
        #expect(try run(["node", kit.tool, "--answer", "../x"], environment: kit.env, stdin: "dismissed").status == 2)
        try run(["node", kit.tool, "--answer", "v-12345678"], environment: kit.env, stdin: "dismissed")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("d/answers/v-12345678").path))
        #expect(try watched(kit.watch, env: kit.env).isEmpty)
    }

    /// What the hook adds to the prompt, or nil when it prints nothing; it never fails.
    private func hookContext(_ kit: (tool: String, watch: String, env: [String: String]), prompt: String) throws -> String? {
        let input = #"{"session_id":"s","hook_event_name":"UserPromptSubmit","prompt":"\#(prompt)"}"#
        let result = try run(["node", kit.tool, "--hook", "claude"], environment: kit.env, stdin: input)
        #expect(result.status == 0)
        guard !result.out.isEmpty else { return nil }
        let output = try #require(JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any])
        return (output["hookSpecificOutput"] as? [String: Any])?["additionalContext"] as? String
    }

    private func set(_ settings: VoiceSettings, _ kit: (tool: String, watch: String, env: [String: String])) throws {
        try run(["node", kit.tool, "--set-status", tab], environment: kit.env, stdin: String(decoding: settings.json, as: UTF8.self))
    }

    @Test(.enabled(if: AgentStatusKitTests.hasNode)) func theHookTellsTheAgentAboutASpokenPromptAndHowToReply() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let kit = try install(in: dir)
        try set(VoiceSettings(voice: true, voiceReply: false), kit)
        try run(["node", kit.tool, "--dictated", tab], environment: kit.env, stdin: "Fix the  PolicyPlanner test")

        // what Claude Code sends on UserPromptSubmit (code.claude.com/docs/en/hooks; a capture on the Mac is PAD-34)
        let spoken = try #require(try hookContext(kit, prompt: "fix the policyplanner test"))
        #expect(spoken.contains("dictated this prompt") && spoken.contains("as usual") && !spoken.contains("paddock-voice say \""))

        // the record is used once; a typed prompt with voice reply off and broken input say nothing
        #expect(try hookContext(kit, prompt: "fix the policyplanner test") == nil)
        let broken = try run(["node", kit.tool, "--hook", "claude"], environment: kit.env, stdin: "not json")
        #expect(broken.out.isEmpty && broken.status == 0)

        // voice reply on: every prompt, typed too, asks for a spoken summary or question
        try set(VoiceSettings(voice: true, voiceReply: true), kit)
        let typed = try #require(try hookContext(kit, prompt: "run the tests"))
        #expect(typed.contains("paddock-voice say \"") && typed.contains("paddock-voice ask") && !typed.contains("dictated this prompt"))
        // muted, nothing is spoken, so the agent replies as usual
        try set(VoiceSettings(voice: false, voiceReply: true), kit)
        #expect(try hookContext(kit, prompt: "run the tests") == nil)
    }

    @Test(.enabled(if: AgentStatusKitTests.hasNode)) func theAgentMaySayAnythingWhateverVoiceReplyIs() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let kit = try install(in: dir)
        // no settings yet, and voice reply off: Paddock shows it in the popup and decides what is read aloud
        #expect(try run(["node", kit.tool, "say", "Done."], environment: kit.env).status == 0)
        try set(VoiceSettings(voice: true, voiceReply: false), kit)
        #expect(try run(["node", kit.tool, "say", "Still done."], environment: kit.env).status == 0)
        #expect(try watched(kit.watch, env: kit.env).map(\.kind) == [.say(text: "Done."), .say(text: "Still done.")])
        // and there is nothing else to learn: no status command
        #expect(try run(["node", kit.tool, "status"], environment: kit.env).status == 2)
    }

    @Test(.enabled(if: AgentStatusKitTests.hasNode)) func settingsNeedBothSwitches() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let kit = try install(in: dir)
        for bad in [#"{"voice":true}"#, #"{"voice":true,"voiceReply":"yes"}"#, "not json"] {
            #expect(try run(["node", kit.tool, "--set-status", tab], environment: kit.env, stdin: bad).status == 2)
        }
    }

    @Test func theHookIsMergedLikeTheStatusKits() throws {
        let hooks = try #require(JSONSerialization.jsonObject(with: Data(VoiceKit.claudeHooksJSON.utf8)) as? [String: [[String: Any]]])
        #expect(Array(hooks.keys) == ["UserPromptSubmit"])
        let hook = try #require((hooks["UserPromptSubmit"]?.first?["hooks"] as? [[String: Any]])?.first)
        #expect(hook["command"] as? String == "paddock-voice --hook claude" && hook["timeout"] as? Int == 5)
    }

    @Test func theKitIsWrittenOnceAndHoldsEveryPiece() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = PaddockPaths(configDirectory: dir.path)
        let kit = try BuiltinKits.install(.voice, in: paths)
        #expect(kit == dir.path + "/kits/paddock-voice")
        let spec = try String(contentsOfFile: KitFile.file(in: kit), encoding: .utf8)
        #expect(spec.contains("provides: [paddock-voice]") && spec.contains("kind: mixin") && spec.contains("agent-context@1"))
        #expect(spec.contains(Data(VoiceKit.script.utf8).base64EncodedString()))
        #expect(spec.contains(Data(VoiceKit.watchScript.utf8).base64EncodedString()))
        #expect(AppConfig.defaultKits["voice"]?.needs == ["status"] && AppConfig.defaultKits["voice"]?.recommended == false)
        #expect(SandboxWatchers.commands.contains("paddock-voice-watch"))
        #expect(VoiceKit.watchArguments(sandbox: "paddock-app").suffix(2) == ["paddock-voice-watch", SandboxWatchers.owner])
    }

    @Test func theAppsCommandsKeepTextOutOfArgv() {
        let tabID = UUID()
        #expect(VoiceKit.answerArguments(sandbox: "paddock-app", id: "v-1a2b3c4d")
                == ["exec", "-i", "paddock-app", "paddock-voice", "--answer", "v-1a2b3c4d"])
        #expect(VoiceKit.answerArguments(sandbox: "paddock-app", id: "v-1a2b3c4d; rm") == nil)
        #expect(VoiceKit.dictatedArguments(sandbox: "paddock-app", tab: tabID).last == tabID.uuidString)
        #expect(VoiceKit.settingsArguments(sandbox: "paddock-app", tab: tabID)
                == ["exec", "-i", "paddock-app", "paddock-voice", "--set-status", tabID.uuidString])
    }
}
