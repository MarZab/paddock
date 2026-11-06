import Foundation

/// One project, stored as `~/.config/paddock/projects/<name>.json`: only what sbx cannot hold
/// (backlog doc ProjectStore). sbx is the truth for everything else: the sandbox's ports and network
/// rules live there and are never copied into this file. Folder and agent are kept because a
/// project exists before its sandbox and is created again from them. A project's `sbxenv.yaml` and
/// its own kit describe its sandbox; they take effect only once the operator confirmed exactly
/// that version (`approvedEnvironment`; backlog doc Project config file).
public struct Project: Sendable, Equatable, Codable, Identifiable {
    /// A published port: `127.0.0.1:hostPort` on the Mac reaches `sandboxPort` in the sandbox.
    public struct PortMapping: Sendable, Equatable, Codable {
        public var sandboxPort: Int
        public var hostPort: Int

        public init(sandboxPort: Int, hostPort: Int) {
            self.sandboxPort = sandboxPort
            self.hostPort = hostPort
        }
    }

    /// A folder mounted besides the project folder, read-only unless the operator chose otherwise
    /// (`ExtraFolders`; backlog doc Security rules, PAD-73.5). Only the operator adds one, here.
    public struct ExtraFolder: Sendable, Equatable, Codable, Hashable {
        /// Canonical, as checked when it was added.
        public var path: String
        public var readOnly: Bool

        public init(path: String, readOnly: Bool = true) {
            self.path = path
            self.readOnly = readOnly
        }

        private enum CodingKeys: String, CodingKey { case path, readOnly }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = try c.decode(String.self, forKey: .path)
            // Read-only unless the file says otherwise.
            readOnly = try c.decodeIfPresent(Bool.self, forKey: .readOnly) ?? true
        }
    }

    public let id: UUID
    /// The sbx sandbox name; also the file name.
    public var name: String
    public var folder: String
    /// An agent entry in `paddock.yaml`, or, for a sandbox Paddock did not create, the agent or
    /// kit name sbx reports (such a project can be managed but not recreated).
    public var agent: String
    public var provider: String
    public var cloneMode: Bool
    /// The project's gateway port from `models.gatewayPorts`, assigned when the project is created
    /// with a local model. The sandbox is created with it, so it never changes afterwards.
    public var gatewayPort: Int?
    /// `ProjectEnvironment.fingerprint` of the project's `sbxenv.yaml` and own kits when the
    /// operator last confirmed them; a create needs it to match the files as they are.
    public var approvedEnvironment: String?
    /// Hosts a project kit allows that the operator declined when confirming: each gets a sandbox
    /// deny right after create (a deny beats the kit's allow; backlog doc M0 findings).
    public var declinedHosts: [String]
    /// The fingerprint the sandbox was created from; a different confirmed one is a recreate item.
    /// sbx does not report it. Nil for a sandbox created without an `sbxenv.yaml`.
    public var sandboxEnvironment: String?
    /// The same version piece by piece (`EnvironmentRecord`), so the recreate item can say what
    /// changed; nil for a sandbox created before Paddock kept it (PAD-103).
    public var sandboxEnvironmentRecord: EnvironmentRecord?
    /// The `[kits]` sections the operator chose (backlog doc Kits); nil in files from before kits,
    /// which get what Paddock always added (`KitSelection.legacy`).
    public var kits: [String]?
    /// The kits the sandbox was created with (`ResolvedKit.recorded`: the `--kit` values, with a
    /// hash of Paddock's own kits' specs). sbx does not report them, so this is how a changed
    /// choice, or a newer version of Paddock's kit, shows as a difference; nil when unknown.
    public var sandboxKits: [String]?
    /// Suggestions the operator chose to ignore for this project (their ids, such as
    /// `SyncItem.serviceDeniesID`); they no longer show.
    public var ignoredSuggestions: [String]
    /// The colors of the project's terminals in Paddock (`TerminalTheme` id), so its sessions look
    /// unlike other projects'; nil for the terminal's own. The operator's choice, never from the folder.
    public var terminalTheme: String?
    /// Folders mounted besides the project folder, in the order added (`ExtraFolders`).
    public var extraFolders: [ExtraFolder]

    public init(id: UUID = UUID(), name: String, folder: String, agent: String = "claude", provider: String = "agent-default",
                cloneMode: Bool = false, gatewayPort: Int? = nil, approvedEnvironment: String? = nil,
                declinedHosts: [String] = [], sandboxEnvironment: String? = nil, kits: [String]? = nil, sandboxKits: [String]? = nil, ignoredSuggestions: [String] = [],
                terminalTheme: String? = nil, extraFolders: [ExtraFolder] = []) {
        self.id = id
        self.name = name
        self.folder = folder
        self.agent = agent
        self.provider = provider
        self.cloneMode = cloneMode
        self.gatewayPort = gatewayPort
        self.approvedEnvironment = approvedEnvironment
        self.declinedHosts = declinedHosts
        self.sandboxEnvironment = sandboxEnvironment
        self.kits = kits
        self.sandboxKits = sandboxKits
        self.ignoredSuggestions = ignoredSuggestions
        self.terminalTheme = terminalTheme
        self.extraFolders = extraFolders
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, folder, agent, provider, cloneMode, gatewayPort, approvedEnvironment, declinedHosts, sandboxEnvironment
        case sandboxEnvironmentRecord
        case kits, sandboxKits, ignoredSuggestions
        case terminalTheme, extraFolders
    }

    /// Files are hand-editable, so the optional parts may be left out. Keys from older versions
    /// (`ports`, `network`, `policy`, and `approvedConfigHash` and `imageTag` from before
    /// `sbxenv.yaml`) are ignored: ports and rules live in sbx, and an `sbxenv.yaml` needs a new approval.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        folder = try c.decode(String.self, forKey: .folder)
        agent = try c.decode(String.self, forKey: .agent)
        provider = try c.decode(String.self, forKey: .provider)
        cloneMode = try c.decodeIfPresent(Bool.self, forKey: .cloneMode) ?? false
        gatewayPort = try c.decodeIfPresent(Int.self, forKey: .gatewayPort)
        approvedEnvironment = try c.decodeIfPresent(String.self, forKey: .approvedEnvironment)
        declinedHosts = try c.decodeIfPresent([String].self, forKey: .declinedHosts) ?? []
        sandboxEnvironment = try c.decodeIfPresent(String.self, forKey: .sandboxEnvironment)
        sandboxEnvironmentRecord = try c.decodeIfPresent(EnvironmentRecord.self, forKey: .sandboxEnvironmentRecord)
        kits = try c.decodeIfPresent([String].self, forKey: .kits)
        sandboxKits = try c.decodeIfPresent([String].self, forKey: .sandboxKits)
        ignoredSuggestions = try c.decodeIfPresent([String].self, forKey: .ignoredSuggestions) ?? []
        terminalTheme = try c.decodeIfPresent(String.self, forKey: .terminalTheme)
        extraFolders = try c.decodeIfPresent([ExtraFolder].self, forKey: .extraFolders) ?? []
    }
}

extension Project {
    /// Whether the project's provider routes through its ModelGateway port.
    public func usesGateway(_ app: AppConfig) -> Bool {
        if case .local? = app.provider(named: provider) { return gatewayPort != nil }
        return false
    }

    /// The kits the project asks for: its own choice, or for files from before kits what Paddock
    /// always added. Empty for a sandbox Paddock did not create (no agent section).
    /// With what they need added: a kit that gained a need (status and browser need node since
    /// PAD-73.2) still works for a project that chose it before.
    public func chosenKits(_ app: AppConfig) -> [String] {
        let chosen = app.agents[agent].map { kits ?? KitSelection.legacy(agent: $0, app: app) } ?? kits ?? []
        let kept = chosen.filter { !KitSelection.removed.contains($0) }
        let added = KitSelection.withNeeds(kept, app: app).subtracting(kept).sorted()
        return kept + added
    }

    /// The `--kit` values the project's sandbox gets (`KitSelection.resolve`).
    public func resolvedKits(_ app: AppConfig, paths: PaddockPaths, projectFolders: [String]) throws(KitError) -> [ResolvedKit] {
        guard let agent = app.agents[agent] else { return [] }
        return try KitSelection.resolve(chosenKits(app), agent: agent, usesGateway: usesGateway(app), app: app,
                                        paths: paths, projectFolders: projectFolders)
    }
}

public enum ProjectStoreError: Error, Equatable, CustomStringConvertible {
    case malformed(file: String, message: String)
    case unsupportedVersion(file: String, version: Int?)
    case nameMismatch(file: String, name: String)
    case duplicateName(String)
    case invalidName(String)
    case duplicateGatewayPort(Int)
    case duplicateFolder(String)

    public var description: String {
        switch self {
        case .malformed(let file, let message): "\(file) is not valid: \(message)"
        case .unsupportedVersion(let file, let v): "\(file): version \(v.map(String.init) ?? "missing") is not supported"
        case .nameMismatch(let file, let name): "\(file) names the project \(name); the file must be called \(name).json"
        case .duplicateName(let name): "two projects are named \(name)"
        case .invalidName(let name): "\(name) is not a valid sandbox name"
        case .duplicateGatewayPort(let port): "two projects use gateway port \(port)"
        case .duplicateFolder(let folder): "two projects use the folder \(folder)"
        }
    }
}

/// The loaded projects. Every rule that spans projects lives here.
public struct ProjectList: Sendable, Equatable {
    public static let currentVersion = 1
    public private(set) var projects: [Project] = []

    public init() {}

    /// Inserts each project, so the same rules apply as for one added later.
    public init(validating projects: [Project]) throws(ProjectStoreError) {
        for project in projects {
            try insert(project)
        }
    }

    /// Adds a project if it breaks no rule: a valid, unique name, and no folder or gateway port
    /// shared with another project (a shared port would let one sandbox use another project's model).
    public mutating func insert(_ project: Project) throws(ProjectStoreError) {
        guard Self.isValidSandboxName(project.name) else { throw .invalidName(project.name) }
        guard !projects.contains(where: { $0.name == project.name }) else { throw .duplicateName(project.name) }
        guard !projects.contains(where: { $0.folder == project.folder }) else { throw .duplicateFolder(project.folder) }
        if let port = project.gatewayPort, projects.contains(where: { $0.gatewayPort == port }) {
            throw .duplicateGatewayPort(port)
        }
        projects.append(project)
        projects.sort { $0.name < $1.name }
    }

    /// Replaces the project of the same name, checked against the others.
    public mutating func update(_ project: Project) throws(ProjectStoreError) {
        var others = self
        others.remove(named: project.name)
        try others.insert(project)
        self = others
    }

    public mutating func remove(named name: String) {
        projects.removeAll { $0.name == name }
    }

    public func project(named name: String) -> Project? {
        projects.first { $0.name == name }
    }

    /// The lowest port in `range` no project uses yet, or nil when the range is full.
    public func nextGatewayPort(in range: ClosedRange<Int>) -> Int? {
        let used = Set(projects.compactMap(\.gatewayPort))
        return range.first { !used.contains($0) }
    }

    /// sbx's rule (`sbx create --help`): at least two characters, starting with a letter or number,
    /// only letters, numbers, hyphens, and periods; `default` is reserved.
    public static func isValidSandboxName(_ name: String) -> Bool {
        guard name.count >= 2, name != "default" else { return false }
        guard let first = name.unicodeScalars.first, CharacterSet.alphanumerics.contains(first) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

/// `~/.config/paddock/projects/`, one hand-editable `<name>.json` per project. A bad file is
/// reported and skipped, so one typo never hides the other projects.
public struct ProjectDirectory: Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public struct Loaded: Sendable, Equatable {
        public var projects: ProjectList
        public var problems: [ProjectStoreError]
    }

    public func load() -> Loaded {
        var list = ProjectList()
        var problems: [ProjectStoreError] = []
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        for file in names.sorted() where file.hasSuffix(".json") {
            let data = FileManager.default.contents(atPath: path + "/" + file) ?? Data()
            do throws(ProjectStoreError) {
                try list.insert(try Self.decode(file: file, data: data))
            } catch {
                problems.append(error)
            }
        }
        return Loaded(projects: list, problems: problems)
    }

    static func decode(file: String, data: Data) throws(ProjectStoreError) -> Project {
        let version: Int?
        do {
            version = try JSONDecoder().decode(VersionField.self, from: data).version
        } catch {
            throw .malformed(file: file, message: String(describing: error))
        }
        // Checked before the rest, so a newer file says so instead of looking broken.
        guard version == ProjectList.currentVersion else { throw .unsupportedVersion(file: file, version: version) }
        let project: Project
        do {
            project = try JSONDecoder().decode(Project.self, from: data)
        } catch {
            throw .malformed(file: file, message: String(describing: error))
        }
        guard file == project.name + ".json" else { throw .nameMismatch(file: file, name: project.name) }
        return project
    }

    public static func encode(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Versioned(project: project))
    }

    /// Writes `<name>.json` atomically, owner-only.
    /// The project file for a project name.
    public func file(named name: String) -> String {
        path + "/" + name + ".json"
    }

    public func save(_ project: Project) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = file(named: project.name)
        try Self.encode(project).write(to: URL(fileURLWithPath: file), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file)
    }

    public func delete(named name: String) throws {
        let file = file(named: name)
        if FileManager.default.fileExists(atPath: file) {
            try FileManager.default.removeItem(atPath: file)
        }
    }

    private struct VersionField: Decodable {
        let version: Int?
    }

    private struct Versioned: Encodable {
        let project: Project

        func encode(to encoder: Encoder) throws {
            try project.encode(to: encoder)
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(ProjectList.currentVersion, forKey: .version)
        }

        enum Key: String, CodingKey { case version }
    }
}
