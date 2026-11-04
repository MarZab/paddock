import Foundation

/// The sbx state Paddock reads. Two sources answer it: sbx's CLI (`SbxCLIReads`, always there) and
/// sandboxd's socket (`SandboxdReads`, about 100 times faster, a private API); `FallbackSbxReads`
/// picks between them. Nothing here changes anything: commands are always sbx's (`SbxService`).
public protocol SbxReads: Sendable {
    /// `sbx ls --json`
    func sandboxes() async throws -> [SbxSandbox]
    /// `sbx policy ls [N] --json`: every rule, or the global rules plus sandbox N's own.
    func policies(sandbox: String?) async throws -> SbxPolicyList
    /// `sbx policy log [N] --json`
    func policyLog(sandbox: String?) async throws -> SbxPolicyLog
    /// `sbx policy approval ls --json`
    func approvals() async throws -> [SbxApproval]
    /// `sbx events --json`: the current state, then `sync`/`complete`, then live events.
    func events() -> AsyncThrowingStream<SbxEvent, any Error>
    /// The pending approval requests, now and whenever they change (and now and then when they did
    /// not). sbx's CLI has no stream for them, so by default this reads `approvals()` every
    /// `approvalsPollInterval`.
    func approvalUpdates() -> AsyncThrowingStream<[SbxApproval], any Error>
}

/// How often `approvalUpdates` reads the list without a stream that says when it changed.
public let approvalsPollInterval: Duration = .seconds(10)

extension SbxReads {
    public func approvalUpdates() -> AsyncThrowingStream<[SbxApproval], any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        continuation.yield(try await approvals())
                        try await Task.sleep(for: approvalsPollInterval)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// `SbxReads` through sbx's JSON output.
public struct SbxCLIReads: SbxReads {
    let cli: SbxCLI
    private let streamer: any LineStreaming

    public init(runner: ProcessRunner, sbx: URL, streamer: any LineStreaming = FoundationLineStreamer()) {
        self.init(cli: SbxCLI(runner: runner, sbx: sbx), streamer: streamer)
    }

    init(cli: SbxCLI, streamer: any LineStreaming = FoundationLineStreamer()) {
        self.cli = cli
        self.streamer = streamer
    }

    /// `sbx daemon status --format json`, for the socket's path.
    public func daemonStatus() async throws -> SbxDaemonStatus {
        try await cli.daemonStatus()
    }

    public func sandboxes() async throws -> [SbxSandbox] {
        try await cli.query([SbxSandbox].self, ["ls", "--json"])
    }

    public func policies(sandbox: String?) async throws -> SbxPolicyList {
        try await cli.query(SbxPolicyList.self, ["policy", "ls"] + (sandbox.map { [$0] } ?? []) + ["--json"])
    }

    public func policyLog(sandbox: String?) async throws -> SbxPolicyLog {
        try await cli.query(SbxPolicyLog.self, ["policy", "log"] + (sandbox.map { [$0] } ?? []) + ["--json"])
    }

    public func approvals() async throws -> [SbxApproval] {
        try await cli.query([SbxApproval].self, ["policy", "approval", "ls", "--json"])
    }

    public func events() -> AsyncThrowingStream<SbxEvent, any Error> {
        SbxEventStream(streamer: streamer, sbx: cli.sbx).events()
    }
}
