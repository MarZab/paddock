import Foundation

/// What the New Project sheet edits (backlog doc UI, Sheets).
public struct ProjectDraft: Sendable, Equatable {
    public var folder: String
    public var name: String
    public var agent: String
    public var provider: String
    public var cloneMode = false
    /// paddock.yaml's kits, preselected from the recommended ones.
    public var kits: [String] = []
    /// Folders to mount besides the project folder, read-only unless switched (PAD-73.5).
    public var extraFolders: [Project.ExtraFolder] = []
    /// Keep Claude's sessions on this Mac across recreates (PAD-127): the operator's choice, off
    /// unless chosen; it applies to a Claude Code project.
    public var keepsClaudeSessions = false

    public init(folder: String, name: String, agent: String, provider: String, cloneMode: Bool = false,
                kits: [String] = []) {
        self.folder = folder
        self.name = name
        self.agent = agent
        self.provider = provider
        self.cloneMode = cloneMode
        self.kits = kits
    }

    /// After the agent changed: the kits offered for it, preselected again (the operator's other
    /// choices that still apply are kept).
    public mutating func agentChanged(app: AppConfig) {
        guard let agent = app.agents[agent] else { return }
        let kept = kits.filter { app.kits[$0]?.isOffered(for: agent) ?? false }
        kits = KitSelection.withNeeds(Set(kept + KitSelection.preselected(agent: agent, app: app)), app: app)
            .filter { app.kits[$0]?.isOffered(for: agent) ?? false }.sorted()
    }

    /// Selects or unselects a kit: selecting adds the kits it needs, unselecting removes the kits
    /// that need it.
    public mutating func setKit(_ name: String, selected: Bool, app: AppConfig) {
        kits = selected ? KitSelection.withNeeds(kits + [name], app: app).sorted() : KitSelection.removing(name, from: kits, app: app)
    }
}

public enum NewProjectError: Error, Equatable, CustomStringConvertible {
    case folder(FolderPolicyViolation)
    case folderAlreadyAProject(name: String)
    case invalidName(String)
    case nameTaken(String)
    case sandboxExists(String)
    case unknownSection(kind: String, name: String)
    case gatewayPortsExhausted
    case cloneNeedsGit
    case kit(KitError)
    case extraFolder(String, ExtraFolderProblem)

    public var description: String {
        switch self {
        case .folder(let violation): violation.description
        case .folderAlreadyAProject(let name): "this folder is already the project \(name)"
        case .invalidName(let name): "\(name) is not a valid name: start with a letter or number, then letters, numbers, hyphens, and periods"
        case .nameTaken(let name): "a project named \(name) exists"
        case .sandboxExists(let name): "an sbx sandbox named \(name) exists already"
        case .unknownSection(let kind, let name): "\(kind) \"\(name)\" is not defined in paddock.yaml"
        case .gatewayPortsExhausted: "every port in models.gatewayPorts is taken"
        case .cloneNeedsGit: "clone mode needs a Git repository: this folder has no .git of its own"
        case .kit(let error): error.description
        case .extraFolder(let path, let problem): "extra folder \(path): \(problem.description)"
        }
    }
}

public enum NewProject {
    /// Whether `sbx create --clone` takes the folder: it must be a Git repository itself (`.git`
    /// is a directory, or a file in a worktree). sbx 0.49.2 refused a folder inside a repository.
    public static func supportsClone(_ folder: String) -> Bool {
        FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent(".git"))
    }

    /// The folder's name, lowercased and reduced to sbx's characters, made unique. A name sbx
    /// would refuse (empty, one character, `default`) becomes `project` or `project-<name>`.
    public static func suggestedName(for folder: String, taken: Set<String>) -> String {
        let base = (folder as NSString).lastPathComponent.lowercased()
        var cleaned = ""
        for scalar in base.unicodeScalars {
            if CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.").contains(scalar) {
                cleaned.unicodeScalars.append(scalar)
            } else if !cleaned.hasSuffix("-") {
                cleaned += "-"
            }
        }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        let stem = ProjectList.isValidSandboxName(cleaned) ? cleaned
            : cleaned.isEmpty ? "project" : "project-" + cleaned
        var candidate = stem
        var counter = 2
        while taken.contains(candidate) {
            candidate = "\(stem)-\(counter)"
            counter += 1
        }
        return candidate
    }

    /// A draft for `folder`: the app's defaults, and what the folder's `sbxenv.yaml` names where
    /// it can (its sandbox name when that is free, the `paddock.yaml` agent whose sbx agent it
    /// names). A file that does not read comes back as a problem to show; its full check and the
    /// operator's confirmation come before the sandbox is created.
    public static func draft(folder: String, app: AppConfig, taken: Set<String>) -> (draft: ProjectDraft, problem: SbxEnvFileError?) {
        var file: SbxEnvFile?
        var problem: SbxEnvFileError?
        if let data = FileManager.default.contents(atPath: folder + "/" + SbxEnvFile.fileName) {
            do {
                file = try SbxEnvFile.load(from: data)
            } catch {
                problem = error
            }
        }
        let fileName = file?.name.flatMap { ProjectList.isValidSandboxName($0) && !taken.contains($0) ? $0 : nil }
        let fileAgent = file.flatMap { file in app.agents.keys.sorted().first { app.agents[$0]?.sbxAgent == file.agent } }
        var draft = ProjectDraft(
            folder: folder,
            name: fileName ?? suggestedName(for: folder, taken: taken),
            agent: fileAgent ?? app.defaults.agent,
            provider: app.defaults.provider
        )
        draft.agentChanged(app: app)
        return (draft, problem)
    }

    /// Checks a draft and turns it into a project. `sandboxes` are the names sbx already uses.
    /// An `sbxenv.yaml` is not confirmed here: it is checked and confirmed in its own sheet before
    /// the sandbox is created.
    public static func make(
        _ draft: ProjectDraft,
        app: AppConfig,
        existing: ProjectList,
        sandboxes: Set<String>,
        folderPolicy: FolderPolicy
    ) throws(NewProjectError) -> Project {
        let folder = FolderPolicy.canonical(draft.folder)
        do {
            try folderPolicy.check(folder)
        } catch {
            throw .folder(error)
        }
        if let owner = existing.projects.first(where: { $0.folder == folder }) {
            throw .folderAlreadyAProject(name: owner.name)
        }
        guard ProjectList.isValidSandboxName(draft.name) else {
            throw .invalidName(draft.name)
        }
        guard existing.project(named: draft.name) == nil else { throw .nameTaken(draft.name) }
        guard !sandboxes.contains(draft.name) else { throw .sandboxExists(draft.name) }
        guard app.agents[draft.agent] != nil else { throw .unknownSection(kind: "agent", name: draft.agent) }
        guard let provider = app.provider(named: draft.provider) else { throw .unknownSection(kind: "provider", name: draft.provider) }

        if draft.cloneMode && !supportsClone(folder) { throw .cloneNeedsGit }

        var gatewayPort: Int?
        if case .local = provider {
            guard let port = existing.nextGatewayPort(in: app.models.gatewayPorts) else { throw .gatewayPortsExhausted }
            gatewayPort = port
        }

        var project = Project(name: draft.name, folder: folder, agent: draft.agent, provider: draft.provider,
                              cloneMode: draft.cloneMode, gatewayPort: gatewayPort, kits: draft.kits.sorted(),
                              keepsClaudeSessions: draft.keepsClaudeSessions && app.agents[draft.agent] == .claudeCode)
        // Each extra folder is checked like the project folder, and against the ones before it.
        for extra in draft.extraFolders {
            do throws(ExtraFolderProblem) {
                let checked = try ExtraFolders.check(extra.path, for: project, policy: folderPolicy)
                project.extraFolders.append(Project.ExtraFolder(
                    path: checked, readOnly: ExtraFolders.readOnly(extra.readOnly, path: checked, policy: folderPolicy)))
            } catch {
                throw .extraFolder(extra.path, error)
            }
        }
        do {
            if let agent = app.agents[draft.agent] {
                _ = try KitSelection.ordered(draft.kits, agent: agent, app: app, projectFolders: existing.projects.map(\.folder) + [folder])
            }
        } catch {
            throw .kit(error)
        }
        return project
    }
}
