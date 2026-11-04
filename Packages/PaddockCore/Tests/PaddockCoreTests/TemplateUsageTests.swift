import Foundation
import Testing
@testable import PaddockCore

/// The Templates page: sbx's images, what uses them, and removing them.
@Suite("TemplateUsage")
struct TemplateUsageTests {
    static func templates() throws -> [SbxTemplate] {
        try Fixture.decode([SbxTemplate].self, "sbx", "template-ls.json")
    }

    @Test func everyTemplateGetsARowWithItsKind() throws {
        let rows = TemplateUsage.rows(try Self.templates())
        #expect(rows.count == 20)
        let agent = try #require(rows.first { $0.name == "docker/sandbox-templates:claude-code-docker" })
        #expect(agent.kind == .agentTemplate)
        #expect(agent.usedBy == "new claude-code-docker sandboxes")
        // Paddock's images from before PAD-73.4: nothing uses them
        let paddock = try #require(rows.first { $0.name == "paddock/m0:test" })
        #expect(paddock.kind == .oldProjectImage && paddock.removalNote == "nothing uses it")
        let other = try #require(rows.first { $0.name == "library/custom-1:local" })
        #expect(other.kind == .other)
        #expect(other.usedBy == "not known")
        // old project images first, then other images, then sbx's agent templates
        #expect(rows.first?.kind == .oldProjectImage)
        #expect(rows.last?.kind == .agentTemplate)
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test func anOlderBuildOfAKitIsMarked() throws {
        let json = #"""
        [{"id":"sha256:1","repository":"sbx-kit-src","tag":"paddock-aaa","created_at":"2026-10-01T10:00:00Z","size":10},
         {"id":"sha256:2","repository":"sbx-kit-src","tag":"paddock-bbb","created_at":"2026-10-21T10:00:00Z","size":10},
         {"id":"sha256:3","repository":"sbx-kit-src","tag":"other-ccc","created_at":"2026-09-01T10:00:00Z","size":10}]
        """#
        let rows = TemplateUsage.rows(try JSONCoding.decode([SbxTemplate].self, from: Data(json.utf8)))
        #expect(rows.first { $0.template.tag == "paddock-aaa" }?.isOlderBuild == true)
        #expect(rows.first { $0.template.tag == "paddock-bbb" }?.isOlderBuild == false)
        #expect(rows.first { $0.template.tag == "other-ccc" }?.isOlderBuild == false)
    }

    @Test func anAssembledKitImageIsNamedAsOne() throws {
        let json = #"[{"id":"sha256:1","repository":"docker.io/library/sandbox-kit-assembled","tag":"7233ebf8b1bdddf4-kit-2","created_at":"2026-10-21T14:33:43Z","size":10}]"#
        let templates = try JSONCoding.decode([SbxTemplate].self, from: Data(json.utf8))
        #expect(TemplateUsage.rows(templates).first?.kind == .kitAssembled)
    }

    @Test func aKitSbxBuiltIsNamedAsOne() throws {
        let json = #"[{"id":"sha256:1","repository":"sbx-kit-src","tag":"example-dev-abc","created_at":"2026-10-21T14:33:43Z","size":10}]"#
        let templates = try JSONCoding.decode([SbxTemplate].self, from: Data(json.utf8))
        #expect(TemplateUsage.rows(templates).first?.kind == .kitBuild)
    }

    @Test func aLongRemovalNamesEightAndCountsTheRest() throws {
        let rows = TemplateUsage.rows(try Self.templates())
        let (named, more) = TemplateUsage.confirmationList(rows)
        #expect(named.count == 8 && more.count == rows.count - 8)
        #expect(named + more == rows)
        // nine fit as they are: a "1 more" line would save nothing
        #expect(TemplateUsage.confirmationList(Array(rows.prefix(9))).more.isEmpty)
        #expect(TemplateUsage.confirmationList(Array(rows.prefix(10))).named.count == 8)
        #expect(TemplateUsage.confirmationList([]).named.isEmpty)
    }

    @Test func theTotalSizeAddsUp() throws {
        let templates = try Self.templates()
        let rows = TemplateUsage.rows(templates)
        #expect(TemplateUsage.size(of: rows) == templates.reduce(0) { $0 + $1.size })
    }

    /// A runner whose `sbx template ls` is the fixture and whose `sbx ls` lists `sandboxes`.
    static func runner(sandboxes: [String]) throws -> (ProjectRunner, FakeRunner) {
        let fake = FakeRunner()
        fake.respond(to: ["template", "ls", "--json"], with: try Fixture.data("sbx", "template-ls.json"))
        let list = sandboxes.map {
            #"{"name":"\#($0)","id":"\#($0)","agent":"claude","status":"stopped","workspaces":[],"created_at":"2026-10-24T10:00:00Z"}"#
        }
        fake.respond(to: ["ls", "--json"], with: Data(("[" + list.joined(separator: ",") + "]").utf8))
        let paths = PaddockPaths(configDirectory: NSTemporaryDirectory() + "paddock-unused")
        return (ProjectRunner(sbx: SbxService(runner: fake, sbx: URL(fileURLWithPath: "/opt/homebrew/bin/sbx")), paths: paths), fake)
    }

    @Test func removingChecksAgainstAFreshListAndRemovesEachWithForce() async throws {
        let (runner, fake) = try Self.runner(sandboxes: ["m0"])
        fake.respond(to: ["template", "rm", "--force", "docker/sandbox-templates:cursor-agent-docker"], with: Data())
        fake.respond(to: ["template", "rm", "--force", "library/custom-1:local"], with: Data(), exitCode: 1, stderr: "image is in use")
        let result = try await runner.removeTemplates(
            ["docker/sandbox-templates:cursor-agent-docker", "library/custom-1:local", "gone/image:1"]
        )
        #expect(result.removed == ["docker/sandbox-templates:cursor-agent-docker"])
        #expect(result.failed.map(\.name) == ["library/custom-1:local", "gone/image:1"])
        #expect(result.failed[0].reason.contains("image is in use"))
        #expect(result.failed[1].reason == "sbx does not list it any more")
        // the unknown one never reached sbx
        let removals = fake.calls.filter { $0.starts(with: ["template", "rm"]) }
        #expect(removals == [["template", "rm", "--force", "docker/sandbox-templates:cursor-agent-docker"],
                             ["template", "rm", "--force", "library/custom-1:local"]])
    }

    @Test func aFailedListRemovesNothing() async throws {
        let fake = FakeRunner()
        fake.respond(to: ["template", "ls", "--json"], with: Data(), exitCode: 1, stderr: "daemon not running")
        let paths = PaddockPaths(configDirectory: NSTemporaryDirectory() + "paddock-unused")
        let runner = ProjectRunner(sbx: SbxService(runner: fake, sbx: URL(fileURLWithPath: "/opt/homebrew/bin/sbx")), paths: paths)
        await #expect(throws: (any Error).self) { try await runner.removeTemplates(["paddock/m0:test"]) }
        #expect(!fake.calls.contains { $0.starts(with: ["template", "rm"]) })
    }
}
