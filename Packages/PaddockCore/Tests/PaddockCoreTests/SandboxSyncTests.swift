import Foundation
import Testing
@testable import PaddockCore

/// sbx is the only store for ports and rules; the few differences left are Paddock's own
/// (backlog doc App config, Sync).
@Suite("SandboxSync")
struct SandboxSyncTests {
    let app: AppConfig
    let globals: [SbxPolicyRule]
    let sandboxRules: [SbxPolicyRule]

    init() throws {
        app = try AppConfig.load(from: Fixture.data("config", "paddock-full.yaml")).config
        globals = try Fixture.decode(SbxPolicyList.self, "sbx", "policy-ls.json").rules
        sandboxRules = try Fixture.decode(SbxPolicyList.self, "sbx", "policy-ls-sandbox.json").rules  // sandbox m0-claude
    }

    func sandbox(_ name: String = "m0-claude", agent: String = "claude", folder: String = "/Users/op/src/app") throws -> SbxSandbox {
        let json = #"{"name":"\#(name)","id":"1","agent":"\#(agent)","status":"running","workspaces":["\#(folder)"],"created_at":"2026-10-24T10:00:00Z"}"#
        return try JSONCoding.decode(SbxSandbox.self, from: Data(json.utf8))
    }

    func snapshot(ports: [SbxPort] = [], agent: String = "claude", folder: String = "/Users/op/src/app") throws -> SandboxSnapshot {
        SandboxSnapshot(sandbox: try sandbox(agent: agent, folder: folder), ports: ports, rules: sandboxRules + globals)
    }

    @Test func otherExtraFoldersMeanRecreate() throws {
        var project = Project(name: "m0-claude", folder: "/Users/op/src/app")
        let json = #"{"name":"m0-claude","id":"1","agent":"claude","status":"running","workspaces":["/Users/op/src/app","/Users/op/src/lib:ro"],"created_at":"2026-10-24T10:00:00Z"}"#
        let snap = SandboxSnapshot(sandbox: try JSONCoding.decode(SbxSandbox.self, from: Data(json.utf8)), ports: [], rules: sandboxRules + globals)
        func extraItem() -> SyncItem? {
            SandboxSync.diff(project: project, snapshot: snap, globalRules: globals, app: app)
                .first { $0.id == "extra-folders" }
        }
        #expect(extraItem()?.apply == .recreate)  // the project names none
        project.extraFolders = [.init(path: "/Users/op/src/lib")]
        #expect(extraItem() == nil)
        project.extraFolders = [.init(path: "/Users/op/src/lib", readOnly: false)]
        #expect(extraItem()?.apply == .recreate)  // writable now
        // a sandbox with only the project folder and a project with none: nothing
        project.extraFolders = []
        #expect(SandboxSync.diff(project: project, snapshot: try snapshot(), globalRules: globals, app: app)
            .allSatisfy { $0.id != "extra-folders" })
    }

    @Test func aConfirmedEnvironmentTheSandboxLacksMeansRecreate() throws {
        var project = Project(name: "m0-claude", folder: "/Users/op/src/app")
        func item() throws -> SyncItem? {
            SandboxSync.diff(project: project, snapshot: try snapshot(), globalRules: globals, app: app).first { $0.id == "environment" }
        }
        #expect(try item() == nil)  // no sbxenv.yaml
        project.approvedEnvironment = "b"
        #expect(try item()?.apply == .recreate)  // created without it
        #expect(try item()?.summary.contains("without") == true)
        project.sandboxEnvironment = "a"
        #expect(try item()?.summary.contains("changed") == true)
        project.sandboxEnvironment = "b"
        #expect(try item() == nil)
    }

    @Test func noSandboxMeansCreate() {
        let items = SandboxSync.diff(project: Project(name: "paddock-app", folder: "/a"), snapshot: nil, globalRules: globals, app: app)
        #expect(items.map(\.apply) == [.create])
    }

    @Test func snapshotKeepsOnlyItsOwnRules() throws {
        let snap = try snapshot()
        #expect(snap.rules.allSatisfy { $0.sandboxScope == "m0-claude" })
        // the claude kit's provisioned allows are sbx's, not the operator's
        #expect(snap.added("allow").allSatisfy { $0.createdVia != "provisioned" })
    }

    @Test func adoptWritesOnlyWhatSbxCannotHold() throws {
        let project = SandboxSync.adopt(try snapshot(ports: [SbxPort(hostIP: "127.0.0.1", hostPort: 18000, sandboxPort: 8000)]), app: app)
        #expect(project.name == "m0-claude")
        #expect(project.agent == "claude")  // the paddock.yaml agent whose sbx agent matches
        #expect(project.folder == FolderPolicy.canonical("/Users/op/src/app"))
        #expect(project.provider == app.defaults.provider)
    }

    @Test func unsavedProjectsKeepSbxsID() throws {
        let sandbox = try JSONCoding.decode(SbxSandbox.self, from: Data(#"{"name":"example","id":"12557394-b7c9-4190-bcdc-d64840acfa0c","agent":"example","status":"running","workspaces":["/Users/op/src/example"],"created_at":"2026-10-24T10:00:00Z"}"#.utf8))
        let first = SandboxSync.unsaved(sandbox, app: app)
        #expect(first.id == UUID(uuidString: "12557394-b7c9-4190-bcdc-d64840acfa0c"))
        #expect(first == SandboxSync.unsaved(sandbox, app: app))
        #expect(SandboxSync.stableID("x") == SandboxSync.stableID("x") && SandboxSync.stableID("x") != SandboxSync.stableID("y"))
    }

    @Test func kitSandboxesKeepTheirAgentName() throws {
        let project = SandboxSync.adopt(try snapshot(agent: "example"), app: app)
        #expect(project.agent == "example")
        let items = SandboxSync.diff(project: project, snapshot: try snapshot(agent: "example"), globalRules: globals, app: app)
        #expect(!items.contains { $0.id == "agent" })
    }

    @Test func missingDeniesForPaddocksServicesAreOneItem() throws {
        let project = SandboxSync.adopt(try snapshot(), app: app)
        let items = SandboxSync.diff(project: project, snapshot: try snapshot(), globalRules: globals, app: app)
        let denies = try #require(items.first { $0.id == "network-denies" })
        guard case .deny(let resources)? = denies.apply else {
            Issue.record("expected a deny apply")
            return
        }
        // The fixture sandbox denies localhost:17434, not host.docker.internal:17434.
        #expect(resources == ["host.docker.internal:17434"])
        #expect(denies.summary.contains("host.docker.internal:17434"))
        // sbx's global allows stay: no deny for them, the Docker API included.
        #expect(!resources.contains("localhost:2375") && !resources.contains("localhost:5432"))
    }

    @Test func aDifferentFolderIsARecreate() throws {
        let project = SandboxSync.adopt(try snapshot(), app: app)
        let moved = try snapshot(folder: "/Users/op/src/other")
        let item = try #require(SandboxSync.diff(project: project, snapshot: moved, globalRules: globals, app: app).first { $0.id == "folder" })
        #expect(item.apply == .recreate && item.applyIsDestructive)
    }

    @Test func theProjectsHostsFeedThePlan() throws {
        let project = Project(name: "paddock-app", folder: "/a")
        let plan = try ProjectRunner.plan(project, usesGateway: false, allowed: ["github.com:443", "api.example.com"],
                                          denied: ["ads.example.com"], globalRules: globals, app: app)
        #expect(plan.allows == ["api.example.com"])  // github.com:443 is allowed globally already
        #expect(plan.denies == ["localhost:17434", "host.docker.internal:17434", "ads.example.com"])
    }

    @Test func aSandboxAllowForLlmmanDoesNotBreakThePlan() throws {
        // It shows as "not denied" under Ports; the plan still covers everything else.
        let allow = #"{"id":"a","name":"a","policy_id":"p","scope":"sandbox:m0-claude","applies_to":"sandbox:m0-claude","resource_type":"network","decision":"allow","resources":["localhost:17434","api.example.com"],"origin":"scoped","layer":"local","status":"active","editable":true,"provenance":{"created_via":"added"},"actions":[]}"#
        let rules = try JSONCoding.decode(SbxPolicyList.self, from: Data(#"{"rules":[\#(allow)]}"#.utf8)).rules
        let snap = SandboxSnapshot(sandbox: try sandbox(), ports: [], rules: rules)
        #expect(HostRules.plannedAllows(snap, app: app) == ["api.example.com"])
        let items = SandboxSync.diff(project: SandboxSync.adopt(snap, app: app), snapshot: snap, globalRules: globals, app: app)
        #expect(!items.contains { $0.id == "network-plan" })
    }

    @Test func applyBatchesDenies() async throws {
        let fake = FakeRunner()
        fake.succeedByDefault = true
        let runner = ProjectRunner(sbx: SbxService(runner: fake, sbx: URL(fileURLWithPath: "/sbx")), paths: PaddockPaths(configDirectory: "/tmp/p"))
        let resources = (1...85).map { "host\($0).example:443" }
        try await runner.apply(.deny(resources), for: Project(name: "claude-plane", folder: "/a"), app: app, models: nil)
        #expect(fake.calls.count == 3)
        #expect(fake.calls.first?.prefix(5) == ["policy", "deny", "network", "--sandbox", "claude-plane"])
    }
}

@Suite("Snapshots")
struct SnapshotTests {
    func sandbox() throws -> SbxSandbox {
        try JSONCoding.decode(SbxSandbox.self, from: Data(#"{"name":"example","id":"1","agent":"example","status":"running","workspaces":["/a"],"created_at":"2026-10-24T10:00:00Z"}"#.utf8))
    }

    func runner(_ fake: FakeRunner) -> ProjectRunner {
        ProjectRunner(sbx: SbxService(runner: fake, sbx: URL(fileURLWithPath: "/sbx")), paths: PaddockPaths(configDirectory: "/tmp/p"))
    }

    @Test func portsSurviveAFailingRulesCall() async throws {
        let fake = FakeRunner()
        fake.respond(to: ["ports", "example", "--json"], with: try Fixture.data("sbx", "ports.json"))
        let snapshot = try await runner(fake).snapshot(of: try sandbox())
        #expect(snapshot.ports.map(\.hostPort) == [18000])
        #expect(snapshot.rules.isEmpty)
    }

    @Test func rulesSurviveAFailingPortsCall() async throws {
        let fake = FakeRunner()
        fake.respond(to: ["policy", "ls", "example", "--json"], with: Data(#"{"rules":[]}"#.utf8))
        let snapshot = try await runner(fake).snapshot(of: try sandbox())
        #expect(snapshot.ports.isEmpty)
    }

    @Test func bothFailingIsAnError() async throws {
        await #expect(throws: SbxError.self) { _ = try await runner(FakeRunner()).snapshot(of: try sandbox()) }
    }
}
