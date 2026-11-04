import Foundation

/// One row of the Ports table (backlog doc UI, Ports): every port across all sandboxes.
public struct PortRow: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        /// Sandbox to Mac: `localhost:HOST` reaches the sandbox's port.
        case published
        /// Sandbox to the Mac's loopback: the sandbox may reach `host.docker.internal:PORT`.
        case hostService
    }

    public enum State: String, Sendable, Equatable, CaseIterable {
        /// In effect in sbx (the only record of it).
        case live
        /// A Paddock service's port (llmman, another project's gateway) that the
        /// sandbox can still reach: an allow covers it and its denies are missing.
        case notDenied
    }

    public let sandbox: String
    /// Whether `sandbox` has a project file.
    public let isProject: Bool
    public let kind: Kind
    public let hostIP: String
    public let hostPort: Int?
    public let sandboxPort: Int?
    public let state: State
    /// What a suggestion is for ("publish", "host service"), or why a port is listed.
    public let label: String?
    /// For `.notDenied`: the denies the sandbox is missing (`localhost:PORT`, `host.docker.internal:PORT`).
    public var missingDenies: [String] = []

    public var id: String {
        "\(sandbox)|\(kind.rawValue)|\(hostIP)|\(hostPort.map(String.init) ?? "-")|\(sandboxPort.map(String.init) ?? "-")|\(state.rawValue)"
    }

    /// Where to open a published port.
    public var url: String? {
        guard kind == .published, let hostPort, hostIP == Ports.hostIP || hostIP == "::1" else { return nil }
        return "http://localhost:\(hostPort)"
    }

    public init(sandbox: String, isProject: Bool, kind: Kind, hostIP: String, hostPort: Int?, sandboxPort: Int?,
                state: State, label: String?) {
        self.sandbox = sandbox
        self.isProject = isProject
        self.kind = kind
        self.hostIP = hostIP
        self.hostPort = hostPort
        self.sandboxPort = sandboxPort
        self.state = state
        self.label = label
    }
}

public enum PortsTable {
    /// - Parameters:
    ///   - snapshots: what sbx reports, by sandbox name; a name missing here has no snapshot yet.
    ///   - sandboxes: every sbx sandbox name, so a project without a sandbox is told apart from one not read yet.
    public static func rows(
        projects: [Project],
        snapshots: [String: SandboxSnapshot],
        sandboxes: Set<String>,
        globalRules: [SbxPolicyRule],
        app: AppConfig
    ) -> [PortRow] {
        let globalAllows = Ports.globalAllows(globalRules)
        var rows: [PortRow] = []
        let projectNames = Set(projects.map(\.name))

        // What sbx has, for every sandbox read so far.
        for (name, snapshot) in snapshots.sorted(by: { $0.key < $1.key }) {
            let isProject = projectNames.contains(name)
            for port in snapshot.ports {
                rows.append(PortRow(sandbox: name, isProject: isProject, kind: .published, hostIP: port.hostIP,
                                    hostPort: port.hostPort, sandboxPort: port.sandboxPort, state: .live, label: nil))
            }
            for port in Ports.hostServices(snapshot, app: app) {
                rows.append(PortRow(sandbox: name, isProject: isProject, kind: .hostService, hostIP: Ports.hostIP,
                                    hostPort: port, sandboxPort: nil, state: .live, label: nil))
            }
        }

        for project in projects {
            guard let snapshot = snapshots[project.name] else { continue }
            let otherGateways = Set(projects.filter { $0.name != project.name }.compactMap(\.gatewayPort))
            for (port, missing) in undeniedReservedPorts(snapshot: snapshot, otherGateways: otherGateways, globalAllows: globalAllows) {
                var row = PortRow(sandbox: project.name, isProject: true, kind: .hostService, hostIP: Ports.hostIP,
                                  hostPort: port, sandboxPort: nil, state: .notDenied, label: "Paddock denies this port")
                row.missingDenies = missing
                rows.append(row)
            }
        }
        return rows
    }

    /// The ports Paddock always denies that this sandbox can still reach, with the denies it is
    /// missing: a global or sandbox allow covers the port and not every loopback name is denied.
    /// Gateway ports count only when another project uses them (the project's own is reached
    /// through its HTTP rule), so one broad allow does not list the whole range.
    static func undeniedReservedPorts(snapshot: SandboxSnapshot, otherGateways: Set<Int>,
                                      globalAllows: [HostPattern]) -> [(port: Int, missing: [String])] {
        let allows = globalAllows + snapshot.rules
            .filter { $0.decision == "allow" && $0.resourceType == "network" }
            .flatMap(\.resources).map(HostPattern.init(parsing:))
        let denied = Set(snapshot.rules.filter { $0.decision == "deny" }.flatMap(\.resources))
        return otherGateways.union([AppConfig.llmmanPort]).sorted().compactMap { port in
            let names = PolicyPlanner.hostLoopbackNames.map { "\($0):\(port)" }
            let reachable = names.contains { name in allows.contains { $0.covers(HostPattern(parsing: name)) } }
            let missing = names.filter { !denied.contains($0) }
            return reachable && !missing.isEmpty ? (port, missing) : nil
        }
    }
}
