import Crypto
import Foundation

/// sbx mixin kits a project's sandbox is created with (`sbx create --kit`), as `[kits.NAME]`
/// entries under `kits:` in `paddock.yaml` (backlog doc Kits). The operator picks them per project in the New
/// Project sheet or later on its Info tab; `recommended` kits and Paddock's own are preselected.
/// A kit runs its install steps inside the sandbox and adds its own network rules there (sbx marks
/// them `provisioned`). These are Paddock's kits for a project; a project's own `sbxenv.yaml` names
/// sbx's catalog kits and its own local kits (`ProjectEnvironment`), never one from here.
public struct Kit: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// One of Paddock's own kits, written to `~/.config/paddock/kits/<name>` before create.
        case builtin(BuiltinKit)
        /// Anything `sbx create --kit` takes: an image reference (`docker.io/sbx/playwright-kit:1.61.1`),
        /// a `git+https://` URL, or an absolute local path.
        case reference(String)
    }

    public var source: Source
    public var summary: String
    /// Preselected for new projects.
    public var recommended: Bool
    /// The agent kinds it is offered for; empty for every agent.
    public var agents: [AppConfig.Agent]
    /// Kits it builds on: selected with it and created before it.
    public var needs: [String]

    public init(source: Source, summary: String = "", recommended: Bool = false, agents: [AppConfig.Agent] = [], needs: [String] = []) {
        self.source = source
        self.summary = summary
        self.recommended = recommended
        self.agents = agents
        self.needs = needs
    }

    public func isOffered(for agent: AppConfig.Agent) -> Bool { agents.isEmpty || agents.contains(agent) }

    /// What the New Project sheet shows under the kit's name.
    public var sourceDescription: String {
        switch source {
        case .builtin: "Paddock"
        case .reference(let reference): reference
        }
    }
}

/// Paddock's own kits that the operator can choose.
public enum BuiltinKit: String, Sendable, Equatable, CaseIterable {
    case node
    case browser
    case status
    case voice
}

/// One kit of a sandbox, in `sbx create` order.
public struct ResolvedKit: Sendable, Equatable {
    /// Its `paddock.yaml` entry.
    public let name: String
    /// The `--kit` value.
    public let argument: String
    public let builtin: BuiltinKit?
    /// What `Project.sandboxKits` records: the `--kit` value, and for Paddock's own kits a hash of
    /// the spec Paddock writes, so a sandbox created from an older version of one shows "recreate".
    public let recorded: String

    init(name: String, argument: String, builtin: BuiltinKit?, spec: String? = nil) {
        self.name = name
        self.argument = argument
        self.builtin = builtin
        recorded = spec.map { argument + "#" + Self.digest($0) } ?? argument
    }

    static func digest(_ spec: String) -> String {
        SHA256.hash(data: Data(spec.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}

public enum KitError: Error, Equatable, CustomStringConvertible {
    case unknownKit(String)
    case notForAgent(kit: String, agent: String)
    case missingNeed(kit: String, needs: String)
    /// A local kit inside a project folder: an agent could rewrite its install steps and network rules.
    case kitInsideProject(kit: String, path: String)

    public var description: String {
        switch self {
        case .unknownKit(let name): "kit \"\(name)\" is not defined in paddock.yaml"
        case .notForAgent(let kit, let agent): "kit \(kit) is not offered for \(agent) projects"
        case .missingNeed(let kit, let needs): "kit \(kit) needs the kit \(needs); select both"
        case .kitInsideProject(let kit, let path): "kit \(kit) is in a project folder (\(path)), which an agent can change"
        }
    }
}

public enum KitSelection {
    /// Paddock's kits that are gone; a project that chose one drops it (its sandbox shows a
    /// recreate item). `setup` went in PAD-73.3: Paddock writes a project's files itself.
    /// `opencode` went in PAD-73.2: sbx 0.51's own opencode kit ships OpenCode 2.
    public static let removed: Set<String> = ["setup", "opencode"]

    /// The kits a project gets when its file names none (files from before kits): what Paddock
    /// always added then, which was only the opencode kit, now gone. Nothing.
    public static func legacy(agent: AppConfig.Agent, app: AppConfig) -> [String] {
        []
    }

    /// The preselection for a new project: recommended kits offered for the agent, with what they need.
    public static func preselected(agent: AppConfig.Agent, app: AppConfig) -> [String] {
        let recommended = app.kits.filter { $0.value.recommended }.map(\.key)
        let offered = Set(recommended).filter { app.kits[$0]?.isOffered(for: agent) ?? false }
        return withNeeds(offered, app: app).sorted()
    }

    /// `names` plus every kit they need, directly or not.
    public static func withNeeds(_ names: some Collection<String>, app: AppConfig) -> Set<String> {
        var result = Set<String>()
        var queue = Array(names)
        while let name = queue.popLast() {
            guard result.insert(name).inserted else { continue }
            queue += app.kits[name]?.needs ?? []
        }
        return result
    }

    /// `names` without the kits that need one of `removed`, directly or not (unselecting a kit
    /// unselects what builds on it).
    public static func removing(_ removed: String, from names: [String], app: AppConfig) -> [String] {
        var gone: Set<String> = [removed]
        var changed = true
        while changed {
            changed = false
            for name in names where !gone.contains(name) && !(app.kits[name]?.needs ?? []).allSatisfy({ !gone.contains($0) }) {
                gone.insert(name)
                changed = true
            }
        }
        return names.filter { !gone.contains($0) }
    }

    /// The `--kit` values for a sandbox, in order (`ordered`). The gateway needs no kit: it is
    /// environment at create (`ClaudeGateway`).
    public static func resolve(_ names: [String], agent: AppConfig.Agent, usesGateway: Bool, app: AppConfig,
                               paths: PaddockPaths, projectFolders: [String]) throws(KitError) -> [ResolvedKit] {
        var resolved: [ResolvedKit] = []
        for name in try ordered(names, agent: agent, app: app, projectFolders: projectFolders) {
            guard let kit = app.kits[name] else { throw .unknownKit(name) }
            switch kit.source {
            case .builtin(let builtin):
                resolved.append(ResolvedKit(name: name, argument: BuiltinKits.directory(builtin, in: paths), builtin: builtin,
                                            spec: BuiltinKits.spec(builtin)))
            case .reference(let reference):
                resolved.append(ResolvedKit(name: name, argument: reference, builtin: nil))
            }
        }
        return resolved
    }

    /// `names` checked and in `sbx create` order: each kit after the kits it needs, otherwise by
    /// name. Every kit must be defined, offered for the agent, and have what it needs selected; a
    /// local kit in any of `projectFolders` is refused.
    public static func ordered(_ names: [String], agent: AppConfig.Agent, app: AppConfig,
                               projectFolders: [String]) throws(KitError) -> [String] {
        var ordered: [String] = []
        var placed = Set<String>()
        let chosen = Set(names)
        // Needs first; a cycle cannot happen (AppConfig.validate refuses one).
        func place(_ name: String) throws(KitError) {
            guard !placed.contains(name) else { return }
            guard let kit = app.kits[name] else { throw .unknownKit(name) }
            guard kit.isOffered(for: agent) else { throw .notForAgent(kit: name, agent: agent.sbxAgent) }
            for need in kit.needs {
                guard chosen.contains(need) else { throw .missingNeed(kit: name, needs: need) }
                try place(need)
            }
            if case .reference(let reference) = kit.source, reference.hasPrefix("/") {
                let path = FolderPolicy.canonical(reference)
                for folder in projectFolders {
                    let root = FolderPolicy.canonical(folder)
                    if path == root || FolderPolicy.isAncestor(root, of: path) { throw .kitInsideProject(kit: name, path: reference) }
                }
            }
            placed.insert(name)
            ordered.append(name)
        }
        for name in chosen.sorted() {
            try place(name)
        }
        return ordered
    }
}

extension AppConfig {
    /// The kits every `paddock.yaml` has unless it sets `enabled: false` on one: Paddock's own,
    /// and sbx's Playwright kit, which the browser kit builds on (backlog doc Kits). Any other kit is
    /// a `[kits.NAME]` section, added by hand or from the kit field in the New Project sheet.
    public static let defaultKits: [String: Kit] = [
        "browser": Kit(source: .builtin(.browser),
                       summary: "A browser the agent drives with playwright-cli, shown live in the project's browser tab",
                       needs: ["playwright", "node"]),
        "status": Kit(source: .builtin(.status),
                      summary: "Shows whether the agent is working, waiting on you, or idle, on its tab and in the sidebar",
                      recommended: true, needs: ["node"]),
        // sbx's agents ship no Node; Paddock's helpers and sbx's Playwright kit need it (PAD-73.2).
        "node": Kit(source: .builtin(.node), summary: "Node.js for Paddock's kits and Playwright (sbx's agents no longer ship it)"),
        "voice": Kit(source: .builtin(.voice),
                     summary: "Talk with the agent: it speaks, asks you things out loud, and helps dictation spell its names",
                     needs: ["status"]),
        // sbx's v3 build 1.61.1, pinned by digest: its tags move.
        "playwright": Kit(source: .reference(Kit.contribReference("playwright") + ":1.61.1@sha256:d60c965e2ee124128e611f9ea95ea36e240c1db8dd3017f890622c5091492287"),
                          summary: "Playwright 1.61 and headless Chromium, for end-to-end tests the agent writes and runs",
                          needs: ["node"]),
        // sbx's v3 build 2026.5.2, pinned by digest: its tags move. Off by default.
        "mise": Kit(source: .reference(Kit.contribReference("mise") + ":2026.5.2@sha256:c5fe07daed708f4a3c56d785439104f94d4dd3423f0b689a8217d5737b1e11f4"),
                    summary: "mise, so the project's mise.toml installs its pinned tools in the sandbox"),
    ]
}

extension Kit {
    /// sbx's kit of that name from `docker/sbx-kits-contrib`: the v3 build, `docker.io/sbx/<name>`.
    /// From sbx 0.51 the built-in agents are v3 kits too, and v2 builds (`<name>-kit`) no longer
    /// combine with them (PAD-73.2). What a kit entry without `source` means. Unpinned: it
    /// follows `latest`.
    public static func contribReference(_ name: String) -> String { "docker.io/sbx/\(name)" }

    /// sbx's kit names: lowercase letters, digits, and inner hyphens.
    public static func isValidName(_ name: String) -> Bool {
        guard let first = name.first, let last = name.last, first != "-", last != "-" else { return false }
        return name.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// What the operator typed in the kit field: a contrib kit's name (`mise`), or anything
    /// `--kit` takes (an image reference, `git+https://`, an absolute path), whose name comes from
    /// its last path part without `-kit`, a tag, or a digest.
    public static func parseInput(_ text: String) throws(KitInputError) -> (name: String, source: String?) {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidName(input) { return (input, nil) }
        if let problem = AppConfig.referenceProblem(input) { throw .invalidReference(problem) }
        // A git source's `#dir=...` or `?ref=...` is not part of its name.
        let path = input.split(separator: "#").first.flatMap { $0.split(separator: "?").first }.map(String.init) ?? input
        var last = path.split(separator: "/").last.map(String.init) ?? path
        if let at = last.firstIndex(of: "@") { last = String(last[..<at]) }
        if let colon = last.firstIndex(of: ":") { last = String(last[..<colon]) }
        if last.hasSuffix(".git") { last = String(last.dropLast(4)) }
        if last.hasSuffix("-kit") { last = String(last.dropLast(4)) }
        let name = last.lowercased()
        guard isValidName(name) else { throw .noName(input) }
        return (name, input)
    }
}

public enum KitInputError: Error, Equatable, CustomStringConvertible {
    case invalidReference(String)
    case noName(String)
    /// `paddock.yaml` has a kit of that name with another source.
    case nameTaken(String)

    public var description: String {
        switch self {
        case .invalidReference(let problem): problem
        case .noName(let input): "Paddock cannot name a kit after \(input); add it to paddock.yaml under kits: by hand"
        case .nameTaken(let name): "paddock.yaml has a kit named \(name) already"
        }
    }
}

/// Paddock's own changes to the operator's config (operator actions in its interface). The file is
/// hand-edited, so a kit is inserted as text and everything else in it stays as it is, comments too.
public enum AppConfigFile {
    public enum Problem: Error, Equatable, CustomStringConvertible {
        /// `kits:` is written in a form Paddock does not insert into (`kits: {}` on one line, say).
        case kitsNotABlock

        public var description: String {
            switch self {
            case .kitsNotABlock: "kits: in paddock.yaml is not a block of kits; add the kit by hand"
            }
        }
    }

    /// Adds a kit for the kit field and returns its name: `NAME:` under `kits:` in `paddock.yaml`,
    /// with `source` unless it is a contrib kit by name. A kit `app` has already is only returned: by its name, or by the same source.
    /// Without a file, the file starts as `template`.
    @discardableResult
    public static func addKit(_ text: String, app: AppConfig, path: String) throws -> String {
        let (name, source) = try Kit.parseInput(text)
        if let existing = app.kits[name] {
            guard source == nil || existing.source == .reference(source ?? "") else { throw KitInputError.nameTaken(name) }
            return name
        }
        let current = FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) }
        let file = try insertingKit(name, source: source, into: current ?? template)
        // Checked like any hand edit before it is written.
        _ = try AppConfig.load(from: Data(file.utf8))
        try write(file, to: path)
        return name
    }

    /// `text` with the kit added at the end of its top-level `kits:` block, or a new `kits:` block
    /// at the end. Lines are only added, never changed.
    static func insertingKit(_ name: String, source: String?, into text: String) throws(Problem) -> String {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        // `name` is a kit name (letters, digits, hyphens) and `source` has no quotes, backslashes,
        // or whitespace (`Kit.parseInput`), so neither needs escaping.
        var entry = ["  # Added from Paddock's kit field."]
        entry.append(source.map { "  \(name):\n    source: \"\($0)\"" } ?? "  \(name): {}")
        let isTopLevel = { (line: String) in
            guard let first = line.first else { return false }
            return first != " " && first != "\t" && first != "#"
        }
        if let kitsLine = lines.firstIndex(where: { $0.hasPrefix("kits:") }) {
            let rest = lines[kitsLine].dropFirst("kits:".count).trimmingCharacters(in: .whitespaces)
            guard rest.isEmpty || rest.hasPrefix("#") else { throw .kitsNotABlock }
            // The block ends before the next top-level key; insert after its last indented line.
            var end = kitsLine
            var index = kitsLine + 1
            while index < lines.count, !isTopLevel(lines[index]) {
                if lines[index].first == " " || lines[index].first == "\t" { end = index }
                index += 1
            }
            lines.insert(contentsOf: entry, at: end + 1)
        } else {
            if lines.last.map({ !$0.isEmpty }) ?? false { lines.append("") }
            lines.append("kits:")
            lines += entry
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func write(_ text: String, to path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// A new `paddock.yaml`: every section with its defaults and what each key does, commented out,
    /// so it means exactly the built-in defaults until the operator changes something.
    public static let template = #"""
        # Paddock's settings. Paddock reads this file again whenever it uses it, and every key is
        # optional: each section below shows its defaults, commented out. Remove the "# " to change one
        # (and the "# " of its section line).
        version: 1

        # The model gateway: one loopback port per project on a local model.
        # models:
        #   gatewayPorts: [17480, 17579]  # two ports, low to high; not 2375, 2376, 17434, or within ports.publishRange
        #   maxBodyMB: 32                 # the largest request an agent may send
        #   maxConcurrentPerProject: 2    # requests at once per project

        # What a new project gets when it names nothing.
        # defaults:
        #   agent: claude                 # an agents entry
        #   provider: agent-default       # a providers entry, or "local:MODEL" for any model in llmman's store

        # Providers. Defining any replaces the built-in list, so keep agent-default.
        # providers:
        #   agent-default:
        #     kind: agentDefault          # the agent's own account (Claude Code with Anthropic, say); no gateway
        #   local-qwen:
        #     kind: local                 # through Paddock's gateway, pinned to this model
        #     model: "hf.co/unsloth/Qwen3.5-35B-A3B-GGUF:latest"   # as llmman's /api/tags lists it

        # Agents. Defining any replaces the built-in list.
        # agents:
        #   claude:
        #     kind: claudeCode
        #   opencode:
        #     kind: openCode

        # Host ports for the sandbox ports Paddock publishes (on 127.0.0.1).
        # ports:
        #   publishRange: [18000, 18999]

        # sbx kits a project's sandbox can be created with, chosen per project (New Project sheet, or
        # the Kits row on its Info tab). Built in: browser (needs playwright), playwright,
        # status, voice (needs status), mise.
        # A kit with no keys is sbx's kit of that name from github.com/docker/sbx-kits-contrib
        # (docker.io/sbx/NAME, sbx's v3 build, which follows its latest; set source with a digest to pin it).
        # Kits Paddock's kit field adds go at the end of this block.
        # kits:
        #   gh: {}
        #   my-tools:
        #     source: "docker.io/acme/tools-kit@sha256:..."  # anything `sbx create --kit` takes: an image, git+https://..., or an absolute path
        #     builtin: browser            # instead of source: one of Paddock's own kits (browser, status, voice)
        #     summary: What it adds
        #     recommended: true           # preselected for new projects
        #     agents: [claudeCode]        # the agent kinds it is offered for; every agent when left out
        #     needs: [playwright]         # kits it builds on: selected with it and created before it
        #   playwright:
        #     recommended: true           # a kit without source changes a built-in kit
        #   opencode:
        #     enabled: false              # removes a built-in kit

        """#
}

/// Paddock's own kits that the operator can choose, written before a create.
public enum BuiltinKits {
    public static func directory(_ kit: BuiltinKit, in paths: PaddockPaths) -> String {
        switch kit {
        case .node: NodeKit.directory(in: paths)
        case .browser: BrowserKit.directory(in: paths)
        case .status: AgentStatusKit.directory(in: paths)
        case .voice: VoiceKit.directory(in: paths)
        }
    }

    public static func spec(_ kit: BuiltinKit) -> String {
        switch kit {
        // The dockerfile too, so a change to either shows the sandbox as needing a recreate.
        case .node: NodeKit.spec + NodeKit.dockerfile
        case .browser: BrowserKit.spec
        case .status: AgentStatusKit.spec
        case .voice: VoiceKit.spec
        }
    }

    /// Writes the kit if it is missing or differs. Returns its directory.
    @discardableResult
    public static func install(_ kit: BuiltinKit, in paths: PaddockPaths) throws -> String {
        switch kit {
        case .node: try NodeKit.install(in: paths)
        case .browser: try BrowserKit.install(in: paths)
        case .status: try AgentStatusKit.install(in: paths)
        case .voice: try VoiceKit.install(in: paths)
        }
    }
}
