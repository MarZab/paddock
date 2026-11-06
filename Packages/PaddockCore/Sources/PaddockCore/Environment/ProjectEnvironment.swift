import Crypto
import Foundation

/// A project's `sbxenv.yaml` and its own local kits, checked by Paddock's rules (backlog doc
/// Project config file, Security rules). The agent can write all of it, so nothing here applies
/// until the operator confirmed exactly this version: the confirmation sheet shows `summary`,
/// every refusal stops a create, and `fingerprint` is what the approval covers.
///
/// Checks collect every problem instead of stopping at the first, so the sheet lists them all.
public struct ProjectEnvironment: Sendable, Equatable {
    /// What a check needs besides the folder.
    public struct Context: Sendable {
        public var folderPolicy: FolderPolicy
        public var app: AppConfig
        /// Other projects' folders (canonical) by project name, to mark an extra folder that is one.
        public var otherProjects: [String: String]

        public init(folderPolicy: FolderPolicy, app: AppConfig, otherProjects: [String: String] = [:]) {
            self.folderPolicy = folderPolicy
            self.app = app
            self.otherProjects = otherProjects
        }
    }

    public enum Problem: Sendable, Equatable, CustomStringConvertible {
        case file(SbxEnvFileError)
        /// A key sbx knows that Paddock does not accept in a project file, and why.
        case refusedKey(String, reason: String)
        case refusedOption(String)
        case refusedEnv(String)
        case workspaceNotProject(String)
        case extraFolder(String, FolderPolicyViolation)
        case extraFolderMissing(String)
        case extraFolderIsProject(String)
        case extraFolderTarget(String)
        case port(Int)
        case portHostIP(String)
        /// A kit that is neither sbx's published catalog nor the project's own local kit.
        case customKit(String)
        case localKitPath(String)
        case kit(String, String)

        public var description: String {
            switch self {
            case .file(let error): error.description
            case .refusedKey(let key, let reason): "\(key) is not accepted in a project file: \(reason)"
            case .refusedOption(let key): "sandboxOptions.\(key) is not accepted in a project file (cpus, memory, and pullPolicy are)"
            case .refusedEnv(let name): "env \(name) is Paddock's own (the model gateway and its kits set it)"
            case .workspaceNotProject(let path): "workspace \(path) is not the project folder"
            case .extraFolder(let path, let violation): "extra folder \(path): \(violation)"
            case .extraFolderMissing(let path): "extra folder \(path) does not exist"
            case .extraFolderIsProject(let path): "extra folder \(path) is the project folder itself"
            case .extraFolderTarget(let target): "extra folder target \(target) must be an absolute path under /workspace, /mnt, /srv, /data, or the Mac home folder"
            case .port(let port): "port \(port) is not allowed (Paddock's own services, the Docker API, or out of range)"
            case .portHostIP(let address): "published ports bind 127.0.0.1 only, not \(address)"
            case .customKit(let source): "kit \(source) is not sbx's; a custom kit goes in paddock.yaml, which only the operator edits"
            case .localKitPath(let source): "kit \(source) must be a folder inside the project, named without .. or a link"
            case .kit(let source, let message): "kit \(source): \(message)"
            }
        }
    }

    /// One kit as the project file lists it.
    public struct Kit: Sendable, Equatable {
        public enum Origin: Sendable, Equatable {
            /// sbx's published kits (`docker.io/sbx/…`, `docker.io/docker/sbx-kit-…`).
            case catalog
            /// The project's own kit, at this canonical folder inside the project.
            case local(String)
            case refused
        }

        public var source: String
        public var origin: Origin
        /// Read for a local kit only; sbx reads a catalog kit's at create.
        public var descriptor: SbxKitDescriptor?
    }

    /// A host a local kit asks for, in the phase it asks.
    public struct HostRequest: Sendable, Equatable {
        public var kit: String
        public var host: String
        public var methods: [String]
        public var paths: [String]
        public var deny: Bool
    }

    public struct ExtraFolder: Sendable, Equatable {
        /// Canonical: symlinks followed, relative to the project folder.
        public var path: String
        public var readOnly: Bool
        public var target: String?
        /// The Paddock project whose folder this is, if any.
        public var otherProject: String?
    }

    public static let fileName = SbxEnvFile.fileName

    /// The project folder, canonical.
    public var folder: String
    /// nil when the file did not parse (`problems` says why).
    public var file: SbxEnvFile?
    public var kits: [Kit] = []
    public var extraFolders: [ExtraFolder] = []
    public var runtimeHosts: [HostRequest] = []
    /// Open only while the kits install, before the agent starts.
    public var installHosts: [HostRequest] = []
    public var problems: [Problem] = []
    /// SHA-256 over the file and every file of each local kit; the operator's approval covers it.
    public var fingerprint: String
    /// The same, piece by piece, so a later version can say what changed (PAD-103).
    public var record = EnvironmentRecord()

    public var isAcceptable: Bool { file != nil && problems.isEmpty }
}

extension ProjectEnvironment {
    /// Paddock sets these through its overlay (the gateway and its kits); a project may not.
    public static let paddockEnvPrefixes = ["PADDOCK_", "SBX_CRED_", "ANTHROPIC_", "OPENAI_", "OPENCODE_"]
    public static let allowedOptions: Set<String> = ["cpus", "memory", "pullPolicy"]
    /// Capabilities a project's own kit may ask for. Anything else (credentials, the SSH agent,
    /// host mounts, the kit registry, and every type not listed) is refused. `host-port@1` is not
    /// listed: sbx 0.51 does not support it (PAD-73.1), so this Mac's ports stay sbx rules
    /// Paddock manages (backlog doc UI, Ports).
    public static let allowedCapabilities: Set<String> = [
        "network-policy@1", "network-policy@2", "lifecycle@1", "agent-context@1",
        "agent-skill@1", "agent-skills@1", "port@1", "volume@1", "resources@1",
        "long-running@1", "dockerd@1", "privileged@1", "git-identity@1",
    ]
    static let refusedKeys: [String: String] = [
        "lifecycle": "it runs commands on this Mac",
        "secrets": "Paddock manages no secrets; sbx secret is the operator's",
        "bindings": "credential approvals are the operator's",
        "registries": "registry credentials are the operator's",
        "mounts": "only the project folder and confirmed extra folders are mounted",
        "mcp": "MCP servers are not checked yet",
        "args": "environment arguments are not checked yet",
        "workspace": "workspace must be a path",
    ]

    /// Reads `<folder>/sbxenv.yaml` and checks it; nil when the folder has none.
    public static func read(folder: String, context: Context) -> ProjectEnvironment? {
        let root = FolderPolicy.canonical(folder)
        guard let data = FileManager.default.contents(atPath: root + "/" + fileName) else { return nil }
        return check(data: data, folder: root, context: context)
    }

    /// Checks the file's `data` for the project at `folder` (canonical).
    public static func check(data: Data, folder: String, context: Context) -> ProjectEnvironment {
        var result = ProjectEnvironment(folder: folder, file: nil, fingerprint: "")
        let file: SbxEnvFile
        do {
            file = try SbxEnvFile.load(from: data)
        } catch {
            result.problems = [.file(error)]
            result.fingerprint = Fingerprint.of([("", data)])
            result.record = EnvironmentRecord.of(data: data, kits: [])
            return result
        }
        result.file = file
        result.checkKeys(file)
        result.checkWorkspace(file)
        result.checkExtraFolders(file, context: context)
        result.checkPorts(file, app: context.app)
        result.checkKits(file, app: context.app)
        var parts: [(String, Data)] = [("", data)]
        var kitFiles: [(source: String, files: [(String, Data)])] = []
        for kit in result.kits {
            if case .local(let path) = kit.origin {
                let files = Fingerprint.files(in: path, named: kit.source)
                parts += files
                kitFiles.append((kit.source, files.map { (String($0.0.dropFirst(kit.source.count + 1)), $0.1) }))
            }
        }
        result.fingerprint = Fingerprint.of(parts)
        result.record = EnvironmentRecord.of(data: data, kits: kitFiles)
        return result
    }

    private mutating func checkKeys(_ file: SbxEnvFile) {
        for key in file.otherKeys.sorted() {
            problems.append(.refusedKey(key, reason: Self.refusedKeys[key] ?? "not checked yet"))
        }
        for key in file.sandboxOptions.keys.sorted() where !Self.allowedOptions.contains(key) {
            problems.append(.refusedOption(key))
        }
        for name in file.env.keys.sorted() where Self.paddockEnvPrefixes.contains(where: name.hasPrefix) {
            problems.append(.refusedEnv(name))
        }
    }

    private mutating func checkWorkspace(_ file: SbxEnvFile) {
        guard let workspace = file.workspace else { return }
        if resolve(workspace) != folder { problems.append(.workspaceNotProject(workspace)) }
    }

    private mutating func checkExtraFolders(_ file: SbxEnvFile, context: Context) {
        for entry in file.additionalWorkspaces {
            let path = resolve(entry.path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                problems.append(.extraFolderMissing(entry.path))
                continue
            }
            if path == folder {
                problems.append(.extraFolderIsProject(entry.path))
                continue
            }
            do throws(FolderPolicyViolation) {
                try context.folderPolicy.check(path)
            } catch {
                problems.append(.extraFolder(entry.path, error))
            }
            if let target = entry.target {
                let clean = (target as NSString).standardizingPath
                if !Self.isAllowedTarget(clean, original: target, home: context.folderPolicy.home) {
                    problems.append(.extraFolderTarget(target))
                }
            }
            extraFolders.append(ExtraFolder(path: path, readOnly: entry.readOnly, target: entry.target,
                                            otherProject: context.otherProjects.first { $0.value == path }?.key))
        }
    }

    private mutating func checkPorts(_ file: SbxEnvFile, app: AppConfig) {
        for mapping in file.ports {
            for port in [mapping.sandbox] + (mapping.host.map { [$0] } ?? []) where !Self.isAllowedPort(port, app: app) {
                problems.append(.port(port))
            }
            if let address = mapping.hostIP, address != Ports.hostIP { problems.append(.portHostIP(address)) }
        }
    }

    /// Where an extra folder may appear in the sandbox: under `/workspace`, `/mnt`, `/srv`, `/data`,
    /// or at a path under the operator's home (sbx mounts a folder at its Mac path by default). An
    /// allowlist, so nothing can cover the agent's settings or Paddock's kit scripts (PAD-86).
    static func isAllowedTarget(_ clean: String, original: String, home: String) -> Bool {
        guard original.hasPrefix("/"), !original.contains("\0"),
              !original.split(separator: "/").contains("..") else { return false }
        for root in Self.targetRoots + [home] where clean.hasPrefix(root + "/") { return true }
        return false
    }

    static let targetRoots = ["/workspace", "/mnt", "/srv", "/data"]

    static func isAllowedPort(_ port: Int, app: AppConfig) -> Bool {
        (1...65535).contains(port) && !AppConfig.reservedPorts.contains(port) && !app.models.gatewayPorts.contains(port)
    }

    private mutating func checkKits(_ file: SbxEnvFile, app: AppConfig) {
        for entry in file.kits {
            let source = entry.source
            if Self.isCatalog(source) {
                kits.append(Kit(source: source, origin: .catalog))
            } else if Self.looksLocal(source) {
                guard let path = localKitFolder(source) else {
                    problems.append(.localKitPath(source))
                    kits.append(Kit(source: source, origin: .refused))
                    continue
                }
                var kit = Kit(source: source, origin: .local(path))
                kit.descriptor = checkLocalKit(source, at: path, app: app)
                kits.append(kit)
            } else {
                problems.append(.customKit(source))
                kits.append(Kit(source: source, origin: .refused))
            }
        }
    }

    /// sbx's own published kits: `docker.io/sbx/NAME` (the contrib kits) and
    /// `docker.io/docker/sbx-kit-NAME` (Docker's agent workloads), with or without `docker.io/`.
    public static func isCatalog(_ source: String) -> Bool {
        let bare = source.hasPrefix("docker.io/") ? String(source.dropFirst("docker.io/".count)) : source
        guard let first = bare.unicodeScalars.first, CharacterSet.lowercaseLetters.contains(first) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-._/:@")
        guard bare.unicodeScalars.allSatisfy(allowed.contains), !bare.contains("..") else { return false }
        return (bare.hasPrefix("sbx/") && bare.dropFirst(4).split(separator: "/").count == 1)
            || (bare.hasPrefix("docker/sbx-kit-") && !bare.dropFirst("docker/".count).contains("/"))
    }

    static func looksLocal(_ source: String) -> Bool {
        source == "." || source.hasPrefix("./") || source.hasPrefix("../") || source.hasPrefix("/") || source.hasPrefix("~")
    }

    /// A local kit's folder, canonical, when it is inside the project and named without `..`, an
    /// absolute path, or a symlink on the way.
    func localKitFolder(_ source: String) -> String? {
        guard source.hasPrefix("./") else { return nil }
        let parts = source.split(separator: "/").dropFirst()
        guard !parts.isEmpty, !parts.contains(".."), !parts.contains(".") else { return nil }
        var current = folder
        for part in parts {
            current += "/\(part)"
            let attributes = try? FileManager.default.attributesOfItem(atPath: current)
            guard attributes?[.type] as? FileAttributeType == .typeDirectory else { return nil }
        }
        return FolderPolicy.isAncestor(folder, of: current) ? current : nil
    }

    /// Reads the kit's descriptor (`<folder>/<name>.yaml`) and checks what it asks for.
    private mutating func checkLocalKit(_ source: String, at path: String, app: AppConfig) -> SbxKitDescriptor? {
        let name = (path as NSString).lastPathComponent
        if let link = Fingerprint.firstSymlink(in: path) {
            problems.append(.kit(source, "\(link) is a link; a kit's files must be its own"))
            return nil
        }
        guard let data = FileManager.default.contents(atPath: "\(path)/\(name).yaml") else {
            problems.append(.kit(source, "\(name).yaml is missing"))
            return nil
        }
        let descriptor: SbxKitDescriptor
        do {
            descriptor = try SbxKitDescriptor.load(from: data)
        } catch {
            problems.append(.kit(source, error.description))
            return nil
        }
        for name in descriptor.unversionedProvides {
            problems.append(.kit(source, "provides \(name) without a version (add @1.0.0, or a top-level version:)"))
        }
        if descriptor.kind != .mixin {
            problems.append(.kit(source, "a project's own kit must be a mixin, not a \(descriptor.kind.rawValue)"))
        }
        for capability in descriptor.capabilities {
            let short = SbxKitDescriptor.shortName(capability.type)
            if short == "agent-context@2" {
                // sbx's own claude and playwright kits use @1 and sbx refuses to compose the two
                // (backlog doc Kits); sbx fails the create late, so refuse it here.
                problems.append(.kit(source, "use agent-context@1: sbx's kits use @1 and @1 and @2 cannot compose"))
            } else if !capability.type.hasPrefix(SbxKitDescriptor.capabilityPrefix) || !Self.allowedCapabilities.contains(short) {
                problems.append(.kit(source, "\(short) is not accepted in a project's kit"))
            }
        }
        for phase in ["install", "runtime"] {
            let rules: SbxKitDescriptor.NetworkRules
            do {
                rules = try descriptor.network(phase: phase)
            } catch {
                problems.append(.kit(source, error.description))
                continue
            }
            let requests = checkHosts(rules.allow, deny: false, kit: source) + checkHosts(rules.deny, deny: true, kit: source)
            if phase == "install" { installHosts += requests } else { runtimeHosts += requests }
        }
        return descriptor
    }

    private mutating func checkHosts(_ entries: [SbxKitDescriptor.NetworkEntry], deny: Bool, kit: String) -> [HostRequest] {
        var requests: [HostRequest] = []
        for entry in entries {
            for host in entry.hosts {
                // A deny may name anything; an allow is checked like a host rule (never this Mac,
                // never every host; a bare * is every host in a kit too).
                if !deny {
                    if host.trimmingCharacters(in: .whitespaces) == "*" {
                        problems.append(.kit(kit, "* would match every host"))
                        continue
                    }
                    do throws(HostRules.Problem) {
                        _ = try HostRules.validated(host)
                    } catch {
                        problems.append(.kit(kit, error.description))
                        continue
                    }
                }
                requests.append(HostRequest(kit: kit, host: host, methods: entry.methods, paths: entry.paths, deny: deny))
            }
        }
        return requests
    }

    /// A path from the file, relative to the project folder, canonical.
    private func resolve(_ path: String) -> String {
        let expanded = path.hasPrefix("/") ? path : folder + "/" + path
        return FolderPolicy.canonical(expanded)
    }
}

/// The approval hash: each part length-prefixed with its name, so moving bytes between files or
/// renaming one changes it.
enum Fingerprint {
    static func of(_ parts: [(String, Data)]) -> String {
        var hasher = SHA256()
        for (name, data) in parts {
            for chunk in [Data(name.utf8), data] {
                var length = UInt64(chunk.count).bigEndian
                hasher.update(data: Data(bytes: &length, count: 8))
                hasher.update(data: chunk)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Every regular file under `folder`, sorted, named `<label>/<relative path>`.
    static func files(in folder: String, named label: String) -> [(String, Data)] {
        guard let enumerator = FileManager.default.enumerator(atPath: folder) else { return [] }
        var relatives: [String] = []
        while let relative = enumerator.nextObject() as? String { relatives.append(relative) }
        return relatives.sorted().compactMap { relative in
            let path = folder + "/" + relative
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue,
                  let data = FileManager.default.contents(atPath: path) else { return nil }
            return ("\(label)/\(relative)", data)
        }
    }

    /// The first symlink under `folder`, relative, if any.
    static func firstSymlink(in folder: String) -> String? {
        guard let enumerator = FileManager.default.enumerator(atPath: folder) else { return nil }
        while let relative = enumerator.nextObject() as? String {
            let attributes = try? FileManager.default.attributesOfItem(atPath: folder + "/" + relative)
            if attributes?[.type] as? FileAttributeType == .typeSymbolicLink { return relative }
        }
        return nil
    }
}
