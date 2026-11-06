import Foundation
import Testing
@testable import PaddockCore

/// Answers llmman paths with fixtures from `Fixtures/llmman`.
struct FixtureTransport: LlmmanTransport {
    var files: [String: String] = [
        "/api/version": "version.json",
        "/api/tags": "tags.json",
        "/api/ps": "ps-empty.json",
        "/llmman/node": "node.json",
        "/llmman/shell": "shell-status.json",
    ]
    var overrides: [String: (Int, String)] = [:]

    func get(_ path: String) async throws -> (status: Int, body: Data) {
        if let (status, body) = overrides[path] {
            return (status, Data(body.utf8))
        }
        guard let name = files[path] else { return (404, Data()) }
        return (200, try Fixture.data("llmman", name))
    }
}

@Suite("LlmmanAPI")
struct LlmmanAPITests {
    @Test func readsEveryEndpointFromFixtures() async throws {
        let api = LlmmanAPI(transport: FixtureTransport())
        #expect(try await api.version().pid == 65175)
        #expect(try await api.tags().models.first?.name == "hf.co/unsloth/Qwen3.5-0.8B-GGUF:latest")
        #expect(try await api.loaded().models.isEmpty)
        #expect(try await api.node().memory == 68_719_476_736)
        #expect(try await api.shellStatus() == LlmmanShellStatus(enabled: false, reason: "LLMMAN_SHELL is off"))
    }

    @Test func onlyReadOnlyPathsAreAllowed() {
        #expect(LlmmanAPI.allowedPaths == ["/api/version", "/api/tags", "/api/ps", "/llmman/node", "/llmman/shell"])
        for path in ["/api/pull", "/api/delete", "/api/create", "/api/push", "/llmman/providers"] {
            #expect(!LlmmanAPI.allowedPaths.contains(path))
        }
    }

    @Test func errorsAreTyped() async {
        var transport = FixtureTransport()
        transport.overrides["/api/version"] = (500, "{}")
        transport.overrides["/api/tags"] = (200, "not json")
        let api = LlmmanAPI(transport: transport)
        await #expect(throws: LlmmanError.httpStatus(path: "/api/version", status: 500)) { try await api.version() }
        await #expect(throws: LlmmanError.self) { try await api.tags() }
    }

    /// Security rule: never open the shell's WebSocket. The status request is a plain GET.
    @Test func shellStatusIsAPlainGetWithoutUpgrade() async throws {
        let upstream = try await FakeUpstream()
        let task = Task { _ = try? await upstream.serve() }
        let transport = HTTPLlmmanTransport(base: "http://127.0.0.1:\(upstream.port)")
        _ = try await transport.get("/llmman/shell")
        try await transport.shutdown()
        await upstream.stop()
        task.cancel()
        let sent = try #require(upstream.received.all.first)
        #expect(sent.path == "/llmman/shell")
        #expect(sent.headers["upgrade"] == nil)
        #expect(sent.headers["sec-websocket-key"] == nil)
        #expect(sent.headers["connection"]?.lowercased().contains("upgrade") != true)
    }

    @Test func unreachableLlmmanFailsFast() async throws {
        let transport = HTTPLlmmanTransport(base: "http://127.0.0.1:9")
        let started = ContinuousClock.now
        let error = await #expect(throws: (any Error).self) { _ = try await transport.get("/api/version") }
        try await transport.shutdown()
        // Refused, not the connect timeout: a time limit alone fails on a loaded CI runner, where
        // this took 6 s with nothing waiting.
        #expect(error.map { "\($0)".contains("Connection refused") } ?? false)
        #expect(ContinuousClock.now - started < .seconds(15))
    }
}

/// Security rule: local models only while every hardening check is green (CLAUDE.md).
@Suite("LlmmanHealth")
struct LlmmanHealthTests {
    let version = try? Fixture.decode(LlmmanVersion.self, "llmman", "version.json")
    let shellOff = try? Fixture.decode(LlmmanShellStatus.self, "llmman", "shell-status.json")
    let loopback = [ListenAddress(host: "127.0.0.1", port: 17434), ListenAddress(host: "::1", port: 17434)]

    @Test func allGreenOnTheVerifiedSetup() {
        let health = LlmmanHealthEvaluator.evaluate(version: version, shell: shellOff, listeners: loopback, promptHistoryBytes: nil)
        #expect(health.overall == .green)
        #expect(health.allowsLocalModels)
        #expect(Set(health.checks.map(\.kind)) == Set(LlmmanHealth.Kind.allCases))
    }

    @Test func promptHistoryIsOnlyAWarning() {
        let health = LlmmanHealthEvaluator.evaluate(version: version, shell: shellOff, listeners: loopback, promptHistoryBytes: 2048)
        #expect(health.check(.promptHistory)?.status == .yellow)
        #expect(health.overall == .yellow)
        #expect(health.allowsLocalModels)
    }

    @Test func shellOnBlocksLocalModels() {
        let on = LlmmanShellStatus(enabled: true, reason: nil)
        let health = LlmmanHealthEvaluator.evaluate(version: version, shell: on, listeners: loopback, promptHistoryBytes: nil)
        #expect(health.check(.shellOff)?.status == .red)
        #expect(!health.allowsLocalModels)
    }

    @Test func unknownShellStatusIsRed() {
        let health = LlmmanHealthEvaluator.evaluate(version: version, shell: nil, listeners: loopback, promptHistoryBytes: nil)
        #expect(health.check(.shellOff)?.status == .red)
    }

    @Test func lanListenerIsRed() {
        let listeners = loopback + [ListenAddress(host: "*", port: 17434)]
        let health = LlmmanHealthEvaluator.evaluate(version: version, shell: shellOff, listeners: listeners, promptHistoryBytes: nil)
        #expect(health.check(.loopbackOnly)?.status == .red)
        #expect(health.check(.loopbackOnly)?.detail.contains("*:17434") == true)
    }

    @Test func unexpectedPortIsRed() {
        let health = LlmmanHealthEvaluator.evaluate(version: version, shell: shellOff,
                                                    listeners: [ListenAddress(host: "127.0.0.1", port: 17999)], promptHistoryBytes: nil)
        #expect(health.check(.expectedPort)?.status == .red)
        #expect(health.check(.loopbackOnly)?.status == .green)
    }

    @Test func nothingObservedIsAllRedExceptHistory() {
        let health = LlmmanHealthEvaluator.evaluate(version: nil, shell: nil, listeners: nil, promptHistoryBytes: nil)
        #expect(health.checks.filter { $0.status == .red }.map(\.kind) == [.reachable, .shellOff, .loopbackOnly, .expectedPort])
        #expect(!health.allowsLocalModels)
    }

    /// Captured on the operator's Mac: `lsof -nP -a -p PID -iTCP -sTCP:LISTEN -F n` for llmman.
    @Test func parsesCapturedLsofOutput() throws {
        let output = String(decoding: try Fixture.data("lsof", "llmman-listen.txt"), as: UTF8.self)
        #expect(ListenAddress.parse(lsofFields: output) == [ListenAddress(host: "127.0.0.1", port: 17434)])
    }

    /// Forms not seen on the Mac yet: IPv6 brackets and a wildcard.
    @Test func parsesOtherLsofForms() {
        let output = "p65175\nf9\nn127.0.0.1:17434\nf10\nn[::1]:17434\nf11\nn*:8080\n"
        #expect(ListenAddress.parse(lsofFields: output) == [
            ListenAddress(host: "127.0.0.1", port: 17434),
            ListenAddress(host: "::1", port: 17434),
            ListenAddress(host: "*", port: 8080),
        ])
        #expect(ListenAddress.parse(lsofFields: "") == [])
        #expect(!ListenAddress(host: "*", port: 1).isLoopback && !ListenAddress(host: "192.168.1.5", port: 1).isLoopback)
    }

    @Test func checkerGathersEverything() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-llmman-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: home) }
        let history = LlmmanHealthChecker.promptHistoryPath(home: home)
        try FileManager.default.createDirectory(atPath: (history as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(String(repeating: "x", count: 100).utf8).write(to: URL(fileURLWithPath: history))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: history)

        let runner = FakeRunner()
        runner.respond(to: ["-nP", "-a", "-p", "65175", "-iTCP", "-sTCP:LISTEN", "-F", "n"],
                       with: try Fixture.data("lsof", "llmman-listen.txt"))
        let checker = LlmmanHealthChecker(api: LlmmanAPI(transport: FixtureTransport()), runner: runner, home: home)
        let health = await checker.check()
        #expect(health.check(.loopbackOnly)?.status == .green)
        #expect(health.check(.expectedPort)?.status == .green)
        #expect(health.check(.promptHistory)?.status == .yellow)

        try checker.clearPromptHistory()
        let attributes = try FileManager.default.attributesOfItem(atPath: history)
        #expect((attributes[.size] as? NSNumber)?.intValue == 0)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(await checker.check().check(.promptHistory)?.status == .green)
    }

    @Test func lsofFailureIsRed() async {
        let checker = LlmmanHealthChecker(api: LlmmanAPI(transport: FixtureTransport()), runner: FakeRunner(), home: "/nonexistent")
        #expect(await checker.check().check(.loopbackOnly)?.status == .red)
    }
}

/// Security rule: embed llmman's UI, never its shell (CLAUDE.md).
@Suite("LlmmanWebPolicy")
struct LlmmanWebPolicyTests {
    func url(_ text: String) throws -> URL { try #require(URL(string: text)) }

    @Test func homeIsLlmmanOnLoopback() {
        #expect(LlmmanWebPolicy.homeURL.absoluteString == "http://127.0.0.1:17434/")
    }

    @Test(arguments: ["http://127.0.0.1:17434/", "http://127.0.0.1:17434/models?q=x", "http://localhost:17434/chat", "about:blank"])
    func allowsLlmmanPages(page: String) throws {
        #expect(LlmmanWebPolicy.decide(url: try url(page), userClicked: false) == .allow)
    }

    @Test(arguments: ["http://127.0.0.1:17434/llmman/shell", "http://127.0.0.1:17434/llmman/shell/x",
                      "http://127.0.0.1:17434/LLMMAN/SHELL", "ws://127.0.0.1:17434/llmman/shell"])
    func blocksTheShellEvenWhenClicked(page: String) throws {
        #expect(LlmmanWebPolicy.decide(url: try url(page), userClicked: true) == .block)
    }

    @Test func otherSitesOpenOnlyWhenClicked() throws {
        let site = try url("https://huggingface.co/unsloth")
        #expect(LlmmanWebPolicy.decide(url: site, userClicked: true) == .openExternally)
        #expect(LlmmanWebPolicy.decide(url: site, userClicked: false) == .block)
        // other local ports and schemes never load or open
        #expect(LlmmanWebPolicy.decide(url: try url("http://127.0.0.1:17480/v1/models"), userClicked: false) == .block)
        #expect(LlmmanWebPolicy.decide(url: try url("file:///etc/passwd"), userClicked: true) == .block)
        #expect(LlmmanWebPolicy.decide(url: try url("http://127.0.0.1.evil.example:17434/"), userClicked: false) == .block)
    }

    @Test func contentRulesBlockAllButLlmmanThenTheShell() throws {
        let data = Data(LlmmanWebPolicy.contentRules.utf8)
        let rules = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: [String: String]]])
        #expect(rules.first?["action"]?["type"] == "block")
        #expect(rules.first?["trigger"]?["url-filter"] == ".*")
        #expect(rules.last?["action"]?["type"] == "block")
        #expect(rules.last?["trigger"]?["url-filter"] == "/llmman/shell")
        let allowed = rules.filter { $0["action"]?["type"] == "ignore-previous-rules" }.compactMap { $0["trigger"]?["url-filter"] }
        #expect(allowed.contains(#"^http://127\.0\.0\.1:17434/"#))
        #expect(allowed.contains(#"^ws://127\.0\.0\.1:17434/"#))
        // WebKit's url-filter has no alternation or lookahead
        #expect(!LlmmanWebPolicy.contentRules.contains("|") && !LlmmanWebPolicy.contentRules.contains("(?"))
    }
}
