import Foundation

/// A project's host rules: the allows and denies its sandbox has in sbx (the only store for them).
public enum HostRules {
    public enum Decision: String, Sendable, Equatable {
        case allow, deny
    }

    public enum Problem: Error, Equatable, CustomStringConvertible {
        case invalid(String)
        /// This Mac's ports go through Ports (host services), which keep the reserved ports out.
        case hostLoopback(String)
        case allHosts

        public var description: String {
            switch self {
            case .invalid(let text): "\"\(text)\" is not a host (examples: example.com, *.example.com:443)"
            case .hostLoopback(let text): "\(text) is this Mac; allow its ports under Ports"
            case .allHosts: "** would match every host"
            }
        }
    }

    /// One row of a project's host rules.
    public struct Row: Sendable, Equatable, Identifiable {
        public enum Source: Sendable, Equatable {
            /// A rule the sandbox has in sbx.
            case sandbox
        }

        public let host: String
        public let decision: Decision
        public let source: Source
        public var id: String { "\(host)|\(decision.rawValue)|\(source)" }
    }

    /// What a host rule may contain. A comma would make one sbx argument several rules. Built once:
    /// the views validate on every render, and building it each time held up project switches (PAD-29).
    private static let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_*?[]!:"))

    /// The host as sbx expects it, or why it cannot be a rule.
    public static func validated(_ text: String) throws(Problem) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            throw .invalid(text)
        }
        let pattern = HostPattern(parsing: trimmed)
        guard !pattern.host.isEmpty, pattern.port.map({ (1...65535).contains($0) }) ?? true else { throw .invalid(text) }
        if pattern.isAllHosts { throw .allHosts }
        if PolicyPlanner.hostLoopbackNames.contains(where: { pattern.covers(HostPattern(host: $0, port: pattern.port)) }) {
            throw .hostLoopback(trimmed)
        }
        return pattern.description
    }

    /// - Parameters:
    ///   - snapshot: the sandbox as sbx reports it; nil before it exists (or was read).
    ///   - globalAllows: sbx's global allows; a host one of them covers is allowed already.
    ///   - plannedDenies: Paddock's denies for its own services (`SandboxPolicyPlan.denies`), not
    ///     the operator's rules, so they are not listed.
    public static func rows(snapshot: SandboxSnapshot?, globalAllows: [HostPattern], plannedDenies: Set<String>) -> [Row] {
        let own = (snapshot?.added("allow") ?? []).flatMap(\.resources).filter(isHostRule)
        let ownDenies = (snapshot?.added("deny") ?? []).flatMap(\.resources).filter(isHostRule)
            .filter { !plannedDenies.contains($0) }
        var rows: [Row] = []
        var current: [String: Decision] = [:]
        // A deny in the sandbox overrides an allow for the same host.
        for host in ownDenies where current[host] == nil { current[host] = .deny }
        for host in own where current[host] == nil { current[host] = .allow }
        for decision in [Decision.allow, .deny] {
            var listed = Set<String>()
            for host in own + ownDenies where current[host] == decision && listed.insert(host).inserted {
                rows.append(Row(host: host, decision: decision, source: .sandbox))
            }
        }
        return rows
    }

    /// A resource a host rule names (not this Mac, whose ports are host services under Ports).
    static func isHostRule(_ resource: String) -> Bool {
        (try? validated(resource)) != nil
    }

    /// The sandbox's own network allows that feed the plan: host rules and host services, without
    /// Paddock's own services (those show as "not denied" under Ports instead).
    public static func plannedAllows(_ snapshot: SandboxSnapshot?, app: AppConfig) -> [String] {
        plannedAllows((snapshot?.added("allow") ?? []).flatMap(\.resources), app: app)
    }

    static func plannedAllows(_ resources: [String], app: AppConfig) -> [String] {
        resources.filter { resource in
            let pattern = HostPattern(parsing: resource)
            if PolicyPlanner.hostLoopbackNames.contains(pattern.host) {
                return pattern.port.map { !Ports.isReserved($0, app: app) } ?? false
            }
            return isHostRule(resource)
        }
    }
}
