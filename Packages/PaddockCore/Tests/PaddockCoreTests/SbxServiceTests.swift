import Foundation
import Testing
@testable import PaddockCore

@Suite("SbxService")
struct SbxServiceTests {
    let sbx = URL(fileURLWithPath: "/opt/homebrew/bin/sbx")

    @Test func versionGateAcceptsFixture() async throws {
        let runner = FakeRunner()
        runner.respond(to: ["version", "--json"], with: try Fixture.data("sbx", "version-0.51.json"))
        let version = try await SbxService(runner: runner, sbx: sbx).checkedVersion()
        #expect(version.client.version == "v0.51.0")
    }

    /// 0.49 is too old since PAD-73.2: Paddock's kits are v3 and need sbx's v3 agents (0.51).
    @Test func versionGateRejectsOldSbx() async throws {
        let runner = FakeRunner()
        runner.respond(to: ["version", "--json"], with: try Fixture.data("sbx", "version.json"))
        await #expect(throws: SbxError.versionTooOld(found: "v0.49.2", minimum: SbxService.minimumVersion)) {
            try await SbxService(runner: runner, sbx: sbx).checkedVersion()
        }
    }

    @Test func versionGateRejectsStoppedDaemon() async throws {
        let stopped = String(decoding: try Fixture.data("sbx", "version-0.51.json"), as: UTF8.self)
            .replacingOccurrences(of: "\"running\"", with: "\"stopped\"")
        let runner = FakeRunner()
        runner.respond(to: ["version", "--json"], with: Data(stopped.utf8))
        await #expect(throws: SbxError.daemonNotRunning(state: "stopped")) {
            try await SbxService(runner: runner, sbx: sbx).checkedVersion()
        }
    }

    @Test func usesJSONFlags() async throws {
        let runner = FakeRunner()
        runner.respond(to: ["ls", "--json"], with: try Fixture.data("sbx", "ls.json"))
        runner.respond(to: ["policy", "ls", "m0-claude", "--json"], with: try Fixture.data("sbx", "policy-ls-sandbox.json"))
        runner.respond(to: ["daemon", "status", "--format", "json"], with: try Fixture.data("sbx", "daemon-status.json"))
        runner.respond(to: ["policy", "log", "--json"], with: try Fixture.data("sbx", "policy-log.json"))
        let service = SbxService(runner: runner, sbx: sbx)
        _ = try await service.sandboxes()
        _ = try await service.policies(sandbox: "m0-claude")
        _ = try await service.daemonStatus()
        _ = try await service.policyLog()
        #expect(runner.calls.allSatisfy { $0.contains("--json") || $0.suffix(2) == ["--format", "json"] })
    }

    @Test func failedCommandSurfacesStderr() async throws {
        let runner = FakeRunner()
        runner.respond(to: ["ls", "--json"], with: Data(), exitCode: 1, stderr: "daemon unreachable")
        await #expect(throws: SbxError.commandFailed(arguments: ["ls", "--json"], exitCode: 1, stderr: "daemon unreachable")) {
            try await SbxService(runner: runner, sbx: sbx).sandboxes()
        }
    }

    @Test func failedCommandAddsTheTailOfStdout() async throws {
        let runner = FakeRunner()
        let lines = (1...50).map { "hook line \($0)" }.joined(separator: "\n")
        runner.respond(to: ["env", "create"], with: Data(lines.utf8), exitCode: 1, stderr: "error: failed to apply kit")
        do {
            try await SbxService(runner: runner, sbx: sbx).perform(["env", "create"])
            Issue.record("expected a failure")
        } catch let SbxError.commandFailed(_, _, text) {
            #expect(text.hasPrefix("error: failed to apply kit\noutput:\n"))
            #expect(text.contains("hook line 50") && text.contains("hook line 11") && !text.contains("hook line 10\n"))
        }
    }

    @Test func tableOutputIsADecodingError() async throws {
        let runner = FakeRunner()
        runner.respond(to: ["ls", "--json"], with: Data("NAME  STATUS\nfoo   running\n".utf8))
        do {
            _ = try await SbxService(runner: runner, sbx: sbx).sandboxes()
            Issue.record("expected a decoding error")
        } catch let error as SbxError {
            guard case .decodingFailed = error else {
                Issue.record("unexpected error \(error)")
                return
            }
        }
    }
}
