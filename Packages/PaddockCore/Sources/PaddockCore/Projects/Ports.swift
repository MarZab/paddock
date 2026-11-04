import Foundation

public enum PortsError: Error, Equatable, CustomStringConvertible {
    case invalidPort(Int)
    /// llmman or a gateway port: a Paddock service, never reachable from or published by a sandbox.
    case reserved(Int)
    case outsidePublishRange(Int, ClosedRange<Int>)
    case hostPortTaken(Int, by: String)
    case sandboxPortPublished(Int)
    case publishRangeFull

    public var description: String {
        switch self {
        case .invalidPort(let port): "\(port) is not a port"
        case .reserved(let port): "port \(port) is a Paddock service (llmman or a gateway)"
        case .outsidePublishRange(let port, let range): "host port \(port) is outside ports.publishRange (\(range.lowerBound)-\(range.upperBound))"
        case .hostPortTaken(let port, let name): "host port \(port) is already used by \(name)"
        case .sandboxPortPublished(let port): "sandbox port \(port) is already published"
        case .publishRangeFull: "every port in ports.publishRange is taken"
        }
    }
}

/// The Ports panel's rules (backlog doc UI, Ports). Published ports bind loopback only, from
/// `ports.publishRange`; host services are loopback ports on the Mac a sandbox may reach.
public enum Ports {
    /// Published ports bind here, never on a LAN address.
    public static let hostIP = "127.0.0.1"

    /// Paddock's own services: llmman's port and the gateway ports.
    static func isReserved(_ port: Int, app: AppConfig) -> Bool {
        port == AppConfig.llmmanPort || app.models.gatewayPorts.contains(port)
    }

    /// The port on this Mac a resource names (`localhost:PORT`, `host.docker.internal:PORT`), when it
    /// is one a sandbox may be given as a host service (not one of Paddock's own).
    public static func hostServicePort(_ resource: String, app: AppConfig) -> Int? {
        let pattern = HostPattern(parsing: resource)
        guard PolicyPlanner.hostLoopbackNames.contains(pattern.host), let port = pattern.port, !isReserved(port, app: app) else {
            return nil
        }
        return port
    }

    public static func checkHostService(_ port: Int, app: AppConfig) throws(PortsError) {
        guard (1...65535).contains(port) else { throw .invalidPort(port) }
        guard !isReserved(port, app: app) else { throw .reserved(port) }
    }

    /// Picks the host port for publishing `sandboxPort` from `sandbox`: the same number when it
    /// is in the range and free, otherwise the lowest free port. `published` is what sbx
    /// publishes, by sandbox (`sbx ports N --json`), the only record of published ports.
    public static func mapping(for sandboxPort: Int, sandbox: String, published: [String: [SbxPort]],
                               app: AppConfig) throws(PortsError) -> Project.PortMapping {
        guard (1...65535).contains(sandboxPort) else { throw .invalidPort(sandboxPort) }
        guard !(published[sandbox] ?? []).contains(where: { $0.sandboxPort == sandboxPort }) else { throw .sandboxPortPublished(sandboxPort) }
        let used = Set(published.values.flatMap { $0.map(\.hostPort) })
        let range = app.ports.publishRange
        let free = { (port: Int) in range.contains(port) && !used.contains(port) && !isReserved(port, app: app) }
        if free(sandboxPort) {
            return .init(sandboxPort: sandboxPort, hostPort: sandboxPort)
        }
        guard let port = range.first(where: free) else { throw .publishRangeFull }
        return .init(sandboxPort: sandboxPort, hostPort: port)
    }

    /// Checks a mapping the operator typed.
    public static func check(_ mapping: Project.PortMapping, sandbox: String, published: [String: [SbxPort]],
                             app: AppConfig) throws(PortsError) {
        for port in [mapping.sandboxPort, mapping.hostPort] where !(1...65535).contains(port) {
            throw .invalidPort(port)
        }
        guard !isReserved(mapping.hostPort, app: app) else { throw .reserved(mapping.hostPort) }
        guard app.ports.publishRange.contains(mapping.hostPort) else { throw .outsidePublishRange(mapping.hostPort, app.ports.publishRange) }
        for (name, ports) in published.sorted(by: { $0.key < $1.key })
        where name != sandbox && ports.contains(where: { $0.hostPort == mapping.hostPort }) {
            throw .hostPortTaken(mapping.hostPort, by: name)
        }
    }

    /// sbx's active global network allows, which every sandbox gets unless it denies them.
    public static func globalAllows(_ rules: [SbxPolicyRule]) -> [HostPattern] {
        rules.filter { $0.isGlobal && $0.decision == "allow" && $0.status == "active" && $0.resourceType == "network" }
            .flatMap(\.resources).map(HostPattern.init(parsing:))
    }

    /// Whether the sandbox may reach `port` on the Mac: it allows the port itself, or a global
    /// rule allows it and the sandbox does not deny it.
    public static func allowsHostService(_ port: Int, snapshot: SandboxSnapshot, globalAllows: [HostPattern]) -> Bool {
        let names = PolicyPlanner.hostLoopbackNames.map { "\($0):\(port)" }
        if snapshot.added("allow").contains(where: { $0.resources.contains(where: names.contains) }) { return true }
        let denied = snapshot.rules.contains { $0.decision == "deny" && $0.resources.contains(where: names.contains) }
        let globallyAllowed = globalAllows.contains { $0.covers(HostPattern(host: "localhost", port: port)) }
        return globallyAllowed && !denied
    }

    /// Host services the sandbox allows itself (`localhost:PORT` rules Paddock or the operator
    /// added), without the ports Paddock always denies.
    public static func hostServices(_ snapshot: SandboxSnapshot, app: AppConfig) -> [Int] {
        let ports = snapshot.added("allow").flatMap(\.resources).compactMap { resource -> Int? in
            let pattern = HostPattern(parsing: resource)
            guard PolicyPlanner.hostLoopbackNames.contains(pattern.host), let port = pattern.port, !isReserved(port, app: app) else { return nil }
            return port
        }
        return Array(Set(ports)).sorted()
    }

    /// The `-p` / `--publish` spec: always on loopback.
    public static func spec(_ mapping: Project.PortMapping) -> String {
        "\(hostIP):\(mapping.hostPort):\(mapping.sandboxPort)"
    }

    /// The URL to open a published port in a browser.
    public static func url(_ mapping: Project.PortMapping) -> String {
        "http://localhost:\(mapping.hostPort)"
    }
}
