import Foundation

/// `SbxReads` straight from sandboxd's socket: the requests `sbx` itself sends, mapped to the shapes
/// of its `--json` output. A private API, captured on sbx 0.49.2 (API 0.42.0) and sbx 0.51.0 (API 0.49.0) with
/// `tools/tasks/capture/socket.py`; `FallbackSbxReads` uses it only after `checkHealth()` passed.
/// Fixtures: Tests/PaddockCoreTests/Fixtures/sandboxd (0.42) and sandboxd/0.49.
public struct SandboxdReads: SbxReads {
    /// sandboxd API versions (major.minor) whose answers were captured.
    public static let supportedAPIVersions: Set<String> = ["0.42", "0.49"]
    /// How long `/user-prompts` may take to replay the pending requests.
    static let replayTimeout: Duration = .seconds(10)
    /// How often `approvalUpdates` reads the list again without a line saying it changed.
    static let approvalsRecheck: Duration = .seconds(15)

    private let transport: any SandboxdTransport

    public init(transport: any SandboxdTransport) {
        self.transport = transport
    }

    /// `GET /daemon/health`: healthy, and in an API version Paddock knows.
    public func checkHealth() async throws -> SandboxdHealth {
        let health = try await get(SandboxdHealth.self, "/daemon/health")
        guard health.status == "healthy" else {
            throw SandboxdError.unmapped(path: "/daemon/health", message: "status \(health.status)")
        }
        let majorMinor = health.apiVersion.split(separator: ".").prefix(2).joined(separator: ".")
        guard Self.supportedAPIVersions.contains(majorMinor) else {
            throw SandboxdError.unsupportedAPI(found: health.apiVersion)
        }
        return health
    }

    /// `GET /sandbox`; sbx turns `workspace` into `workspaces`.
    public func sandboxes() async throws -> [SbxSandbox] {
        try await get([Sandbox].self, "/sandbox").map { try $0.sbxSandbox() }
    }

    /// `GET /policy/network/rules?type=all`, the same rules as `sbx policy ls`. For one sandbox sbx
    /// keeps the global rules and that sandbox's own.
    public func policies(sandbox: String?) async throws -> SbxPolicyList {
        let list = try await get(SbxPolicyList.self, "/policy/network/rules?type=all")
        guard let sandbox else { return list }
        return SbxPolicyList(rules: list.rules.filter { $0.isGlobal || $0.sandboxScope == sandbox })
    }

    /// `GET /policy/network/log`, renamed the way sbx renames it; for one sandbox, its entries.
    public func policyLog(sandbox: String?) async throws -> SbxPolicyLog {
        let log = try await get(NetworkLog.self, "/policy/network/log")
        let keep = { (host: NetworkLog.Host) in sandbox == nil || host.vmName == sandbox }
        return SbxPolicyLog(allowed: (log.allowedHosts ?? []).filter(keep).map(\.entry),
                            blocked: (log.blockedHosts ?? []).filter(keep).map(\.entry))
    }

    /// `GET /user-prompts` streams `requested` prompts, then `synced`, then new ones; sbx reads it
    /// up to `synced`.
    public func approvals() async throws -> [SbxApproval] {
        let path = "/user-prompts"
        return try await withThrowingTaskGroup(of: [SbxApproval]?.self) { group in
            group.addTask {
                var pending: [SbxApproval] = []
                for try await line in transport.lines(path) where !line.isEmpty {
                    let event = try Self.decode(UserPromptEvent.self, Data(line.utf8), path: path)
                    switch event.action {
                    case "synced": return pending
                    case "requested": if let prompt = event.prompt { pending.append(prompt) }
                    default: continue
                    }
                }
                throw SandboxdError.unmapped(path: path, message: "the stream ended before \"synced\"")
            }
            group.addTask {
                try await Task.sleep(for: Self.replayTimeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let approvals = first else {
                throw SandboxdError.unreachable(path: path, message: "no \"synced\" within \(Self.replayTimeout)")
            }
            return approvals
        }
    }

    /// `/user-prompts` keeps streaming after `synced`. Only `requested` was captured, so any line
    /// after the replay is taken as "the list changed" and the list is read again in full (a fresh
    /// replay, a few milliseconds), and so is it every `approvalsRecheck`, for answers that come
    /// without a line.
    public func approvalUpdates() -> AsyncThrowingStream<[SbxApproval], any Error> {
        let prompts = transport.lines("/user-prompts")
        return AsyncThrowingStream { continuation in
            let (triggers, trigger) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let task = Task {
                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            var synced = false
                            for try await line in prompts where !line.isEmpty {
                                let event = try Self.decode(UserPromptEvent.self, Data(line.utf8), path: "/user-prompts")
                                if synced || event.action == "synced" {
                                    synced = true
                                    trigger.yield()
                                }
                            }
                        }
                        group.addTask {
                            while true {
                                try await Task.sleep(for: Self.approvalsRecheck)
                                trigger.yield()
                            }
                        }
                        // One read at a time, so a list never overtakes a newer one.
                        group.addTask {
                            for await _ in triggers {
                                continuation.yield(try await approvals())
                            }
                        }
                        // The prompts stream ended (sandboxd restarted): the caller connects again.
                        try await group.next()
                        group.cancelAll()
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `GET /events`: the same lines `sbx events --json` prints.
    public func events() -> AsyncThrowingStream<SbxEvent, any Error> {
        let lines = transport.lines("/events")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in lines {
                        if let event = try? SbxEventDecoder.decode(line: line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func get<T: Decodable>(_ type: T.Type, _ path: String) async throws -> T {
        let response = try await transport.get(path)
        guard response.status == 200 else {
            throw SandboxdError.status(path: path, code: response.status, body: String(decoding: response.body.prefix(1024), as: UTF8.self))
        }
        return try Self.decode(type, response.body, path: path)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data, path: String) throws -> T {
        do {
            return try JSONCoding.decode(type, from: data)
        } catch {
            throw SandboxdError.decodingFailed(path: path, message: String(describing: error))
        }
    }
}

/// `GET /daemon/health`
public struct SandboxdHealth: Sendable, Equatable, Codable {
    /// `healthy`
    public let status: String
    /// `v0.49.2`, sbx's version.
    public let version: String
    public let revision: String
    /// `0.42.0`, the same as `sbx version`'s `server.api_version`.
    public let apiVersion: String
    public let release: Bool?
}

// MARK: - Wire shapes that differ from sbx's output

/// One entry of `GET /sandbox`.
private struct Sandbox: Decodable {
    let name: String
    let id: String
    let agent: String
    let status: String
    let lastUsedAt: Date?
    /// Missing while sbx is still creating the sandbox, as in `sbx ls`.
    let createdAt: Date?
    let workspace: String
    /// API 0.49: extra folders and the `sbxenv.yaml` of `sbx env create`; sbx lists each after
    /// the workspace in `workspaces`, with `:ro` when read-only.
    let additionalWorkspaces: [AdditionalWorkspace]?
    /// Always empty in the captures; how sbx lists them in `workspaces` is not known.
    let runtimeMounts: [JSONValue]?

    struct AdditionalWorkspace: Decodable {
        let dir: String
        let readOnly: Bool?
    }

    func sbxSandbox() throws -> SbxSandbox {
        guard runtimeMounts?.isEmpty ?? true else {
            throw SandboxdError.unmapped(path: "/sandbox", message: "\(name) has runtime mounts")
        }
        let extra = (additionalWorkspaces ?? []).map { $0.readOnly == true ? $0.dir + ":ro" : $0.dir }
        return SbxSandbox(name: name, id: id, agent: agent, status: status, lastUsedAt: lastUsedAt,
                          workspaces: (workspace.isEmpty ? [] : [workspace]) + extra, createdAt: createdAt)
    }
}

/// `GET /policy/network/log`
private struct NetworkLog: Decodable {
    struct Host: Decodable {
        let host: String
        /// The sandbox's name (sbx: `sandbox_id`).
        let vmName: String
        let proxyType: String?
        /// Empty when no rule matched an allowed host; sbx then leaves it out.
        let rule: String?
        let reason: String?
        /// sbx: `count`
        let countSince: Int
        /// sbx: `first_seen`
        let since: Date
        let lastSeen: Date

        var entry: SbxPolicyLog.Entry {
            SbxPolicyLog.Entry(sandboxId: vmName, host: host, proxyType: proxyType, rule: rule?.isEmpty == false ? rule : nil,
                               reason: reason, count: countSince, firstSeen: since, lastSeen: lastSeen)
        }
    }

    let allowedHosts: [Host]?
    let blockedHosts: [Host]?
}

/// One line of `GET /user-prompts`: `{"action": "requested", "prompt": {...}}` or `{"action": "synced"}`.
private struct UserPromptEvent: Decodable {
    let action: String
    /// The same shape as an entry of `sbx policy approval ls --json`.
    let prompt: SbxApproval?
}
