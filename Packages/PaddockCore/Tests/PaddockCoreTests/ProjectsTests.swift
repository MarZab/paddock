import Foundation
import Testing
@testable import PaddockCore

@Suite("LineStreamer")
struct LineStreamerTests {
    let sh = URL(fileURLWithPath: "/bin/sh")

    func collect(_ script: String) async throws -> [String] {
        var lines: [String] = []
        for try await line in FoundationLineStreamer().lines(sh, arguments: ["-c", script]) {
            lines.append(line)
        }
        return lines
    }

    @Test func linesAcrossChunksAndWithoutAFinalNewline() async throws {
        #expect(try await collect("printf 'a\\nb'; sleep 0.1; printf 'c\\nlast'") == ["a", "bc", "last"])
    }

    @Test func nonZeroExitIsAnError() async {
        await #expect(throws: ProcessExitError.self) { _ = try await collect("echo x; exit 3") }
    }

    /// The app ends `sbx events` by cancelling the task that reads it; that must stop the process.
    /// (Leaving a `for await` loop with `break` does not end the stream, so it is not used here.)
    @Test func cancellingTheReaderStopsTheProcess() async throws {
        let stream = FoundationLineStreamer().lines(sh, arguments: ["-c", "echo first; exec sleep 30"])
        let reader = Task {
            var lines: [String] = []
            for try await line in stream { lines.append(line) }
            return lines
        }
        try await Task.sleep(for: .milliseconds(300))
        let started = ContinuousClock.now
        reader.cancel()
        _ = try? await reader.value
        #expect(ContinuousClock.now - started < .seconds(5))
    }
}

/// Returns canned lines, as `sbx events --json` would.
struct FakeLineStreamer: LineStreaming {
    let output: [String]

    func lines(_ executable: URL, arguments: [String]) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            for line in output { continuation.yield(line) }
            continuation.finish()
        }
    }
}

@Suite("SandboxStates")
struct SandboxStatesTests {
    func fixtureLines() throws -> [String] {
        String(decoding: try Fixture.data("sbx", "events-lifecycle.ndjson"), as: UTF8.self).split(separator: "\n").map(String.init)
    }

    @Test func replayThenLifecycleFromTheCapture() async throws {
        let lines = try fixtureLines()
        let stream = SbxEventStream(streamer: FakeLineStreamer(output: ["not an event"] + lines), sbx: URL(fileURLWithPath: "/sbx"))
        var states = SandboxStates()
        var afterSync: SandboxStates?
        var sawCreatedApp = false
        for try await event in stream.events() {
            states.apply(event)
            if event.isSyncComplete { afterSync = states }
            if event.sandboxName == "paddock-app", event.action == "started" { sawCreatedApp = states["paddock-app"] == .running }
        }
        let replay = try #require(afterSync)
        #expect(replay.isSynced)
        #expect(replay["project-a"] == .stopped)
        #expect(replay["project-c"] == .running)
        #expect(sawCreatedApp)
        // both test sandboxes were deleted at the end of the capture
        #expect(states["paddock-app"] == nil && states["paddock-builder"] == nil)
    }

    @Test func aSandboxSbxLsNoLongerListsIsDropped() throws {
        let lines = try fixtureLines()
        let events = try lines.map { try JSONCoding.decode(SbxEvent.self, from: Data($0.utf8)) }
        let start = Date(timeIntervalSince1970: 1000)
        var states = SandboxStates()
        for event in events where event.sandboxName != "paddock-app" || event.action != "deleted" {
            states.apply(event, at: start)  // the stream missed paddock-app's deleted event
        }
        let listed = try Fixture.decode([SbxSandbox].self, "sbx", "ls.json")  // without paddock-app
        #expect(states["paddock-app"] != nil)
        states.reconcile(with: listed, listedAt: start.addingTimeInterval(10))
        #expect(states["paddock-app"] == nil)
        #expect(states["project-a"] == .stopped)
    }

    @Test func aSandboxCreatedAfterTheListStays() throws {
        let created = try JSONCoding.decode(SbxEvent.self, from: Data(try #require(fixtureLines().first { $0.contains("\"created\"") }).utf8))
        let name = try #require(created.sandboxName)
        var states = SandboxStates()
        states.apply(created, at: Date(timeIntervalSince1970: 2000))
        states.reconcile(with: [], listedAt: Date(timeIntervalSince1970: 1990))
        #expect(states[name] == .stopped)
    }

    @Test func sbxLsCorrectsAStateTheEventsMissed() throws {
        let listed = try Fixture.decode([SbxSandbox].self, "sbx", "ls.json")
        let stopped = try #require(listed.first { $0.status == "stopped" })
        let line = #"{"action":"started","id":"e1","sandbox_name":"\#(stopped.name)","timestamp":"2026-10-24T18:57:18Z","type":"sandbox.lifecycle"}"#
        let started = try JSONCoding.decode(SbxEvent.self, from: Data(line.utf8))
        var states = SandboxStates()
        states.apply(started, at: Date(timeIntervalSince1970: 1000))  // the stream missed the stopped event
        states.reconcile(with: listed, listedAt: Date(timeIntervalSince1970: 1010))
        #expect(states[stopped.name] == .stopped)
        // an event after the list wins
        states.apply(started, at: Date(timeIntervalSince1970: 1020))
        states.reconcile(with: listed, listedAt: Date(timeIntervalSince1970: 1010))
        #expect(states[stopped.name] == .running)
    }

    @Test func fromSbxLs() throws {
        let sandboxes = try Fixture.decode([SbxSandbox].self, "sbx", "ls.json")
        let states = SandboxStates(sandboxes: sandboxes)
        #expect(states.isSynced)
        #expect(states.states.count == sandboxes.count)
    }
}

@Suite("NewProject")
struct NewProjectTests {
    struct Folder {
        let home: String
        let project: String

        init(name: String = "My App") throws {
            home = FolderPolicy.canonical(NSTemporaryDirectory()) + "/paddock-home-" + UUID().uuidString
            project = home + "/src/" + name
            try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        }

        var policy: FolderPolicy { FolderPolicy(home: home, paddockConfigDirectory: home + "/.config/paddock") }

        func write(_ name: String, _ text: String) throws {
            try Data(text.utf8).write(to: URL(fileURLWithPath: project + "/" + name))
        }

        func cleanup() { try? FileManager.default.removeItem(atPath: home) }
    }

    func app() throws -> AppConfig { try AppConfig.load(from: Fixture.data("config", "paddock-full.yaml")).config }

    @Test(arguments: [
        ("/src/My App", "my-app"), ("/src/plane", "plane"), ("/src/über_tool!", "ber-tool"),
        ("/src/---", "project"), ("/src/v1.2", "v1.2"), ("/src/x", "project-x"), ("/src/Default", "project-default"),
    ])
    func suggestedNames(folder: String, name: String) {
        #expect(NewProject.suggestedName(for: folder, taken: []) == name)
        #expect(ProjectList.isValidSandboxName(name))
    }

    @Test func suggestedNamesAreUnique() {
        #expect(NewProject.suggestedName(for: "/src/app", taken: ["app", "app-2"]) == "app-3")
    }

    @Test func draftTakesTheNameAndAgentOfTheSbxenvFile() throws {
        let folder = try Folder()
        defer { folder.cleanup() }
        try folder.write("sbxenv.yaml", "schemaVersion: \"1\"\nname: shop\nagent: opencode\n")
        let (draft, problem) = NewProject.draft(folder: folder.project, app: try app(), taken: [])
        #expect(problem == nil)
        #expect(draft.name == "shop" && draft.agent == "opencode")
        #expect(draft.provider == "agent-default")
        // a name taken already: the folder's
        #expect(NewProject.draft(folder: folder.project, app: try app(), taken: ["shop"]).draft.name == "my-app")
    }

    @Test func aBrokenSbxenvFileIsAProblemNotAFailure() throws {
        let folder = try Folder()
        defer { folder.cleanup() }
        try folder.write("sbxenv.yaml", "agent: [")
        let (draft, problem) = NewProject.draft(folder: folder.project, app: try app(), taken: [])
        #expect(problem != nil)
        #expect(draft.agent == "claude")
    }

    @Test func localProviderGetsTheNextGatewayPortNotApproval() throws {
        let folder = try Folder()
        defer { folder.cleanup() }
        let existing = try ProjectList(validating: [Project(name: "paddock-other", folder: "/o", gatewayPort: 17480)])
        let draft = ProjectDraft(folder: folder.project, name: "paddock-my-app", agent: "claude", provider: "local_qwen")
        let project = try NewProject.make(draft, app: try app(), existing: existing, sandboxes: [], folderPolicy: folder.policy)
        #expect(project.gatewayPort == 17481)
        #expect(project.folder == folder.project)
        // an sbxenv.yaml is confirmed in its own sheet before the create
        #expect(project.approvedEnvironment == nil)
    }

    @Test func anInstalledModelWithoutASectionIsALocalProvider() throws {
        let folder = try Folder()
        defer { folder.cleanup() }
        let name = AppConfig.localProviderName(model: "qwen3:8b")
        #expect(name == "local:qwen3:8b")
        let config = try app()
        #expect(config.provider(named: name) == .local(model: "qwen3:8b"))
        #expect(config.provider(named: "local:") == nil)
        #expect(config.provider(named: "qwen3:8b") == nil)
        let draft = ProjectDraft(folder: folder.project, name: "paddock-my-app", agent: "opencode", provider: name)
        let project = try NewProject.make(draft, app: config, existing: ProjectList(), sandboxes: [], folderPolicy: folder.policy)
        #expect(project.gatewayPort != nil)
        #expect(project.usesGateway(config))
    }

    @Test func cloneModeNeedsTheFolderToBeAGitRepository() throws {
        let folder = try Folder()
        defer { folder.cleanup() }
        var draft = ProjectDraft(folder: folder.project, name: "paddock-my-app", agent: "claude", provider: "agent-default", cloneMode: true)
        #expect(!NewProject.supportsClone(folder.project))
        #expect(throws: NewProjectError.cloneNeedsGit) {
            try NewProject.make(draft, app: try app(), existing: ProjectList(), sandboxes: [], folderPolicy: folder.policy)
        }
        // A worktree has a .git file instead of a directory.
        try folder.write(".git", "gitdir: /elsewhere/.git/worktrees/app\n")
        #expect(NewProject.supportsClone(folder.project))
        #expect(try NewProject.make(draft, app: try app(), existing: ProjectList(), sandboxes: [], folderPolicy: folder.policy).cloneMode)
        draft.cloneMode = false
        try FileManager.default.removeItem(atPath: folder.project + "/.git")
        #expect(try !NewProject.make(draft, app: try app(), existing: ProjectList(), sandboxes: [], folderPolicy: folder.policy).cloneMode)
    }

    @Test func agentDefaultHasNoGatewayPort() throws {
        let folder = try Folder()
        defer { folder.cleanup() }
        let draft = ProjectDraft(folder: folder.project, name: "paddock-my-app", agent: "claude", provider: "agent-default")
        #expect(try NewProject.make(draft, app: try app(), existing: ProjectList(), sandboxes: [], folderPolicy: folder.policy).gatewayPort == nil)
    }

    @Test func refusals() throws {
        let folder = try Folder()
        defer { folder.cleanup() }
        let good = ProjectDraft(folder: folder.project, name: "my-app", agent: "claude", provider: "agent-default")
        let app = try app()
        func make(_ draft: ProjectDraft, existing: ProjectList = ProjectList(), sandboxes: Set<String> = []) throws(NewProjectError) {
            _ = try NewProject.make(draft, app: app, existing: existing, sandboxes: sandboxes, folderPolicy: folder.policy)
        }
        var home = good
        home.folder = folder.home
        #expect(throws: NewProjectError.folder(.home)) { try make(home) }
        let taken = try ProjectList(validating: [Project(name: "my-app", folder: "/elsewhere")])
        #expect(throws: NewProjectError.nameTaken("my-app")) { try make(good, existing: taken) }
        let sameFolder = try ProjectList(validating: [Project(name: "paddock-first", folder: folder.project)])
        #expect(throws: NewProjectError.folderAlreadyAProject(name: "paddock-first")) { try make(good, existing: sameFolder) }
        #expect(throws: NewProjectError.sandboxExists("my-app")) { try make(good, sandboxes: ["my-app"]) }
        var badName = good
        badName.name = "-app"
        #expect(throws: NewProjectError.invalidName("-app")) { try make(badName) }
        var unknown = good
        unknown.provider = "openrouter"
        #expect(throws: NewProjectError.unknownSection(kind: "provider", name: "openrouter")) { try make(unknown) }
    }

}
