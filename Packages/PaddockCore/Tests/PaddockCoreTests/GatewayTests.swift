import Foundation
import Testing
@testable import PaddockCore

/// Security rule: the gateway forwards inference only, pinned to one model (CLAUDE.md).
@Suite("GatewayPolicy")
struct GatewayPolicyTests {
    let policy = GatewayPolicy(maxBodyBytes: 1024)
    var binding: GatewayBinding { GatewayBinding(projectID: UUID(), projectName: "paddock-app", model: "hf.co/unsloth/Qwen3.5-0.8B-GGUF:latest") }

    func decide(_ method: String, _ target: String, body: String = #"{"model":"claude-opus","max_tokens":5}"#,
                headers: [(name: String, value: String)]? = nil) -> GatewayDecision {
        let request = GatewayRequest(method: method, target: target,
                                     headers: headers ?? [("X-Api-Key", "paddock"), ("Content-Type", "application/json")],
                                     body: Data(body.utf8))
        return policy.decide(request, binding: binding)
    }

    func status(_ decision: GatewayDecision) -> Int {
        switch decision {
        case .forward: 0
        case .respond(let status, _): status
        }
    }

    @Test(arguments: ["/v1/messages", "/v1/messages/count_tokens", "/v1/chat/completions", "/v1/responses"])
    func forwardsInferenceRoutes(path: String) {
        guard case .forward(let forwarded, _, _) = decide("POST", path) else {
            Issue.record("\(path) was not forwarded")
            return
        }
        #expect(forwarded == path)
    }

    @Test(arguments: [
        ("POST", "/api/pull"), ("DELETE", "/api/delete"), ("POST", "/api/push"), ("POST", "/api/create"),
        ("GET", "/api/tags"), ("GET", "/llmman/shell"), ("PUT", "/llmman/providers/openai/key"),
        ("GET", "/"), ("GET", "/metrics"), ("GET", "/v1/messages"), ("POST", "/v1/messages/../../api/pull"),
        ("POST", "/v1//messages"), ("POST", "/V1/messages"), ("POST", "/v1/messagesx"), ("GET", "/props"),
    ])
    func refusesEverythingElse(method: String, path: String) {
        #expect(status(decide(method, path)) == 403)
    }

    @Test func refusesRebindingHostsAndBrowserOrigins() {
        for host in ["evil.example:17500", "evil.example", "127.0.0.1.evil.example", "192.168.1.5:17500"] {
            #expect(status(decide("POST", "/v1/messages", headers: [("Host", host), ("Content-Type", "application/json")])) == 403)
        }
        #expect(status(decide("POST", "/v1/messages", headers: [("Host", "localhost:17500"), ("Origin", "https://evil.example")])) == 403)
        #expect(status(decide("GET", "/v1/models", headers: [("Origin", "http://localhost:3000")])) == 403)
    }

    @Test func answersLoopbackAndSandboxHostNames() {
        for host in ["127.0.0.1:17500", "localhost:17500", "LOCALHOST", "[::1]:17500", "host.docker.internal:17500"] {
            #expect(status(decide("GET", "/v1/models", headers: [("Host", host)])) == 200)
        }
    }

    @Test func queryStringsDoNotChangeTheRoute() {
        guard case .forward(let path, _, _) = decide("POST", "/v1/messages?beta=true") else {
            Issue.record("not forwarded")
            return
        }
        #expect(path == "/v1/messages")
    }

    @Test func anyKeyIsFineBecauseThePortIdentifiesTheProject() {
        #expect(status(decide("POST", "/v1/messages", headers: [("content-type", "application/json")])) == 0)
        #expect(status(decide("POST", "/v1/chat/completions", headers: [("Authorization", "Bearer whatever")])) == 0)
    }

    @Test func pinsTheModel() throws {
        guard case .forward(_, _, let body) = decide("POST", "/v1/messages") else {
            Issue.record("not forwarded")
            return
        }
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == binding.model)
        #expect(object["max_tokens"] as? Int == 5)
    }

    @Test func pinsEvenWhenTheModelIsMissing() throws {
        guard case .forward(_, _, let body) = decide("POST", "/v1/messages", body: #"{"messages":[]}"#) else {
            Issue.record("not forwarded")
            return
        }
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == binding.model)
    }

    @Test(arguments: ["[]", "\"text\"", "not json", ""])
    func rejectsNonObjectBodies(body: String) {
        #expect(status(decide("POST", "/v1/messages", body: body)) == 400)
    }

    @Test func enforcesTheBodyLimit() {
        let big = #"{"x":""# + String(repeating: "a", count: 2048) + #""}"#
        #expect(status(decide("POST", "/v1/messages", body: big)) == 413)
    }

    @Test func forwardsOnlyAllowedHeaders() {
        let decision = decide("POST", "/v1/messages", headers: [
            ("x-api-key", "paddock"), ("Authorization", "Bearer paddock"), ("Cookie", "a=b"),
            ("Anthropic-Version", "2023-06-01"), ("Host", "evil"), ("X-Forwarded-For", "1.2.3.4"), ("Connection", "upgrade"),
        ])
        guard case .forward(_, let headers, _) = decision else {
            Issue.record("not forwarded")
            return
        }
        #expect(Set(headers.map(\.name)) == ["anthropic-version", "content-type"])
    }

    @Test func answersModelListItself() throws {
        guard case .respond(200, let body) = decide("GET", "/v1/models") else {
            Issue.record("models list not answered")
            return
        }
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try #require(object["data"] as? [[String: Any]])
        #expect(data.map { $0["id"] as? String } == [binding.model])
    }

    @Test func concurrencyLimiterCapsPerProject() async {
        let limiter = GatewayConcurrencyLimiter(limitPerProject: 2)
        let a = UUID()
        let b = UUID()
        #expect(await limiter.acquire(a))
        #expect(await limiter.acquire(a))
        #expect(!(await limiter.acquire(a)))
        #expect(await limiter.acquire(b))
        await limiter.release(a)
        #expect(await limiter.acquire(a))
    }
}

/// Security rule: llmman's port is defined once, so the deny, the reserved ports, the web view and the
/// gateway's upstream cannot drift apart (PAD-89).
@Suite("llmman endpoint")
struct LlmmanEndpointTests {
    @Test func everyUseAgrees() {
        #expect(LlmmanWebPolicy.port == AppConfig.llmmanPort)
        #expect(AppConfig.reservedPorts.contains(AppConfig.llmmanPort))
        #expect(ModelGateway.Configuration().upstream == "http://127.0.0.1:\(AppConfig.llmmanPort)")
        #expect(LlmmanWebPolicy.homeURL.port == AppConfig.llmmanPort)
    }
}
