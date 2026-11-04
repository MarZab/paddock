import Foundation

/// The per-sandbox rules for a Paddock sandbox (backlog doc Network policy). A sandbox gets sbx's
/// global rules plus the hosts of its project's confirmed `sbxenv.yaml` kits (less the ones the
/// operator declined); Paddock adds rules of its own
/// only to protect its own services: llmman's port (agents use the gateway, which pins the model
/// and the routes) and other projects' gateway ports (a port is a project's identity).
public struct SandboxPolicyPlan: Sendable, Equatable {
    public struct HTTPAllow: Sendable, Equatable {
        public let resource: String
        public let methods: [String]
        public let path: String
    }

    /// `--deny-network R` on `sbx create`. Deny beats allow.
    public var denies: [String]
    /// `sbx policy allow network --sandbox N R` for allowed hosts no global rule covers.
    public var allows: [String]
    /// `sbx policy allow network --sandbox N R --method ... --path ...`
    public var httpAllows: [HTTPAllow]

    /// The `sbx create` arguments for the denies.
    public var createArguments: [String] { denies.flatMap { ["--deny-network", $0] } }
}

public enum PolicyPlanError: Error, Equatable, CustomStringConvertible {
    /// The project asked for one of Paddock's own services.
    case forbiddenResource(String)

    public var description: String {
        switch self {
        case .forbiddenResource(let resource):
            "\(resource) is a Paddock service (llmman or a gateway port) and is never allowed for a sandbox"
        }
    }
}

public struct PolicyPlanner: Sendable {
    /// This project's gateway port (the only one its sandbox may reach).
    public let gatewayPort: Int
    /// Every project's gateway ports (`models.gatewayPorts`). The port is what tells the gateway
    /// which project is asking, so a sandbox must never reach another project's port.
    public let gatewayPorts: ClosedRange<Int>
    public let llmmanPort: Int

    public init(gatewayPort: Int, gatewayPorts: ClosedRange<Int> = AppConfig.Models.defaultGatewayPorts, llmmanPort: Int = AppConfig.llmmanPort) {
        self.gatewayPort = gatewayPort
        self.gatewayPorts = gatewayPorts
        self.llmmanPort = llmmanPort
    }

    /// The host names under which a sandbox reaches the host's loopback.
    public static let hostLoopbackNames = ["localhost", "host.docker.internal"]

    /// Whether `pattern` names any gateway port on the host's loopback.
    func reachesGatewayPorts(_ pattern: HostPattern) -> Bool {
        let namesLoopback = Self.hostLoopbackNames.contains {
            HostPattern(host: pattern.host, port: nil).covers(HostPattern(host: $0, port: nil))
        }
        return namesLoopback && (pattern.port.map(gatewayPorts.contains) ?? true)
    }

    /// Always denied, whatever a global rule or the project says: llmman's port. Agents reach
    /// models only through the gateway.
    public var paddockServiceDenies: [String] {
        Self.hostLoopbackNames.map { "\($0):\(llmmanPort)" }
    }

    /// - Parameters:
    ///   - globalRules: rules from `sbx policy ls --json`; only active global network allows matter.
    ///   - allowed: the project's confirmed hosts and the allows its sandbox has.
    ///   - denied: the project's confirmed denies.
    ///   - usesGateway: whether the project's provider routes through the ModelGateway.
    public func plan(globalRules: [SbxPolicyRule], allowed: [String], denied: [String] = [],
                     usesGateway: Bool) throws(PolicyPlanError) -> SandboxPolicyPlan {
        let services = paddockServiceDenies.map(HostPattern.init(parsing:))
        let wanted = allowed.map(HostPattern.init(parsing:))
        for entry in wanted where services.contains(where: { $0.covers(entry) || entry.covers($0) }) || reachesGatewayPorts(entry) {
            throw .forbiddenResource(entry.description)
        }
        let globals = globalRules
            .filter { $0.isGlobal && $0.decision == "allow" && $0.status == "active" && $0.resourceType == "network" }
            .flatMap(\.resources).map(HostPattern.init(parsing:))

        // Allowed hosts a global rule already allows need no rule of their own.
        let allows = Self.unique(wanted.filter { entry in !globals.contains { $0.covers(entry) } }.map(\.description))
        var httpAllows: [SandboxPolicyPlan.HTTPAllow] = []
        if usesGateway {
            httpAllows.append(.init(resource: "localhost:\(gatewayPort)", methods: ["GET", "POST"], path: "/v1/**"))
        }
        // A global rule that reaches the gateway ports (say `localhost`, or `**`) would also reach
        // other projects' gateways: those are denied explicitly then.
        let otherGateways = globals.contains(where: reachesGatewayPorts)
            ? gatewayPorts.filter { $0 != gatewayPort }.flatMap { port in Self.hostLoopbackNames.map { "\($0):\(port)" } }
            : []
        return SandboxPolicyPlan(
            denies: Self.unique(paddockServiceDenies + otherGateways + denied),
            allows: allows,
            httpAllows: httpAllows
        )
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}

extension PolicyPlanner {
    /// The gateway port a sandbox was created with, read back from its HTTP allow rule
    /// (`sbx policy ls N --json`). Nil when the sandbox has no such rule, or rules for more than
    /// one gateway port. The same port may appear more than once (for example once per method).
    public static func gatewayPort(ofSandbox name: String, rules: [SbxPolicyRule], in range: ClosedRange<Int>) -> Int? {
        let ports = Set(rules
            .filter { $0.sandboxScope == name && $0.resourceType == "http" && $0.decision == "allow" }
            .flatMap { $0.httpTargets ?? [] }
            .filter { $0.path == "/v1/**" }
            .compactMap { HostPattern(parsing: $0.host).port }
            .filter(range.contains))
        return ports.count == 1 ? ports.first : nil
    }
}
