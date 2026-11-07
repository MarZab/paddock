import Foundation

/// The actual state of one sandbox, as sbx reports it.
public struct SandboxSnapshot: Sendable, Equatable {
    public let sandbox: SbxSandbox
    /// `sbx ports N --json`
    public let ports: [SbxPort]
    /// `sbx policy ls N --json`, only the rules scoped to this sandbox.
    public let rules: [SbxPolicyRule]

    public init(sandbox: SbxSandbox, ports: [SbxPort], rules: [SbxPolicyRule]) {
        self.sandbox = sandbox
        self.ports = ports
        self.rules = rules.filter { $0.sandboxScope == sandbox.name }
    }

    /// The first workspace is the project folder (`:ro` extras follow it).
    public var folder: String? {
        sandbox.workspaces.first.map { $0.hasSuffix(":ro") ? String($0.dropLast(3)) : $0 }
    }

    /// Rules Paddock or the operator added (not sbx's own kit rules).
    func added(_ decision: String, type: String = "network") -> [SbxPolicyRule] {
        rules.filter { $0.decision == decision && $0.resourceType == type && $0.createdVia != "provisioned" }
    }
}

/// One difference between what the project asks for and its sandbox, with what Apply does to sbx
/// (backlog doc App config, Sync). sbx is the only store for ports and rules, so these are few: the sandbox is
/// missing, its folder, agent, kits, extra folders, or confirmed `sbxenv.yaml` differ, or Paddock's own per-sandbox denies or gateway rule are.
public struct SyncItem: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case sandbox, setting, network
    }

    /// Changes to sbx.
    public enum Apply: Sendable, Equatable {
        case create
        /// Folder, agent, kits, extra folders, or the project's `sbxenv.yaml` differ; sbx cannot
        /// change them in place.
        case recreate
        case deny([String])
        case gatewayRule
    }

    public let id: String
    public let kind: Kind
    public let summary: String
    public let apply: Apply?

    public init(id: String, kind: Kind, summary: String, apply: Apply?) {
        self.id = id
        self.kind = kind
        self.summary = summary
        self.apply = apply
    }

    /// The item for Paddock's missing denies for its own services.
    public static let serviceDeniesID = "network-denies"

    /// Apply removes or replaces something sbx has; the app confirms first.
    public var applyIsDestructive: Bool {
        switch apply {
        case .recreate?: true
        default: false
        }
    }
}

public enum SandboxSync {
    /// The differences between `project` and `snapshot` (nil when the sandbox does not exist).
    /// `globalRules` are `sbx policy ls --json`'s rules, for the per-sandbox denies Paddock adds.
    /// `expectedKits` are the kits the project asks for (`ResolvedKit.recorded`), nil to leave
    /// kits out. `environment` is the record of the project's `sbxenv.yaml` as it is now, when that
    /// is the confirmed version; it says what changed since the create.
    /// `claudeSessions` is the folder the project's sandbox should mount for Claude's sessions
    /// (`ClaudeSessions.folder`), nil when it should mount none.
    public static func diff(project: Project, snapshot: SandboxSnapshot?, globalRules: [SbxPolicyRule], app: AppConfig,
                            expectedKits: Result<[String], KitError>? = nil, environment: EnvironmentRecord? = nil,
                            claudeSessions: String? = nil) -> [SyncItem] {
        guard let snapshot else {
            return [SyncItem(id: "sandbox", kind: .sandbox, summary: "No sandbox yet", apply: .create)]
        }
        var items: [SyncItem] = []

        if let folder = snapshot.folder, FolderPolicy.canonical(folder) != FolderPolicy.canonical(project.folder) {
            items.append(SyncItem(id: "folder", kind: .setting, summary: "The sandbox mounts \(folder), the project names \(project.folder)",
                                  apply: .recreate))
        }
        let mounted = ExtraFolders.inSandbox(snapshot.sandbox.workspaces).map {
            Project.ExtraFolder(path: FolderPolicy.canonical($0.path), readOnly: $0.readOnly)
        }
        let chosen = project.extraFolders.map { Project.ExtraFolder(path: FolderPolicy.canonical($0.path), readOnly: $0.readOnly) }
        if Set(mounted) != Set(chosen) {
            items.append(SyncItem(id: "extra-folders", kind: .setting,
                                  summary: "The sandbox mounts other extra folders than the project names; recreate it to mount the ones chosen now",
                                  apply: app.agents[project.agent] == nil ? nil : .recreate))
        }
        let sbxAgent = app.agents[project.agent]?.sbxAgent ?? project.agent
        if snapshot.sandbox.agent != sbxAgent {
            items.append(SyncItem(id: "agent", kind: .setting, summary: "The sandbox runs \(snapshot.sandbox.agent), the project names \(sbxAgent)",
                                  apply: app.agents[project.agent] == nil ? nil : .recreate))
        }
        // Only a confirmed version counts: one the operator has not confirmed waits for that first.
        if let approved = project.approvedEnvironment, approved != project.sandboxEnvironment,
           let summary = environmentSummary(project: project, now: environment) {
            items.append(SyncItem(id: "environment", kind: .setting, summary: summary,
                                  apply: app.agents[project.agent] == nil ? nil : .recreate))
        }
        switch expectedKits {
        case .success(let kits)?:
            // Only when Paddock created the sandbox and recorded its kits: sbx does not report them.
            if let created = project.sandboxKits {
                let changes = kitChanges(created: created, now: kits)
                if !changes.isEmpty {
                    items.append(SyncItem(id: "kits", kind: .setting,
                                          summary: "The sandbox's kits differ: \(changes.joined(separator: "; ")); recreate it to get the kits chosen now",
                                          apply: app.agents[project.agent] == nil ? nil : .recreate))
                }
            }
        case .failure(let error)?:
            items.append(SyncItem(id: "kits", kind: .setting, summary: "The project's kits cannot be used: \(error.description)", apply: nil))
        case nil:
            break
        }
        // Only when Paddock created the sandbox: it recorded the sessions folder it mounted then.
        if project.sandboxKits != nil, project.sandboxClaudeSessions.map(FolderPolicy.canonical) != claudeSessions.map(FolderPolicy.canonical) {
            let summary = claudeSessions == nil
                ? "The sandbox keeps Claude's sessions on this Mac, the project no longer does; recreate it to stop"
                : "Claude's sessions are not kept on this Mac yet; recreate the sandbox to keep them (its current sessions are lost once)"
            items.append(SyncItem(id: "claude-sessions", kind: .setting, summary: summary,
                                  apply: app.agents[project.agent] == nil ? nil : .recreate))
        }
        items += networkItems(project: project, snapshot: snapshot, globalRules: globalRules, app: app)
        return items
    }

    /// What changed in the confirmed `sbxenv.yaml` since the create; nil when nothing that counts
    /// did (formatting, comments, Finder files). Without a record from the create, Paddock cannot tell.
    static func environmentSummary(project: Project, now: EnvironmentRecord?) -> String? {
        guard project.sandboxEnvironment != nil else {
            return "The sandbox was created without the project's sbxenv.yaml; recreate it to use it"
        }
        guard let before = project.sandboxEnvironmentRecord else {
            return "The project's sbxenv.yaml or its kit changed since the sandbox was created "
                + "(Paddock kept no details for this sandbox); recreate it to use them"
        }
        guard let now else {
            return "The project's sbxenv.yaml or its kit changed since the sandbox was created, and again since it was "
                + "confirmed; review it, then recreate the sandbox"
        }
        let changes = now.changes(since: before)
        guard !changes.isEmpty else { return nil }
        return "Changed since the sandbox was created: \(changes.joined(separator: "; ")); recreate it to use them"
    }

    /// The kits a sandbox was created with against the ones chosen now (`ResolvedKit.recorded`):
    /// added, removed, and Paddock's kits whose spec is newer. Order alone is no change.
    static func kitChanges(created: [String], now: [String]) -> [String] {
        func base(_ recorded: String) -> String { String(recorded.split(separator: "#", maxSplits: 1).first ?? "") }
        func label(_ recorded: String) -> String {
            let argument = base(recorded)
            // Paddock's kits and local ones are folders: their name says enough.
            return argument.hasPrefix("/") ? (argument as NSString).lastPathComponent : argument
        }
        let before = Dictionary(created.map { (base($0), $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(now.map { (base($0), $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [String] = []
        let added = after.keys.filter { before[$0] == nil }.map { label(after[$0] ?? $0) }.sorted()
        let removed = before.keys.filter { after[$0] == nil }.map { label(before[$0] ?? $0) }.sorted()
        let newer = after.keys.filter { before[$0] != nil && before[$0] != after[$0] }.map { label(after[$0] ?? $0) }.sorted()
        if !added.isEmpty { changes.append("added \(added.joined(separator: ", "))") }
        if !removed.isEmpty { changes.append("removed \(removed.joined(separator: ", "))") }
        if !newer.isEmpty { changes.append("newer \(newer.joined(separator: ", "))") }
        return changes
    }

    /// The plan for the sandbox as it is now: the allows it has in sbx, with Paddock's denies for
    /// its own services.
    public static func plan(project: Project, snapshot: SandboxSnapshot?, globalRules: [SbxPolicyRule],
                            app: AppConfig) throws(PolicyPlanError) -> SandboxPolicyPlan {
        try ProjectRunner.plan(project, usesGateway: project.usesGateway(app), allowed: HostRules.plannedAllows(snapshot, app: app),
                               globalRules: globalRules, app: app)
    }

    static func networkItems(project: Project, snapshot: SandboxSnapshot, globalRules: [SbxPolicyRule], app: AppConfig) -> [SyncItem] {
        let plan: SandboxPolicyPlan
        do throws(PolicyPlanError) {
            plan = try Self.plan(project: project, snapshot: snapshot, globalRules: globalRules, app: app)
        } catch {
            return [SyncItem(id: "network-plan", kind: .network, summary: "Paddock cannot plan this sandbox's network: \(error.description)",
                             apply: nil)]
        }
        var items: [SyncItem] = []
        // Paddock's denies for its own services: llmman's port, and other projects' gateway ports
        // when a global rule reaches them (those also show as "not denied" under Ports).
        let actualDenies = Set(snapshot.rules.filter { $0.decision == "deny" }.flatMap(\.resources))
        let missingDenies = plan.denies.filter { !actualDenies.contains($0) }
        if !missingDenies.isEmpty {
            let shown = missingDenies.prefix(3).joined(separator: ", ") + (missingDenies.count > 3 ? ", ..." : "")
            items.append(SyncItem(id: SyncItem.serviceDeniesID, kind: .network,
                                  summary: "Paddock's services are not denied for this sandbox: \(shown)", apply: .deny(missingDenies)))
        }
        if project.usesGateway(app), let port = project.gatewayPort,
           PolicyPlanner.gatewayPort(ofSandbox: project.name, rules: snapshot.rules, in: app.models.gatewayPorts) != port {
            items.append(SyncItem(id: "gateway-rule", kind: .network, summary: "The gateway rule for port \(port) is missing",
                                  apply: .gatewayRule))
        }
        return items
    }

    /// The project for a sandbox without a project file, from what `sbx ls` reports. Its id is
    /// sbx's sandbox id, so it stays the same once its file is written.
    public static func unsaved(_ sandbox: SbxSandbox, app: AppConfig) -> Project {
        let agentSection = app.agents.first { $0.value.sbxAgent == sandbox.agent }?.key
        let folder = sandbox.workspaces.first.map { $0.hasSuffix(":ro") ? String($0.dropLast(3)) : $0 } ?? "/"
        return Project(id: UUID(uuidString: sandbox.id) ?? Self.stableID(sandbox.name), name: sandbox.name,
                       folder: FolderPolicy.canonical(folder), agent: agentSection ?? sandbox.agent,
                       provider: app.defaults.provider)
    }

    /// The project file for a sandbox Paddock did not create, written the first time it is
    /// managed: its name, folder, and agent. Its ports and rules stay in sbx.
    public static func adopt(_ snapshot: SandboxSnapshot, app: AppConfig) -> Project {
        unsaved(snapshot.sandbox, app: app)
    }

    /// For sandbox ids that are not UUIDs: the same name always gives the same id.
    static func stableID(_ name: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in name.utf8.enumerated() {
            bytes[index % 16] = bytes[index % 16] &* 31 &+ byte
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
