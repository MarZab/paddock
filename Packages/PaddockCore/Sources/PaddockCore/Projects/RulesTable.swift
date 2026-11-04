import Foundation

/// One row of the Network Rules and Filesystem tables: one host or path of an sbx policy rule
/// (global or one sandbox's; a rule naming 40 hosts is 40 rows), a sandbox's mount, a host the
/// log saw that no rule names, or a deny Paddock suggests.
public struct RuleRow: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case network, http
        case filesystemRead, filesystemWrite
        /// A folder sbx mounts into the sandbox (its workspace).
        case mount

        public var isFilesystem: Bool { self == .filesystemRead || self == .filesystemWrite || self == .mount }
    }

    public enum Source: String, Sendable, Equatable {
        /// sbx's built-in defaults.
        case sbxDefault
        /// Added by an sbx kit (an agent's own hosts).
        case kit
        /// Added by the operator or Paddock.
        case added
        /// Saved from an sbx approval prompt.
        case approval
        /// Organization policy, not editable here.
        case organization
        /// Paddock's per-sandbox deny protecting its own services (llmman's port, other projects'
        /// gateway ports).
        case paddockPlan
        /// The sandbox's workspace.
        case workspace
        /// A host the sandbox connected to (or tried) that no rule names: sbx's default decides.
        case unruled
        /// A deny Paddock suggests but does not apply on its own (`RulesTable.suggestedDenies`).
        case paddockSuggestion
    }

    public let id: String
    /// The sandbox it applies to; nil for every sandbox.
    public let sandbox: String?
    public let kind: Kind
    /// `allow` or `deny`.
    public let decision: String
    /// One host, path, or HTTP target.
    public let target: String
    public let source: Source
    /// The sbx rule's name, and every resource it names: removing the rule removes them all.
    public let ruleName: String?
    public let ruleResources: [String]
    /// Inactive rules (hidden by remote governance) still show, marked.
    public let active: Bool
    /// sbx's rule id, for removing it.
    public let ruleID: String?
    /// Local rules sbx lets the operator remove.
    public let removable: Bool
    /// For a network rule naming exactly one host (not this Mac): that host, so it can be allowed
    /// or denied for its sandbox.
    public let host: String?
    /// What the sandbox did with the hosts this row covers, from the network log.
    public var activity: HostActivity? = nil

    /// Not in sbx yet: a deny Paddock suggests. Shown disabled.
    public var isSuggestion: Bool { source == .paddockSuggestion }
}

/// Connections to one host (or every host a rule covers), from sbx's network log.
public struct HostActivity: Sendable, Equatable {
    public var lastSeen: Date?
    public var allowed: Int
    public var blocked: Int

    public init(lastSeen: Date? = nil, allowed: Int = 0, blocked: Int = 0) {
        self.lastSeen = lastSeen
        self.allowed = allowed
        self.blocked = blocked
    }

    /// Two hosts' activity as one (a rule that covers both).
    public func adding(_ other: HostActivity) -> HostActivity {
        let last = [lastSeen, other.lastSeen].compactMap { $0 }.max()
        return HostActivity(lastSeen: last, allowed: allowed + other.allowed, blocked: blocked + other.blocked)
    }
}

/// Which sandbox reached which host (`host:port` as the log names it).
public struct ActivityKey: Sendable, Hashable {
    public let sandbox: String
    public let host: String

    public init(sandbox: String, host: String) {
        self.sandbox = sandbox
        self.host = host
    }
}

public enum RulesTable {
    /// Every rule sbx reports, in this order: global rules, then each sandbox's rules and mounts.
    /// A project kit's hosts are among the sandbox's rules (`kit:<sandbox>`, provisioned).
    /// - Parameters:
    ///   - globalRules: `sbx policy ls --json`.
    ///   - snapshots: each sandbox read so far; its rules are the ones scoped to it.
    public static func rows(globalRules: [SbxPolicyRule], snapshots: [String: SandboxSnapshot], projects: [Project],
                            app: AppConfig) -> [RuleRow] {
        var rows = globalRules.filter(\.isGlobal).flatMap { Self.rows($0, sandbox: nil, plannedDenies: []) }
        let projectsByName = Dictionary(projects.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let names = Set(snapshots.keys).union(projects.map(\.name)).sorted()
        for name in names {
            let snapshot = snapshots[name]
            let project = projectsByName[name]
            let planned = project.flatMap {
                try? SandboxSync.plan(project: $0, snapshot: snapshot, globalRules: globalRules, app: app)
            }.map { Set($0.denies) } ?? []
            for rule in snapshot?.rules ?? [] {
                rows += Self.rows(rule, sandbox: name, plannedDenies: planned)
            }
            if let snapshot {
                rows += suggestedDenyRows(snapshot: snapshot, globalAllows: Ports.globalAllows(globalRules))
            }
            for (index, workspace) in (snapshot?.sandbox.workspaces ?? []).enumerated() {
                let readOnly = workspace.hasSuffix(":ro")
                rows.append(RuleRow(id: "\(name)|mount|\(index)", sandbox: name, kind: .mount, decision: readOnly ? "read" : "read, write",
                                    target: readOnly ? String(workspace.dropLast(3)) : workspace, source: .workspace,
                                    ruleName: nil, ruleResources: [], active: true, ruleID: nil, removable: false, host: nil))
            }
        }
        return rows
    }

    /// Denies Paddock suggests for every sandbox, but leaves to the operator (backlog doc Network
    /// policy): a short list of what a sandbox should rarely reach on this Mac or its network.
    public static let suggestedDenies: [(title: String, resources: [String])] = [
        ("Docker API (2375, 2376)", ["localhost:2375", "host.docker.internal:2375", "localhost:2376", "host.docker.internal:2376"]),
        ("Cloud metadata (169.254.169.254)", ["169.254.169.254"]),
    ]

    /// A sandbox's suggested denies: the ones an allow (global or its own) reaches and it does not
    /// deny yet, each with the resources still to deny.
    static func suggestedDenyRows(snapshot: SandboxSnapshot, globalAllows: [HostPattern]) -> [RuleRow] {
        let allows = globalAllows + snapshot.rules
            .filter { $0.decision == "allow" && $0.resourceType == "network" }
            .flatMap(\.resources).map(HostPattern.init(parsing:))
        let denied = Set(snapshot.rules.filter { $0.decision == "deny" }.flatMap(\.resources))
        let name = snapshot.sandbox.name
        return suggestedDenies.compactMap { title, resources in
            let reachable = resources.contains { resource in allows.contains { $0.covers(HostPattern(parsing: resource)) } }
            let missing = resources.filter { !denied.contains($0) }
            guard reachable, !missing.isEmpty else { return nil }
            return RuleRow(id: "\(name)|paddock|\(title)", sandbox: name, kind: .network, decision: "deny", target: title,
                           source: .paddockSuggestion, ruleName: nil, ruleResources: missing, active: false, ruleID: nil,
                           removable: false, host: nil)
        }
    }

    /// The rows that apply to one sandbox: every sandbox's (global) and its own.
    public static func applying(to sandbox: String, _ rows: [RuleRow]) -> [RuleRow] {
        rows.filter { $0.sandbox == nil || $0.sandbox == sandbox }
    }

    /// One row per resource of `rule` (per target of an HTTP rule).
    static func rows(_ rule: SbxPolicyRule, sandbox: String?, plannedDenies: Set<String>) -> [RuleRow] {
        let kind: RuleRow.Kind
        switch rule.resourceType {
        case "network": kind = .network
        case "http": kind = .http
        case "filesystem:read": kind = .filesystemRead
        case "filesystem:write": kind = .filesystemWrite
        default: return []
        }
        let targets: [String]
        if let http = rule.httpTargets, !http.isEmpty {
            let methods = rule.methods.map { $0.joined(separator: ",") + " " } ?? ""
            targets = http.map { "\(methods)\($0.host)\($0.path)" }
        } else {
            targets = rule.resources
        }
        let local = rule.layer == "local"
        let ruleSource: RuleRow.Source
        if !local {
            ruleSource = .organization
        } else {
            switch rule.createdVia {
            case "default", "implicit": ruleSource = .sbxDefault
            case "provisioned": ruleSource = .kit
            case "approval": ruleSource = .approval
            default: ruleSource = .added
            }
        }
        return targets.enumerated().map { index, target in
            // Paddock's per-sandbox deny for its plan: plumbing, not the operator's rule.
            let planned = sandbox != nil && local && kind == .network && rule.decision == "deny"
                && ruleSource != .kit && plannedDenies.contains(target)
            let host = kind == .network && HostRules.isHostRule(target) ? target : nil
            return RuleRow(id: "\(sandbox ?? "*")|\(rule.id)|\(index)", sandbox: sandbox, kind: kind, decision: rule.decision,
                           target: target, source: planned ? .paddockPlan : ruleSource, ruleName: rule.name,
                           ruleResources: rule.resources, active: rule.status == "active", ruleID: rule.id,
                           // sbx marks its own defaults editable, but they stay (cc36eb3): only the
                           // operator's local rules can be removed.
                           removable: rule.editable && local && ruleSource != .sbxDefault, host: host)
        }
    }
}

/// The rows of one scope: every sandbox (global), or one sandbox.
public struct RuleSection: Sendable, Equatable, Identifiable {
    public let sandbox: String?
    public let rows: [RuleRow]
    public var id: String { sandbox ?? "*" }
    public var title: String { sandbox ?? "All sandboxes" }
}

/// What the rules tables show: a search, a decision, and activity.
public struct RuleFilter: Sendable, Equatable {
    public enum Decision: String, Sendable, Equatable, CaseIterable {
        case all, allow, deny, suggested
    }

    public enum Seen: String, Sendable, Equatable, CaseIterable {
        case all
        /// Rows with activity in the log.
        case seen
        /// Rows with blocked connections.
        case blocked
    }

    public var query = ""
    public var decision = Decision.all
    public var seen = Seen.all

    public init() {}

    /// The rows to show.
    public func apply(_ rows: [RuleRow]) -> [RuleRow] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return rows.filter { row in
            switch decision {
            case .all: break
            case .allow: guard row.decision == "allow" || row.kind == .mount, !row.isSuggestion else { return false }
            case .deny: guard row.decision == "deny", !row.isSuggestion else { return false }
            case .suggested: guard row.isSuggestion else { return false }
            }
            switch seen {
            case .all: break
            case .seen: guard row.activity != nil else { return false }
            case .blocked: guard (row.activity?.blocked ?? 0) > 0 else { return false }
            }
            if !needle.isEmpty {
                let haystack = [row.target, row.sandbox ?? "", row.ruleName ?? ""].joined(separator: " ").lowercased()
                guard haystack.contains(needle) else { return false }
            }
            return true
        }
    }
}

extension RulesTable {
    /// The rules and the network log as one list: each network row gets the activity of the hosts
    /// it covers (one host, or every host its pattern matches), and each host no rule covers
    /// becomes a row of its own (`unruled`), so the operator can allow or deny it.
    /// - Parameter sandbox: the sandbox a project's table shows; then only its activity counts,
    ///   global rows included. Nil (the Network Rules page) counts every sandbox's.
    public static func merging(_ rows: [RuleRow], activity: [ActivityKey: HostActivity], sandbox: String?) -> [RuleRow] {
        let relevant = activity.filter { sandbox == nil || $0.key.sandbox == sandbox }
        var claimed = Set<ActivityKey>()
        var merged = rows.map { row -> RuleRow in
            guard row.kind == .network || row.kind == .http, !row.isSuggestion else { return row }
            let pattern = HostPattern(parsing: row.kind == .http ? Self.httpHost(row.target) : row.target)
            var total: HostActivity?
            for (key, seen) in relevant where (row.sandbox == nil || row.sandbox == key.sandbox)
                && pattern.covers(HostPattern(parsing: key.host)) {
                total = total.map { $0.adding(seen) } ?? seen
                claimed.insert(key)
            }
            var row = row
            row.activity = total
            return row
        }
        for (key, seen) in relevant.sorted(by: { ($0.key.sandbox, $0.key.host) < ($1.key.sandbox, $1.key.host) })
        where !claimed.contains(key) {
            merged.append(RuleRow(id: "\(key.sandbox)|seen|\(key.host)", sandbox: key.sandbox, kind: .network,
                                  decision: seen.allowed > 0 ? "allow" : "deny", target: key.host, source: .unruled,
                                  ruleName: nil, ruleResources: [], active: true, ruleID: nil, removable: false,
                                  host: HostRules.isHostRule(key.host) ? key.host : nil, activity: seen))
        }
        return merged
    }

    /// The host of an HTTP row's target (`GET,POST localhost:17480/v1/**` is `localhost:17480`).
    static func httpHost(_ target: String) -> String {
        let withoutMethods = target.split(separator: " ").last.map(String.init) ?? target
        return withoutMethods.split(separator: "/", maxSplits: 1).first.map(String.init) ?? withoutMethods
    }

    /// The rows by scope: every sandbox's first, then each sandbox's, in order; empty scopes are
    /// left out. A `selected` sandbox's own rules come before everything else.
    public static func sections(_ rows: [RuleRow], selected: String? = nil) -> [RuleSection] {
        var order: [String?] = []
        var byScope: [String: [RuleRow]] = [:]
        for row in rows {
            let key = row.sandbox ?? "*"
            if byScope[key] == nil { order.append(row.sandbox) }
            byScope[key, default: []].append(row)
        }
        func rank(_ scope: String?) -> Int {
            if let selected, scope == selected { return 0 }
            return scope == nil ? 1 : 2
        }
        let sorted = order.sorted { (rank($0), $0 ?? "") < (rank($1), $1 ?? "") }
        return sorted.map { RuleSection(sandbox: $0, rows: byScope[$0 ?? "*"] ?? []) }
    }
}
