import Foundation
import Testing
@testable import PaddockCore

/// sbx's approval requests, offered on the project's Info.
@Suite("ApprovalRequests")
struct ApprovalRequestsTests {
    let app: AppConfig

    init() throws {
        app = try AppConfig.load(from: Fixture.data("config", "paddock-full.yaml")).config
    }

    func approvals() throws -> [SbxApproval] { try Fixture.decode([SbxApproval].self, "sbx", "policy-approval-ls.json") }

    @Test func decodesTheCapture() throws {
        let all = try approvals()
        #expect(all.count == 6)
        let tcp = try #require(all.first { $0.title == "host7.example.test:443" })
        #expect(tcp.sandboxName == "m0-claude" && tcp.host == "host7.example.test:443")
        #expect(tcp.options.map(\.id) == ["allow", "dismiss"] && tcp.options.map(\.label) == ["Allow", "Dismiss"])
        #expect(all.first { $0.title.hasPrefix("GET ") }?.host == "localhost:17480")
    }

    @Test func aSandboxsRequestsWithoutPaddocksServices() throws {
        // The test sandbox asked for example.org and, on other paths, for its own gateway port.
        let pending = ApprovalRequests.pending(try approvals(), sandbox: "m0-claude", app: app)
        #expect(pending.map(\.host) == ["host7.example.test:443"])
        let two = ApprovalRequests.pending(try approvals(), sandbox: "project-a", app: app)
        #expect(two.count == 2 && two[0].createdAt > two[1].createdAt)
        #expect(ApprovalRequests.pending(try approvals(), sandbox: "nobody", app: app).isEmpty)
        // Dismissed before: the same request asked again stays dismissed.
        let dismissed = ApprovalRequests.ignoreID(two[0])
        #expect(ApprovalRequests.pending(try approvals(), sandbox: "project-a", ignored: [dismissed], app: app).map(\.id) == [two[1].id])
    }

    @Test func answersOnlyItsOwnWithOfferedOptions() async throws {
        let fake = FakeRunner()
        fake.succeedByDefault = true
        let runner = ProjectRunner(sbx: SbxService(runner: fake, sbx: URL(fileURLWithPath: "/sbx")), paths: PaddockPaths(configDirectory: "/tmp/p"))
        let request = try #require(try approvals().first { $0.sandboxName == "m0-claude" && !$0.title.contains(" ") })
        let project = Project(name: "m0-claude", folder: "/a")
        try await runner.respond(to: request, with: "allow", for: project)
        #expect(fake.calls == [["policy", "approval", "respond", request.id, "--option", "allow"]])
        await #expect(throws: ProjectRunError.approvalMismatch(request.id)) {
            try await runner.respond(to: request, with: "always", for: project)
        }
        await #expect(throws: ProjectRunError.approvalMismatch(request.id)) {
            try await runner.respond(to: request, with: "allow", for: Project(name: "project-a", folder: "/b"))
        }
    }
}
