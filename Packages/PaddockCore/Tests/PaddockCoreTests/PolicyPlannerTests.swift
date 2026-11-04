import Foundation
import Testing
@testable import PaddockCore

@Suite("HostPattern")
struct HostPatternTests {
    @Test(arguments: [
        ("**.github.com:443", "api.github.com:443", true),
        ("**.github.com:443", "a.b.github.com:443", true),
        ("**.github.com:443", "github.com:443", false),
        ("**.github.com:443", "api.github.com:80", false),
        ("*.npmjs.org", "registry.npmjs.org:443", true),
        ("*.npmjs.org", "a.b.npmjs.org", false),
        ("registry.npmjs.org", "registry.npmjs.org:443", true),
        ("registry.npmjs.org:443", "registry.npmjs.org", false),
        ("api?.example.com", "api1.example.com", true),
        ("api[12].example.com", "api3.example.com", false),
        ("api[!1].example.com", "api2.example.com", true),
        ("localhost:5432", "localhost:5432", true),
        ("**", "anything.example:1", true),
        ("Example.COM", "example.com", true),
    ])
    func covers(pattern: String, target: String, expected: Bool) {
        #expect(HostPattern(parsing: pattern).covers(HostPattern(parsing: target)) == expected)
    }

    @Test func parsesPorts() {
        #expect(HostPattern(parsing: "localhost:17480") == HostPattern(host: "localhost", port: 17480))
        #expect(HostPattern(parsing: "*.npmjs.org").port == nil)
    }

    @Test func compilesEachGlobOnce() {
        // PAD-29: the views match on every render; compiling each time held up project switches.
        let cache = HostGlobCache()
        for host in ["api.github.com", "a.b.github.com", "github.com", "api.github.com"] {
            _ = HostPattern.hostMatches(pattern: "**.github.com", literal: host, cache: cache)
        }
        #expect(HostPattern.hostMatches(pattern: "*.npmjs.org", literal: "registry.npmjs.org", cache: cache))
        #expect(cache.compileCount == 2)
    }

    @Test func uncompilableGlobComparesLiterallyAndIsNotRetried() {
        let cache = HostGlobCache()
        #expect(HostPattern.compile("a[") == nil)
        #expect(HostPattern.hostMatches(pattern: "a[", literal: "a[", cache: cache))
        #expect(!HostPattern.hostMatches(pattern: "a[", literal: "ab", cache: cache))
        #expect(cache.compileCount == 1)
    }

    @Test func cacheStartsOverAtItsLimit() {
        let cache = HostGlobCache(limit: 3)
        for index in 0..<10 {
            _ = HostPattern.hostMatches(pattern: "host\(index).example", literal: "x", cache: cache)
        }
        #expect(cache.count <= 3)
        #expect(cache.compileCount == 10)
    }

    @Test func cacheIsSafeFromManyThreads() async {
        let cache = HostGlobCache()
        await withTaskGroup(of: Bool.self) { group in
            for index in 0..<200 {
                let domain = "p\(index % 10).example"
                group.addTask { HostPattern.hostMatches(pattern: "*.\(domain)", literal: "a.\(domain)", cache: cache) }
            }
            for await matched in group { #expect(matched) }
        }
        #expect(cache.count == 10)
    }
}

/// Security rule: Paddock adds rules only to protect its own services: llmman's port, and other
/// projects' gateway ports (CLAUDE.md, Security rules). sbx's global rules stay in effect.
@Suite("PolicyPlanner")
struct PolicyPlannerTests {
    let planner = PolicyPlanner(gatewayPort: 17480)

    func globalRules() throws -> [SbxPolicyRule] {
        try Fixture.decode(SbxPolicyList.self, "sbx", "policy-ls.json").rules
    }

    @Test func globalAllowsStayInEffect() throws {
        let plan = try planner.plan(globalRules: try globalRules(), allowed: [], usesGateway: false)
        #expect(!plan.denies.contains("localhost:5432"))
        #expect(!plan.denies.contains("api.anthropic.com:443"))
        #expect(!plan.denies.contains("localhost:2375"))  // the Docker API is not a Paddock service
        #expect(plan.allows.isEmpty)
    }

    @Test func alwaysDeniesLlmman() throws {
        let plan = try planner.plan(globalRules: try globalRules(), allowed: ["registry.npmjs.org"], usesGateway: true)
        #expect(plan.denies.prefix(2) == ["localhost:17434", "host.docker.internal:17434"])
        let bare = try planner.plan(globalRules: [], allowed: [], usesGateway: false)
        #expect(bare.denies == ["localhost:17434", "host.docker.internal:17434"])
    }

    @Test func theProjectsDeniesAreAdded() throws {
        let plan = try planner.plan(globalRules: try globalRules(), allowed: [], denied: ["registry.npmjs.org:443"], usesGateway: false)
        #expect(plan.denies.contains("registry.npmjs.org:443"))
    }

    @Test func hostsAGlobalRuleAllowsNeedNoRule() throws {
        let plan = try planner.plan(globalRules: try globalRules(), allowed: ["registry.npmjs.org:443", "api.github.com:443"],
                                    usesGateway: false)
        #expect(plan.allows.isEmpty)  // one exactly, one through **.github.com:443
    }

    @Test func uncoveredEntriesBecomeSandboxAllows() throws {
        let plan = try planner.plan(globalRules: try globalRules(), allowed: ["pypi.example.test", "localhost:8080"], usesGateway: false)
        #expect(plan.allows == ["pypi.example.test", "localhost:8080"])
    }

    @Test func gatewayGetsAnHTTPRuleOnlyWhenUsed() throws {
        let with = try planner.plan(globalRules: try globalRules(), allowed: [], usesGateway: true)
        #expect(with.httpAllows == [.init(resource: "localhost:17480", methods: ["GET", "POST"], path: "/v1/**")])
        #expect(!with.denies.contains("localhost:17480"))
        let without = try planner.plan(globalRules: try globalRules(), allowed: [], usesGateway: false)
        #expect(without.httpAllows.isEmpty)
    }

    @Test(arguments: ["localhost:17434", "host.docker.internal:17434", "local*:17434"])
    func refusesLlmman(entry: String) throws {
        #expect(throws: PolicyPlanError.forbiddenResource(HostPattern(parsing: entry).description)) {
            try planner.plan(globalRules: try globalRules(), allowed: [entry], usesGateway: false)
        }
    }

    /// The gateway port identifies the project, so no project may name any gateway port.
    @Test(arguments: ["localhost:17481", "host.docker.internal:17480", "localhost", "*.docker.internal:17500", "localhost:17579"])
    func refusesGatewayPorts(entry: String) throws {
        #expect(throws: PolicyPlanError.forbiddenResource(HostPattern(parsing: entry).description)) {
            try planner.plan(globalRules: [], allowed: [entry], usesGateway: true)
        }
    }

    @Test func otherPortsOnLoopbackAreFine() throws {
        let plan = try planner.plan(globalRules: [], allowed: ["localhost:5432", "localhost:2375", "localhost:17580"], usesGateway: true)
        #expect(plan.allows == ["localhost:5432", "localhost:2375", "localhost:17580"])
    }

    @Test(arguments: ["localhost", "**"])
    func aBroadGlobalRuleGetsOtherGatewaysDenied(resource: String) throws {
        let rules = try JSONCoding.decode(SbxPolicyList.self, from: Data(Self.globalRule(resource).utf8)).rules
        let plan = try planner.plan(globalRules: rules, allowed: [], usesGateway: true)
        #expect(plan.denies.contains("localhost:17481") && plan.denies.contains("host.docker.internal:17579"))
        #expect(!plan.denies.contains("localhost:17480"))  // this project's own port
        #expect(plan.denies.contains("localhost:17434"))
    }

    @Test func noGatewayDeniesWithoutABroadRule() throws {
        let plan = try planner.plan(globalRules: try globalRules(), allowed: [], usesGateway: true)
        #expect(!plan.denies.contains("localhost:17481"))
    }

    @Test func readsTheGatewayPortBackFromTheSandboxRule() throws {
        let rules = try Fixture.decode(SbxPolicyList.self, "sbx", "policy-ls-sandbox.json").rules
        #expect(PolicyPlanner.gatewayPort(ofSandbox: "m0-claude", rules: rules, in: 17480...17579) == 17480)
        #expect(PolicyPlanner.gatewayPort(ofSandbox: "m0-claude", rules: rules, in: 17481...17579) == nil)
        #expect(PolicyPlanner.gatewayPort(ofSandbox: "paddock-other", rules: rules, in: 17480...17579) == nil)
        // the same port twice (one rule per method) is still one port; two ports are ambiguous
        let http = try #require(rules.first { $0.resourceType == "http" })
        #expect(PolicyPlanner.gatewayPort(ofSandbox: "m0-claude", rules: [http, http], in: 17480...17579) == 17480)
        let json = try JSONEncoder().encode(http)
        let other = String(decoding: json, as: UTF8.self).replacingOccurrences(of: "localhost:17480", with: "localhost:17481")
        let second = try JSONDecoder().decode(SbxPolicyRule.self, from: Data(other.utf8))
        #expect(PolicyPlanner.gatewayPort(ofSandbox: "m0-claude", rules: [http, second], in: 17480...17579) == nil)
    }

    static func globalRule(_ resource: String) -> String {
        """
        {"rules":[{"id":"r1","name":"r1","policy_id":"p","scope":"global","applies_to":"all","resource_type":"network",
        "decision":"allow","resources":["\(resource)"],"origin":"local","layer":"local","status":"active","editable":true,
        "provenance":{"created_via":"added"},"actions":["net:connect:tcp"]}]}
        """
    }

    @Test func ignoresFilesystemAndSandboxScopedRules() throws {
        // The fixture has global filesystem rules with resource "**" and sandbox-scoped rules.
        let rules = try globalRules() + Fixture.decode(SbxPolicyList.self, "sbx", "policy-ls-sandbox.json").rules
        let plan = try planner.plan(globalRules: rules, allowed: [], usesGateway: false)
        #expect(!plan.denies.contains("**"))
        #expect(!plan.denies.contains("localhost:17481"))  // the filesystem's ** is not a network rule
    }

    @Test func createArgumentsPairEachDeny() throws {
        let plan = try planner.plan(globalRules: [], allowed: [], usesGateway: false)
        #expect(plan.createArguments.count == plan.denies.count * 2)
        #expect(plan.createArguments.first == "--deny-network")
    }
}
