import Foundation

/// `~/.config/paddock/paddock.yaml`: the operator-owned desired state, in named sections.
/// Projects only refer to these sections by name (see backlog doc App config).
public struct AppConfig: Sendable, Equatable {
    public struct Models: Sendable, Equatable, Codable {
        /// One loopback gateway port per project, assigned from this range (backlog doc ModelGateway).
        public var gatewayPorts: ClosedRange<Int> = Self.defaultGatewayPorts
        public static let defaultGatewayPorts = 17480...17579
        public var maxBodyMB: Int = 32
        public var maxConcurrentPerProject: Int = 2
    }

    public enum Provider: Sendable, Equatable {
        /// The agent's default provider through its own account (for example Claude Code with
        /// Anthropic); no gateway.
        case agentDefault
        /// A model in llmman's store, reached only through the gateway.
        case local(model: String)
    }

    public enum Agent: String, Sendable, Equatable, Codable {
        case claudeCode
        case openCode

        /// The built-in sbx agent name.
        public var sbxAgent: String {
            switch self {
            case .claudeCode: "claude"
            case .openCode: "opencode"
            }
        }
    }

    /// The only port setting: host ports for published sandbox ports (loopback only).
    public struct Ports: Sendable, Equatable, Codable {
        public var publishRange: ClosedRange<Int> = 18000...18999
    }

    /// What a new project gets when the operator chooses nothing else.
    public struct Defaults: Sendable, Equatable, Codable {
        public var agent: String = "claude"
        public var provider: String = "agent-default"
    }

    public static let currentVersion = 1

    public var models = Models()
    public var defaults = Defaults()
    public var providers: [String: Provider] = ["agent-default": .agentDefault]
    public var agents: [String: Agent] = ["claude": .claudeCode, "opencode": .openCode]
    public var ports = Ports()
    /// `[kits.NAME]`: `defaultKits`, changed or added to by the file.
    public var kits: [String: Kit] = AppConfig.defaultKits

    public init() {}

    /// A project's provider: a `[providers]` section, or `local:MODEL` for a model in llmman's
    /// store that has no section of its own (the New Project sheet offers every installed model).
    public func provider(named name: String) -> Provider? {
        if let provider = providers[name] { return provider }
        guard name.hasPrefix(Self.localPrefix) else { return nil }
        let model = String(name.dropFirst(Self.localPrefix.count))
        return model.isEmpty ? nil : .local(model: model)
    }

    /// The provider name for an installed model without a section.
    public static func localProviderName(model: String) -> String { localPrefix + model }

    static let localPrefix = "local:"
}

public enum AppConfigError: Error, Equatable, CustomStringConvertible {
    case malformed(String)
    case unsupportedVersion(Int?)
    case unknownProviderKind(name: String, kind: String)
    case unknownAgentKind(name: String, kind: String)
    case localProviderWithoutModel(String)
    case invalidGatewayPorts
    case missingDefaultSection(kind: String, name: String)
    case invalidPublishRange
    case invalidKit(name: String, problem: String)

    public var description: String {
        switch self {
        case .malformed(let message): "Paddock's config is not valid: \(message)"
        case .unsupportedVersion(let v): "Paddock's config: version \(v.map(String.init) ?? "missing") is not supported"
        case .unknownProviderKind(let name, let kind): "provider \(name) has unknown kind \(kind)"
        case .unknownAgentKind(let name, let kind): "agent \(name) has unknown kind \(kind)"
        case .localProviderWithoutModel(let name): "provider \(name) is local but names no model"
        case .invalidGatewayPorts: "models.gatewayPorts must be two ports, low to high, clear of reserved ports and ports.publishRange"
        case .invalidPublishRange: "ports.publishRange must be two ports from 1024 to 65535, low to high"
        case .missingDefaultSection(let kind, let name): "defaults.\(kind) names \(name), which is not defined"
        case .invalidKit(let name, let problem): "kit \(name): \(problem)"
        }
    }
}

extension AppConfig {
    /// Ports no Paddock setting may use: the Docker Engine API and llmman.
    /// Ports no range in this file may include: the Docker Engine API and llmman's.
    public static let reservedPorts: Set<Int> = [2375, 2376, llmmanPort]
    /// sbx's bundled llmman, the model server behind Paddock's gateway.
    public static let llmmanPort = 17434

    /// The config at `path`; a missing file means the built-in defaults.
    public static func load(atPath path: String) throws(AppConfigError) -> (config: AppConfig, unknownKeys: [String]) {
        guard let data = FileManager.default.contents(atPath: path) else { return (AppConfig(), []) }
        return try load(from: data)
    }

    /// Decodes and validates the config. Unknown keys are not an error; they come back in
    /// `unknownKeys` so the UI can show them (a typo should not silently change behavior).
    public static func load(from data: Data) throws(AppConfigError) -> (config: AppConfig, unknownKeys: [String]) {
        let raw: RawAppConfig
        let tree: JSONValue
        do {
            // YAML, decoded as JSON. Plain decoder: Paddock's files are camelCase, and a
            // snake_case strategy would also rewrite section names such as "local_qwen".
            let json = try JSONEncoder().encode(yamlTree(data))
            raw = try JSONDecoder().decode(RawAppConfig.self, from: json)
            tree = try JSONDecoder().decode(JSONValue.self, from: json)
        } catch {
            throw .malformed(String(describing: error))
        }
        guard raw.version == currentVersion else { throw .unsupportedVersion(raw.version) }

        var config = AppConfig()
        if let models = raw.models {
            config.models = models
        }
        if let defaults = raw.defaults {
            config.defaults = defaults
        }
        if let providers = raw.providers {
            config.providers = [:]
            for (name, provider) in providers {
                switch provider.kind {
                case "agentDefault":
                    config.providers[name] = .agentDefault
                case "local":
                    guard let model = provider.model, !model.isEmpty else { throw .localProviderWithoutModel(name) }
                    config.providers[name] = .local(model: model)
                default:
                    throw .unknownProviderKind(name: name, kind: provider.kind)
                }
            }
        }
        if let agents = raw.agents {
            config.agents = [:]
            for (name, agent) in agents {
                guard let kind = Agent(rawValue: agent.kind) else { throw .unknownAgentKind(name: name, kind: agent.kind) }
                config.agents[name] = kind
            }
        }
        for (name, kit) in raw.kits ?? [:] {
            config.kits[name] = try kit.merged(onto: config.kits[name], name: name)
        }
        if let range = raw.ports?.publishRange {
            guard range.count == 2, range[0] <= range[1] else { throw .invalidPublishRange }
            config.ports.publishRange = range[0]...range[1]
        }
        try config.validate()
        return (config, Self.unknownKeys(in: tree))
    }

    public func validate() throws(AppConfigError) {
        let valid = 1024...65535
        let gateway = models.gatewayPorts
        guard valid.contains(gateway.lowerBound), valid.contains(gateway.upperBound),
              !Self.reservedPorts.contains(where: gateway.contains), !gateway.overlaps(ports.publishRange) else {
            throw .invalidGatewayPorts
        }
        guard valid.contains(ports.publishRange.lowerBound), valid.contains(ports.publishRange.upperBound),
              !Self.reservedPorts.contains(where: ports.publishRange.contains) else {
            throw .invalidPublishRange
        }
        if agents[defaults.agent] == nil { throw .missingDefaultSection(kind: "agent", name: defaults.agent) }
        if provider(named: defaults.provider) == nil { throw .missingDefaultSection(kind: "provider", name: defaults.provider) }
        try validateKits()
    }

    /// Every kit's source is something `sbx create --kit` takes as one argument, and its needs
    /// are defined kits, without a cycle.
    func validateKits() throws(AppConfigError) {
        for (name, kit) in kits {
            if case .reference(let reference) = kit.source, let problem = Self.referenceProblem(reference) {
                throw .invalidKit(name: name, problem: problem)
            }
            for need in kit.needs where kits[need] == nil {
                throw .invalidKit(name: name, problem: "needs \(need), which is not defined")
            }
        }
        for name in kits.keys.sorted() {
            var path: [String] = []
            func visit(_ current: String) throws(AppConfigError) {
                if path.contains(current) { throw .invalidKit(name: name, problem: "its needs go round in a circle") }
                path.append(current)
                for need in kits[current]?.needs ?? [] { try visit(need) }
                path.removeLast()
            }
            try visit(name)
        }
    }

    /// Why `reference` cannot be a `--kit` value: empty, an option, a relative path, or with
    /// whitespace or control characters.
    static func referenceProblem(_ reference: String) -> String? {
        if reference.isEmpty { return "source is empty" }
        if reference.hasPrefix("-") { return "source may not start with -" }
        if reference.hasPrefix(".") || reference.hasPrefix("~") { return "a local kit needs an absolute path" }
        if reference.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) {
            return "source may not contain spaces or control characters"
        }
        return nil
    }

    /// `paddock.yaml` as a tree: a known section whose keys are all commented out (`models:`
    /// alone) is absent, and a kit without keys (`gh:`) is an empty section.
    static func yamlTree(_ data: Data) throws -> JSONValue {
        let value: JSONValue
        do {
            value = try YAMLCoding.value(fromYAML: data)
        } catch {
            guard error == .empty else { throw error }
            return .object([:])
        }
        guard case .object(var top) = value else { return value }
        // An unknown one stays (empty), so it is still reported.
        for (key, section) in top where section == .null {
            top[key] = (knownKeys[""] ?? []).contains(key) ? nil : .object([:])
        }
        if case .object(var kits)? = top["kits"] {
            for (name, kit) in kits where kit == .null { kits[name] = .object([:]) }
            top["kits"] = .object(kits)
        }
        return .object(top)
    }

    private static let knownKeys: [String: Set<String>] = [
        // No `policies`: a sandbox's network is sbx's global rules plus its project's confirmed
        // `sbxenv.yaml` kits; a `policies` section left from before is reported as unknown.
        "": ["version", "models", "defaults", "providers", "agents", "ports", "kits"],
        "models": ["gatewayPorts", "maxBodyMB", "maxConcurrentPerProject"],
        "defaults": ["agent", "provider"],
        "ports": ["publishRange"],
    ]

    private static let knownKitKeys: Set<String> = ["builtin", "source", "summary", "recommended", "agents", "needs", "enabled"]

    private static func unknownKeys(in tree: JSONValue) -> [String] {
        guard case .object(let top) = tree else { return [] }
        var unknown: [String] = []
        for key in top.keys.sorted() where !(knownKeys[""] ?? []).contains(key) {
            unknown.append(key)
        }
        for (section, keys) in knownKeys where !section.isEmpty {
            guard case .object(let object)? = top[section] else { continue }
            unknown += object.keys.sorted().filter { !keys.contains($0) }.map { "\(section).\($0)" }
        }
        if case .object(let kits)? = top["kits"] {
            for (name, kit) in kits {
                guard case .object(let object) = kit else { continue }
                unknown += object.keys.sorted().filter { !knownKitKeys.contains($0) }.map { "kits.\(name).\($0)" }
            }
        }
        return unknown.sorted()
    }
}

/// The on-disk shape, before validation.
private struct RawAppConfig: Decodable {
    struct Provider: Decodable {
        let kind: String
        let model: String?
    }

    struct Agent: Decodable {
        let kind: String
    }

    let version: Int?
    let models: AppConfig.Models?
    let defaults: AppConfig.Defaults?
    let providers: [String: Provider]?
    let agents: [String: Agent]?
    let ports: RawPorts?
    let kits: [String: RawKit]?

    struct RawPorts: Decodable {
        let publishRange: [Int]?
    }
}

/// A `[kits.NAME]` section. With neither `builtin` nor `source` it changes a default kit (say,
/// `recommended = true`) or names sbx's contrib kit (`gh:` is `docker.io/sbx/gh`);
/// `enabled = false` removes one.
private struct RawKit: Decodable {
    let builtin: String?
    let source: String?
    let summary: String?
    let recommended: Bool?
    /// Agent kinds, as in `[agents]` (`claudeCode`, `openCode`).
    let agents: [String]?
    let needs: [String]?
    let enabled: Bool?

    func merged(onto base: Kit?, name: String) throws(AppConfigError) -> Kit? {
        if enabled == false { return nil }
        var kit: Kit
        switch (builtin, source) {
        case (let builtin?, nil):
            guard let builtinKit = BuiltinKit(rawValue: builtin) else {
                let known = BuiltinKit.allCases.map(\.rawValue).joined(separator: ", ")
                throw .invalidKit(name: name, problem: "builtin \(builtin) is not one of Paddock's kits (\(known))")
            }
            kit = Kit(source: .builtin(builtinKit))
        case (nil, let source?):
            kit = Kit(source: .reference(source))
        case (nil, nil):
            // A default kit changed, or sbx's contrib kit of that name.
            if let base {
                kit = base
            } else if Kit.isValidName(name) {
                kit = Kit(source: .reference(Kit.contribReference(name)))
            } else {
                throw .invalidKit(name: name, problem: "set source (or builtin); without one the name must be an sbx kit name")
            }
        default:
            throw .invalidKit(name: name, problem: "set either source or builtin, not both")
        }
        if let summary { kit.summary = summary }
        if let recommended { kit.recommended = recommended }
        if let needs { kit.needs = needs }
        if let agents {
            kit.agents = []
            for agent in agents {
                guard let kind = AppConfig.Agent(rawValue: agent) else {
                    throw .invalidKit(name: name, problem: "agents names \(agent), which is not an agent kind (claudeCode, openCode)")
                }
                kit.agents.append(kind)
            }
        }
        return kit
    }
}

extension AppConfig.Models {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig.Models()
        if let range = try c.decodeIfPresent([Int].self, forKey: .gatewayPorts) {
            guard range.count == 2, range[0] <= range[1] else {
                throw DecodingError.dataCorruptedError(forKey: .gatewayPorts, in: c, debugDescription: "two ports, low to high")
            }
            gatewayPorts = range[0]...range[1]
        } else {
            gatewayPorts = defaults.gatewayPorts
        }
        maxBodyMB = try c.decodeIfPresent(Int.self, forKey: .maxBodyMB) ?? defaults.maxBodyMB
        maxConcurrentPerProject = try c.decodeIfPresent(Int.self, forKey: .maxConcurrentPerProject) ?? defaults.maxConcurrentPerProject
    }
}

extension AppConfig.Defaults {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig.Defaults()
        agent = try c.decodeIfPresent(String.self, forKey: .agent) ?? defaults.agent
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? defaults.provider
    }
}
