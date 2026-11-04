import Foundation

/// Paddock's part of a project's sandbox, as an sbx environment file of its own, kept in Paddock's
/// config dir where agents cannot reach it (backlog doc Project config file, Paddock's overlay).
/// Paddock runs `sbx env create <project>/sbxenv.yaml <overlay>`: sbx merges the two, maps by key
/// and lists by concatenation, with the later file's scalars winning, so the overlay adds
/// Paddock's kits and its environment and sets the workspace to the project folder.
///
/// The project file is never written here: a terminal's `sbx env run` keeps working without
/// Paddock, and Paddock's values (the gateway's port and model) never land where the agent can
/// change them.
public struct PaddockOverlay: Sendable, Equatable {
    /// Same agent as the project file (sbx requires one in each file).
    public var agent: String
    /// The project folder, absolute: the overlay sits elsewhere, and relative paths resolve
    /// from the file that names them.
    public var workspace: String
    /// Paddock's kits (`--kit` values), after the project's.
    public var kits: [String]
    /// The gateway's variables and `PADDOCK_*`; a project file may not set these.
    public var env: [String: String]
    /// The folders the operator added in Paddock (`Project.extraFolders`), checked at this create;
    /// sbx adds them to the project file's own `additionalWorkspaces`.
    public var extraFolders: [Project.ExtraFolder]

    public init(agent: String, workspace: String, kits: [String] = [], env: [String: String] = [:],
                extraFolders: [Project.ExtraFolder] = []) {
        self.agent = agent
        self.workspace = workspace
        self.kits = kits
        self.env = env
        self.extraFolders = extraFolders
    }

    /// From `AgentLaunchPlanner.environment`'s pairs.
    public init(agent: String, workspace: String, kits: [String], env: [(name: String, value: String)],
                extraFolders: [Project.ExtraFolder]) {
        self.init(agent: agent, workspace: workspace, kits: kits,
                  env: Dictionary(env.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last }), extraFolders: extraFolders)
    }

    /// Writes the file, owner-only, in Paddock's config dir.
    public func write(to path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(yaml.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    /// `sbx env create <project file> <overlay> --name N --skip-host-commands --force [--clone]`.
    /// `--skip-host-commands`: nothing from a project file runs on the Mac (Paddock also refuses a
    /// file with `lifecycle`). `--force`: sbx's own approval of the workspaces, which the operator
    /// gave in Paddock's confirmation. `--name`: the project's sandbox, whatever the file says.
    public static func createArguments(environmentFile: String, overlay: String, name: String, clone: Bool) -> [String] {
        ["env", "create", environmentFile, overlay, "--name", name, "--skip-host-commands", "--force"] + (clone ? ["--clone"] : [])
    }

    /// `<config>/projects/<name>.sbxenv.yaml`, beside the project's own file.
    public static func path(project: String, paths: PaddockPaths) -> String {
        paths.projects + "/\(project).sbxenv.yaml"
    }

    /// The file's text. Every value is a double-quoted YAML string written as JSON writes it, so no
    /// value can change the file's structure.
    public var yaml: String {
        var lines = [
            "# Written by Paddock for its own part of this project's sandbox; edits are replaced.",
            "schemaVersion: \(Self.quoted(SbxEnvFile.schemaVersion))",
            "agent: \(Self.quoted(agent))",
            "workspace: \(Self.quoted(workspace))",
        ]
        if !kits.isEmpty {
            lines.append("kits:")
            lines += kits.map { "  - \(Self.quoted($0))" }
        }
        if !extraFolders.isEmpty {
            lines.append("additionalWorkspaces:")
            lines += extraFolders.map { "  - { path: \(Self.quoted($0.path)), readOnly: \($0.readOnly) }" }
        }
        if !env.isEmpty {
            lines.append("env:")
            lines += env.keys.sorted().map { "  \(Self.quoted($0)): \(Self.quoted(env[$0] ?? ""))" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func quoted(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = (try? encoder.encode(text)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
