import Foundation

public enum SbxError: Error, Equatable, CustomStringConvertible {
    case commandFailed(arguments: [String], exitCode: Int32, stderr: String)
    case decodingFailed(arguments: [String], message: String)
    case versionTooOld(found: String, minimum: SemanticVersion)
    case unparsableVersion(String)
    case daemonNotRunning(state: String)

    public var description: String {
        switch self {
        case .commandFailed(let arguments, let exitCode, let stderr):
            "sbx \(arguments.joined(separator: " ")) failed (exit \(exitCode)): \(stderr)"
        case .decodingFailed(let arguments, let message):
            "unexpected output from sbx \(arguments.joined(separator: " ")): \(message)"
        case .versionTooOld(let found, let minimum):
            "sbx \(found) is too old; Paddock needs \(minimum) or newer"
        case .unparsableVersion(let version):
            "cannot read the sbx version \(version)"
        case .daemonNotRunning(let state):
            "the sbx daemon is not running (state: \(state))"
        }
    }
}

/// sbx queries and the few commands Paddock runs. Queries use sbx's JSON output, never its tables;
/// the read-only ones that `SbxReads` covers may come from sandboxd's socket instead (`FallbackSbxReads`).
/// Every command that changes something is an sbx command.
public actor SbxService {
    public static let minimumVersion = SemanticVersion(0, 51, 0)

    private let cli: SbxCLI
    private let reads: any SbxReads

    /// `reads` answers `sandboxes`, `policies`, `policyLog`, and `approvals`; sbx's CLI when nil.
    public init(runner: ProcessRunner, sbx: URL, reads: (any SbxReads)? = nil) {
        let cli = SbxCLI(runner: runner, sbx: sbx)
        self.cli = cli
        self.reads = reads ?? SbxCLIReads(cli: cli)
    }

    /// `sbx version --json`, checked against the minimum version and the daemon state.
    public func checkedVersion() async throws -> SbxVersion {
        let version = try await cli.query(SbxVersion.self, ["version", "--json"])
        guard let found = SemanticVersion(parsing: version.client.version) else {
            throw SbxError.unparsableVersion(version.client.version)
        }
        guard found >= Self.minimumVersion else {
            throw SbxError.versionTooOld(found: version.client.version, minimum: Self.minimumVersion)
        }
        guard version.isServerRunning else {
            throw SbxError.daemonNotRunning(state: version.server.state)
        }
        return version
    }

    /// The CLI's own version, without the minimum-version and daemon checks.
    public func clientVersion() async throws -> String {
        try await cli.query(SbxVersion.self, ["version", "--json"]).client.version
    }

    public func daemonStatus() async throws -> SbxDaemonStatus {
        try await cli.daemonStatus()
    }

    public func sandboxes() async throws -> [SbxSandbox] {
        try await reads.sandboxes()
    }

    public func policies(sandbox: String? = nil) async throws -> SbxPolicyList {
        try await reads.policies(sandbox: sandbox)
    }

    /// What each sandbox's proxy allowed or blocked (`sbx policy log [N] --json`).
    public func policyLog(sandbox: String? = nil) async throws -> SbxPolicyLog {
        try await reads.policyLog(sandbox: sandbox)
    }

    /// Requests no rule decided, waiting for the operator (`sbx policy approval ls --json`).
    public func approvals() async throws -> [SbxApproval] {
        try await reads.approvals()
    }

    public func ports(sandbox: String) async throws -> [SbxPort] {
        try await cli.query([SbxPort].self, ["ports", sandbox, "--json"])
    }

    public func templates() async throws -> [SbxTemplate] {
        try await cli.query([SbxTemplate].self, ["template", "ls", "--json"])
    }

    public func modelFeature() async throws -> SbxSetting<SbxModelFeature> {
        try await cli.query(SbxSetting<SbxModelFeature>.self, ["settings", "get", "feature.model", "--json"])
    }

    /// `sbx create ...`
    public func create(_ launch: SandboxLaunch) async throws {
        try await perform(launch.arguments)
    }

    /// `sbx policy allow network --sandbox N ...` and other commands without JSON output.
    public func perform(_ arguments: [String]) async throws {
        try await cli.perform(arguments)
    }

    /// A command's standard output, for the few that print data that is not JSON (`sbx exec`).
    public func output(_ arguments: [String]) async throws -> Data {
        try await cli.output(arguments)
    }
}

/// Runs sbx through the `ProcessRunner` and decodes its JSON output.
struct SbxCLI: Sendable {
    let runner: ProcessRunner
    let sbx: URL

    func daemonStatus() async throws -> SbxDaemonStatus {
        try await query(SbxDaemonStatus.self, ["daemon", "status", "--format", "json"])
    }

    func perform(_ arguments: [String]) async throws {
        let result = try await runner.run(sbx, arguments: arguments)
        guard result.exitCode == 0 else {
            throw SbxError.commandFailed(arguments: arguments, exitCode: result.exitCode, stderr: result.failureText())
        }
    }

    func output(_ arguments: [String]) async throws -> Data {
        let result = try await runner.run(sbx, arguments: arguments)
        guard result.exitCode == 0 else {
            throw SbxError.commandFailed(arguments: arguments, exitCode: result.exitCode, stderr: result.failureText())
        }
        return result.stdout
    }

    func query<T: Decodable>(_ type: T.Type, _ arguments: [String]) async throws -> T {
        let result = try await runner.run(sbx, arguments: arguments)
        guard result.exitCode == 0 else {
            throw SbxError.commandFailed(arguments: arguments, exitCode: result.exitCode, stderr: result.stderrText)
        }
        do {
            return try JSONCoding.decode(type, from: result.stdout)
        } catch {
            throw SbxError.decodingFailed(arguments: arguments, message: String(describing: error))
        }
    }
}
