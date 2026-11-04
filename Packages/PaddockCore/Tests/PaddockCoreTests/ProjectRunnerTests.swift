import Foundation
import Testing
@testable import PaddockCore

/// Create, start, stop, and remove through sbx, with the ownership and approval checks.
@Suite("ProjectRunner")
struct ProjectRunnerTests {
    struct Setup {
        let root: String
        let paths: PaddockPaths
        let runner = FakeRunner()
        let app: AppConfig
        var project: Project
        /// llmman's store: the fixture's local model.
        var models: [String]? = ["hf.co/unsloth/Qwen3.5-35B-A3B-GGUF:latest"]

        init(provider: String = "local_qwen", agent: String = "claude", gatewayRule: Bool = true) throws {
            root = FolderPolicy.canonical(NSTemporaryDirectory()) + "/paddock-runner-" + UUID().uuidString
            let folder = root + "/src/app"
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            paths = PaddockPaths(configDirectory: root + "/.config/paddock")
            app = try AppConfig.load(from: Fixture.data("config", "paddock-full.yaml")).config
            project = Project(name: "paddock-app", folder: folder, agent: agent, provider: provider,
                              gatewayPort: provider == "local_qwen" ? 17480 : nil)
            runner.succeedByDefault = true
            runner.respond(to: ["policy", "ls", "--json"], with: try Fixture.data("sbx", "policy-ls.json"))
            let sandboxRules = String(decoding: try Fixture.data("sbx", "policy-ls-sandbox.json"), as: UTF8.self)
                .replacingOccurrences(of: "m0-claude", with: "paddock-app")
            let rules = gatewayRule ? sandboxRules : sandboxRules.replacingOccurrences(of: "\"http\"", with: "\"other\"")
            runner.respond(to: ["policy", "ls", "paddock-app", "--json"], with: Data(rules.utf8))
            listSandbox(status: "stopped")
        }

        /// `sbx ls --json` with paddock-app in the given state.
        func listSandbox(status: String) {
            let json = #"[{"name":"paddock-app","id":"1","agent":"claude","status":"\#(status)","workspaces":[],"created_at":"2026-10-24T10:00:00Z"}]"#
            runner.respond(to: ["ls", "--json"], with: Data(json.utf8))
        }

        var service: ProjectRunner {
            ProjectRunner(sbx: SbxService(runner: runner, sbx: URL(fileURLWithPath: "/opt/homebrew/bin/sbx")), paths: paths)
        }

        func cleanup() { try? FileManager.default.removeItem(atPath: root) }

        /// The project's sbxenv.yaml as the runner reads it.
        var environment: ProjectEnvironment? {
            ProjectEnvironment.read(folder: project.folder, context: .init(
                folderPolicy: FolderPolicy(home: FileManager.default.homeDirectoryForCurrentUser.path,
                                           paddockConfigDirectory: paths.configDirectory), app: app))
        }
    }

    @Test func createsALocalModelClaudeSandboxLikeTheTrial() async throws {
        let setup = try Setup()
        defer { setup.cleanup() }
        try await setup.service.create(setup.project, app: setup.app, models: setup.models)
        let calls = setup.runner.calls
        let create = try #require(calls.first { $0.first == "create" })
        #expect(create.contains("ANTHROPIC_BASE_URL=http://host.docker.internal:17480"))
        #expect(Array(create.suffix(2)) == ["claude", setup.project.folder])
        // sbx's global rules stay in effect; Paddock denies only its own services: llmman's port
        #expect(create.filter { $0 == "--deny-network" }.count == 2)
        #expect(create.contains("localhost:17434") && create.contains("host.docker.internal:17434"))
        #expect(!create.contains("localhost:5432") && !create.contains("github.com:443"))
        #expect(calls.contains(["policy", "allow", "network", "--sandbox", "paddock-app", "localhost:17480", "--method", "GET,POST", "--path", "/v1/**"]))
        #expect(calls.last == ["policy", "ls", "paddock-app", "--json"])  // the rule is checked after adding it
        #expect(create.contains("ANTHROPIC_AUTH_TOKEN=paddock") && !create.contains("--kit"))
    }

    @Test func anOpenCodeProjectGetsItsConfigFileAtCreateAndBeforeEachSession() async throws {
        let setup = try Setup(agent: "opencode")
        defer { setup.cleanup() }
        try await setup.service.create(setup.project, app: setup.app, models: setup.models)
        let writes = { setup.runner.calls.filter { Array($0.prefix(4)) == ["exec", "paddock-app", "sh", "-c"] } }
        #expect(writes().count == 1)
        try await setup.service.prepareAgentSession(setup.project, app: setup.app)
        #expect(writes().count == 2)
        // a Claude Code or default-provider project has no OpenCode config
        let claude = try Setup()
        defer { claude.cleanup() }
        try await claude.service.prepareAgentSession(claude.project, app: claude.app)
        #expect(claude.runner.calls.isEmpty)
    }

    /// A project with an sbxenv.yaml: Paddock's overlay, `sbx env create`, then its denies and the
    /// hosts the operator declined (backlog doc Project config file).
    @Test func anSbxenvProjectIsCreatedWithPaddocksOverlay() async throws {
        var setup = try Setup()
        defer { setup.cleanup() }
        try SandboxFiles.write(SandboxFiles.files(.init(name: "paddock-app", agent: "claude", workload: "docker.io/sbx/claude:latest",
                                                        allow: ["api.example.com", "ads.example.com"])), into: setup.project.folder)
        let environment = try #require(setup.environment)
        let review = EnvironmentReview.make(environment, project: setup.project, globalRules: [])
        #expect(review.needsApproval && review.canApprove)
        setup.project = review.approve(setup.project, declined: ["ads.example.com", "not-asked.example.com"])
        #expect(setup.project.declinedHosts == ["ads.example.com"])
        let created = try await setup.service.create(setup.project, app: setup.app, models: setup.models)
        let overlay = PaddockOverlay.path(project: "paddock-app", paths: setup.paths)
        #expect(setup.runner.calls.contains(["env", "create", setup.project.folder + "/sbxenv.yaml", overlay,
                                             "--name", "paddock-app", "--skip-host-commands", "--force"]))
        #expect(!setup.runner.calls.contains { $0.first == "create" })
        // Paddock's denies (llmman's port) and the declined host follow, then the gateway rule
        let denies = setup.runner.calls.filter { $0.starts(with: ["policy", "deny", "network", "--sandbox", "paddock-app"]) }
        #expect(denies.contains { $0.last?.contains("localhost:17434") == true && $0.last?.contains("ads.example.com") == true })
        #expect(setup.runner.calls.contains(["policy", "allow", "network", "--sandbox", "paddock-app", "localhost:17480",
                                             "--method", "GET,POST", "--path", "/v1/**"]))
        // the overlay: the agent, the folder, and the gateway's environment, never in the project
        let text = try String(contentsOfFile: overlay, encoding: .utf8)
        #expect(text.contains("workspace: \"\(FolderPolicy.canonical(setup.project.folder))\""))
        #expect(text.contains("\"ANTHROPIC_AUTH_TOKEN\": \"paddock\"") && text.contains("\"ANTHROPIC_BASE_URL\""))
        #expect(created.sandboxEnvironment == environment.fingerprint)
    }

    @Test func anSbxenvFileNeedsConfirmationAndCleanChecks() async throws {
        var setup = try Setup()
        defer { setup.cleanup() }
        try SandboxFiles.write(SandboxFiles.files(.init(name: "paddock-app", agent: "claude", workload: "docker.io/sbx/claude:latest")),
                               into: setup.project.folder)
        await #expect(throws: ProjectRunError.environmentNeedsApproval) {
            try await setup.service.create(setup.project, app: setup.app, models: setup.models)
        }
        // confirmed, then changed: confirm again
        setup.project.approvedEnvironment = try #require(setup.environment).fingerprint
        try Data("schemaVersion: \"1\"\nagent: claude\nenv: { A: b }\n".utf8)
            .write(to: URL(fileURLWithPath: setup.project.folder + "/sbxenv.yaml"))
        await #expect(throws: ProjectRunError.environmentNeedsApproval) {
            try await setup.service.create(setup.project, app: setup.app, models: setup.models)
        }
        // refused entries stop it before anything else
        try Data("schemaVersion: \"1\"\nagent: claude\nlifecycle: { initialize: [{ command: touch x }] }\n".utf8)
            .write(to: URL(fileURLWithPath: setup.project.folder + "/sbxenv.yaml"))
        await #expect(throws: ProjectRunError.self) { try await setup.service.create(setup.project, app: setup.app, models: setup.models) }
        #expect(!setup.runner.calls.contains { $0.first == "create" || $0.first == "env" })
        // a sandbox runs on as it is: starting it needs no confirmation
        try await setup.service.start(setup.project, app: setup.app, models: setup.models)
        #expect(setup.runner.calls.contains(["run", "--detach", "--name", "paddock-app"]))
    }

    @Test func aFileChangedWhileSbxCreatesTheSandboxRemovesIt() async throws {
        var setup = try Setup()
        defer { setup.cleanup() }
        try SandboxFiles.write(SandboxFiles.files(.init(name: "paddock-app", agent: "claude", workload: "docker.io/sbx/claude:latest")),
                               into: setup.project.folder)
        setup.project.approvedEnvironment = try #require(setup.environment).fingerprint
        let file = setup.project.folder + "/sbxenv.yaml"
        setup.runner.whenCalled({ $0.starts(with: ["env", "create"]) }) {
            try? Data("schemaVersion: \"1\"\nagent: claude\nenv: { A: swapped }\n".utf8).write(to: URL(fileURLWithPath: file))
        }
        await #expect(throws: ProjectRunError.environmentChangedDuringCreate) {
            try await setup.service.create(setup.project, app: setup.app, models: setup.models)
        }
        #expect(setup.runner.calls.contains(["rm", "--force", "--json", "paddock-app"]))
    }

    @Test func onlyValidSandboxNames() async throws {
        var setup = try Setup()
        defer { setup.cleanup() }
        setup.project.name = "-bad name"
        await #expect(throws: ProjectRunError.invalidSandboxName("-bad name")) { try await setup.service.remove(setup.project) }
        await #expect(throws: ProjectRunError.invalidSandboxName("-bad name")) { try await setup.service.stop(setup.project) }
        #expect(setup.runner.calls.isEmpty)
    }

    @Test func kitAgentsCannotBeRecreated() async throws {
        var setup = try Setup(provider: "agent-default")
        defer { setup.cleanup() }
        setup.project.agent = "example"
        await #expect(throws: ProjectRunError.cannotRecreate(agent: "example")) { try await setup.service.create(setup.project, app: setup.app, models: setup.models) }
        // but it can be managed
        try await setup.service.stop(setup.project)
        #expect(setup.runner.calls == [["stop", "paddock-app"], ["ls", "--json"]])
    }

    @Test func aLocalModelMustBeInLlmmansStore() async throws {
        var setup = try Setup()
        defer { setup.cleanup() }
        setup.models = ["qwen3:8b"]
        await #expect(throws: ProjectRunError.modelNotInstalled("hf.co/unsloth/Qwen3.5-35B-A3B-GGUF:latest")) {
            try await setup.service.create(setup.project, app: setup.app, models: setup.models)
        }
        await #expect(throws: ProjectRunError.modelNotInstalled("hf.co/unsloth/Qwen3.5-35B-A3B-GGUF:latest")) {
            try await setup.service.start(setup.project, app: setup.app, models: setup.models)
        }
        // llmman did not answer: no check, no start
        await #expect(throws: ProjectRunError.modelsUnknown) { try await setup.service.start(setup.project, app: setup.app, models: nil) }
        #expect(setup.runner.calls.isEmpty)
        // the agent's default provider needs no model
        let hosted = try Setup(provider: "agent-default")
        defer { hosted.cleanup() }
        try await hosted.service.start(hosted.project, app: hosted.app, models: nil)
    }

    @Test func startChecksTheGatewayRuleThenRunsDetached() async throws {
        let setup = try Setup()
        defer { setup.cleanup() }
        try await setup.service.start(setup.project, app: setup.app, models: setup.models)
        #expect(setup.runner.calls == [["policy", "ls", "paddock-app", "--json"], ["run", "--detach", "--name", "paddock-app"]])
    }

    @Test func startReAddsAMissingRuleAndFailsIfSbxStillLacksIt() async throws {
        let setup = try Setup(gatewayRule: false)
        defer { setup.cleanup() }
        await #expect(throws: ProjectRunError.gatewayRuleMissing("paddock-app")) { try await setup.service.start(setup.project, app: setup.app, models: setup.models) }
        #expect(setup.runner.calls.contains { $0.starts(with: ["policy", "allow", "network", "--sandbox", "paddock-app", "localhost:17480"]) })
        #expect(!setup.runner.calls.contains { $0.first == "run" })
    }

    @Test func stopAndRemove() async throws {
        let setup = try Setup()
        defer { setup.cleanup() }
        try await setup.service.stop(setup.project)
        try await setup.service.remove(setup.project)
        #expect(setup.runner.calls == [["stop", "paddock-app"], ["ls", "--json"], ["rm", "--force", "--json", "paddock-app"]])
    }

    @Test func aStopThatLeavesTheSandboxRunningIsAnError() async throws {
        let setup = try Setup()
        defer { setup.cleanup() }
        setup.listSandbox(status: "running")
        await #expect(throws: ProjectRunError.stillRunning("paddock-app")) { try await setup.service.stop(setup.project) }
    }
}

@Suite("GatewayHost", .serialized)
struct GatewayHostTests {
    let app: AppConfig

    init() throws {
        app = try AppConfig.load(from: Fixture.data("config", "paddock-full.yaml")).config
    }

    func port() -> Int { Int.random(in: 41000...48999) }

    @Test func oneListenerPerLocalModelProject() async throws {
        let host = GatewayHost(models: app.models) { _ in }
        let local = Project(name: "paddock-a", folder: "/a", provider: "local_qwen", gatewayPort: port())
        var other = Project(name: "paddock-b", folder: "/b", provider: "agent-default")
        #expect(await host.sync([local, other], app: app).isEmpty)
        #expect(await host.listeners[local.id]?.model == "hf.co/unsloth/Qwen3.5-35B-A3B-GGUF:latest")
        #expect(await host.listeners[other.id] == nil)

        // switching a project away from the local model stops its listener
        other.provider = "local_qwen"
        other.gatewayPort = local.gatewayPort.map { $0 + 1 }
        _ = await host.sync([other], app: app)
        #expect(await host.listeners.keys.sorted() == [other.id])
        await host.shutdown()
    }

    @Test func anInstalledModelWithoutASectionGetsAListener() async throws {
        let host = GatewayHost(models: app.models) { _ in }
        let project = Project(name: "paddock-a", folder: "/a", provider: AppConfig.localProviderName(model: "qwen3:8b"), gatewayPort: port())
        #expect(await host.sync([project], app: app).isEmpty)
        #expect(await host.listeners[project.id]?.model == "qwen3:8b")
        await host.shutdown()
    }

    @Test func aTakenPortIsReported() async throws {
        let first = GatewayHost(models: app.models) { _ in }
        let second = GatewayHost(models: app.models) { _ in }
        let shared = port()
        _ = await first.sync([Project(name: "paddock-a", folder: "/a", provider: "local_qwen", gatewayPort: shared)], app: app)
        let failures = await second.sync([Project(name: "paddock-b", folder: "/b", provider: "local_qwen", gatewayPort: shared)], app: app)
        #expect(failures["paddock-b"]?.contains("in use") == true)
        await first.shutdown()
        await second.shutdown()
    }
}
