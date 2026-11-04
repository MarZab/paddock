import Foundation
import Testing
@testable import PaddockCore

@Suite("DependencyCheck")
struct DependencyCheckTests {
    func locator(found: Bool) -> BinaryLocator {
        BinaryLocator(loginPath: nil, directories: ["/opt/homebrew/bin"]) { found && $0 == "/opt/homebrew/bin/sbx" }
    }

    func version(_ client: String) -> Data {
        Data(#"{"client":{"version":"\#(client)","revision":"x"},"server":{"state":"running","version":"\#(client)","revision":"x","api_version":"1"}}"#.utf8)
    }

    @Test func installedSbxFromTheFixture() async throws {
        let runner = FakeRunner()
        runner.respond(to: ["version", "--json"], with: try Fixture.data("sbx", "version-0.51.json"))
        let reports = await DependencyCheck(locator: locator(found: true), runner: runner).check()
        let sbx = try #require(reports.first)
        #expect(sbx.path == "/opt/homebrew/bin/sbx")
        #expect(sbx.isSatisfied)
    }

    @Test func missingSbxShowsTheExampleCommand() async throws {
        let reports = await DependencyCheck(locator: locator(found: false), runner: FakeRunner()).check()
        let sbx = try #require(reports.first)
        #expect(sbx.state == .missing)
        #expect(sbx.dependency.exampleInstall == "brew install docker/tap/sbx")
    }

    @Test func tooOldSbx() async throws {
        let runner = FakeRunner()
        runner.respond(to: ["version", "--json"], with: version("0.47.9"))
        let reports = await DependencyCheck(locator: locator(found: true), runner: runner).check()
        #expect(reports.first?.state == .tooOld(found: "0.47.9"))
    }

    @Test func unreadableVersion() async throws {
        let runner = FakeRunner()
        runner.respond(to: ["version", "--json"], with: Data("garbage".utf8))
        let reports = await DependencyCheck(locator: locator(found: true), runner: runner).check()
        guard case .unknownVersion = reports.first?.state else {
            Issue.record("expected unknownVersion, got \(String(describing: reports.first?.state))")
            return
        }
    }

    @Test func loginShellPath() async {
        let runner = FakeRunner()
        runner.respond(to: ["-l", "-c", "printf %s \"$PATH\""], with: Data("/Users/op/.local/bin:/usr/bin\n".utf8))
        #expect(await LoginShell.path(runner: runner) == "/Users/op/.local/bin:/usr/bin")
        #expect(await LoginShell.path(runner: FakeRunner()) == nil)
    }
}

@Suite("StatusProbe")
struct StatusProbeTests {
    let sbxURL = URL(fileURLWithPath: "/opt/homebrew/bin/sbx")

    @Test func runningCountsRunningSandboxes() async throws {
        let runner = FakeRunner()
        runner.respond(to: ["version", "--json"], with: try Fixture.data("sbx", "version-0.51.json"))
        let ls = #"""
        [{"name":"paddock-app","id":"1","agent":"claude","status":"running","workspaces":[],"created_at":"2026-10-24T10:00:00Z"},
         {"name":"paddock-old","id":"2","agent":"claude","status":"stopped","workspaces":[],"created_at":"2026-10-24T10:00:00Z"},
         {"name":"mine","id":"3","agent":"shell","status":"running","workspaces":[],"created_at":"2026-10-24T10:00:00Z"}]
        """#
        runner.respond(to: ["ls", "--json"], with: Data(ls.utf8))
        let state = await StatusProbe.sbxState(SbxService(runner: runner, sbx: sbxURL))
        guard case .running(_, let total, let paddock) = state else {
            Issue.record("expected running, got \(state)")
            return
        }
        #expect(total == 3 && paddock == 2)
    }

    @Test func stoppedDaemon() async {
        let runner = FakeRunner()
        let stopped = #"{"client":{"version":"0.51.0","revision":"x"},"server":{"state":"stopped","version":"","revision":"","api_version":""}}"#
        runner.respond(to: ["version", "--json"], with: Data(stopped.utf8))
        #expect(await StatusProbe.sbxState(SbxService(runner: runner, sbx: sbxURL)) == .daemonStopped(version: "0.51.0"))
    }

    @Test func failingSbxIsUnavailable() async {
        guard case .unavailable = await StatusProbe.sbxState(SbxService(runner: FakeRunner(), sbx: sbxURL)) else {
            Issue.record("expected unavailable")
            return
        }
    }
}
