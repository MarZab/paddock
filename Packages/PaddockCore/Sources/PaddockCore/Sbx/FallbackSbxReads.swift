import Foundation

/// Reads from sandboxd's socket while it answers as captured, from sbx's CLI otherwise. A failed
/// socket read is answered by the CLI at once; the socket is tried again after `retryAfter`.
/// sandboxd busy (503, for example while the Mac wakes and the Docker login refreshes) is not a
/// failed socket: the CLI asks the same daemon, so the error is thrown as is and the socket stays.
/// One per app, so the choice is made once and not per request.
public actor FallbackSbxReads: SbxReads {
    public enum Source: Sendable, Equatable {
        case socket(apiVersion: String)
        /// sandboxd answers in an API version whose answers were never captured (sbx was updated).
        case unsupportedAPI(found: String)
        /// Why the socket is not in use.
        case cli(reason: String)

        public var isSocket: Bool {
            if case .socket = self { return true }
            return false
        }
    }

    /// A socket that passed its health check.
    public struct Connection: Sendable {
        public let reads: any SbxReads
        public let apiVersion: String

        public init(reads: any SbxReads, apiVersion: String) {
            self.reads = reads
            self.apiVersion = apiVersion
        }
    }

    public static let retryAfter: Duration = .seconds(60)

    private let cli: any SbxReads
    private let connect: @Sendable () async throws -> Connection
    private let clock = ContinuousClock()
    private var socket: (any SbxReads)?
    private var connecting: Task<Connection, any Error>?
    private var retryAt: ContinuousClock.Instant?
    /// Nil until the first read.
    public private(set) var source: Source?

    public init(cli: any SbxReads, connect: @escaping @Sendable () async throws -> Connection) {
        self.cli = cli
        self.connect = connect
    }

    /// The socket `sbx daemon status` names, checked with `GET /daemon/health`.
    public static func live(runner: ProcessRunner, sbx: URL) -> FallbackSbxReads {
        let cli = SbxCLIReads(runner: runner, sbx: sbx)
        return FallbackSbxReads(cli: cli) {
            let status = try await cli.daemonStatus()
            let reads = SandboxdReads(transport: UnixSocketTransport(socketPath: status.socket))
            return Connection(reads: reads, apiVersion: try await reads.checkHealth().apiVersion)
        }
    }

    public func sandboxes() async throws -> [SbxSandbox] {
        try await read { try await $0.sandboxes() }
    }

    public func policies(sandbox: String?) async throws -> SbxPolicyList {
        try await read { try await $0.policies(sandbox: sandbox) }
    }

    public func policyLog(sandbox: String?) async throws -> SbxPolicyLog {
        try await read { try await $0.policyLog(sandbox: sandbox) }
    }

    public func approvals() async throws -> [SbxApproval] {
        try await read { try await $0.approvals() }
    }

    public nonisolated func events() -> AsyncThrowingStream<SbxEvent, any Error> {
        stream { $0.events() }
    }

    public nonisolated func approvalUpdates() -> AsyncThrowingStream<[SbxApproval], any Error> {
        stream { $0.approvalUpdates() }
    }

    /// The socket's stream when it connects; the CLI's when the socket fails before its first element.
    /// A stream that fails later ends with the error, and the caller's reconnect chooses again.
    private nonisolated func stream<Element: Sendable>(
        _ open: @escaping @Sendable (any SbxReads) -> AsyncThrowingStream<Element, any Error>
    ) -> AsyncThrowingStream<Element, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let socket = await self.usableSocket() {
                        var received = false
                        do {
                            for try await element in open(socket) {
                                received = true
                                continuation.yield(element)
                            }
                            continuation.finish()
                            return
                        } catch where !received && !Task.isCancelled {
                            await self.failed(error)
                        }
                    }
                    for try await element in open(self.cli) {
                        continuation.yield(element)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func read<T: Sendable>(_ operation: (any SbxReads) async throws -> T) async throws -> T {
        if let socket = await usableSocket() {
            do {
                return try await operation(socket)
            } catch where Task.isCancelled || error is CancellationError {
                throw error
            } catch SandboxdError.unmapped {
                // Only this answer is new to Paddock; the socket itself works.
            } catch let error as SandboxdError where error.isUnavailable {
                throw error
            } catch {
                failed(error)
            }
        }
        return try await operation(cli)
    }

    private func usableSocket() async -> (any SbxReads)? {
        if let socket { return socket }
        if let retryAt, clock.now < retryAt { return nil }
        // Concurrent first reads share one health check.
        let attempt = connecting ?? Task { try await connect() }
        connecting = attempt
        defer { connecting = nil }
        do {
            let connection = try await attempt.value
            socket = connection.reads
            retryAt = nil
            source = .socket(apiVersion: connection.apiVersion)
            return connection.reads
        } catch {
            failed(error)
            return nil
        }
    }

    private func failed(_ error: any Error) {
        socket = nil
        // Busy, not broken: the next read tries the socket again.
        let busy = (error as? SandboxdError)?.isUnavailable == true
        retryAt = busy ? nil : clock.now + Self.retryAfter
        if case SandboxdError.unsupportedAPI(let found) = error {
            source = .unsupportedAPI(found: found)
        } else {
            source = .cli(reason: String(describing: error))
        }
    }
}
