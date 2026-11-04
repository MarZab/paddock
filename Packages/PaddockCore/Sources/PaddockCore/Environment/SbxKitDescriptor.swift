import Foundation

/// A v3 kit descriptor (`<kit>/<kit>.yaml`, github.com/docker/sandbox-kit-spec SPEC-v3): what a
/// project's own local kit asks for. Only the parts Paddock checks are typed: its kind and its
/// capabilities, with the network rules and host ports spelled out. sbx validates the rest when
/// it builds the kit.
public struct SbxKitDescriptor: Sendable, Equatable {
    public static let schemaVersion = "3"

    public enum Kind: String, Sendable, Equatable {
        case workload, mixin, set
    }

    public struct Capability: Sendable, Equatable {
        /// `com.docker.sandbox/NAME@VERSION`.
        public var type: String
        public var optional: Bool
        public var config: JSONValue?

        public init(type: String, optional: Bool = false, config: JSONValue? = nil) {
            self.type = type
            self.optional = optional
            self.config = config
        }
    }

    /// One allow or deny entry of `network-policy@1`/`@2`: hosts, bounded to methods and paths
    /// when the entry says so.
    public struct NetworkEntry: Sendable, Equatable {
        public var hosts: [String]
        public var methods: [String]
        public var paths: [String]

        public init(hosts: [String], methods: [String] = [], paths: [String] = []) {
            self.hosts = hosts
            self.methods = methods
            self.paths = paths
        }

        public var isBounded: Bool { !methods.isEmpty || !paths.isEmpty }
    }

    /// What the kit's network policy allows and denies in one phase.
    public struct NetworkRules: Sendable, Equatable {
        public var allow: [NetworkEntry] = []
        public var deny: [NetworkEntry] = []

        public init(allow: [NetworkEntry] = [], deny: [NetworkEntry] = []) {
            self.allow = allow
            self.deny = deny
        }
    }

    public var kind: Kind
    public var displayName: String?
    /// The top-level `version`, the fallback for `provides` entries without one.
    public var version: String?
    /// Names this kit provides (`name` or `name@version`).
    public var provides: [String] = []
    public var capabilities: [Capability]
    /// A recipe beside or inside the descriptor: `<kit>.dockerfile`, `build`, or `dockerfile`.
    public var hasRecipe: Bool

    public init(kind: Kind, displayName: String? = nil, capabilities: [Capability] = [], hasRecipe: Bool = false) {
        self.kind = kind
        self.displayName = displayName
        self.capabilities = capabilities
        self.hasRecipe = hasRecipe
    }
}

public enum SbxKitDescriptorError: Error, Equatable, CustomStringConvertible {
    case yaml(YAMLCoding.Problem)
    case unsupportedVersion(String?)
    case invalid(String)

    public var description: String {
        switch self {
        case .yaml(let problem): "the kit descriptor is \(problem)"
        case .unsupportedVersion(let version):
            "schemaVersion \(version.map { "\"\($0)\"" } ?? "missing") is not a v3 kit (\"\(SbxKitDescriptor.schemaVersion)\")"
        case .invalid(let message): message
        }
    }
}

extension SbxKitDescriptor {
    public static let capabilityPrefix = "com.docker.sandbox/"

    public static func load(from data: Data) throws(SbxKitDescriptorError) -> SbxKitDescriptor {
        let root: JSONValue
        do {
            root = try YAMLCoding.value(fromYAML: data)
        } catch {
            throw .yaml(error)
        }
        guard case .object(let object) = root else { throw .invalid("the kit descriptor must be a mapping of keys") }
        guard case .string(let version)? = object["schemaVersion"], version == schemaVersion else {
            throw .unsupportedVersion(object["schemaVersion"]?.plainText)
        }
        guard case .string(let kindText)? = object["kind"], let kind = Kind(rawValue: kindText) else {
            throw .invalid("kind must be workload, mixin, or set")
        }
        var capabilities: [Capability] = []
        if case .array(let items)? = object["capabilities"] {
            for (index, item) in items.enumerated() {
                guard case .string(let type)? = item["type"] else {
                    throw .invalid("capabilities[\(index)] has no type (Paddock does not read grouped capabilities)")
                }
                var optional = false
                if case .bool(let flag)? = item["optional"] { optional = flag }
                capabilities.append(Capability(type: type, optional: optional, config: item["config"]))
            }
        } else if object["capabilities"] != nil {
            throw .invalid("capabilities must be a list")
        }
        var descriptor = SbxKitDescriptor(kind: kind, displayName: object["displayName"]?.stringValue, capabilities: capabilities,
                                          hasRecipe: object["build"] != nil || object["dockerfile"] != nil)
        descriptor.version = object["version"]?.stringValue
        if case .array(let items)? = object["provides"] {
            descriptor.provides = items.compactMap(\.stringValue)
        }
        return descriptor
    }

    /// `provides` entries sbx refuses to build: no `@version` and no top-level `version` (checked
    /// on the Mac with sbx 0.49.2's kit builder, sandbox-kit 3.0.0-m.11; the schema allows them).
    public var unversionedProvides: [String] {
        version == nil ? provides.filter { !$0.contains("@") } : []
    }

    /// The capability's name without the `com.docker.sandbox/` prefix (`network-policy@2`), or the
    /// whole type for another namespace.
    public static func shortName(_ type: String) -> String {
        type.hasPrefix(capabilityPrefix) ? String(type.dropFirst(capabilityPrefix.count)) : type
    }

    /// The network rules of a phase (`install` or `runtime`), from `network-policy@1` or `@2`.
    /// An entry Paddock cannot read throws, so a rule is never skipped.
    public func network(phase: String) throws(SbxKitDescriptorError) -> NetworkRules {
        var rules = NetworkRules()
        for capability in capabilities where ["network-policy@1", "network-policy@2"].contains(Self.shortName(capability.type)) {
            guard let config = capability.config else { continue }
            guard let phaseValue = config[phase] else { continue }
            guard case .object = phaseValue else { throw .invalid("network \(phase) must be a mapping with allow and deny lists") }
            rules.allow += try Self.entries(phaseValue["allow"], at: "\(phase).allow")
            rules.deny += try Self.entries(phaseValue["deny"], at: "\(phase).deny")
        }
        return rules
    }

    private static func entries(_ value: JSONValue?, at path: String) throws(SbxKitDescriptorError) -> [NetworkEntry] {
        guard let value else { return [] }
        guard case .array(let items) = value else { throw .invalid("network \(path) must be a list") }
        var result: [NetworkEntry] = []
        for item in items {
            switch item {
            case .string(let host):
                result.append(NetworkEntry(hosts: [host]))
            case .object(let object):
                func strings(_ key: String) throws(SbxKitDescriptorError) -> [String] {
                    guard let list = object[key] else { return [] }
                    guard case .array(let values) = list else { throw .invalid("network \(path): \(key) must be a list") }
                    var texts: [String] = []
                    for entry in values {
                        guard case .string(let text) = entry else { throw .invalid("network \(path): \(key) must be strings") }
                        texts.append(text)
                    }
                    return texts
                }
                let unknown = Set(object.keys).subtracting(["hosts", "methods", "paths"])
                guard unknown.isEmpty else { throw .invalid("network \(path): \(unknown.sorted().joined(separator: ", ")) is not known") }
                result.append(NetworkEntry(hosts: try strings("hosts"), methods: try strings("methods"), paths: try strings("paths")))
            default:
                throw .invalid("network \(path) entries must be hosts or mappings")
            }
        }
        return result
    }
}
