import Foundation

// Shapes verified against sbx v0.49.2 (M0 rounds 1 to 4). Fixtures: Tests/PaddockCoreTests/Fixtures/sbx.

/// `sbx version --json`
public struct SbxVersion: Sendable, Equatable, Codable {
    public struct Client: Sendable, Equatable, Codable {
        public let version: String
        public let revision: String
    }

    public struct Server: Sendable, Equatable, Codable {
        public let state: String
        public let version: String
        public let revision: String
        public let apiVersion: String
    }

    public let client: Client
    public let server: Server

    public var isServerRunning: Bool { server.state == "running" }
}

/// `sbx daemon status --format json`
public struct SbxDaemonStatus: Sendable, Equatable, Codable {
    public let status: String
    public let socket: String
    public let logs: String
}

/// One entry of `sbx ls --json`.
public struct SbxSandbox: Sendable, Equatable, Codable, Identifiable {
    public let name: String
    public let id: String
    public let agent: String
    public let status: String
    public let lastUsedAt: Date?
    public let workspaces: [String]
    /// Missing while sbx is still creating the sandbox.
    public let createdAt: Date?

    public var isRunning: Bool { status == "running" }
}

/// One entry of `sbx ports N --json`.
public struct SbxPort: Sendable, Equatable, Codable {
    public let hostIP: String
    public let hostPort: Int
    public let sandboxPort: Int
    public let `protocol`: String

    public init(hostIP: String, hostPort: Int, sandboxPort: Int, protocol: String = "tcp4") {
        self.hostIP = hostIP
        self.hostPort = hostPort
        self.sandboxPort = sandboxPort
        self.protocol = `protocol`
    }

    enum CodingKeys: String, CodingKey {
        case hostIP = "hostIp"
        case hostPort, sandboxPort
        case `protocol`
    }
}

/// One entry of `sbx rm --json` (and other commands that report a result array).
public struct SbxActionResult: Sendable, Equatable, Codable {
    public let action: String
    public let resource: String
    public let name: String
}

/// One entry of `sbx template ls --json`.
public struct SbxTemplate: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let repository: String
    public let tag: String
    /// The agent the image is for (`claude-code`, `shell-docker`, ...). Missing on images that
    /// carry no sbx label, such as one built `FROM scratch` and loaded with `sbx template load`.
    public let flavor: String?
    public let createdAt: Date
    public let size: Int64

    public var reference: String { "\(repository):\(tag)" }
}

/// `sbx policy ls [N] --json`
public struct SbxPolicyList: Sendable, Equatable, Codable {
    public let rules: [SbxPolicyRule]
}

public struct SbxPolicyRule: Sendable, Equatable, Codable, Identifiable {
    public struct Provenance: Sendable, Equatable, Codable {
        /// `default`, `added`, `provisioned`, or `approval`
        public let createdVia: String
        public let source: String?
    }

    /// Present on HTTP rules (`resource_type: "http"`).
    public struct HTTPTarget: Sendable, Equatable, Codable {
        public let host: String
        public let path: String
    }

    public let id: String
    public let name: String
    /// Missing on sbx 0.51's implicit `default-deny-all` rule (PAD-73.1).
    public let policyId: String?
    /// `global` or `sandbox:NAME`
    public let scope: String
    public let appliesTo: String
    /// `network`, `http`, `filesystem:read`, `filesystem:write`
    public let resourceType: String
    /// `allow` or `deny`
    public let decision: String
    public let resources: [String]
    public let origin: String
    public let layer: String
    public let status: String
    public let editable: Bool
    public let sandboxId: String?
    /// Missing on sbx 0.51's implicit `default-deny-all` rule (PAD-73.1); see `createdVia`.
    public let provenance: Provenance?
    public let actions: [String]
    public let methods: [String]?
    public let httpTargets: [HTTPTarget]?

    public var isGlobal: Bool { scope == "global" }

    /// `provenance.createdVia`, or `implicit` for a rule without one (sbx's `default-deny-all`).
    public var createdVia: String { provenance?.createdVia ?? "implicit" }

    /// The sandbox name for a `sandbox:NAME` scope.
    public var sandboxScope: String? {
        scope.hasPrefix("sandbox:") ? String(scope.dropFirst("sandbox:".count)) : nil
    }
}

/// `sbx policy log [N] --json`: the hosts each sandbox's proxy allowed or blocked, with counts.
public struct SbxPolicyLog: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        /// The sandbox's name (sbx calls it `sandbox_id`).
        public let sandboxId: String
        /// `host:port`.
        public let host: String
        /// `forward` or `forward-bypass`.
        public let proxyType: String?
        /// The rule that matched, or why none did; free text.
        public let rule: String?
        /// Why a connection was blocked (`Denied by local rule`, `No matching allow rule (default deny)`).
        public let reason: String?
        public let count: Int
        public let firstSeen: Date
        public let lastSeen: Date
    }

    public internal(set) var allowed: [Entry]
    public internal(set) var blocked: [Entry]

    public init(allowed: [Entry], blocked: [Entry]) {
        self.allowed = allowed
        self.blocked = blocked
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        allowed = try c.decodeIfPresent([Entry].self, forKey: .allowed) ?? []
        blocked = try c.decodeIfPresent([Entry].self, forKey: .blocked) ?? []
    }

    /// Per sandbox and host, for the Network table: a host can have several entries (one per HTTP
    /// request the proxy judged on its own), which add up.
    public var activity: [ActivityKey: HostActivity] {
        var result: [ActivityKey: HostActivity] = [:]
        for (entries, blocked) in [(allowed, false), (self.blocked, true)] {
            for entry in entries {
                let seen = HostActivity(lastSeen: entry.lastSeen, allowed: blocked ? 0 : entry.count, blocked: blocked ? entry.count : 0)
                let key = ActivityKey(sandbox: entry.sandboxId, host: entry.host)
                result[key] = result[key].map { $0.adding(seen) } ?? seen
            }
        }
        return result
    }
}

/// One entry of `sbx policy approval ls --json`: a request no rule decided ("default deny"),
/// waiting for the operator, with the answers sbx offers (`allow`, `dismiss`).
public struct SbxApproval: Sendable, Equatable, Codable, Identifiable {
    public struct Option: Sendable, Equatable, Codable, Identifiable {
        public let id: String
        public let label: String
    }

    /// `network:...`, for `sbx policy approval respond ID --option OPTION`.
    public let id: String
    public let sandboxName: String
    /// `host:port`, or `METHOD host:port/path` for an HTTP request.
    public let title: String
    /// Free text (protocol, resource type, why).
    public let detail: String
    public let options: [Option]
    public let createdAt: Date

    /// The `host:port` the request is for.
    public var host: String {
        let target = title.split(separator: " ").last.map(String.init) ?? title
        return target.split(separator: "/", maxSplits: 1).first.map(String.init) ?? target
    }
}

/// `sbx settings get KEY --json` and the entries of `sbx settings ls --json`.
public struct SbxSetting<Value: Sendable & Equatable & Codable>: Sendable, Equatable, Codable {
    public let key: String
    public let type: String
    /// `default` or `override`
    public let source: String
    public let value: Value
    public let `default`: Value
    public let description: String
    public let envVar: String?
    public let featureFlag: Bool?
}

/// Value of the `feature.model` setting. Paddock reads it but never enables it (backlog doc App config).
public struct SbxModelFeature: Sendable, Equatable, Codable {
    public let enabled: Bool
    public let variant: String
    public let variantPayload: String
}
