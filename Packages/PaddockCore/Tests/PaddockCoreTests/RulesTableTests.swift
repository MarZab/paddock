import Foundation
import Testing
@testable import PaddockCore

@Suite("RulesTable")
struct RulesTableTests {
    let app: AppConfig
    let globals: [SbxPolicyRule]
    let sandboxRules: [SbxPolicyRule]

    init() throws {
        app = try AppConfig.load(from: Fixture.data("config", "paddock-full.yaml")).config
        globals = try Fixture.decode(SbxPolicyList.self, "sbx", "policy-ls.json").rules
        sandboxRules = try Fixture.decode(SbxPolicyList.self, "sbx", "policy-ls-sandbox.json").rules  // sandbox m0-claude
    }

    func snapshot(rules: [SbxPolicyRule], workspaces: String = #"["/Users/op/src/app","/Users/op/docs:ro"]"#) throws -> SandboxSnapshot {
        let json = #"{"name":"m0-claude","id":"1","agent":"claude","status":"running","workspaces":\#(workspaces),"created_at":"2026-10-24T10:00:00Z"}"#
        let sandbox = try JSONCoding.decode(SbxSandbox.self, from: Data(json.utf8))
        return SandboxSnapshot(sandbox: sandbox, ports: [], rules: rules)
    }

    @Test func rulesAndMountsInOneList() throws {
        let project = Project(name: "m0-claude", folder: "/Users/op/src/app")
        let rows = RulesTable.rows(globalRules: globals, snapshots: ["m0-claude": try snapshot(rules: sandboxRules)],
                                   projects: [project], app: app)

        // Global rules: sbx's defaults, filesystem ones included, for every sandbox.
        #expect(rows.contains { $0.sandbox == nil && $0.kind == .filesystemWrite && $0.target == "**" && $0.source == .sbxDefault })
        #expect(rows.contains { $0.sandbox == nil && $0.kind == .network && $0.target == "localhost:2375" })
        // The sandbox's own: the kit's hosts, the operator's deny, the HTTP rule.
        let own = rows.filter { $0.sandbox == "m0-claude" }
        // One row per host: the kit's rule names seven.
        let kit = own.filter { $0.source == .kit }
        #expect(kit.count == 7 && kit.contains { $0.target == "api.anthropic.com:443" })
        #expect(kit.allSatisfy { $0.ruleResources.count == 7 && $0.ruleName == "kit:m0-claude" })
        #expect(own.contains { $0.kind == .http && $0.target == "GET localhost:17480/v1/**" })
        // Paddock denies llmman's port: its deny is marked as Paddock's.
        #expect(own.first { $0.target == "localhost:17434" }?.source == .paddockPlan)
        // Mounts, with read-only ones marked.
        #expect(own.filter { $0.kind == .mount }.map(\.target) == ["/Users/op/src/app", "/Users/op/docs"])
        #expect(own.first { $0.target == "/Users/op/docs" }?.decision == "read")
        // the Docker API deny the fixture sandbox has is its own rule
        #expect(own.first { $0.target == "localhost:5432" }?.source == .added)
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test func aSandboxSeesGlobalRulesAndItsOwn() throws {
        let rows = RulesTable.rows(globalRules: globals, snapshots: ["m0-claude": try snapshot(rules: sandboxRules)],
                                   projects: [], app: app)
        let mine = RulesTable.applying(to: "m0-claude", rows)
        #expect(mine.allSatisfy { $0.sandbox == nil || $0.sandbox == "m0-claude" })
        #expect(RulesTable.applying(to: "other", rows).allSatisfy { $0.sandbox == nil })
    }

    @Test func theFilters() throws {
        let rows = RulesTable.rows(globalRules: globals, snapshots: ["m0-claude": try snapshot(rules: sandboxRules)],
                                   projects: [Project(name: "m0-claude", folder: "/Users/op/src/app")], app: app)
        var filter = RuleFilter()
        #expect(filter.apply(rows).count == rows.count)  // Paddock's own denies show too: there are few
        filter.decision = .suggested
        #expect(Set(filter.apply(rows).map(\.target)) == ["Docker API (2375, 2376)"])
        filter.decision = .deny
        #expect(filter.apply(rows).allSatisfy { $0.decision == "deny" && !$0.isSuggestion })
        filter.decision = .all
        filter.query = "ANTHROPIC"
        #expect(!filter.apply(rows).isEmpty && filter.apply(rows).allSatisfy {
            $0.target.lowercased().contains("anthropic") || ($0.ruleName ?? "").contains("anthropic")
        })
    }

    @Test func paddockSuggestsAShortListOfDenies() throws {
        // The fixture's globals allow localhost:2375, which the sandbox does not deny; nothing allows metadata.
        let rows = RulesTable.rows(globalRules: globals, snapshots: ["m0-claude": try snapshot(rules: sandboxRules)],
                                   projects: [], app: app)
        let suggested = rows.filter { $0.source == .paddockSuggestion }
        #expect(suggested.map(\.target) == ["Docker API (2375, 2376)"])
        #expect(suggested.first?.ruleResources.contains("localhost:2375") == true && suggested.first?.isSuggestion == true)
        // Denied already: no suggestion.
        let denies = RulesTable.suggestedDenies[0].resources.map { resource in
            #"{"id":"d-\#(resource)","name":"d","policy_id":"p","scope":"sandbox:m0-claude","applies_to":"sandbox:m0-claude","resource_type":"network","decision":"deny","resources":["\#(resource)"],"origin":"scoped","layer":"local","status":"active","editable":true,"provenance":{"created_via":"added"},"actions":[]}"#
        }
        let deniedRules = try JSONCoding.decode(SbxPolicyList.self, from: Data(#"{"rules":[\#(denies.joined(separator: ","))]}"#.utf8)).rules
        let after = RulesTable.rows(globalRules: globals, snapshots: ["m0-claude": try snapshot(rules: sandboxRules + deniedRules)],
                                    projects: [], app: app)
        #expect(!after.contains { $0.source == .paddockSuggestion })
    }

    @Test func sectionsPutEverySandboxFirst() throws {
        let rows = RulesTable.rows(globalRules: globals, snapshots: ["m0-claude": try snapshot(rules: sandboxRules)],
                                   projects: [], app: app)
        let sections = RulesTable.sections(rows)
        #expect(sections.map(\.title) == ["All sandboxes", "m0-claude"])
        #expect(sections.map(\.rows.count).reduce(0, +) == rows.count)
        // A chosen sandbox's own rules come first.
        #expect(RulesTable.sections(rows, selected: "m0-claude").map(\.title) == ["m0-claude", "All sandboxes"])
    }

    @Test func theLogMergesIntoTheRules() throws {
        let rows = RulesTable.rows(globalRules: globals, snapshots: ["m0-claude": try snapshot(rules: sandboxRules)],
                                   projects: [], app: app)
        let at = Date(timeIntervalSince1970: 1000)
        let activity: [ActivityKey: HostActivity] = [
            ActivityKey(sandbox: "m0-claude", host: "api.github.com:443"): HostActivity(lastSeen: at, allowed: 3),
            ActivityKey(sandbox: "m0-claude", host: "raw.githubusercontent.com:443"): HostActivity(allowed: 1),
            ActivityKey(sandbox: "m0-claude", host: "evil.example:443"): HostActivity(lastSeen: at, blocked: 2),
            ActivityKey(sandbox: "other", host: "api.github.com:443"): HostActivity(allowed: 5),
            ActivityKey(sandbox: "m0-claude", host: "localhost:17480"): HostActivity(allowed: 1, blocked: 2),  // the gateway
        ]
        let merged = RulesTable.merging(rows, activity: activity, sandbox: "m0-claude")
        // A pattern rule carries the activity of every host it covers, for this sandbox only.
        let github = try #require(merged.first { $0.sandbox == nil && $0.target == "**.github.com:443" })
        #expect(github.activity == HostActivity(lastSeen: at, allowed: 3))
        // A host no rule covers is a row of its own, blocked, ready to allow or deny.
        let evil = try #require(merged.first { $0.target == "evil.example:443" })
        #expect(evil.source == .unruled && evil.decision == "deny" && evil.sandbox == "m0-claude" && evil.host == "evil.example:443")
        #expect(evil.activity?.blocked == 2)
        #expect(!merged.contains { $0.sandbox == "other" })
        // The gateway's traffic belongs to the sandbox's HTTP rule, not to a row of its own.
        #expect(merged.first { $0.kind == .http }?.activity == HostActivity(allowed: 1, blocked: 2))
        #expect(!merged.contains { $0.source == .unruled && $0.target == "localhost:17480" })
        // Every sandbox's activity on the Network Rules page.
        let all = RulesTable.merging(rows, activity: activity, sandbox: nil)
        #expect(all.first { $0.sandbox == nil && $0.target == "**.github.com:443" }?.activity?.allowed == 8)

        var filter = RuleFilter()
        filter.seen = .blocked
        #expect(Set(filter.apply(merged).map(\.target)) == ["evil.example:443", "GET localhost:17480/v1/**"])
        filter.seen = .seen
        #expect(filter.apply(merged).allSatisfy { $0.activity != nil })
    }

    @Test func onlyLocalEditableRulesAreRemovable() throws {
        let rows = RulesTable.rows(globalRules: globals, snapshots: [:], projects: [], app: app)
        #expect(rows.filter { $0.source == .sbxDefault }.allSatisfy { !$0.removable })
    }
}
