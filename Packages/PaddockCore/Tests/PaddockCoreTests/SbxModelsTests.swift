import Foundation
import Testing
@testable import PaddockCore

@Suite("sbx JSON fixtures")
struct SbxModelsTests {
    @Test func version() throws {
        let version = try Fixture.decode(SbxVersion.self, "sbx", "version.json")
        #expect(version.client.version == "v0.49.2")
        #expect(version.server.apiVersion == "0.42.0")
        #expect(version.isServerRunning)
    }

    @Test func daemonStatus() throws {
        let status = try Fixture.decode(SbxDaemonStatus.self, "sbx", "daemon-status.json")
        #expect(status.status == "running")
        #expect(status.socket.hasSuffix("sandboxd.sock"))
    }

    @Test func sandboxList() throws {
        let sandboxes = try Fixture.decode([SbxSandbox].self, "sbx", "ls.json")
        #expect(sandboxes.count == 5)
        #expect(sandboxes[0].name == "project-a")
        #expect(sandboxes[0].workspaces == ["/Users/operator/Projects/project-a"])
        #expect(sandboxes.contains { $0.isRunning })
        // fractional and whole-second timestamps both decode
        #expect(sandboxes[0].lastUsedAt != nil)
    }

    @Test func sandboxListWithPorts() throws {
        let sandboxes = try Fixture.decode([SbxSandbox].self, "sbx", "ls-ports.json")
        #expect(sandboxes.map(\.name) == ["paddock-project-a", "paddock-project-b", "project-c"])
        #expect(sandboxes.allSatisfy { $0.createdAt != nil })
    }

    // Not a capture: sbx listed a sandbox it was still creating without created_at, and the
    // whole list failed to decode (PAD-56). This is the fixture's first entry without it.
    @Test func sandboxWithoutCreatedAt() throws {
        let json = #"""
        [{"name": "paddock-project-a", "id": "57c86b65-96b8-4d6a-9b7e-95db4e7c8ee3", "agent": "claude",
          "status": "running", "last_used_at": "2026-10-30T07:34:04.861914Z",
          "workspaces": ["/Users/operator/Projects/project-a"]}]
        """#
        let sandboxes = try JSONCoding.decoder().decode([SbxSandbox].self, from: Data(json.utf8))
        #expect(sandboxes.first?.createdAt == nil)
        #expect(sandboxes.first?.isRunning == true)
    }

    @Test func policyList() throws {
        let policy = try Fixture.decode(SbxPolicyList.self, "sbx", "policy-ls.json")
        let defaults = policy.rules.filter { $0.createdVia == "default" && $0.resourceType == "network" }
        #expect(!defaults.isEmpty)
        #expect(policy.rules.contains { $0.isGlobal && $0.resources.contains("localhost:2375") })
        #expect(policy.rules.contains { $0.resourceType == "filesystem:write" && $0.resources == ["**"] })
    }

    @Test func sandboxPolicyWithHTTPRule() throws {
        let policy = try Fixture.decode(SbxPolicyList.self, "sbx", "policy-ls-sandbox.json")
        let http = try #require(policy.rules.first { $0.resourceType == "http" })
        #expect(http.decision == "allow")
        #expect(http.methods == ["GET"])
        #expect(http.httpTargets == [.init(host: "localhost:17480", path: "/v1/**")])
        #expect(http.sandboxScope == "m0-claude")

        let denies = policy.rules.filter { $0.decision == "deny" }.flatMap(\.resources)
        #expect(denies.contains("localhost:17434"))
        #expect(denies.contains("localhost:5432"))
    }

    @Test func modelSandboxGetsProvisionedLlmmanAllow() throws {
        // The reason Paddock never passes --model: sbx opens llmman's whole port.
        let policy = try Fixture.decode(SbxPolicyList.self, "sbx", "policy-ls-model-sandbox.json")
        let provisioned = policy.rules.filter { $0.createdVia == "provisioned" }
        #expect(provisioned.contains { $0.resourceType == "network" && $0.resources.contains("localhost:17434") })
    }

    @Test func policyLogFromTheCapture() throws {
        let log = try Fixture.decode(SbxPolicyLog.self, "sbx", "policy-log-sandbox.json")  // sandbox m0-claude
        #expect(log.allowed.count == 5 && log.blocked.count == 4)
        let anthropic = try #require(log.allowed.first { $0.host == "api.anthropic.com:443" })
        #expect(anthropic.sandboxId == "m0-claude" && anthropic.count == 11 && anthropic.proxyType == "forward")
        #expect(log.blocked.contains { $0.host == "localhost:17434" && $0.reason == "Denied by local rule" })

        let activity = log.activity
        #expect(activity[ActivityKey(sandbox: "m0-claude", host: "api.anthropic.com:443")]?.allowed == 11)
        // The gateway port: one GET allowed through its HTTP rule, two requests on other paths blocked.
        let gateway = try #require(activity[ActivityKey(sandbox: "m0-claude", host: "localhost:17480")])
        #expect(gateway.allowed == 1 && gateway.blocked == 2)
        #expect(gateway.lastSeen == log.blocked.filter { $0.host == "localhost:17480" }.map(\.lastSeen).max())
    }

    @Test func policyLogForEverySandbox() throws {
        let log = try Fixture.decode(SbxPolicyLog.self, "sbx", "policy-log.json")
        #expect(Set(log.allowed.map(\.sandboxId) + log.blocked.map(\.sandboxId)) == ["project-a", "project-b", "project-c", "project-d"])
        #expect(log.blocked.contains { $0.reason == "No matching allow rule (default deny)" })
        #expect(try JSONCoding.decode(SbxPolicyLog.self, from: Data("{}".utf8)) == SbxPolicyLog(allowed: [], blocked: []))
    }

    @Test func ports() throws {
        let ports = try Fixture.decode([SbxPort].self, "sbx", "ports.json")
        #expect(ports == [SbxPort(hostIP: "127.0.0.1", hostPort: 18000, sandboxPort: 8000, protocol: "tcp4")])
    }

    @Test func removeResult() throws {
        let results = try Fixture.decode([SbxActionResult].self, "sbx", "rm.json")
        #expect(results == [SbxActionResult(action: "removed", resource: "sandbox", name: "m0-model")])
    }

    @Test func templates() throws {
        let templates = try Fixture.decode([SbxTemplate].self, "sbx", "template-ls.json")
        #expect(templates.contains { $0.reference == "docker.io/docker/sandbox-templates:claude-code-docker" })
        #expect(templates.first { $0.reference.hasPrefix("docker.io/docker/") }?.flavor != nil)
        // an image loaded with `sbx template load` that has no sbx label
        #expect(templates.contains { $0.reference == "docker.io/paddock/m0:test" && $0.flavor == nil })
    }

    @Test func modelFeatureSetting() throws {
        let off = try Fixture.decode(SbxSetting<SbxModelFeature>.self, "sbx", "settings-feature-model.json")
        #expect(off.value.enabled == false)
        #expect(off.source == "default")
        let on = try Fixture.decode(SbxSetting<SbxModelFeature>.self, "sbx", "settings-feature-model-enabled.json")
        #expect(on.value.enabled == true)
        #expect(on.source == "override")
    }

    @Test func events() throws {
        let text = String(decoding: try Fixture.data("sbx", "events-idle.ndjson"), as: UTF8.self)
        let events = try text.split(separator: "\n").compactMap { try SbxEventDecoder.decode(line: String($0)) }
        #expect(events.contains { $0.kind == .sandboxLifecycle })
        #expect(events.contains { $0.kind == .policyNetwork && $0.data?["host"] != nil })
        #expect(events.last?.isSyncComplete == true)
    }

    @Test func blankEventLinesAreSkipped() throws {
        #expect(try SbxEventDecoder.decode(line: "  ") == nil)
    }
}
