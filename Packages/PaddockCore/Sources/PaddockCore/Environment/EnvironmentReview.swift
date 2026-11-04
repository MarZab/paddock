import Foundation

/// A project's `sbxenv.yaml` and own kits, next to sbx's global rules, for the operator to confirm
/// in one sheet (backlog doc Project config file). Built from Paddock's own checks
/// (`ProjectEnvironment`): `sbx env plan` prints text only, which Paddock does not parse.
/// Confirming records the fingerprint and the hosts the operator declined; a create then applies
/// the file, and a sandbox deny for each declined host (a deny beats a kit's allow).
public struct EnvironmentReview: Sendable, Equatable {
    /// A host a project kit allows while the agent runs.
    public struct Host: Sendable, Equatable, Identifiable {
        public let host: String
        /// Bounded to these methods and paths, when the kit says so.
        public let methods: [String]
        public let paths: [String]
        /// The kit (as the file names it) that asks for it.
        public let kit: String
        /// A global rule that allows it already (that rule's resource): declining still denies it here.
        public let allowedGlobally: String?
        public var id: String { host + "|" + kit }
    }

    public let environment: ProjectEnvironment
    /// What the agent may reach: a project kit's runtime allows. The operator may decline each.
    public let runtimeHosts: [Host]
    /// Hosts the kits deny.
    public let deniedHosts: [String]
    /// Open only while the kits install, before the agent starts: confirmed with the file as a
    /// whole (they cannot be declined one by one).
    public let installHosts: [String]
    /// The fingerprint the project last confirmed.
    public let approved: String?

    /// Whether this version still needs the operator: never confirmed, or changed since.
    public var needsApproval: Bool { approved != environment.fingerprint }
    /// Refused entries stop a confirmation (and a create).
    public var canApprove: Bool { environment.isAcceptable }

    public static func make(_ environment: ProjectEnvironment, project: Project, globalRules: [SbxPolicyRule]) -> EnvironmentReview {
        let globalResources = globalRules
            .filter { $0.isGlobal && $0.decision == "allow" && $0.status == "active" && $0.resourceType == "network" }
            .flatMap(\.resources)
        func covering(_ host: String) -> String? {
            let pattern = HostPattern(parsing: host)
            return globalResources.first { HostPattern(parsing: $0).covers(pattern) }
        }
        var seen = Set<String>()
        let runtime = environment.runtimeHosts.filter { !$0.deny }.compactMap { request -> Host? in
            guard seen.insert(request.host + "|" + request.kit).inserted else { return nil }
            return Host(host: request.host, methods: request.methods, paths: request.paths, kit: request.kit,
                        allowedGlobally: covering(request.host))
        }
        return EnvironmentReview(
            environment: environment, runtimeHosts: runtime,
            deniedHosts: Array(Set(environment.runtimeHosts.filter(\.deny).map(\.host))).sorted(),
            installHosts: Array(Set(environment.installHosts.filter { !$0.deny }.map(\.host))).sorted(),
            approved: project.approvedEnvironment)
    }

    /// The project confirmed with `declined` hosts: those the operator turned down, only among the
    /// runtime hosts (anything else is dropped).
    public func approve(_ project: Project, declined: Set<String>) -> Project {
        var approved = project
        approved.approvedEnvironment = environment.fingerprint
        approved.declinedHosts = runtimeHosts.map(\.host).filter(declined.contains).reduce(into: [String]()) { list, host in
            if !list.contains(host) { list.append(host) }
        }
        return approved
    }
}
