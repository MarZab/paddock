import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import Synchronization

/// Paddock's model gateway: the only path from a sandbox to a model (backlog doc ModelGateway).
/// One loopback listener per project (`bind(port:binding:)`), all sharing one upstream client.
/// Every decision is made by `GatewayPolicy`; this type only moves bytes.
public final class ModelGateway: Sendable {
    public struct Configuration: Sendable {
        /// Loopback only. Anything else is refused at bind time.
        public var host: String = "127.0.0.1"
        /// llmman. Not configurable from any config file; tests point it at a fake.
        public var upstream: String = "http://127.0.0.1:\(AppConfig.llmmanPort)"
        public var maxBodyBytes: Int = 32 * 1024 * 1024
        public var maxConcurrentPerProject: Int = 2
        /// Open client connections across all listeners; one more is closed at once. Each may hold a
        /// request body up to `maxBodyBytes` in memory, so this bounds memory (PAD-88).
        public var maxConnections: Int = 32
        public var upstreamTimeout: TimeAmount = .minutes(30)

        public init() {}

        public init(models: AppConfig.Models) {
            self.maxBodyBytes = models.maxBodyMB * 1024 * 1024
            self.maxConcurrentPerProject = models.maxConcurrentPerProject
        }
    }

    public enum GatewayError: Error, Equatable, CustomStringConvertible {
        case notLoopback(String)
        case portInUse(Int)

        public var description: String {
            switch self {
            case .notLoopback(let host): "the gateway only listens on loopback, not \(host)"
            case .portInUse(let port): "port \(port) is already in use (is another gateway still running?)"
            }
        }
    }

    private let configuration: Configuration
    private let policy: GatewayPolicy
    private let limiter: GatewayConcurrencyLimiter
    private let client: HTTPClient
    private let log: @Sendable (GatewayLogEntry) -> Void
    private let openConnections = Mutex(0)

    /// How much of each response is kept to read token usage from; bodies are never logged.
    private static let usageTailBytes = 64 * 1024

    public init(configuration: Configuration, log: @escaping @Sendable (GatewayLogEntry) -> Void) {
        self.configuration = configuration
        self.policy = GatewayPolicy(maxBodyBytes: configuration.maxBodyBytes)
        self.limiter = GatewayConcurrencyLimiter(limitPerProject: configuration.maxConcurrentPerProject)
        // No proxy, no redirects, no decompression: bytes go to llmman and back unchanged.
        // A refused connection fails at once (502) instead of being retried until the long
        // generation deadline; `upstreamTimeout` only bounds a request that did connect.
        var clientConfiguration = HTTPClient.Configuration(redirectConfiguration: .disallow)
        clientConfiguration.connectionPool.retryConnectionEstablishment = false
        clientConfiguration.timeout.connect = .seconds(5)
        self.client = HTTPClient(eventLoopGroupProvider: .singleton, configuration: clientConfiguration)
        self.log = log
    }

    /// Binds one project's listener. Call `serve()` on the result to accept connections.
    public func bind(port: Int, binding: GatewayBinding) async throws -> BoundGateway {
        guard ["127.0.0.1", "::1"].contains(configuration.host) else {
            throw GatewayError.notLoopback(configuration.host)
        }
        do {
            let channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .bind(host: configuration.host, port: port) { child in
                    child.eventLoop.makeCompletedFuture {
                        try child.pipeline.syncOperations.configureHTTPServerPipeline()
                        return try NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>(wrappingChannelSynchronously: child)
                    }
                }
            return BoundGateway(gateway: self, binding: binding, channel: channel)
        } catch let error as IOError where error.errnoCode == EADDRINUSE {
            throw GatewayError.portInUse(port)
        }
    }

    /// Releases the upstream client. Call after the bound gateway has stopped, and also when
    /// `bind()` failed: the client must be shut down before the gateway is released.
    public func shutdown() async throws {
        try await client.shutdown()
    }

    // MARK: - Connections

    typealias Connection = NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>

    /// Counts a new connection; false (nothing counted) when the gateway is at its limit.
    func admitConnection() -> Bool {
        openConnections.withLock { count in
            guard count < configuration.maxConnections else { return false }
            count += 1
            return true
        }
    }

    func releaseConnection() {
        openConnections.withLock { $0 -= 1 }
    }

    func handle(_ connection: Connection, binding: GatewayBinding) async {
        do {
            try await connection.executeThenClose { inbound, outbound in
                var head: HTTPRequestHead?
                var body = ByteBuffer()
                var oversized = false
                for try await part in inbound {
                    switch part {
                    case .head(let next):
                        head = next
                        body.clear()
                        oversized = false
                    case .body(var chunk):
                        if body.readableBytes + chunk.readableBytes > configuration.maxBodyBytes {
                            oversized = true
                        } else if !oversized {
                            body.writeBuffer(&chunk)
                        }
                    case .end:
                        guard let request = head else { continue }
                        head = nil
                        let keepAlive = try await respond(to: request, body: body, oversized: oversized, binding: binding, outbound: outbound)
                        if !keepAlive { return }
                    }
                }
            }
        } catch {
            // A broken client connection only affects that client.
        }
    }

    /// Returns whether the connection may be reused.
    private func respond(
        to head: HTTPRequestHead,
        body: ByteBuffer,
        oversized: Bool,
        binding: GatewayBinding,
        outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>
    ) async throws -> Bool {
        let started = ContinuousClock.now
        let keepAlive = head.isKeepAlive
        let route = "\(head.method.rawValue) \(head.uri.split(separator: "?").first ?? "")"
        let request = GatewayRequest(
            method: head.method.rawValue,
            target: head.uri,
            headers: head.headers.map { (name: $0.name, value: $0.value) },
            body: Data(body.readableBytesView)
        )

        let decision: GatewayDecision
        if oversized {
            decision = GatewayPolicy.error(413, "request_too_large", "request body is larger than \(configuration.maxBodyBytes) bytes")
        } else {
            decision = policy.decide(request, binding: binding)
        }

        switch decision {
        case .respond(let status, let data):
            try await writeLocal(status: status, body: data, version: head.version, keepAlive: keepAlive, to: outbound)
            log(GatewayLogEntry(date: Date(), project: binding.projectName, route: route, status: status, requestBytes: body.readableBytes,
                                responseBytes: data.count, duration: ContinuousClock.now - started, inputTokens: nil, outputTokens: nil))
            return keepAlive

        case .forward(let path, let headers, let pinnedBody):
            guard await limiter.acquire(binding.projectID) else {
                let busy = GatewayPolicy.error(429, "rate_limit_error", "too many concurrent requests for \(binding.projectName)")
                if case .respond(let status, let data) = busy {
                    try await writeLocal(status: status, body: data, version: head.version, keepAlive: keepAlive, to: outbound)
                    log(GatewayLogEntry(date: Date(), project: binding.projectName, route: route, status: status, requestBytes: body.readableBytes,
                                        responseBytes: data.count, duration: ContinuousClock.now - started, inputTokens: nil, outputTokens: nil))
                }
                return keepAlive
            }
            let result = await forward(path: path, headers: headers, body: pinnedBody, head: head, keepAlive: keepAlive, to: outbound)
            await limiter.release(binding.projectID)
            let usage = GatewayUsage.extract(from: result.tail)
            log(GatewayLogEntry(date: Date(), project: binding.projectName, route: route, status: result.status,
                                requestBytes: pinnedBody.count, responseBytes: result.bytes,
                                duration: ContinuousClock.now - started, inputTokens: usage.input, outputTokens: usage.output))
            if let error = result.error { throw error }
            return keepAlive
        }
    }

    private struct ForwardResult {
        var status: Int
        var bytes: Int
        var tail: Data
        /// Set when the stream broke after the head was sent; the connection must close.
        var error: (any Error)?
    }

    private func forward(
        path: String,
        headers: [GatewayHeader],
        body: Data,
        head: HTTPRequestHead,
        keepAlive: Bool,
        to outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>
    ) async -> ForwardResult {
        var upstreamRequest = HTTPClientRequest(url: configuration.upstream + path)
        upstreamRequest.method = .POST
        for header in headers {
            upstreamRequest.headers.add(name: header.name, value: header.value)
        }
        upstreamRequest.body = .bytes(ByteBuffer(bytes: body))

        var result = ForwardResult(status: 502, bytes: 0, tail: Data(), error: nil)
        var headSent = false
        do {
            let response = try await client.execute(upstreamRequest, timeout: configuration.upstreamTimeout)
            var responseHeaders = HTTPHeaders()
            for name in ["content-type", "cache-control", "content-length"] {
                for value in response.headers[name] {
                    responseHeaders.add(name: name, value: value)
                }
            }
            if !keepAlive {
                responseHeaders.add(name: "connection", value: "close")
            }
            result.status = Int(response.status.code)
            try await outbound.write(.head(HTTPResponseHead(version: head.version, status: response.status, headers: responseHeaders)))
            headSent = true
            for try await chunk in response.body {
                result.bytes += chunk.readableBytes
                result.tail.append(contentsOf: chunk.readableBytesView)
                if result.tail.count > Self.usageTailBytes {
                    result.tail.removeFirst(result.tail.count - Self.usageTailBytes)
                }
                try await outbound.write(.body(.byteBuffer(chunk)))
            }
            try await outbound.write(.end(nil))
        } catch {
            if headSent {
                result.error = error
            } else if case .respond(let status, let data) = GatewayPolicy.error(502, "api_error", "the local model server did not answer") {
                result.status = status
                try? await writeLocal(status: status, body: data, version: head.version, keepAlive: keepAlive, to: outbound)
            }
        }
        return result
    }

    private func writeLocal(
        status: Int,
        body: Data,
        version: HTTPVersion,
        keepAlive: Bool,
        to outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>
    ) async throws {
        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: "application/json")
        headers.add(name: "content-length", value: String(body.count))
        if !keepAlive {
            headers.add(name: "connection", value: "close")
        }
        try await outbound.write(.head(HTTPResponseHead(version: version, status: HTTPResponseStatus(statusCode: status), headers: headers)))
        try await outbound.write(.body(.byteBuffer(ByteBuffer(bytes: body))))
        try await outbound.write(.end(nil))
    }
}

/// A gateway with its listener bound.
public struct BoundGateway: Sendable {
    let gateway: ModelGateway
    public let binding: GatewayBinding
    let channel: NIOAsyncChannel<ModelGateway.Connection, Never>

    /// The port actually bound (useful with port 0 in tests).
    public var port: Int? { channel.channel.localAddress?.port }

    /// Accepts connections until `stop()` is called.
    public func serve() async throws {
        try await withThrowingDiscardingTaskGroup { group in
            try await channel.executeThenClose { inbound in
                for try await connection in inbound {
                    guard gateway.admitConnection() else {
                        try? await connection.channel.close()
                        continue
                    }
                    group.addTask {
                        await gateway.handle(connection, binding: binding)
                        gateway.releaseConnection()
                    }
                }
            }
        }
    }

    /// Closes the listener; `serve()` returns once open connections finish.
    public func stop() async {
        try? await channel.channel.close()
    }
}

/// Token counts from the end of a response (JSON or SSE), for the metadata log.
public enum GatewayUsage {
    public static func extract(from tail: Data) -> (input: Int?, output: Int?) {
        let text = String(decoding: tail, as: UTF8.self)
        return (
            last(in: text, keys: ["input_tokens", "prompt_tokens"]),
            last(in: text, keys: ["output_tokens", "completion_tokens"])
        )
    }

    private static func last(in text: String, keys: [String]) -> Int? {
        let pattern = "\"(?:" + keys.joined(separator: "|") + ")\"\\s*:\\s*(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let match = matches.last, let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }
}
