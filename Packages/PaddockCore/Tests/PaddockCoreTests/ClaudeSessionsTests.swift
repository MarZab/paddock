import Foundation
import Testing
@testable import PaddockCore

/// Claude's sessions kept on this Mac (PAD-127, backlog doc Security rules, Claude sessions).
@Suite("ClaudeSessions")
struct ClaudeSessionsTests {
    struct Folders {
        let root: String
        let paths: PaddockPaths
        let policy: FolderPolicy

        init() throws {
            root = FolderPolicy.canonical(NSTemporaryDirectory()) + "/paddock-sessions-" + UUID().uuidString
            try FileManager.default.createDirectory(atPath: root + "/home", withIntermediateDirectories: true)
            paths = PaddockPaths(configDirectory: root + "/home/.config/paddock")
            policy = FolderPolicy(home: root + "/home", paddockConfigDirectory: paths.configDirectory)
        }

        func cleanup() { try? FileManager.default.removeItem(atPath: root) }
    }

    @Test func theDataFolderIsApartFromTheConfigFolder() {
        let paths = PaddockPaths(environment: [:], home: "/Users/op")
        #expect(paths.dataDirectory == "/Users/op/.local/share/paddock")
        #expect(ClaudeSessions.folder(project: "app", paths: paths) == "/Users/op/.local/share/paddock/sessions/app/claude")
        let xdg = PaddockPaths(environment: ["XDG_DATA_HOME": "/data", "XDG_CONFIG_HOME": "/cfg"], home: "/Users/op")
        #expect(xdg.dataDirectory == "/data/paddock" && xdg.configDirectory == "/cfg/paddock")
        // A relative XDG value is ignored, as for the config folder.
        #expect(PaddockPaths(environment: ["XDG_DATA_HOME": "data"], home: "/Users/op").dataDirectory == "/Users/op/.local/share/paddock")
        #expect(PaddockPaths(configDirectory: "/Users/op/.config/paddock").dataDirectory == "/Users/op/.local/share/paddock")
    }

    @Test func theKitDeclaresAHostMountAtClaudesSessions() {
        #expect(ClaudeSessions.spec.contains("com.docker.sandbox/host-mount@1"))
        #expect(ClaudeSessions.spec.contains("path: /home/agent/.claude/projects"))
        #expect(ClaudeSessions.mountArgument(folder: "/d/sessions/app/claude") == "/d/sessions/app/claude:/home/agent/.claude/projects")
    }

    @Test func theFolderIsMadeOwnerOnlyAndChecked() throws {
        let folders = try Folders()
        defer { folders.cleanup() }
        let folder = try ClaudeSessions.prepare(project: "app", paths: folders.paths, policy: folders.policy)
        #expect(folder == folders.paths.sessions + "/app/claude")
        let mode = try FileManager.default.attributesOfItem(atPath: folder)[.posixPermissions] as? Int
        #expect(mode == 0o700)
        // Again, as at every create: the same folder, nothing changed.
        #expect(try ClaudeSessions.prepare(project: "app", paths: folders.paths, policy: folders.policy) == folder)
    }

    /// The agent writes this folder: Paddock mounts only a folder it made, never one a link leads to.
    @Test func aLinkInPaddocksPartOfThePathIsRefused() throws {
        let folders = try Folders()
        defer { folders.cleanup() }
        let ssh = folders.root + "/home/.ssh"
        try FileManager.default.createDirectory(atPath: ssh, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: folders.paths.sessions + "/app", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: folders.paths.sessions + "/app/claude", withDestinationPath: ssh)
        #expect(throws: ClaudeSessionsProblem.notPaddocksFolder(folders.paths.sessions + "/app/claude")) {
            try ClaudeSessions.prepare(project: "app", paths: folders.paths, policy: folders.policy)
        }
        // A file where a folder goes is refused too.
        try FileManager.default.removeItem(atPath: folders.paths.sessions + "/app/claude")
        FileManager.default.createFile(atPath: folders.paths.sessions + "/app/claude", contents: Data())
        #expect(throws: ClaudeSessionsProblem.notPaddocksFolder(folders.paths.sessions + "/app/claude")) {
            try ClaudeSessions.prepare(project: "app", paths: folders.paths, policy: folders.policy)
        }
    }

    @Test func aDataFolderInsidePaddocksConfigIsRefused() throws {
        let folders = try Folders()
        defer { folders.cleanup() }
        let paths = PaddockPaths(configDirectory: folders.paths.configDirectory, dataDirectory: folders.paths.configDirectory + "/data")
        #expect(throws: ClaudeSessionsProblem.folder(.overlapsPaddockConfig)) {
            try ClaudeSessions.prepare(project: "app", paths: paths, policy: folders.policy)
        }
    }

    @Test func theMountIsReadFromSbxLs() throws {
        let sandboxes = try JSONCoding.decoder().decode([SbxSandbox].self, from: try Fixture.data("sbx", "ls-claude-sessions.json"))
        let mounts = try #require(sandboxes.first?.mounts)
        #expect(ClaudeSessions.mounted(in: mounts) == "/Users/operator/src/app/claude-sessions")
        #expect(ClaudeSessions.mounted(in: ["/a:/a", "/s:/home/agent/.claude/skills:ro"]) == nil)
        // sbx's own folder, shared by every sandbox with the kit, is read as what it is.
        let shared = "/Users/op/Library/Application Support/com.docker.sandboxes/sandboxes/kit-host-mounts/b0/69"
        #expect(ClaudeSessions.mounted(in: [shared + ":/home/agent/.claude/projects"]) == shared)
        // Older captures have no mounts.
        let older = try JSONCoding.decoder().decode([SbxSandbox].self, from: try Fixture.data("sbx", "ls.json"))
        #expect(older.allSatisfy { $0.mounts == nil })
    }

    @Test func clearingRemovesSessionsAndLinksButNotWhatLinksPointTo() throws {
        let folders = try Folders()
        defer { folders.cleanup() }
        let folder = try ClaudeSessions.prepare(project: "app", paths: folders.paths, policy: folders.policy)
        let outside = folders.root + "/outside"
        try FileManager.default.createDirectory(atPath: outside, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: URL(fileURLWithPath: outside + "/keep.jsonl"))
        try FileManager.default.createDirectory(atPath: folder + "/-src-app", withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: URL(fileURLWithPath: folder + "/-src-app/a.jsonl"))
        try Data(repeating: 1, count: 5).write(to: URL(fileURLWithPath: folder + "/-src-app/b.jsonl"))
        // What an agent can leave there: links out of the folder.
        try FileManager.default.createSymbolicLink(atPath: folder + "/-src-app/out", withDestinationPath: outside)
        try FileManager.default.createSymbolicLink(atPath: folder + "/top", withDestinationPath: outside)

        // Links are not followed when counting either.
        #expect(ClaudeSessions.summary(folder: folder) == ClaudeSessions.Summary(sessions: 2, bytes: 15))
        try ClaudeSessions.clear(folder: folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder).isEmpty)
        #expect(FileManager.default.fileExists(atPath: outside + "/keep.jsonl"))
        #expect(ClaudeSessions.summary(folder: folder) == ClaudeSessions.Summary(sessions: 0, bytes: 0))
        #expect(ClaudeSessions.summary(folder: folders.root + "/missing") == nil)
    }

    @Test func createMountsTheProjectsFolderAndRecordsIt() async throws {
        var setup = try ProjectRunnerTests.Setup(provider: "agent-default")
        defer { setup.cleanup() }
        setup.project.keepsClaudeSessions = true
        let folder = ClaudeSessions.folder(project: "paddock-app", paths: setup.paths)
        listMounts(setup, [ClaudeSessions.mountArgument(folder: folder)])
        let created = try await setup.service.create(setup.project, app: setup.app, models: setup.models)
        let create = try #require(setup.runner.calls.first { $0.first == "create" })
        #expect(create.contains(ClaudeSessions.kitDirectory(in: setup.paths)))
        let mount = try #require(create.firstIndex(of: "--mount"))
        #expect(create[mount + 1] == folder + ":/home/agent/.claude/projects")
        // The mount is read back from the CLI, which lists a kit's host mounts.
        #expect(setup.runner.calls.contains(["ls", "--json"]))
        #expect(created.sandboxClaudeSessions == folder)
        #expect(FileManager.default.fileExists(atPath: ClaudeSessions.kitDirectory(in: setup.paths)))
    }

    /// A project with an sbxenv.yaml gets the kit and the binding in Paddock's overlay (PAD-130):
    /// sbx env create takes no --mount, an environment file's `mounts:` does the same.
    @Test func anSbxenvProjectGetsTheFolderThroughPaddocksOverlay() async throws {
        var setup = try ProjectRunnerTests.Setup(provider: "agent-default")
        defer { setup.cleanup() }
        try SandboxFiles.write(SandboxFiles.files(.init(name: "paddock-app", agent: "claude", workload: "docker.io/sbx/claude:latest")),
                               into: setup.project.folder)
        let environment = try #require(setup.environment)
        setup.project = EnvironmentReview.make(environment, project: setup.project, globalRules: []).approve(setup.project, declined: [])
        setup.project.keepsClaudeSessions = true
        let folder = ClaudeSessions.folder(project: "paddock-app", paths: setup.paths)
        listMounts(setup, [ClaudeSessions.mountArgument(folder: folder)])
        let created = try await setup.service.create(setup.project, app: setup.app, models: setup.models)
        #expect(setup.runner.calls.contains { $0.starts(with: ["env", "create"]) })
        let text = try String(contentsOfFile: PaddockOverlay.path(project: "paddock-app", paths: setup.paths), encoding: .utf8)
        #expect(text.contains("  - \"\(ClaudeSessions.kitDirectory(in: setup.paths))\""))
        #expect(text.contains("mounts:\n  \"/home/agent/.claude/projects\": \"\(folder)\""))
        #expect(created.sandboxClaudeSessions == folder)
        // The project's own file still may not name mounts: only Paddock's overlay binds a folder.
        #expect(ProjectEnvironment.refusedKeys["mounts"] != nil)
    }

    @Test func theOverlayQuotesItsMounts() {
        let overlay = PaddockOverlay(agent: "claude", workspace: "/src/app", mounts: ["/home/agent/.claude/projects": "/d/a \"b\"\nmounts: x"])
        #expect(overlay.yaml.hasSuffix("mounts:\n  \"/home/agent/.claude/projects\": \"/d/a \\\"b\\\"\\nmounts: x\"\n"))
        #expect(!PaddockOverlay(agent: "claude", workspace: "/src/app").yaml.contains("mounts:"))
    }

    @Test func aSandboxWithAnotherSessionsFolderIsRemoved() async throws {
        var setup = try ProjectRunnerTests.Setup(provider: "agent-default")
        defer { setup.cleanup() }
        setup.project.keepsClaudeSessions = true
        let shared = "/Users/op/Library/Application Support/com.docker.sandboxes/sandboxes/kit-host-mounts/b0/69"
        listMounts(setup, [shared + ":/home/agent/.claude/projects"])
        await #expect(throws: ProjectRunError.claudeSessions(.mountedElsewhere(shared))) {
            try await setup.service.create(setup.project, app: setup.app, models: setup.models)
        }
        #expect(setup.runner.calls.last == ["rm", "--force", "--json", "paddock-app"])
    }

    @Test func withoutTheChoiceOrForAnotherAgentNothingIsMounted() async throws {
        let setup = try ProjectRunnerTests.Setup(provider: "agent-default")
        defer { setup.cleanup() }
        let created = try await setup.service.create(setup.project, app: setup.app, models: setup.models)
        #expect(!(setup.runner.calls.first { $0.first == "create" } ?? []).contains("--mount"))
        #expect(created.sandboxClaudeSessions == nil)

        var openCode = try ProjectRunnerTests.Setup(provider: "agent-default", agent: "opencode")
        defer { openCode.cleanup() }
        openCode.project.keepsClaudeSessions = true
        try await openCode.service.create(openCode.project, app: openCode.app, models: openCode.models)
        #expect(!(openCode.runner.calls.first { $0.first == "create" } ?? []).contains("--mount"))
    }

    @Test func syncWantsARecreateWhenTheChoiceAndTheSandboxDiffer() throws {
        let app = AppConfig()
        let sandbox = SbxSandbox(name: "paddock-app", id: "1", agent: "claude", status: "running", lastUsedAt: nil,
                                 workspaces: ["/src/app"], createdAt: Date())
        let snapshot = SandboxSnapshot(sandbox: sandbox, ports: [], rules: [])
        var project = Project(name: "paddock-app", folder: "/src/app", kits: [], sandboxKits: [])
        let ids = { (wanted: String?) in
            SandboxSync.diff(project: project, snapshot: snapshot, globalRules: [], app: app, claudeSessions: wanted).map(\.id)
        }
        #expect(!ids(nil).contains("claude-sessions"))
        #expect(ids("/d/sessions/paddock-app/claude").contains("claude-sessions"))
        project.sandboxClaudeSessions = "/d/sessions/paddock-app/claude"
        #expect(!ids("/d/sessions/paddock-app/claude").contains("claude-sessions"))
        #expect(ids(nil).contains("claude-sessions"))
        // A sandbox Paddock did not create has no record to compare.
        project.sandboxKits = nil
        #expect(!ids(nil).contains("claude-sessions"))
    }

    @Test func theChoiceIsKeptInTheProjectFile() throws {
        var project = Project(name: "paddock-app", folder: "/src/app", keepsClaudeSessions: true)
        project.sandboxClaudeSessions = "/d/sessions/paddock-app/claude"
        let data = try ProjectDirectory.encode(project)
        let read = try ProjectDirectory.decode(file: "paddock-app.json", data: data)
        #expect(read.keepsClaudeSessions && read.sandboxClaudeSessions == "/d/sessions/paddock-app/claude")
        // Files from before: off.
        let old = #"{"version": \#(ProjectList.currentVersion), "id": "\#(UUID())", "name": "a", "folder": "/a", "agent": "claude", "provider": "agent-default"}"#
        #expect(try !ProjectDirectory.decode(file: "a.json", data: Data(old.utf8)).keepsClaudeSessions)
    }

    @Test func newProjectsKeepThemOnlyForClaudeWhenChosen() throws {
        let folders = try Folders()
        defer { folders.cleanup() }
        let folder = folders.root + "/home/src/app"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let app = try AppConfig.load(from: Fixture.data("config", "paddock-full.yaml")).config
        let make = { (agent: String, keeps: Bool) throws -> Bool in
            var draft = ProjectDraft(folder: folder, name: "app", agent: agent, provider: "agent-default")
            draft.keepsClaudeSessions = keeps
            return try NewProject.make(draft, app: app, existing: ProjectList(), sandboxes: [], folderPolicy: folders.policy).keepsClaudeSessions
        }
        #expect(try make("claude", true))
        #expect(try !make("claude", false))
        #expect(try !make("opencode", true))
    }

    private func listMounts(_ setup: ProjectRunnerTests.Setup, _ mounts: [String]) {
        let list = mounts.map { "\"\($0)\"" }.joined(separator: ",")
        let json = #"[{"name":"paddock-app","id":"1","agent":"claude","status":"running","workspaces":[],"mounts":[\#(list)],"created_at":"2026-10-24T10:00:00Z"}]"#
        setup.runner.respond(to: ["ls", "--json"], with: Data(json.utf8))
    }
}
