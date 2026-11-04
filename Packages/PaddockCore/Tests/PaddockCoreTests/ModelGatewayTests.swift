import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import Testing
@testable import PaddockCore

/// A fake llmman: echoes what it received, streams SSE, or fails, and records every path.
final class FakeUpstream: Sendable {
    let channel: NIOAsyncChannel<NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>, Never>
    let received = Received()

    final class Received: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(path: String, headers: [String: String], body: Data)] = []
        func add(_ path: String, _ headers: [String: String], _ body: Data) { lock.withLock { items.append((path, headers, body)) } }
        var all: [(path: String, headers: [String: String], body: Data)] { lock.withLock { items } }
    }

    var port: Int { channel.channel.localAddress?.port ?? 0 }

    init() async throws {
        channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .bind(host: "127.0.0.1", port: 0) { child in
                child.eventLoop.makeCompletedFuture {
                    try child.pipeline.syncOperations.configureHTTPServerPipeline()
                    return try NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>(wrappingChannelSynchronously: child)
                }
            }
    }

    func serve() async throws {
        let received = self.received
        try await withThrowingDiscardingTaskGroup { group in
            try await channel.executeThenClose { inbound in
                for try await connection in inbound {
                    group.addTask {
                        try? await connection.executeThenClose { requests, out in
                            var head: HTTPRequestHead?
                            var body = Data()
                            for try await part in requests {
                                switch part {
                                case .head(let h): head = h; body = Data()
                                case .body(let b): body.append(contentsOf: b.readableBytesView)
                                case .end:
                                    guard let h = head else { continue }
                                    var hs: [String: String] = [:]
                                    for (k, v) in h.headers { hs[k.lowercased()] = v }
                                    received.add(h.uri, hs, body)
                                    try await Self.reply(h.uri, body, out)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    static func reply(_ path: String, _ body: Data, _ out: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>) async throws {
        switch path {
        case "/v1/chat/completions":
            var headers = HTTPHeaders()
            headers.add(name: "content-type", value: "text/event-stream")
            try await out.write(.head(HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)))
            for i in 1...3 {
                let usage = i == 3 ? #","usage":{"prompt_tokens":11,"completion_tokens":3}"# : ""
                try await out.write(.body(.byteBuffer(ByteBuffer(string: "data: {\"n\":\(i)\(usage)}\n\n"))))
                try await Task.sleep(for: .milliseconds(20))
            }
            try await out.write(.end(nil))
        case "/v1/responses":
            let data = ByteBuffer(string: #"{"error":"boom"}"#)
            var headers = HTTPHeaders()
            headers.add(name: "content-type", value: "application/json")
            headers.add(name: "content-length", value: String(data.readableBytes))
            try await out.write(.head(HTTPResponseHead(version: .http1_1, status: .internalServerError, headers: headers)))
            try await out.write(.body(.byteBuffer(data)))
            try await out.write(.end(nil))
        default:
            let echo = String(decoding: body, as: UTF8.self)
            let data = ByteBuffer(string: #"{"echo":\#(echo),"usage":{"input_tokens":3,"output_tokens":7}}"#)
            var headers = HTTPHeaders()
            headers.add(name: "content-type", value: "application/json")
            headers.add(name: "content-length", value: String(data.readableBytes))
            try await out.write(.head(HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)))
            try await out.write(.body(.byteBuffer(data)))
            try await out.write(.end(nil))
        }
    }

    func stop() async { try? await channel.channel.close() }
}

final class LogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [GatewayLogEntry] = []
    func add(_ entry: GatewayLogEntry) { lock.withLock { items.append(entry) } }
    var entries: [GatewayLogEntry] { lock.withLock { items } }

    /// The gateway logs after it finishes the response, so a client can see the reply first.
    func waitForEntries(timeout: Duration = .seconds(2)) async -> [GatewayLogEntry] {
        let deadline = ContinuousClock.now + timeout
        while entries.isEmpty && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return entries
    }
}

/// End-to-end through real sockets: client -> gateway -> fake llmman.
@Suite("ModelGateway", .serialized)
struct ModelGatewayTests {
    struct Harness {
        let upstream: FakeUpstream
        let gateway: ModelGateway
        let bound: BoundGateway
        let client: HTTPClient
        let logs: LogBox
        let tasks: [Task<Void, Never>]
        let base: String

        static let model = "hf.co/unsloth/Qwen3.5-0.8B-GGUF:latest"

        static func start(upstreamPort: Int? = nil, maxConcurrent: Int = 2) async throws -> Harness {
            let upstream = try await FakeUpstream()
            var config = ModelGateway.Configuration()
            config.upstream = "http://127.0.0.1:\(upstreamPort ?? upstream.port)"
            config.maxBodyBytes = 4096
            config.maxConcurrentPerProject = maxConcurrent
            let logs = LogBox()
            let gateway = ModelGateway(configuration: config) { logs.add($0) }
            let bound = try await gateway.bind(port: 0, binding: GatewayBinding(projectID: UUID(), projectName: "paddock-app", model: model))
            let tasks = [
                Task { _ = try? await upstream.serve() },
                Task { _ = try? await bound.serve() },
            ]
            let client = HTTPClient(eventLoopGroupProvider: .singleton)
            return Harness(upstream: upstream, gateway: gateway, bound: bound, client: client,
                           logs: logs, tasks: tasks, base: "http://127.0.0.1:\(bound.port ?? 0)")
        }

        func send(_ method: HTTPMethod, _ path: String, body: String? = nil, base: String? = nil) async throws -> (status: Int, headers: HTTPHeaders, body: String) {
            var request = HTTPClientRequest(url: (base ?? self.base) + path)
            request.method = method
            request.headers.add(name: "x-api-key", value: "paddock")
            request.headers.add(name: "authorization", value: "Bearer paddock")
            request.headers.add(name: "content-type", value: "application/json")
            if let body { request.body = .bytes(ByteBuffer(string: body)) }
            let response = try await client.execute(request, timeout: .seconds(10))
            let collected = try await response.body.collect(upTo: 1 << 20)
            return (Int(response.status.code), response.headers, String(buffer: collected))
        }

        func stop() async throws {
            try await client.shutdown()
            await bound.stop()
            await upstream.stop()
            for task in tasks { task.cancel() }
            try await gateway.shutdown()
        }
    }

    @Test func forwardsAndPinsTheModel() async throws {
        let h = try await Harness.start()
        let reply = try await h.send(.POST, "/v1/messages", body: #"{"model":"claude-opus-4-8","max_tokens":5}"#)
        let logged = await h.logs.waitForEntries()
        try await h.stop()
        #expect(reply.status == 200)
        let sent = try #require(h.upstream.received.all.first)
        #expect(sent.path == "/v1/messages")
        let object = try #require(try JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        #expect(object["model"] as? String == Harness.model)
        // the agent's dummy key never reaches llmman
        #expect(sent.headers["x-api-key"] == nil)
        #expect(sent.headers["authorization"] == nil)
        let entry = try #require(logged.first)
        #expect(entry.project == "paddock-app" && entry.status == 200)
        #expect(entry.inputTokens == 3 && entry.outputTokens == 7)
    }

    @Test func blockedRoutesNeverReachLlmman() async throws {
        let h = try await Harness.start()
        let pull = try await h.send(.POST, "/api/pull", body: #"{"model":"evil/gguf"}"#)
        let shell = try await h.send(.GET, "/llmman/shell")
        try await h.stop()
        #expect(pull.status == 403)
        #expect(shell.status == 403)
        #expect(h.upstream.received.all.isEmpty)
    }

    @Test func streamsServerSentEvents() async throws {
        let h = try await Harness.start()
        let reply = try await h.send(.POST, "/v1/chat/completions", body: #"{"stream":true}"#)
        let logged = await h.logs.waitForEntries()
        try await h.stop()
        #expect(reply.status == 200)
        #expect(reply.headers.first(name: "content-type") == "text/event-stream")
        #expect(reply.body.components(separatedBy: "data: ").count == 4)
        #expect(logged.first?.inputTokens == 11)
        #expect(logged.first?.outputTokens == 3)
    }

    @Test func upstreamErrorsPassThrough() async throws {
        let h = try await Harness.start()
        let reply = try await h.send(.POST, "/v1/responses", body: "{}")
        try await h.stop()
        #expect(reply.status == 500)
        #expect(reply.body == #"{"error":"boom"}"#)
    }

    @Test func unreachableUpstreamIsA502() async throws {
        let h = try await Harness.start(upstreamPort: 9)  // discard port, nothing listens
        let reply = try await h.send(.POST, "/v1/messages", body: "{}")
        try await h.stop()
        #expect(reply.status == 502)
    }

    @Test func oversizedBodiesAreRejected() async throws {
        let h = try await Harness.start()
        let big = #"{"x":""# + String(repeating: "a", count: 8000) + #""}"#
        let reply = try await h.send(.POST, "/v1/messages", body: big)
        try await h.stop()
        #expect(reply.status == 413)
        #expect(h.upstream.received.all.isEmpty)
    }

    @Test func modelListIsLocal() async throws {
        let h = try await Harness.start()
        let reply = try await h.send(.GET, "/v1/models")
        try await h.stop()
        #expect(reply.status == 200)
        #expect(reply.body.contains(Harness.model))
        #expect(h.upstream.received.all.isEmpty)
    }

    @Test func eachPortServesItsOwnProjectAndModel() async throws {
        let h = try await Harness.start()
        let other = try await h.gateway.bind(port: 0, binding: GatewayBinding(projectID: UUID(), projectName: "paddock-other", model: "other-model"))
        let task = Task { _ = try? await other.serve() }
        _ = try await h.send(.POST, "/v1/messages", body: "{}")
        _ = try await h.send(.POST, "/v1/messages", body: "{}", base: "http://127.0.0.1:\(other.port ?? 0)")
        let logged = await h.logs.waitForEntries()
        await other.stop()
        task.cancel()
        try await h.stop()
        let models = try h.upstream.received.all.map {
            try #require(try JSONSerialization.jsonObject(with: $0.body) as? [String: Any])["model"] as? String
        }
        #expect(models == [Harness.model, "other-model"])
        #expect(Set(logged.map(\.project)).isSubset(of: ["paddock-app", "paddock-other"]))
    }

    @Test func refusesNonLoopbackHosts() async throws {
        var config = ModelGateway.Configuration()
        config.host = "0.0.0.0"
        let gateway = ModelGateway(configuration: config) { _ in }
        let binding = GatewayBinding(projectID: UUID(), projectName: "paddock-app", model: "m")
        await #expect(throws: ModelGateway.GatewayError.notLoopback("0.0.0.0")) { _ = try await gateway.bind(port: 0, binding: binding) }
        try await gateway.shutdown()
    }

    @Test func connectionsAreBounded() async throws {
        // PAD-88: each connection may hold a request body in memory.
        var config = ModelGateway.Configuration()
        config.maxConnections = 2
        let gateway = ModelGateway(configuration: config) { _ in }
        #expect(gateway.admitConnection())
        #expect(gateway.admitConnection())
        #expect(!gateway.admitConnection())
        gateway.releaseConnection()
        #expect(gateway.admitConnection())
        try await gateway.shutdown()
    }

    @Test func occupiedPortIsAClearError() async throws {
        let h = try await Harness.start()
        let port = try #require(h.bound.port)
        let second = ModelGateway(configuration: .init()) { _ in }
        let binding = GatewayBinding(projectID: UUID(), projectName: "paddock-other", model: "m")
        await #expect(throws: ModelGateway.GatewayError.portInUse(port)) { _ = try await second.bind(port: port, binding: binding) }
        try await second.shutdown()
        try await h.stop()
    }

    @Test func usageParsing() {
        let sse = Data(#"data: {"usage":{"input_tokens":1}}\n\ndata: {"usage":{"input_tokens":9,"output_tokens":4}}"#.utf8)
        let usage = GatewayUsage.extract(from: sse)
        #expect(usage.input == 9 && usage.output == 4)
        #expect(GatewayUsage.extract(from: Data("{}".utf8)).input == nil)
    }
}
