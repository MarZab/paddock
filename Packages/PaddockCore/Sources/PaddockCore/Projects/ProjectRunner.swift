import Foundation

public enum ProjectRunError: Error, Equatable, CustomStringConvertible {
    /// Paddock acts only on sandboxes that have a project file, under a name sbx accepts.
    case invalidSandboxName(String)
    /// A project saved back from a kit-based sandbox has no agent section to recreate it from.
    case cannotRecreate(agent: String)
    /// The project's `sbxenv.yaml` or its own kits changed since the operator confirmed them.
    case environmentNeedsApproval
    /// The files changed while sbx created the sandbox, so it may have been built from a version
    /// the operator never confirmed; Paddock removed it (PAD-84).
    case environmentChangedDuringCreate
    /// The project's `sbxenv.yaml` asks for something Paddock refuses (`ProjectEnvironment`).
    case environment([String])
    case policy(PolicyPlanError)
    case missingGatewayPort
    /// The project's local model is not in llmman's store.
    case modelNotInstalled(String)
    /// llmman did not list its models, so the project's model could not be checked.
    case modelsUnknown
    case gatewayRuleMissing(String)
    case globalRuleNotRemovable(String)
    case invalidHost(String, HostRules.Problem)
    /// An approval answered for a project whose sandbox did not ask, or with an answer sbx did not offer.
    case approvalMismatch(String)
    /// `sbx stop` succeeded but sbx still lists the sandbox as running (a session started it again).
    case stillRunning(String)
    case kit(KitError)
    /// An extra folder no longer passes the folder checks (PAD-73.5).
    case extraFolder(String, ExtraFolderProblem)
    /// A file a native tab asked for that Paddock does not read.
    case invalidShowPath(String)

    public var description: String {
        switch self {
        case .invalidSandboxName(let name): "\(name) is not a valid sandbox name"
        case .cannotRecreate(let agent): "agent \(agent) is not a paddock.yaml agent entry, so Paddock cannot create this sandbox"
        case .environmentNeedsApproval: "the project's sbxenv.yaml or its kit changed since you confirmed them; review and confirm first"
        case .environmentChangedDuringCreate:
            "the project's sbxenv.yaml or its kit changed while the sandbox was being created, so Paddock removed it; review and confirm again"
        case .environment(let problems): "the project's sbxenv.yaml cannot be used:\n" + problems.joined(separator: "\n")
        case .policy(let error): error.description
        case .missingGatewayPort: "this project uses a local model but has no gateway port"
        case .modelNotInstalled(let model): "model \(model) is not in llmman's store; download it on the Models page first"
        case .modelsUnknown: "llmman did not list its models, so Paddock cannot check this project's model; is sbx's daemon running?"
        case .gatewayRuleMissing(let name): "sbx does not list the gateway rule for \(name); check: sbx policy ls \(name)"
        case .globalRuleNotRemovable(let id): "rule \(id) is an sbx default or an organization policy and cannot be removed"
        case .extraFolder(let path, let problem): "extra folder \(path) cannot be mounted: \(problem.description)"
        case .invalidHost(_, let problem): problem.description
        case .approvalMismatch(let id): "approval \(id) is not this sandbox's, or sbx does not offer that answer"
        case .stillRunning(let name): "sbx stopped \(name), but it is running again; something started it (sbx exec or sbx run in a terminal)"
        case .kit(let error): error.description
        case .invalidShowPath(let path): "Paddock does not read \(path) for a shown file"
        }
    }
}

/// One of sbx's global rules, to remove: its id and every resource it names (removing the rule
/// removes them all).
public struct SbxRuleReference: Sendable, Equatable {
    public let id: String
    public let resources: [String]
    /// Local rules the operator added; sbx defaults and org policy cannot be removed.
    public let removable: Bool

    public init(id: String, resources: [String], removable: Bool) {
        self.id = id
        self.resources = resources
        self.removable = removable
    }
}

/// Creates, starts, stops, and removes a project's sandbox (backlog doc SbxService). The same steps the
/// gateway trial verified on the Mac, plus the approval and ownership checks.
public struct ProjectRunner: Sendable {
    private let sbx: SbxService
    private let paths: PaddockPaths
    private let log: LogSink?

    /// `log` hears what a create does (the Log page).
    public init(sbx: SbxService, paths: PaddockPaths, log: LogSink? = nil,
                home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.sbx = sbx
        self.paths = paths
        self.log = log
        folderPolicy = FolderPolicy(home: home, paddockConfigDirectory: paths.configDirectory)
    }

    /// For the extra folders, checked again at every create.
    private let folderPolicy: FolderPolicy

    /// `models` is what llmman's `/api/tags` lists (nil when it did not answer), for `checkModel`.
    /// `projectFolders` are every project's folders: a local kit inside one is refused.
    /// Returns the project as created: with the kits and the confirmed `sbxenv.yaml` it was created
    /// from (`Project.sandboxKits`, `Project.sandboxEnvironment`), for the caller to save.
    ///
    /// With an `sbxenv.yaml` in the project folder (backlog doc Project config file), Paddock checks
    /// it (`ProjectEnvironment`), needs the operator's confirmation of exactly this version, writes
    /// its own part (`PaddockOverlay`), and runs `sbx env create <file> <overlay>`. Without one, it
    /// runs `sbx create` as before. Either way Paddock's denies, the hosts the operator declined,
    /// and the gateway rule follow.
    @discardableResult
    public func create(_ project: Project, app: AppConfig, models: [String]?, projectFolders: [String] = [],
                       progress: (@Sendable (String) async -> Void)? = nil) async throws -> Project {
        try owned(project)
        guard let agent = app.agents[project.agent] else { throw ProjectRunError.cannotRecreate(agent: project.agent) }
        let environment = try confirmedEnvironment(project, app: app)
        let provider = app.provider(named: project.provider)
        try Self.checkModel(provider, installed: models)
        let kits: [ResolvedKit]
        do {
            kits = try project.resolvedKits(app, paths: paths, projectFolders: projectFolders + [project.folder])
        } catch {
            throw ProjectRunError.kit(error)
        }

        var gateway: GatewayAccess?
        if case .local(let model)? = provider {
            guard let port = project.gatewayPort else { throw ProjectRunError.missingGatewayPort }
            gateway = GatewayAccess(model: model, port: port)
        }
        let plan: SandboxPolicyPlan
        do {
            plan = try Self.plan(project, usesGateway: gateway != nil, globalRules: try await sbx.policies().rules, app: app)
        } catch let error as PolicyPlanError {
            throw ProjectRunError.policy(error)
        }

        // Paddock's own kits are written before sbx reads them.
        for kit in kits {
            if let builtin = kit.builtin {
                try BuiltinKits.install(builtin, in: paths)
            }
        }
        // Extra folders are checked again: one may have changed, or become a link, since it was added.
        let extras: [Project.ExtraFolder]
        do throws(ExtraFolderProblem) {
            extras = try ExtraFolders.checkAll(project, policy: folderPolicy)
        } catch {
            throw ProjectRunError.extraFolder(project.extraFolders.first?.path ?? "", error)
        }

        let planner = AgentLaunchPlanner(paths: paths)
        await progress?("Creating the sandbox")
        if let environment {
            let overlay = PaddockOverlay(agent: agent.sbxAgent, workspace: FolderPolicy.canonical(project.folder),
                                         kits: kits.map(\.argument), env: planner.environment(agent: agent, gateway: gateway),
                                         extraFolders: extras)
            let overlayPath = PaddockOverlay.path(project: project.name, paths: paths)
            try overlay.write(to: overlayPath)
            log?("sbx env create for \(project.name): \(environment.kits.count) project kits, \(kits.count) of Paddock's")
            try await sbx.perform(PaddockOverlay.createArguments(environmentFile: project.folder + "/" + SbxEnvFile.fileName,
                                                                 overlay: overlayPath, name: project.name, clone: project.cloneMode))
            // sbx read the folder itself, after the check above, and the agent writes that folder: a
            // different version than the confirmed one means the sandbox is not what was approved.
            let context = ProjectEnvironment.Context(folderPolicy: folderPolicy, app: app)
            if ProjectEnvironment.read(folder: project.folder, context: context)?.fingerprint != environment.fingerprint {
                try? await sbx.perform(["rm", "--force", "--json", project.name])
                throw ProjectRunError.environmentChangedDuringCreate
            }
            // `sbx env create` takes no --deny-network: Paddock's denies, and the hosts the operator
            // declined, right after it, before any agent session.
            for command in planner.denyCommands(name: project.name, resources: plan.denies + project.declinedHosts) {
                try await sbx.perform(command)
            }
        } else {
            // Ports are published afterwards: the app picks free host ports across every sandbox.
            try await sbx.create(planner.create(name: project.name, agent: agent, folder: project.folder,
                                                policy: plan, gateway: gateway, kits: kits.map(\.argument),
                                                clone: project.cloneMode, extraFolders: extras.map(ExtraFolders.argument)))
        }
        for command in planner.policyCommands(name: project.name, plan: plan) {
            try await sbx.perform(command)
        }
        if let gateway {
            try await verifyGatewayRule(project.name, port: gateway.port, app: app)
            if agent == .openCode {
                try await sbx.perform(planner.writeOpenCodeConfig(name: project.name, gateway: gateway))
            }
        }
        var created = project
        created.sandboxKits = kits.map(\.recorded)
        created.sandboxEnvironment = environment?.fingerprint
        return created
    }

    /// The project's `sbxenv.yaml` checked and confirmed, or nil without one. Refused entries and a
    /// version the operator has not confirmed stop a create before sbx is asked anything.
    public func confirmedEnvironment(_ project: Project, app: AppConfig) throws -> ProjectEnvironment? {
        let context = ProjectEnvironment.Context(folderPolicy: folderPolicy, app: app)
        guard let environment = ProjectEnvironment.read(folder: project.folder, context: context) else { return nil }
        guard environment.isAcceptable else { throw ProjectRunError.environment(environment.problems.map(\.description)) }
        guard project.approvedEnvironment == environment.fingerprint else { throw ProjectRunError.environmentNeedsApproval }
        return environment
    }

    /// Before an agent session: an OpenCode project on a local model gets its config file written
    /// again (a sandbox created before Paddock wrote it, or one whose file changed). Nothing for
    /// any other project.
    public func prepareAgentSession(_ project: Project, app: AppConfig) async throws {
        try owned(project)
        guard app.agents[project.agent] == .openCode, case .local(let model)? = app.provider(named: project.provider),
              let port = project.gatewayPort else { return }
        try await sbx.perform(AgentLaunchPlanner(paths: paths)
            .writeOpenCodeConfig(name: project.name, gateway: GatewayAccess(model: model, port: port)))
    }

    /// `sbx run -d --name N` restarts an existing sandbox without opening a session.
    public func start(_ project: Project, app: AppConfig, models: [String]?) async throws {
        try owned(project)
        try Self.checkModel(app.provider(named: project.provider), installed: models)
        try await ensureGatewayRule(project, app: app)
        try await sbx.perform(["run", "--detach", "--name", project.name])
    }

    /// `sbx stop` exits 0 even when the sandbox runs again right after (any `sbx exec` or
    /// `sbx run` starts a stopped sandbox), so the state is checked once it returns; a local stop
    /// returns after the sandbox stopped.
    public func stop(_ project: Project) async throws {
        try owned(project)
        try await sbx.perform(["stop", project.name])
        let sandbox = try await sbx.sandboxes().first { $0.name == project.name }
        if sandbox?.status == "running" { throw ProjectRunError.stillRunning(project.name) }
    }

    /// Removes the sandbox only; the project folder and the project file stay. A sandbox sbx no
    /// longer has is already removed, not an error.
    public func remove(_ project: Project) async throws {
        try owned(project)
        do {
            try await sbx.perform(["rm", "--force", "--json", project.name])
        } catch let SbxError.commandFailed(_, _, stderr) where stderr.contains("sandbox '\(project.name)' not found") {
            return
        }
    }

    /// backlog doc M0 findings, open risk 6: llmman may download a model it is asked for but does not have, so a
    /// project on a local model is created or started only while llmman lists that model.
    static func checkModel(_ provider: AppConfig.Provider?, installed: [String]?) throws(ProjectRunError) {
        guard case .local(let model)? = provider else { return }
        guard let installed else { throw .modelsUnknown }
        guard installed.contains(model) else { throw .modelNotInstalled(model) }
    }

    /// Seen once on sbx 0.49.2: a gateway rule added after create was gone later. Re-adds it.
    public func ensureGatewayRule(_ project: Project, app: AppConfig) async throws {
        guard let port = project.gatewayPort else { return }
        let rules = try await sbx.policies(sandbox: project.name).rules
        if PolicyPlanner.gatewayPort(ofSandbox: project.name, rules: rules, in: app.models.gatewayPorts) == port {
            return
        }
        try await sbx.perform(["policy", "allow", "network", "--sandbox", project.name, "localhost:\(port)",
                               "--method", "GET,POST", "--path", "/v1/**"])
        try await verifyGatewayRule(project.name, port: port, app: app)
    }

    // MARK: - Sync

    /// What sbx reports for a sandbox (a project's or any other), for `SandboxSync`. Nil when it
    /// does not exist. Read-only.
    public func snapshot(named name: String) async throws -> SandboxSnapshot? {
        guard let sandbox = try await sbx.sandboxes().first(where: { $0.name == name }) else { return nil }
        return try await snapshot(of: sandbox)
    }

    /// Ports and rules are read separately, so one failing call never hides the other; both
    /// failing is an error.
    public func snapshot(of sandbox: SbxSandbox) async throws -> SandboxSnapshot {
        let ports: [SbxPort]
        let rules: [SbxPolicyRule]
        var failure: (any Error)?
        do { ports = try await sbx.ports(sandbox: sandbox.name) } catch { ports = []; failure = error }
        do { rules = try await sbx.policies(sandbox: sandbox.name).rules } catch {
            if let failure { throw failure }
            rules = []
        }
        return SandboxSnapshot(sandbox: sandbox, ports: ports, rules: rules)
    }

    public func globalRules() async throws -> [SbxPolicyRule] {
        try await sbx.policies().rules
    }

    /// Requests no rule decided, from every sandbox, waiting for the operator. Read-only.
    public func approvals() async throws -> [SbxApproval] {
        try await sbx.approvals()
    }

    /// Answers one of the project's sandbox's approvals with an option sbx offered (`allow`
    /// adds sbx's own rule for it; `dismiss` drops the request).
    public func respond(to approval: SbxApproval, with option: String, for project: Project) async throws {
        try owned(project)
        guard approval.sandboxName == project.name, approval.options.contains(where: { $0.id == option }) else {
            throw ProjectRunError.approvalMismatch(approval.id)
        }
        try await sbx.perform(["policy", "approval", "respond", approval.id, "--option", option])
    }

    /// What every sandbox connected to, or tried to, from sbx's network log. Read-only.
    public func networkLog() async throws -> SbxPolicyLog {
        try await sbx.policyLog()
    }

    /// Makes sbx match the project for one difference. Returns the project as created when it
    /// created the sandbox (see `create`).
    @discardableResult
    public func apply(_ change: SyncItem.Apply, for project: Project, app: AppConfig, models: [String]?,
                      projectFolders: [String] = [], progress: (@Sendable (String) async -> Void)? = nil) async throws -> Project? {
        try owned(project)
        switch change {
        case .create:
            return try await create(project, app: app, models: models, projectFolders: projectFolders, progress: progress)
        case .recreate:
            guard app.agents[project.agent] != nil else { throw ProjectRunError.cannotRecreate(agent: project.agent) }
            // Before the remove, so a missing model never leaves the project without a sandbox.
            try Self.checkModel(app.provider(named: project.provider), installed: models)
            // Also before the remove: an sbxenv.yaml not confirmed, or kits that no longer
            // resolve, would leave no sandbox.
            _ = try confirmedEnvironment(project, app: app)
            do {
                _ = try project.resolvedKits(app, paths: paths, projectFolders: projectFolders + [project.folder])
            } catch {
                throw ProjectRunError.kit(error)
            }
            try await remove(project)
            return try await create(project, app: app, models: models, projectFolders: projectFolders, progress: progress)
        case .deny(let resources):
            // Comma-separated, in batches, so one call never gets an enormous argument.
            for start in stride(from: 0, to: resources.count, by: 40) {
                let batch = resources[start..<min(start + 40, resources.count)]
                try await sbx.perform(["policy", "deny", "network", "--sandbox", project.name, batch.joined(separator: ",")])
            }
        case .gatewayRule:
            try await ensureGatewayRule(project, app: app)
        }
        return nil
    }

    // MARK: - Templates (backlog doc UI, Templates)

    /// sbx's templates, with what each is for.
    public func templateRows() async throws -> [TemplateRow] {
        TemplateUsage.rows(try await sbx.templates())
    }

    /// Removes the named templates, an operator action confirmed first. One sbx no longer lists is
    /// reported, not removed; sbx itself refuses one a sandbox runs.
    public func removeTemplates(_ names: [String]) async throws -> TemplateRemoval {
        let rows = try await templateRows()
        var result = TemplateRemoval()
        for name in names {
            guard rows.contains(where: { $0.name == name }) else {
                result.failed.append(.init(name: name, reason: "sbx does not list it any more"))
                continue
            }
            do {
                try await sbx.perform(TemplateUsage.removeArguments(name))
                result.removed.append(name)
            } catch {
                result.failed.append(.init(name: name, reason: String(describing: error)))
            }
        }
        return result
    }

    /// Blocks a host for every sandbox with a global sbx deny: an operator action from Paddock's
    /// interface, confirmed first (CLAUDE.md: Paddock never changes global rules on its own).
    public func addGlobalDeny(_ host: String) async throws {
        let checked: String
        do throws(HostRules.Problem) {
            checked = try HostRules.validated(host)
        } catch {
            throw ProjectRunError.invalidHost(host, error)
        }
        try await sbx.perform(["policy", "deny", "network", checked])
    }

    /// Removes one of sbx's global rules: an operator action from Paddock's interface, confirmed
    /// first (CLAUDE.md: Paddock never changes global rules on its own).
    public func removeGlobalRule(_ rule: SbxRuleReference) async throws {
        guard rule.removable else { throw ProjectRunError.globalRuleNotRemovable(rule.id) }
        try await removeRule(rule.id, sandbox: nil)
    }

    // MARK: - Ports

    /// What sbx publishes for the sandbox now.
    public func publishedPorts(_ project: Project) async throws -> [SbxPort] {
        try owned(project)
        return try await sbx.ports(sandbox: project.name)
    }

    /// Publishes on loopback. sbx starts a stopped sandbox to do so. Already published there is
    /// done, not an error (sbx answers 409); a host port another sandbox holds names that sandbox.
    public func publish(_ mapping: Project.PortMapping, for project: Project) async throws {
        try owned(project)
        if try await isPublished(mapping, on: project.name) { return }
        do {
            try await sbx.perform(["ports", project.name, "--publish", Ports.spec(mapping)])
        } catch {
            // Read sbx again: the port may have been published meanwhile, here or elsewhere.
            if (try? await isPublished(mapping, on: project.name)) == true { return }
            if let owner = try? await sandbox(holding: mapping.hostPort, except: project.name) {
                throw PortsError.hostPortTaken(mapping.hostPort, by: owner)
            }
            throw error
        }
    }

    private func isPublished(_ mapping: Project.PortMapping, on sandbox: String) async throws -> Bool {
        try await sbx.ports(sandbox: sandbox).contains {
            $0.hostIP == Ports.hostIP && $0.hostPort == mapping.hostPort && $0.sandboxPort == mapping.sandboxPort
        }
    }

    /// The other sandbox that publishes `hostPort` on loopback, if any.
    private func sandbox(holding hostPort: Int, except name: String) async throws -> String? {
        for other in try await sbx.sandboxes() where other.name != name {
            if try await sbx.ports(sandbox: other.name).contains(where: { $0.hostIP == Ports.hostIP && $0.hostPort == hostPort }) {
                return other.name
            }
        }
        return nil
    }

    public func unpublish(hostIP: String, hostPort: Int, sandboxPort: Int, for project: Project) async throws {
        try owned(project)
        try await sbx.perform(["ports", project.name, "--unpublish", "\(hostIP):\(hostPort):\(sandboxPort)"])
    }

    /// Lets an existing sandbox reach `localhost:port` on the Mac: removes the per-sandbox denies
    /// for it (deny beats allow), then allows it.
    public func allowHostService(_ port: Int, for project: Project) async throws {
        try owned(project)
        let names = PolicyPlanner.hostLoopbackNames.map { "\($0):\(port)" }
        for rule in try await sandboxRules(project, decision: "deny", resources: names) {
            try await removeRule(rule.id, sandbox: project.name)
        }
        try await sbx.perform(["policy", "allow", "network", "--sandbox", project.name, "localhost:\(port)"])
    }

    /// The reverse: removes the per-sandbox allow, then denies the port (deny is safe either way).
    public func removeHostService(_ port: Int, for project: Project) async throws {
        try owned(project)
        let names = PolicyPlanner.hostLoopbackNames.map { "\($0):\(port)" }
        for rule in try await sandboxRules(project, decision: "allow", resources: names) {
            try await removeRule(rule.id, sandbox: project.name)
        }
        try await sbx.perform(["policy", "deny", "network", "--sandbox", project.name, names.joined(separator: ",")])
    }

    /// Allows or denies one host in the sandbox, or removes the sandbox's own rule for it (`nil`)
    /// so the policy section decides again. sbx is the only store: the plan comes from the policy
    /// section and the allows the sandbox has now. Denies first, so the host is never reachable
    /// in between when it should not be; other hosts in a replaced rule are kept as they were.
    public func setHostRule(_ decision: HostRules.Decision?, for host: String, on project: Project, app: AppConfig) async throws {
        try owned(project)
        let rules = try await sbx.policies(sandbox: project.name).rules
        let own = rules.filter {
            $0.sandboxScope == project.name && $0.resourceType == "network" && $0.editable && $0.createdVia != "provisioned"
        }
        let allows = HostRules.plannedAllows(own.filter { $0.decision == "allow" }.flatMap(\.resources), app: app).filter { $0 != host }
        let plan: SandboxPolicyPlan
        do {
            plan = try Self.plan(project, usesGateway: project.usesGateway(app),
                                 allowed: allows + (decision == .allow ? [host] : []), denied: decision == .deny ? [host] : [],
                                 globalRules: try await globalRules(), app: app)
        } catch let error as PolicyPlanError {
            throw ProjectRunError.policy(error)
        }
        let denied = plan.denies.contains(host)
        let allowed = !denied && plan.allows.contains(host)
        let touching = own.filter { $0.resources.contains(host) }
        if denied && !touching.contains(where: { $0.decision == "deny" }) {
            try await sbx.perform(["policy", "deny", "network", "--sandbox", project.name, host])
        }
        for rule in touching where (rule.decision == "deny" && !denied) || (rule.decision == "allow" && !allowed) {
            // The rest first, so a denied host is never let through while its rule is replaced.
            let rest = rule.resources.filter { $0 != host }
            if !rest.isEmpty {
                try await sbx.perform(["policy", rule.decision, "network", "--sandbox", project.name, rest.joined(separator: ",")])
            }
            try await removeRule(rule.id, sandbox: project.name)
        }
        if allowed && !touching.contains(where: { $0.decision == "allow" }) {
            try await sbx.perform(["policy", "allow", "network", "--sandbox", project.name, host])
        }
    }

    /// Rules scoped to this sandbox whose every resource is one of `resources` (so removing the
    /// rule never removes anything else).
    private func sandboxRules(_ project: Project, decision: String, resources: [String]) async throws -> [SbxPolicyRule] {
        try await sbx.policies(sandbox: project.name).rules.filter {
            $0.sandboxScope == project.name && $0.decision == decision && $0.resourceType == "network"
                && $0.editable && !$0.resources.isEmpty && $0.resources.allSatisfy(resources.contains)
        }
    }

    /// `sbx policy rm network --id ID [--sandbox N] --force`. A rule scoped to a sandbox is found
    /// only with `--sandbox` (without it sbx looks in the global policy). Without `--force` sbx asks
    /// for confirmation on a terminal and fails without one ("stdin is not a terminal"); Paddock
    /// asks the operator itself where a removal needs it (a global rule).
    private func removeRule(_ id: String, sandbox: String?) async throws {
        try await sbx.perform(["policy", "rm", "network", "--id", id] + (sandbox.map { ["--sandbox", $0] } ?? []) + ["--force"])
    }

    // MARK: - Browser

    /// Starts the browser kit's dashboard in the running sandbox (a no-op when it runs already).
    public func startBrowserDashboard(_ project: Project) async throws {
        try owned(project)
        try await sbx.perform(BrowserKit.startDashboardCommand(sandbox: project.name))
    }

    /// Tells the sandbox what the operator did with a `paddock` tab (the agent hears of it);
    /// closing or dismissing one also closes its page there.
    public func showEvent(_ event: BrowserShow.OperatorEvent, show id: String, of project: Project) async throws {
        try owned(project)
        guard let command = BrowserShow.operatorCommand(sandbox: project.name, id: id, event: event) else { return }
        try await sbx.perform(command)
    }

    /// The operator's Refresh or Back on a show tab rendered in the sandbox: done to the page there.
    public func navigateShow(_ navigation: BrowserShow.Navigation, show id: String, of project: Project) async throws {
        try owned(project)
        guard let command = BrowserShow.navigateCommand(sandbox: project.name, id: id, navigation) else { return }
        try await sbx.perform(command)
    }

    /// A screenshot or recording the operator saved from a dashboard view: copied into the sandbox
    /// (`BrowserCapture.folder`), and the agent whose page it shows is told. Returns its path there.
    @discardableResult
    public func sendCapture(localFile: String, suggestedName: String, owner: BrowserCapture.Owner,
                            of project: Project, at date: Date = Date()) async throws -> String? {
        try owned(project)
        let name = BrowserCapture.fileName(suggested: suggestedName, at: date)
        guard let commands = BrowserCapture.commands(sandbox: project.name, localFile: localFile, fileName: name, owner: owner) else {
            return nil
        }
        for command in commands {
            try await sbx.perform(command)
        }
        return BrowserCapture.folder + "/" + name
    }

    /// An interactive tab's action or the renderer's problems, handed to the sandbox for the agent
    /// (`paddock wait`). `json` comes checked from `OpenUIMessage`.
    public func sendUIEvent(_ event: BrowserShow.UIEvent, json: String, show id: String, of project: Project) async throws {
        try owned(project)
        guard let command = BrowserShow.uiEventCommand(sandbox: project.name, id: id, event, json: json) else { return }
        try await sbx.perform(command)
    }

    /// A file of a native tab (the shown file, or one beside it), read through `sbx exec`.
    public func readShowFile(show id: String, relativePath: String, of project: Project) async throws -> Data {
        try owned(project)
        guard let command = BrowserShow.readCommand(sandbox: project.name, id: id, relativePath: relativePath) else {
            throw ProjectRunError.invalidShowPath(relativePath)
        }
        let output = try await sbx.output(command)
        guard output.count <= NativeShowPolicy.maxFileBytes * 4 / 3 + 4,
              let data = Data(base64Encoded: output, options: .ignoreUnknownCharacters) else {
            throw ProjectRunError.invalidShowPath(relativePath)
        }
        return data
    }

    // MARK: - Checks

    private func owned(_ project: Project) throws {
        guard ProjectList.isValidSandboxName(project.name) else { throw ProjectRunError.invalidSandboxName(project.name) }
    }

    private func verifyGatewayRule(_ name: String, port: Int, app: AppConfig) async throws {
        let rules = try await sbx.policies(sandbox: name).rules
        guard PolicyPlanner.gatewayPort(ofSandbox: name, rules: rules, in: app.models.gatewayPorts) == port else {
            throw ProjectRunError.gatewayRuleMissing(name)
        }
    }

    /// sbx's global rules plus `allowed` and `denied` (the allows its sandbox has, for a host rule
    /// the operator changes), with Paddock's denies for its own services (backlog doc Network policy).
    public static func plan(_ project: Project, usesGateway: Bool, allowed: [String] = [], denied: [String] = [],
                            globalRules: [SbxPolicyRule], app: AppConfig) throws(PolicyPlanError) -> SandboxPolicyPlan {
        try PolicyPlanner(gatewayPort: project.gatewayPort ?? 0, gatewayPorts: app.models.gatewayPorts)
            .plan(globalRules: globalRules, allowed: allowed, denied: denied, usesGateway: usesGateway)
    }
}
