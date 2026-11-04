import AsyncHTTPClient
import Foundation
import NIOCore

/// One GET against llmman. Tests inject a fake that returns fixtures.
public protocol LlmmanTransport: Sendable {
    /// Returns the status code and body of `GET <llmman><path>`.
    func get(_ path: String) async throws -> (status: Int, body: Data)
}

public enum LlmmanError: Error, Equatable, CustomStringConvertible {
    case pathNotAllowed(String)
    case httpStatus(path: String, status: Int)
    case decodingFailed(path: String, message: String)

    public var description: String {
        switch self {
        case .pathNotAllowed(let path): "Paddock does not call llmman's \(path)"
        case .httpStatus(let path, let status): "llmman answered \(status) for \(path)"
        case .decodingFailed(let path, let message): "unexpected answer from llmman's \(path): \(message)"
        }
    }
}

/// Paddock's read-only view of llmman (backlog doc Models). Model management happens in llmman's
/// own web UI; this client only reads, and only the paths below.
public struct LlmmanAPI: Sendable {
    /// Every path Paddock may call. All are GETs; nothing that changes llmman's state.
    public static let allowedPaths: Set<String> = ["/api/version", "/api/tags", "/api/ps", "/llmman/node", "/llmman/shell"]

    private let transport: any LlmmanTransport

    public init(transport: any LlmmanTransport) {
        self.transport = transport
    }

    public func version() async throws -> LlmmanVersion { try await get("/api/version") }
    public func tags() async throws -> LlmmanTags { try await get("/api/tags") }
    public func loaded() async throws -> LlmmanLoaded { try await get("/api/ps") }
    public func node() async throws -> LlmmanNode { try await get("/llmman/node") }

    /// The web shell's status. A plain GET: the transport never sends `Upgrade`, so this can
    /// never open the shell's WebSocket (CLAUDE.md, Security rules).
    public func shellStatus() async throws -> LlmmanShellStatus { try await get("/llmman/shell") }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard Self.allowedPaths.contains(path) else { throw LlmmanError.pathNotAllowed(path) }
        let (status, body) = try await transport.get(path)
        guard status == 200 else { throw LlmmanError.httpStatus(path: path, status: status) }
        do {
            return try JSONCoding.decode(T.self, from: body)
        } catch {
            throw LlmmanError.decodingFailed(path: path, message: String(describing: error))
        }
    }
}

/// The real transport: llmman on loopback, fail-fast connects, small bounded bodies.
public final class HTTPLlmmanTransport: LlmmanTransport {
    /// sbx's llmman (M0 round 2). Not configurable from any config file.
    public static let defaultBase = "http://127.0.0.1:\(AppConfig.llmmanPort)"
    static let maxBodyBytes = 4 * 1024 * 1024

    private let base: String
    private let client: HTTPClient

    public init(base: String = HTTPLlmmanTransport.defaultBase) {
        self.base = base
        var configuration = HTTPClient.Configuration(redirectConfiguration: .disallow)
        configuration.connectionPool.retryConnectionEstablishment = false
        configuration.timeout.connect = .seconds(2)
        self.client = HTTPClient(eventLoopGroupProvider: .singleton, configuration: configuration)
    }

    public func get(_ path: String) async throws -> (status: Int, body: Data) {
        var request = HTTPClientRequest(url: base + path)
        request.method = .GET
        request.headers.add(name: "accept", value: "application/json")
        let response = try await client.execute(request, timeout: .seconds(5))
        let body = try await response.body.collect(upTo: Self.maxBodyBytes)
        return (Int(response.status.code), Data(body.readableBytesView))
    }

    /// Call before releasing the transport.
    public func shutdown() async throws {
        try await client.shutdown()
    }
}
