import Foundation
import Testing
@testable import PaddockCore

/// The Ports panel's rules (backlog doc UI, Ports; CLAUDE.md: Docker API and llmman ports never).
@Suite("Ports")
struct PortsTests {
    let app: AppConfig

    init() throws {
        app = try AppConfig.load(from: Fixture.data("config", "paddock-full.yaml")).config  // publishRange 18000-18999
    }

    func port(_ host: Int, _ sandbox: Int) -> SbxPort { SbxPort(hostIP: "127.0.0.1", hostPort: host, sandboxPort: sandbox) }

    @Test func picksTheSameNumberWhenFreeElseTheLowestFree() throws {
        // What sbx publishes is the only record: another sandbox holds 18000.
        let published = ["paddock-other": [port(18000, 3000)]]
        #expect(try Ports.mapping(for: 18500, sandbox: "paddock-app", published: published, app: app) == .init(sandboxPort: 18500, hostPort: 18500))
        #expect(try Ports.mapping(for: 3000, sandbox: "paddock-app", published: published, app: app) == .init(sandboxPort: 3000, hostPort: 18001))
    }

    @Test func aSandboxPortIsPublishedOnce() throws {
        #expect(throws: PortsError.sandboxPortPublished(3000)) {
            try Ports.mapping(for: 3000, sandbox: "paddock-app", published: ["paddock-app": [port(18000, 3000)]], app: app)
        }
    }

    @Test func checksTypedMappings() throws {
        let published = ["paddock-other": [port(18010, 1)]]
        func check(_ host: Int, _ sandbox: Int = 3000) throws(PortsError) {
            try Ports.check(.init(sandboxPort: sandbox, hostPort: host), sandbox: "paddock-app", published: published, app: app)
        }
        #expect(throws: PortsError.outsidePublishRange(8080, 18000...18999)) { try check(8080) }
        #expect(throws: PortsError.hostPortTaken(18010, by: "paddock-other")) { try check(18010) }
        #expect(throws: PortsError.invalidPort(0)) { try check(18020, 0) }
        try check(18020)
    }

    @Test(arguments: [17434, 17480, 17579, 0, 70000])
    func reservedHostServices(port: Int) {
        #expect(throws: PortsError.self) { try Ports.checkHostService(port, app: app) }
    }

    @Test func hostServicesAreAllowedOtherwise() throws {
        try Ports.checkHostService(5432, app: app)
        try Ports.checkHostService(2375, app: app)  // the Docker API is the operator's call, not a Paddock service
    }

    func snapshot(ports: [SbxPort], rules: String = "") throws -> SandboxSnapshot {
        let sandbox = try JSONCoding.decode(SbxSandbox.self, from: Data(#"{"name":"paddock-app","id":"1","agent":"claude","status":"running","workspaces":["/a"],"created_at":"2026-10-24T10:00:00Z"}"#.utf8))
        let list = try JSONCoding.decode(SbxPolicyList.self, from: Data(#"{"rules":[\#(rules)]}"#.utf8))
        return SandboxSnapshot(sandbox: sandbox, ports: ports, rules: list.rules)
    }

    @Test func hostServicesAreTheSandboxsOwnLoopbackAllows() throws {
        let allow = #"{"id":"a","name":"a","policy_id":"p","scope":"sandbox:paddock-app","applies_to":"sandbox:paddock-app","resource_type":"network","decision":"allow","resources":["localhost:5432"],"origin":"scoped","layer":"local","status":"active","editable":true,"provenance":{"created_via":"added"},"actions":[]}"#
        let sandbox = try snapshot(ports: [port(18000, 3000)], rules: allow)
        #expect(Ports.hostServices(sandbox, app: app) == [5432])
    }

    @Test func specAndURLAreLoopback() {
        let mapping = Project.PortMapping(sandboxPort: 3000, hostPort: 18001)
        #expect(Ports.spec(mapping) == "127.0.0.1:18001:3000")
        #expect(Ports.url(mapping) == "http://localhost:18001")
    }

    @Test func updateReplacesAndStillChecks() throws {
        var list = try ProjectList(validating: [Project(name: "paddock-a", folder: "/a"), Project(name: "paddock-b", folder: "/b", gatewayPort: 17480)])
        var a = try #require(list.project(named: "paddock-a"))
        a.cloneMode = true
        try list.update(a)
        #expect(list.project(named: "paddock-a")?.cloneMode == true)
        a.gatewayPort = 17480
        #expect(throws: ProjectStoreError.duplicateGatewayPort(17480)) { try list.update(a) }
        #expect(list.project(named: "paddock-a")?.gatewayPort == nil)  // unchanged after a failed update
    }
}

@Suite("ProjectRunner ports")
struct ProjectRunnerPortsTests {
    let sbxURL = URL(fileURLWithPath: "/opt/homebrew/bin/sbx")
    let project = Project(name: "paddock-app", folder: "/a")

    func rules(_ json: String) -> Data { Data(#"{"rules":[\#(json)]}"#.utf8) }

    func rule(id: String, decision: String, resources: [String], scope: String = "sandbox:paddock-app", editable: Bool = true) -> String {
        let list = resources.map { "\"\($0)\"" }.joined(separator: ",")
        // swiftlint:disable:next line_length
        return #"{"id":"\#(id)","name":"\#(id)","policy_id":"p","scope":"\#(scope)","applies_to":"\#(scope)","resource_type":"network","decision":"\#(decision)","resources":[\#(list)],"origin":"scoped","layer":"local","status":"active","editable":\#(editable),"provenance":{"created_via":"added"},"actions":["net:connect:tcp"]}"#
    }

    func runner(_ policyJSON: String) -> (FakeRunner, ProjectRunner) {
        let fake = FakeRunner()
        fake.succeedByDefault = true
        fake.respond(to: ["policy", "ls", "paddock-app", "--json"], with: rules(policyJSON))
        return (fake, ProjectRunner(sbx: SbxService(runner: fake, sbx: sbxURL), paths: PaddockPaths(configDirectory: "/tmp/paddock")))
    }

    @Test func publishAndUnpublishOnLoopback() async throws {
        let (fake, runner) = runner("")
        fake.respond(to: ["ports", "paddock-app", "--json"], with: Data("[]".utf8))
        try await runner.publish(.init(sandboxPort: 3000, hostPort: 18001), for: project)
        try await runner.unpublish(hostIP: "127.0.0.1", hostPort: 18001, sandboxPort: 3000, for: project)
        #expect(fake.calls == [["ports", "paddock-app", "--json"],
                               ["ports", "paddock-app", "--publish", "127.0.0.1:18001:3000"],
                               ["ports", "paddock-app", "--unpublish", "127.0.0.1:18001:3000"]])
    }

    @Test func removingASandboxSbxNoLongerHasIsDone() async throws {
        let (fake, runner) = runner("")
        fake.respond(to: ["rm", "--force", "--json", "paddock-app"], with: Data(), exitCode: 1,
                     stderr: "error: sandbox 'paddock-app' not found\n  try: sbx ls")
        try await runner.remove(project)
        fake.respond(to: ["rm", "--force", "--json", "paddock-app"], with: Data(), exitCode: 1, stderr: "error: daemon not running")
        await #expect(throws: SbxError.self) { try await runner.remove(project) }
    }

    @Test func publishingWhatSbxAlreadyPublishesIsDone() async throws {
        // Otherwise sbx answers 409 Conflict: port 127.0.0.1:18000/tcp4 is already published
        let (fake, runner) = runner("")
        fake.respond(to: ["ports", "paddock-app", "--json"], with: try Fixture.data("sbx", "ports.json"))  // 127.0.0.1:18000 -> 8000
        try await runner.publish(.init(sandboxPort: 8000, hostPort: 18000), for: project)
        #expect(fake.calls == [["ports", "paddock-app", "--json"]])
    }

    @Test func aHostPortAnotherSandboxPublishesNamesIt() async throws {
        let (fake, runner) = runner("")
        fake.respond(to: ["ports", "paddock-app", "--json"], with: Data("[]".utf8))
        fake.respond(to: ["ports", "paddock-app", "--publish", "127.0.0.1:18000:3000"], with: Data(), exitCode: 1,
                     stderr: "error: publish ports: request failed: 409 Conflict")
        fake.respond(to: ["ls", "--json"], with: try Fixture.data("sbx", "ls.json"))
        for name in ["project-a", "project-c", "project-d", "project-e"] {
            fake.respond(to: ["ports", name, "--json"], with: Data("[]".utf8))
        }
        fake.respond(to: ["ports", "project-b", "--json"], with: try Fixture.data("sbx", "ports.json"))  // holds 18000
        await #expect(throws: PortsError.hostPortTaken(18000, by: "project-b")) {
            try await runner.publish(.init(sandboxPort: 3000, hostPort: 18000), for: project)
        }
    }

    @Test func allowingAHostServiceRemovesOnlyItsOwnDenies() async throws {
        let json = [
            rule(id: "d1", decision: "deny", resources: ["localhost:5432"]),
            rule(id: "d2", decision: "deny", resources: ["localhost:5432", "github.com:443"]),  // would remove more
            rule(id: "d3", decision: "deny", resources: ["localhost:5432"], scope: "global"),
            rule(id: "d4", decision: "deny", resources: ["localhost:6379"]),
        ].joined(separator: ",")
        let (fake, runner) = runner(json)
        try await runner.allowHostService(5432, for: project)
        #expect(fake.calls.filter { $0.starts(with: ["policy", "rm"]) } == [["policy", "rm", "network", "--id", "d1", "--sandbox", "paddock-app", "--force"]])
        #expect(fake.calls.last == ["policy", "allow", "network", "--sandbox", "paddock-app", "localhost:5432"])
    }

    @Test func removingAHostServiceDeniesItAgain() async throws {
        let (fake, runner) = runner(rule(id: "a1", decision: "allow", resources: ["localhost:5432"]))
        try await runner.removeHostService(5432, for: project)
        #expect(fake.calls.contains(["policy", "rm", "network", "--id", "a1", "--sandbox", "paddock-app", "--force"]))
        #expect(fake.calls.last == ["policy", "deny", "network", "--sandbox", "paddock-app", "localhost:5432,host.docker.internal:5432"])
    }

    @Test func createPublishesApprovedPortsOnLoopback() throws {
        let launch = AgentLaunchPlanner(paths: PaddockPaths(configDirectory: "/tmp/paddock"))
            .create(name: "paddock-app", agent: .claudeCode, folder: "/a",
                    policy: SandboxPolicyPlan(denies: [], allows: [], httpAllows: []),
                    gateway: nil, publish: [.init(sandboxPort: 3000, hostPort: 18001)])
        let index = try #require(launch.arguments.firstIndex(of: "-p"))
        #expect(launch.arguments[index + 1] == "127.0.0.1:18001:3000")
    }
}
