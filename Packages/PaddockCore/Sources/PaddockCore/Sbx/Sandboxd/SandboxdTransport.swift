import AsyncHTTPClient
import Foundation
import NIOCore
import NIOPosix

public enum SandboxdError: Error, Equatable, CustomStringConvertible {
    /// The socket did not answer (missing, refused, timed out).
    case unreachable(path: String, message: String)
    case status(path: String, code: Int, body: String)
    case decodingFailed(path: String, message: String)
    /// sandboxd answers in an API version whose responses were never captured.
    case unsupportedAPI(found: String)
    /// A well-formed answer Paddock cannot map to sbx's output yet (say, a field never captured
    /// with a value). Only that read goes to the CLI; the socket stays in use.
    case unmapped(path: String, message: String)

    public var description: String {
        switch self {
        case .unreachable(let path, let message): "sandboxd's socket did not answer \(path): \(message)"
        case .status(let path, let code, let body): "sandboxd answered \(path) with \(code): \(body)"
        case .decodingFailed(let path, let message): "unexpected answer from sandboxd for \(path): \(message)"
        case .unsupportedAPI(let found): "sandboxd API \(found) is not one Paddock knows"
        case .unmapped(let path, let message): "cannot map sandboxd's answer for \(path): \(message)"
        }
    }

    /// sandboxd answered but cannot serve now (503: the Mac is waking and the Docker login
    /// refreshes); it says this resolves by itself.
    public var isUnavailable: Bool {
        if case .status(_, 503, _) = self { return true }
        return false
    }
}

public struct SandboxdResponse: Sendable, Equatable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// HTTP GETs over sandboxd's Unix socket, the only way PaddockCore talks to it. `path` includes the
/// query (`/policy/network/rules?type=all`). Tests inject a fake that returns fixtures.
public protocol SandboxdTransport: Sendable {
    func get(_ path: String) async throws -> SandboxdResponse
    /// An NDJSON answer line by line, until sandboxd ends it or the consumer cancels.
    func lines(_ path: String) -> AsyncThrowingStream<String, any Error>
}

/// `SandboxdTransport` with AsyncHTTPClient over `http+unix://`.
public struct UnixSocketTransport: SandboxdTransport {
    public static let timeout: TimeAmount = .seconds(10)
    /// `/daemon/diagnostics` is the largest answer seen; nothing Paddock reads comes close.
    static let bodyLimit = 32 * 1024 * 1024

    /// On NIO's POSIX event loops. Not `HTTPClient.shared`: on macOS that runs on Network.framework,
    /// which fails a Unix socket with ENETDOWN ("Network is down"). Lives as long as the app.
    public static let client: HTTPClient = {
        var configuration = HTTPClient.Configuration(redirectConfiguration: .disallow)
        // A socket that is gone (sandboxd stopped) fails at once, so the CLI answers instead; by
        // default the client would try to connect again until the request's deadline, and a stream
        // has none.
        configuration.connectionPool.retryConnectionEstablishment = false
        return HTTPClient(eventLoopGroup: MultiThreadedEventLoopGroup.singleton, configuration: configuration)
    }()

    public let socketPath: String
    private let client: HTTPClient

    public init(socketPath: String, client: HTTPClient = UnixSocketTransport.client) {
        self.socketPath = socketPath
        self.client = client
    }

    public func get(_ path: String) async throws -> SandboxdResponse {
        let request = try self.request(path)
        do {
            let response = try await client.execute(request, timeout: Self.timeout)
            let body = try await response.body.collect(upTo: Self.bodyLimit)
            return SandboxdResponse(status: Int(response.status.code), body: Data(body.readableBytesView))
        } catch {
            throw Self.wrap(error, path: path)
        }
    }

    public func lines(_ path: String) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // A stream has no end to wait for, so no deadline; connecting still times out.
                    let response = try await client.execute(try request(path), deadline: .distantFuture)
                    guard response.status == .ok else {
                        let body = try await response.body.collect(upTo: 64 * 1024)
                        throw SandboxdError.status(path: path, code: Int(response.status.code),
                                                   body: String(decoding: body.readableBytesView, as: UTF8.self))
                    }
                    var splitter = LineSplitter()
                    for try await buffer in response.body {
                        for line in splitter.append(Data(buffer.readableBytesView)) { continuation.yield(line) }
                    }
                    for line in splitter.finish() { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.wrap(error, path: path))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func request(_ path: String) throws -> HTTPClientRequest {
        guard let url = URL(httpURLWithSocketPath: socketPath, uri: path) else {
            throw SandboxdError.unreachable(path: path, message: "cannot address the socket \(socketPath)")
        }
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .GET
        // A Unix socket URL has no host, so the client sends no Host header, and sandboxd (Go)
        // refuses HTTP/1.1 without one. sbx itself sends this value.
        request.headers.add(name: "Host", value: "socket")
        request.headers.add(name: "User-Agent", value: "paddock")
        request.headers.add(name: "Accept", value: "application/json")
        return request
    }

    private static func wrap(_ error: any Error, path: String) -> any Error {
        if error is SandboxdError || error is CancellationError { return error }
        if Task.isCancelled { return CancellationError() }
        return SandboxdError.unreachable(path: path, message: String(describing: error))
    }
}
