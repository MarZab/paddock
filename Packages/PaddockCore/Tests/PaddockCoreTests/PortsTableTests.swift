import Foundation
import Testing
@testable import PaddockCore

@Suite("PortsTable")
struct PortsTableTests {
    let app: AppConfig
    let globals: [SbxPolicyRule]

    init() throws {
        app = try AppConfig.load(from: Fixture.data("config", "paddock-full.yaml")).config
        globals = try Fixture.decode(SbxPolicyList.self, "sbx", "policy-ls.json").rules     // allows localhost:5432 globally
    }

    func snapshot(_ name: String, ports: [SbxPort], rules: String = "") throws -> SandboxSnapshot {
        let sandbox = try JSONCoding.decode(SbxSandbox.self, from: Data(#"{"name":"\#(name)","id":"1","agent":"claude","status":"running","workspaces":["/a"],"created_at":"2026-10-24T10:00:00Z"}"#.utf8))
        let list = try JSONCoding.decode(SbxPolicyList.self, from: Data(#"{"rules":[\#(rules)]}"#.utf8))
        return SandboxSnapshot(sandbox: sandbox, ports: ports, rules: list.rules)
    }

    func port(_ host: Int, _ sandbox: Int, ip: String = "127.0.0.1") throws -> SbxPort {
        try JSONCoding.decode(SbxPort.self, from: Data(#"{"host_ip":"\#(ip)","host_port":\#(host),"sandbox_port":\#(sandbox),"protocol":"tcp4"}"#.utf8))
    }

    func deny(_ resource: String) -> String {
        #"{"id":"d","name":"d","policy_id":"p","scope":"sandbox:paddock-app","applies_to":"sandbox:paddock-app","resource_type":"network","decision":"deny","resources":["\#(resource)"],"origin":"scoped","layer":"local","status":"active","editable":true,"provenance":{"created_via":"added"},"actions":[]}"#
    }

    func allow(_ resource: String) -> String {
        deny(resource).replacingOccurrences(of: "\"deny\"", with: "\"allow\"")
    }

    @Test func everyPortWithItsState() throws {
        let project = Project(name: "paddock-app", folder: "/a")
        let snapshots = [
            "paddock-app": try snapshot("paddock-app", ports: [try port(18001, 3000), try port(18500, 9000)], rules: allow("localhost:6379")),
            "claude-plane": try snapshot("claude-plane", ports: [try port(18800, 5173)]),
        ]
        let rows = PortsTable.rows(projects: [project], snapshots: snapshots, sandboxes: ["paddock-app", "claude-plane"],
                                   globalRules: globals, app: app)
        func state(_ sandbox: String, _ kind: PortRow.Kind, host: Int? = nil, inside: Int? = nil) -> PortRow.State? {
            rows.first { $0.sandbox == sandbox && $0.kind == kind && (host == nil || $0.hostPort == host) && (inside == nil || $0.sandboxPort == inside) }?.state
        }
        // What sbx has is in effect, however it got there.
        #expect(state("paddock-app", .published, host: 18001) == .live)
        #expect(state("paddock-app", .published, host: 18500) == .live)
        #expect(state("paddock-app", .hostService, host: 6379) == .live)
        // sbx's global rules are rows of the rules table, not of the ports
        #expect(rows.allSatisfy { $0.sandbox == "paddock-app" || $0.sandbox == "claude-plane" })
        #expect(rows.first { $0.sandbox == "claude-plane" && $0.hostPort == 18800 }?.isProject == false)  // a sandbox without a project
        #expect(rows.first { $0.hostPort == 18001 }?.url == "http://localhost:18001")
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test func paddocksPortsASandboxCanStillReachGetADenyRow() throws {
        // The sandbox allows llmman's port and denies only one of its names.
        let project = Project(name: "paddock-app", folder: "/a")
        let rules = [allow("localhost:17434"), deny("localhost:17434")].joined(separator: ",")
        let snapshots = ["paddock-app": try snapshot("paddock-app", ports: [], rules: rules)]
        let rows = PortsTable.rows(projects: [project], snapshots: snapshots, sandboxes: ["paddock-app"], globalRules: globals, app: app)
        let row = try #require(rows.first { $0.state == .notDenied && $0.hostPort == 17434 })
        #expect(row.sandbox == "paddock-app")
        #expect(row.missingDenies == ["host.docker.internal:17434"])
        // The Docker API, which the fixture's globals allow, is not a Paddock service: no row.
        #expect(!rows.contains { $0.state == .notDenied && $0.hostPort == 2375 })
    }

    @Test func aFullyDeniedPaddockPortHasNoRow() throws {
        let project = Project(name: "paddock-app", folder: "/a")
        let rules = ([allow("localhost:17434")] + ["localhost:17434", "host.docker.internal:17434"].map(deny)).joined(separator: ",")
        let snapshots = ["paddock-app": try snapshot("paddock-app", ports: [], rules: rules)]
        let rows = PortsTable.rows(projects: [project], snapshots: snapshots, sandboxes: ["paddock-app"], globalRules: globals, app: app)
        #expect(!rows.contains { $0.state == .notDenied })
    }

    @Test func sbxModelKitsLlmmanAllowIsFlagged() throws {
        // sbx --model provisions a sandbox allow for llmman's port, which Paddock never wants.
        let rules = try Fixture.decode(SbxPolicyList.self, "sbx", "policy-ls-model-sandbox.json").rules
        let name = try #require(rules.compactMap(\.sandboxScope).first)
        let sandbox = try JSONCoding.decode(SbxSandbox.self, from: Data(#"{"name":"\#(name)","id":"1","agent":"claude","status":"running","workspaces":["/a"],"created_at":"2026-10-24T10:00:00Z"}"#.utf8))
        let rows = PortsTable.rows(projects: [Project(name: name, folder: "/a")],
                                   snapshots: [name: SandboxSnapshot(sandbox: sandbox, ports: [], rules: rules)],
                                   sandboxes: [name], globalRules: [], app: app)
        let row = try #require(rows.first { $0.state == .notDenied && $0.hostPort == 17434 })
        #expect(row.missingDenies.contains("localhost:17434"))
    }

    @Test func onlyOtherProjectsGatewayPortsAreFlagged() throws {
        let project = Project(name: "paddock-app", folder: "/a", gatewayPort: 17480)
        let other = Project(name: "paddock-other", folder: "/o", gatewayPort: 17481)
        let allow = deny("localhost").replacingOccurrences(of: "\"deny\"", with: "\"allow\"")  // reaches every loopback port
        let snapshots = ["paddock-app": try snapshot("paddock-app", ports: [], rules: allow)]
        let rows = PortsTable.rows(projects: [project, other], snapshots: snapshots, sandboxes: ["paddock-app"], globalRules: [], app: app).filter { $0.state == .notDenied }
        #expect(Set(rows.compactMap(\.hostPort)) == [17434, 17481])  // not its own 17480, not the unused range
    }

    @Test func aSandboxNotReadYetHasNoRows() throws {
        let project = Project(name: "paddock-app", folder: "/a")
        let rows = PortsTable.rows(projects: [project], snapshots: [:], sandboxes: ["paddock-app"], globalRules: [], app: app)
        #expect(rows.isEmpty)
    }
}

@Suite("Project files and global rules")
struct ProjectFilesAndGlobalRulesTests {
    let app: AppConfig

    init() throws {
        app = try AppConfig.load(from: Fixture.data("config", "paddock-full.yaml")).config
    }

    @Test func oldFilesWithPortsAndNetworkStillLoad() throws {
        // Those keys are from before sbx was the only store for ports and rules; they are ignored.
        // swiftlint:disable:next line_length
        let json = #"{"version":1,"id":"6F1C2D3E-4A5B-4C6D-8E7F-0123456789AB","name":"paddock-x","folder":"/x","agent":"claude","provider":"agent-default","policy":"default","ports":{"publish":[{"sandboxPort":1,"hostPort":18001}],"hostServices":[]},"network":{"allow":["a.com"],"deny":[]}}"#
        let project = try ProjectDirectory.decode(file: "paddock-x.json", data: Data(json.utf8))
        #expect(project.name == "paddock-x")
        let saved = String(decoding: try ProjectDirectory.encode(project), as: UTF8.self)
        #expect(!saved.contains("ports") && !saved.contains("network"))
    }

    @Test func blockingAHostForEverySandbox() async throws {
        let fake = FakeRunner()
        fake.succeedByDefault = true
        let runner = ProjectRunner(sbx: SbxService(runner: fake, sbx: URL(fileURLWithPath: "/sbx")), paths: PaddockPaths(configDirectory: "/tmp/p"))
        try await runner.addGlobalDeny(" Ads.Example.com:443 ")
        #expect(fake.calls == [["policy", "deny", "network", "ads.example.com:443"]])
        await #expect(throws: ProjectRunError.invalidHost("a,b", .invalid("a,b"))) { try await runner.addGlobalDeny("a,b") }
        await #expect(throws: ProjectRunError.self) { try await runner.addGlobalDeny("**") }
    }

    @Test func removingAGlobalRuleOnlyForLocalEditableRules() async throws {
        let fake = FakeRunner()
        fake.succeedByDefault = true
        let runner = ProjectRunner(sbx: SbxService(runner: fake, sbx: URL(fileURLWithPath: "/sbx")), paths: PaddockPaths(configDirectory: "/tmp/p"))
        try await runner.removeGlobalRule(SbxRuleReference(id: "r1", resources: ["localhost:5432"], removable: true))
        #expect(fake.calls == [["policy", "rm", "network", "--id", "r1", "--force"]])
        await #expect(throws: ProjectRunError.globalRuleNotRemovable("d1")) {
            try await runner.removeGlobalRule(SbxRuleReference(id: "d1", resources: ["**.github.com:443"], removable: false))
        }
    }
}
