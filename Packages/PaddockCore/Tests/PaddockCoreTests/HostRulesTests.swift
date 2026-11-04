import Foundation
import Testing
@testable import PaddockCore

@Suite("HostRules")
struct HostRulesTests {
    let sbxURL = URL(fileURLWithPath: "/opt/homebrew/bin/sbx")

    @Test func validatesHosts() throws {
        #expect(try HostRules.validated(" Example.com:443 ") == "example.com:443")
        #expect(try HostRules.validated("**.github.com") == "**.github.com")
        // Every character the set allows: letters (any script), digits, and . - _ * ? [ ] ! :
        for text in ["api-1_x.example.com", "api?.ex[!a].com:443", "bücher.example"] {
            #expect(try HostRules.validated(text) == text)
        }
        for text in ["", "a b", "a.com,b.com", "a.com:0", "a.com:70000", "a/b.com", "a@b.com", "a;b.com", "a\"b.com"] {
            #expect(throws: HostRules.Problem.invalid(text)) { try HostRules.validated(text) }
        }
        #expect(throws: HostRules.Problem.allHosts) { try HostRules.validated("**") }
        // this Mac goes through Ports, which keeps the Docker API, llmman, and gateway ports out
        for text in ["localhost:2375", "host.docker.internal", "local*:17434", "*"] {
            #expect(throws: HostRules.Problem.self) { try HostRules.validated(text) }
        }
    }

    // MARK: - Rows

    func app() throws -> AppConfig {
        try AppConfig.load(from: Fixture.data("config", "paddock-full.yaml")).config
    }

    func rule(id: String, decision: String, resources: [String], editable: Bool = true, via: String = "added") -> String {
        let list = resources.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"id":"\#(id)","name":"\#(id)","policy_id":"p","scope":"sandbox:paddock-app","applies_to":"sandbox:paddock-app","resource_type":"network","decision":"\#(decision)","resources":[\#(list)],"origin":"scoped","layer":"local","status":"active","editable":\#(editable),"provenance":{"created_via":"\#(via)"},"actions":["net:connect:tcp"]}"#
    }

    func snapshot(_ rules: [String]) throws -> SandboxSnapshot {
        let sandbox = try JSONCoding.decode(SbxSandbox.self, from: Data(#"{"name":"paddock-app","id":"1","agent":"claude","status":"running","workspaces":["/a"],"created_at":"2026-10-24T10:00:00Z"}"#.utf8))
        let list = try JSONCoding.decode(SbxPolicyList.self, from: Data(#"{"rules":[\#(rules.joined(separator: ","))]}"#.utf8))
        return SandboxSnapshot(sandbox: sandbox, ports: [], rules: list.rules)
    }

    @Test func rowsComeFromTheSandboxAndTheConfig() throws {
        let snapshot = try snapshot([
            rule(id: "a1", decision: "allow", resources: ["example.com", "localhost:5432"]),  // a host service is not a host rule
            rule(id: "d1", decision: "deny", resources: ["pypi.org"]),
            rule(id: "d2", decision: "deny", resources: ["localhost:17434"]),                 // Paddock's own: not listed
            rule(id: "k1", decision: "allow", resources: ["api.anthropic.com:443"], via: "provisioned"),  // sbx's kit
        ])
        let rows = HostRules.rows(snapshot: snapshot, globalAllows: [HostPattern(parsing: "registry.npmjs.org")],
                                  plannedDenies: ["localhost:17434"])
        #expect(rows == [
            .init(host: "example.com", decision: .allow, source: .sandbox),
            .init(host: "pypi.org", decision: .deny, source: .sandbox),
        ])
        #expect(HostRules.rows(snapshot: nil, globalAllows: [], plannedDenies: []).isEmpty)
    }

    // MARK: - Applying to the sandbox

    func runner(_ sandboxRules: [String], globals: Data = Data(#"{"rules":[]}"#.utf8)) -> (FakeRunner, ProjectRunner) {
        let fake = FakeRunner()
        fake.succeedByDefault = true
        fake.respond(to: ["policy", "ls", "--json"], with: globals)
        fake.respond(to: ["policy", "ls", "paddock-app", "--json"],
                     with: Data(#"{"rules":[\#(sandboxRules.joined(separator: ","))]}"#.utf8))
        return (fake, ProjectRunner(sbx: SbxService(runner: fake, sbx: sbxURL), paths: PaddockPaths(configDirectory: "/tmp/paddock")))
    }

    func changes(_ fake: FakeRunner) -> [[String]] {
        fake.calls.filter { !$0.starts(with: ["policy", "ls"]) }
    }

    let project = Project(name: "paddock-app", folder: "/a")

    @Test func allowingReplacesTheDeny() async throws {
        let (fake, runner) = runner([rule(id: "d1", decision: "deny", resources: ["example.com"])])
        try await runner.setHostRule(.allow, for: "example.com", on: project, app: try app())
        #expect(changes(fake) == [["policy", "rm", "network", "--id", "d1", "--sandbox", "paddock-app", "--force"],
                                  ["policy", "allow", "network", "--sandbox", "paddock-app", "example.com"]])
    }

    @Test func denyingAddsTheDenyBeforeRemovingTheAllow() async throws {
        let (fake, runner) = runner([rule(id: "a1", decision: "allow", resources: ["example.com"])])
        try await runner.setHostRule(.deny, for: "example.com", on: project, app: try app())
        #expect(changes(fake) == [["policy", "deny", "network", "--sandbox", "paddock-app", "example.com"],
                                  ["policy", "rm", "network", "--id", "a1", "--sandbox", "paddock-app", "--force"]])
    }

    @Test func removingADenyKeepsTheOtherHostsInItsRuleDenied() async throws {
        let (fake, runner) = runner([rule(id: "d1", decision: "deny", resources: ["example.com", "ads.example.test"])])
        try await runner.setHostRule(nil, for: "example.com", on: project, app: try app())
        #expect(changes(fake) == [["policy", "deny", "network", "--sandbox", "paddock-app", "ads.example.test"],
                                  ["policy", "rm", "network", "--id", "d1", "--sandbox", "paddock-app", "--force"]])
    }

    @Test func allowingAHostAGlobalRuleCoversNeedsNoRule() async throws {
        // registry.npmjs.org:443 is in sbx's default allows: removing the deny is enough.
        let globals = try Fixture.data("sbx", "policy-ls.json")
        let (fake, runner) = runner([rule(id: "d1", decision: "deny", resources: ["registry.npmjs.org:443"])], globals: globals)
        try await runner.setHostRule(.allow, for: "registry.npmjs.org:443", on: project, app: try app())
        #expect(changes(fake) == [["policy", "rm", "network", "--id", "d1", "--sandbox", "paddock-app", "--force"]])
    }

    @Test func neverRemovesADenyForPaddocksServices() async throws {
        // llmman's port stays denied whatever is asked.
        let (fake, runner) = runner([rule(id: "d1", decision: "deny", resources: ["localhost:17434"])])
        try await runner.setHostRule(nil, for: "localhost:17434", on: project, app: try app())
        #expect(changes(fake).isEmpty)
    }

    @Test func leavesSbxKitRulesAlone() async throws {
        let (fake, runner) = runner([rule(id: "k1", decision: "allow", resources: ["example.com"], via: "provisioned")])
        try await runner.setHostRule(.deny, for: "example.com", on: project, app: try app())
        #expect(changes(fake) == [["policy", "deny", "network", "--sandbox", "paddock-app", "example.com"]])
    }
}
