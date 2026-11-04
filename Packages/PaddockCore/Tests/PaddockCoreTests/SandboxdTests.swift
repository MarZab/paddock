import Foundation
import Testing
@testable import PaddockCore

/// Canned sandboxd answers per path (with its query), and records every request.
final class FakeSandboxdTransport: SandboxdTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: SandboxdResponse] = [:]
    private var streams: [String: [String]] = [:]
    private var failures: [String: SandboxdError] = [:]
    /// Streams that stay open after their lines, as sandboxd's do, until the reader cancels.
    private var held: Set<String> = []
    private var open: [AsyncThrowingStream<String, any Error>.Continuation] = []
    private(set) var requests: [String] = []

    func hold(_ path: String) {
        lock.withLock { _ = held.insert(path) }
    }

    func respond(to path: String, with body: Data, status: Int = 200) {
        lock.withLock { answers[path] = SandboxdResponse(status: status, body: body) }
    }

    func stream(_ path: String, lines: [String]) {
        lock.withLock { streams[path] = lines }
    }

    func fail(_ path: String, with error: SandboxdError) {
        lock.withLock { failures[path] = error }
    }

    func get(_ path: String) async throws -> SandboxdResponse {
        try lock.withLock {
            requests.append(path)
            if let failure = failures[path] { throw failure }
            guard let answer = answers[path] else { throw SandboxdError.unreachable(path: path, message: "no fake answer") }
            return answer
        }
    }

    func lines(_ path: String) -> AsyncThrowingStream<String, any Error> {
        let (lines, failure, isHeld) = lock.withLock {
            requests.append(path)
            return (streams[path], failures[path], held.contains(path))
        }
        return AsyncThrowingStream { continuation in
            if let failure {
                continuation.finish(throwing: failure)
                return
            }
            for line in lines ?? [] { continuation.yield(line) }
            if isHeld && failure == nil {
                lock.withLock { open.append(continuation) }
                return
            }
            let missing = lines == nil ? SandboxdError.unreachable(path: path, message: "no fake stream") : nil
            continuation.finish(throwing: failure ?? missing)
        }
    }
}

enum SandboxdFixture {
    static func lines(_ name: String) throws -> [String] {
        String(decoding: try Fixture.data("sandboxd", name), as: UTF8.self).split(separator: "\n").map(String.init)
    }

    /// sandboxd answering the way it did in the capture.
    static func transport() throws -> FakeSandboxdTransport {
        let transport = FakeSandboxdTransport()
        transport.respond(to: "/daemon/health", with: try Fixture.data("sandboxd", "daemon-health.json"))
        transport.respond(to: "/sandbox", with: try Fixture.data("sandboxd", "sandbox.json"))
        transport.respond(to: "/policy/network/rules?type=all", with: try Fixture.data("sandboxd", "policy-network-rules.json"))
        transport.respond(to: "/policy/network/log", with: try Fixture.data("sandboxd", "policy-network-log.json"))
        transport.stream("/user-prompts", lines: try lines("user-prompts.ndjson"))
        transport.stream("/events", lines: try SandboxStatesTests().fixtureLines())
        return transport
    }

    /// sbx's CLI printing what it printed for the same answers.
    static func runner() throws -> FakeRunner {
        let runner = FakeRunner()
        runner.respond(to: ["ls", "--json"], with: try Fixture.data("sandboxd", "cli-ls.json"))
        runner.respond(to: ["policy", "ls", "--json"], with: try Fixture.data("sandboxd", "cli-policy-ls.json"))
        runner.respond(to: ["policy", "log", "--json"], with: try Fixture.data("sandboxd", "cli-policy-log.json"))
        runner.respond(to: ["policy", "approval", "ls", "--json"], with: try Fixture.data("sandboxd", "cli-policy-approval-ls.json"))
        return runner
    }
}

/// Each answer sandboxd gave to a request `sbx` sent, mapped, equals what that sbx command printed.
@Suite("SandboxdReads")
struct SandboxdReadsTests {
    let sbx = URL(fileURLWithPath: "/sbx")

    @Test func sandboxesMatchSbxLs() async throws {
        let reads = SandboxdReads(transport: try SandboxdFixture.transport())
        let expected = try Fixture.decode([SbxSandbox].self, "sandboxd", "cli-ls.json")
        #expect(try await reads.sandboxes() == expected)
        #expect(!expected.isEmpty)
    }

    @Test func rulesMatchSbxPolicyLs() async throws {
        let reads = SandboxdReads(transport: try SandboxdFixture.transport())
        let expected = try Fixture.decode(SbxPolicyList.self, "sandboxd", "cli-policy-ls.json")
        #expect(try await reads.policies(sandbox: nil) == expected)
    }

    /// `sbx policy ls N` keeps the global rules and N's own (checked against the capture).
    @Test func rulesForOneSandbox() async throws {
        let reads = SandboxdReads(transport: try SandboxdFixture.transport())
        let all = try Fixture.decode(SbxPolicyList.self, "sandboxd", "cli-policy-ls.json").rules
        let name = try #require(all.compactMap(\.sandboxScope).first)
        let rules = try await reads.policies(sandbox: name).rules
        #expect(rules == all.filter { $0.isGlobal || $0.sandboxScope == name })
        #expect(rules.contains { $0.isGlobal } && rules.contains { $0.sandboxScope == name })
        #expect(rules.allSatisfy { $0.isGlobal || $0.sandboxScope == name })
    }

    @Test func logMatchesSbxPolicyLog() async throws {
        let reads = SandboxdReads(transport: try SandboxdFixture.transport())
        let expected = try Fixture.decode(SbxPolicyLog.self, "sandboxd", "cli-policy-log.json")
        let log = try await reads.policyLog(sandbox: nil)
        #expect(log == expected)
        // sbx drops the empty rule of an allowed host that no rule named
        #expect(log.allowed.contains { $0.rule == nil })
    }

    @Test func logForOneSandbox() async throws {
        let reads = SandboxdReads(transport: try SandboxdFixture.transport())
        let all = try Fixture.decode(SbxPolicyLog.self, "sandboxd", "cli-policy-log.json")
        let name = try #require(all.blocked.first?.sandboxId)
        let log = try await reads.policyLog(sandbox: name)
        #expect(log == SbxPolicyLog(allowed: all.allowed.filter { $0.sandboxId == name },
                                    blocked: all.blocked.filter { $0.sandboxId == name }))
        #expect(!log.blocked.isEmpty)
    }

    @Test func approvalsMatchSbxPolicyApprovalLs() async throws {
        let reads = SandboxdReads(transport: try SandboxdFixture.transport())
        let expected = try Fixture.decode([SbxApproval].self, "sandboxd", "cli-policy-approval-ls.json")
        #expect(try await reads.approvals() == expected)
        #expect(!expected.isEmpty)
    }

    @Test func approvalsNeedTheSyncedLine() async throws {
        let transport = try SandboxdFixture.transport()
        transport.stream("/user-prompts", lines: try SandboxdFixture.lines("user-prompts.ndjson").filter { !$0.contains("synced") })
        await #expect(throws: SandboxdError.self) { try await SandboxdReads(transport: transport).approvals() }
    }

    @Test func eventsAreTheLinesSbxEventsPrints() async throws {
        let reads = SandboxdReads(transport: try SandboxdFixture.transport())
        var fromSocket: [SbxEvent] = []
        for try await event in reads.events() { fromSocket.append(event) }
        var fromCLI: [SbxEvent] = []
        let cli = SbxEventStream(streamer: FakeLineStreamer(output: try SandboxStatesTests().fixtureLines()), sbx: sbx)
        for try await event in cli.events() { fromCLI.append(event) }
        #expect(fromSocket == fromCLI)
        #expect(fromSocket.contains { $0.isSyncComplete })
    }

    @Test func healthAcceptsTheCapturedAPI() async throws {
        let health = try await SandboxdReads(transport: try SandboxdFixture.transport()).checkHealth()
        #expect(health.apiVersion == "0.42.0")
        #expect(health.version == "v0.49.2")
    }

    @Test func healthRejectsAnotherAPI() async throws {
        let transport = try SandboxdFixture.transport()
        let other = String(decoding: try Fixture.data("sandboxd", "daemon-health.json"), as: UTF8.self)
            .replacingOccurrences(of: "0.42.0", with: "0.43.0")
        transport.respond(to: "/daemon/health", with: Data(other.utf8))
        await #expect(throws: SandboxdError.unsupportedAPI(found: "0.43.0")) {
            try await SandboxdReads(transport: transport).checkHealth()
        }
    }

    /// Never captured with a value, so not guessed: that read goes to the CLI.
    @Test func runtimeMountsAreNotGuessed() async throws {
        let transport = try SandboxdFixture.transport()
        var sandboxes = try JSONSerialization.jsonObject(with: try Fixture.data("sandboxd", "sandbox.json")) as? [[String: Any]] ?? []
        sandboxes[0]["runtime_mounts"] = [["source": "/tmp/x"]]
        transport.respond(to: "/sandbox", with: try JSONSerialization.data(withJSONObject: sandboxes))
        await #expect(throws: SandboxdError.self) { try await SandboxdReads(transport: transport).sandboxes() }
    }

    /// `sbx ls` left `created_at` out for a sandbox it was still creating (PAD-56).
    @Test func aSandboxWithoutCreatedAtIsListed() async throws {
        let transport = try SandboxdFixture.transport()
        let data = try Fixture.data("sandboxd", "sandbox.json")
        var sandboxes = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        sandboxes[0]["created_at"] = nil
        transport.respond(to: "/sandbox", with: try JSONSerialization.data(withJSONObject: sandboxes))
        let listed = try await SandboxdReads(transport: transport).sandboxes()
        #expect(listed.count == sandboxes.count)
        #expect(listed.first?.createdAt == nil)
    }

    @Test func errorStatusIsAnError() async throws {
        let transport = try SandboxdFixture.transport()
        transport.respond(to: "/sandbox", with: Data(#"{"message":"boom"}"#.utf8), status: 500)
        await #expect(throws: SandboxdError.status(path: "/sandbox", code: 500, body: #"{"message":"boom"}"#)) {
            try await SandboxdReads(transport: transport).sandboxes()
        }
    }

    @Test func onlyGetsWithoutPayloads() async throws {
        let transport = try SandboxdFixture.transport()
        let reads = SandboxdReads(transport: transport)
        _ = try await reads.checkHealth()
        _ = try await reads.sandboxes()
        _ = try await reads.policies(sandbox: "x")
        _ = try await reads.policyLog(sandbox: "x")
        _ = try await reads.approvals()
        #expect(Set(transport.requests)
            == ["/daemon/health", "/sandbox", "/policy/network/rules?type=all", "/policy/network/log", "/user-prompts"])
    }
}

/// Counts connection attempts and hands out a prepared result.
private actor Connector {
    private(set) var attempts = 0
    private let result: Result<FallbackSbxReads.Connection, SandboxdError>

    init(_ result: Result<FallbackSbxReads.Connection, SandboxdError>) {
        self.result = result
    }

    func connect() async throws -> FallbackSbxReads.Connection {
        attempts += 1
        try await Task.sleep(for: .milliseconds(20))
        return try result.get()
    }
}

@Suite("FallbackSbxReads")
struct FallbackSbxReadsTests {
    let sbx = URL(fileURLWithPath: "/sbx")

    private func make(_ transport: FakeSandboxdTransport?, runner: FakeRunner) -> (FallbackSbxReads, Connector) {
        let connector = Connector(transport.map { .success(.init(reads: SandboxdReads(transport: $0), apiVersion: "0.42.0")) }
            ?? .failure(.unreachable(path: "/daemon/health", message: "no socket")))
        let reads = FallbackSbxReads(cli: SbxCLIReads(runner: runner, sbx: sbx)) { try await connector.connect() }
        return (reads, connector)
    }

    @Test func readsFromTheSocketWhenItIsHealthy() async throws {
        let runner = try SandboxdFixture.runner()
        let (reads, _) = make(try SandboxdFixture.transport(), runner: runner)
        #expect(try await reads.sandboxes() == Fixture.decode([SbxSandbox].self, "sandboxd", "cli-ls.json"))
        #expect(try await reads.approvals().count == 2)
        #expect(runner.calls.isEmpty)
        #expect(await reads.source == .socket(apiVersion: "0.42.0"))
    }

    @Test func usesTheCLIWithoutASocketAndWaitsBeforeTryingAgain() async throws {
        let runner = try SandboxdFixture.runner()
        let (reads, connector) = make(nil, runner: runner)
        #expect(try await reads.sandboxes() == Fixture.decode([SbxSandbox].self, "sandboxd", "cli-ls.json"))
        _ = try await reads.policies(sandbox: nil)
        #expect(await connector.attempts == 1)
        #expect(runner.calls == [["ls", "--json"], ["policy", "ls", "--json"]])
        guard case .cli = await reads.source else { Issue.record("source should be the CLI"); return }
    }

    @Test func aFailedSocketReadIsAnsweredByTheCLI() async throws {
        let runner = try SandboxdFixture.runner()
        let transport = try SandboxdFixture.transport()
        transport.fail("/policy/network/log", with: .unreachable(path: "/policy/network/log", message: "gone"))
        let (reads, _) = make(transport, runner: runner)
        #expect(try await reads.policyLog(sandbox: nil) == Fixture.decode(SbxPolicyLog.self, "sandboxd", "cli-policy-log.json"))
        // the socket is out until the retry, even for reads that would work
        _ = try await reads.sandboxes()
        #expect(runner.calls == [["policy", "log", "--json"], ["ls", "--json"]])
        #expect(await reads.source == .cli(reason: "sandboxd's socket did not answer /policy/network/log: gone"))
    }

    @Test func anUnmappedAnswerGoesToTheCLIOnlyOnce() async throws {
        let runner = try SandboxdFixture.runner()
        let transport = try SandboxdFixture.transport()
        transport.fail("/sandbox", with: .unmapped(path: "/sandbox", message: "runtime mounts"))
        let (reads, _) = make(transport, runner: runner)
        _ = try await reads.sandboxes()
        _ = try await reads.policies(sandbox: nil)
        #expect(runner.calls == [["ls", "--json"]])
        #expect(await reads.source == .socket(apiVersion: "0.42.0"))
    }

    /// After sleep: "docker login service unavailable: the host is not fully awake".
    static let busy = SandboxdError.status(path: "/sandbox", code: 503, body: #"{"message":"docker login service unavailable"}"#)

    @Test func aBusyDaemonKeepsTheSocketAndSkipsTheCLI() async throws {
        let runner = try SandboxdFixture.runner()
        let transport = try SandboxdFixture.transport()
        transport.fail("/sandbox", with: Self.busy)
        let (reads, _) = make(transport, runner: runner)
        await #expect(throws: Self.busy) { try await reads.sandboxes() }
        _ = try await reads.policies(sandbox: nil)
        #expect(runner.calls.isEmpty)
        #expect(await reads.source == .socket(apiVersion: "0.42.0"))
    }

    @Test func aBusyHealthCheckIsTriedAgainOnTheNextRead() async throws {
        let runner = try SandboxdFixture.runner()
        let connector = Connector(.failure(.status(path: "/daemon/health", code: 503, body: "{}")))
        let reads = FallbackSbxReads(cli: SbxCLIReads(runner: runner, sbx: sbx)) { try await connector.connect() }
        _ = try await reads.sandboxes()
        _ = try await reads.sandboxes()
        #expect(await connector.attempts == 2)
    }

    @Test func concurrentFirstReadsShareOneHealthCheck() async throws {
        let (reads, connector) = make(try SandboxdFixture.transport(), runner: try SandboxdFixture.runner())
        async let a = reads.sandboxes()
        async let b = reads.policies(sandbox: nil)
        async let c = reads.policyLog(sandbox: nil)
        _ = try await (a, b, c)
        #expect(await connector.attempts == 1)
    }

    @Test func eventsFromTheSocket() async throws {
        let transport = try SandboxdFixture.transport()
        let (reads, _) = make(transport, runner: try SandboxdFixture.runner())
        var count = 0
        for try await _ in reads.events() { count += 1 }
        #expect(count == (try SandboxStatesTests().fixtureLines().count))
        #expect(transport.requests.contains("/events"))
    }

    @Test func eventsFallBackWhenTheSocketStreamFailsAtOnce() async throws {
        let transport = try SandboxdFixture.transport()
        transport.fail("/events", with: .unreachable(path: "/events", message: "refused"))
        transport.stream("/events", lines: [])
        let lines = try SandboxStatesTests().fixtureLines()
        let cli = SbxCLIReads(runner: FakeRunner(), sbx: sbx, streamer: FakeLineStreamer(output: lines))
        let reads = FallbackSbxReads(cli: cli) { .init(reads: SandboxdReads(transport: transport), apiVersion: "0.42.0") }
        var count = 0
        for try await _ in reads.events() { count += 1 }
        #expect(count == lines.count)
        guard case .cli = await reads.source else { Issue.record("source should be the CLI"); return }
    }

    /// SbxService sends reads to its source and every command to sbx.
    @Test func serviceReadsFromItsSourceAndWritesWithSbx() async throws {
        let runner = try SandboxdFixture.runner()
        runner.succeedByDefault = true
        let (reads, _) = make(try SandboxdFixture.transport(), runner: runner)
        let service = SbxService(runner: runner, sbx: sbx, reads: reads)
        _ = try await service.sandboxes()
        _ = try await service.policies(sandbox: nil)
        try await service.perform(["policy", "allow", "network", "--sandbox", "x", "example.com"])
        #expect(runner.calls == [["policy", "allow", "network", "--sandbox", "x", "example.com"]])
    }
}
