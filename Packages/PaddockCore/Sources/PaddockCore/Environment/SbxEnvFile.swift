import Foundation

/// A project's `sbxenv.yaml`: sbx's environment file (`sbx env plan|run|create|rm`), which a
/// project keeps at its root so it runs with plain sbx, and which Paddock reads and overlays
/// (backlog doc Project config file). **Untrusted:** the agent can write it. This is only what the
/// file says; `ProjectEnvironment` decides what Paddock accepts.
///
/// Read strictly: a key this model does not know is reported, never skipped, so a newer sbx field
/// that could widen what a sandbox gets is refused until Paddock knows it.
public struct SbxEnvFile: Sendable, Equatable {
    public static let fileName = "sbxenv.yaml"
    public static let schemaVersion = "1"

    public struct KitEntry: Sendable, Equatable {
        /// A local directory, an OCI reference, or a `git+` URL, as sbx takes it.
        public var source: String
        public var args: [String: JSONValue]

        public init(source: String, args: [String: JSONValue] = [:]) {
            self.source = source
            self.args = args
        }
    }

    public struct ExtraFolder: Sendable, Equatable {
        public var path: String
        public var target: String?
        public var readOnly: Bool

        public init(path: String, target: String? = nil, readOnly: Bool = false) {
            self.path = path
            self.target = target
            self.readOnly = readOnly
        }
    }

    public struct PortMapping: Sendable, Equatable {
        public var sandbox: Int
        public var host: Int?
        public var transport: String?
        public var hostIP: String?

        public init(sandbox: Int, host: Int? = nil, transport: String? = nil, hostIP: String? = nil) {
            self.sandbox = sandbox
            self.host = host
            self.transport = transport
            self.hostIP = hostIP
        }
    }

    public var name: String?
    public var agent: String
    public var entrypoint: [String]?
    public var cmd: [String]?
    public var kits: [KitEntry]
    /// nil when the file names none (sbx then mounts nothing; Paddock's overlay names the folder).
    public var workspace: String?
    public var additionalWorkspaces: [ExtraFolder]
    public var env: [String: String]
    public var ports: [PortMapping]
    /// `sandboxOptions` as written; `ProjectEnvironment` allows only some of its keys.
    public var sandboxOptions: [String: JSONValue]
    /// Top-level keys sbx knows that this model keeps only as present (`lifecycle`, `secrets`,
    /// `bindings`, `registries`, `mounts`, `mcp`, `args`, or a `workspace` written as an object):
    /// Paddock refuses most of them.
    public var otherKeys: Set<String>

    public init(name: String? = nil, agent: String, entrypoint: [String]? = nil, cmd: [String]? = nil,
                kits: [KitEntry] = [], workspace: String? = nil, additionalWorkspaces: [ExtraFolder] = [],
                env: [String: String] = [:], ports: [PortMapping] = [], sandboxOptions: [String: JSONValue] = [:],
                otherKeys: Set<String> = []) {
        self.name = name
        self.agent = agent
        self.entrypoint = entrypoint
        self.cmd = cmd
        self.kits = kits
        self.workspace = workspace
        self.additionalWorkspaces = additionalWorkspaces
        self.env = env
        self.ports = ports
        self.sandboxOptions = sandboxOptions
        self.otherKeys = otherKeys
    }
}

public enum SbxEnvFileError: Error, Equatable, CustomStringConvertible {
    case yaml(YAMLCoding.Problem)
    case unsupportedVersion(String?)
    case unknownKey(String)
    case invalid(key: String, expected: String)

    public var description: String {
        switch self {
        case .yaml(let problem): "\(SbxEnvFile.fileName) is \(problem)"
        case .unsupportedVersion(let version):
            "\(SbxEnvFile.fileName): schemaVersion \(version.map { "\"\($0)\"" } ?? "missing") is not supported (\"\(SbxEnvFile.schemaVersion)\" is)"
        case .unknownKey(let key): "\(SbxEnvFile.fileName): \(key) is not a key Paddock knows"
        case .invalid(let key, let expected): "\(SbxEnvFile.fileName): \(key) must be \(expected)"
        }
    }
}

extension SbxEnvFile {
    /// Keys sbx documents for an environment file (docs.docker.com, Environment files) that this
    /// model keeps only as present.
    public static let keptAsPresent: Set<String> = ["args", "lifecycle", "secrets", "bindings", "registries", "mounts", "mcp"]

    public static func load(from data: Data) throws(SbxEnvFileError) -> SbxEnvFile {
        let root: JSONValue
        do {
            root = try YAMLCoding.value(fromYAML: data)
        } catch {
            throw .yaml(error)
        }
        var reader = ObjectReader(root, path: "")
        guard reader.isObject else { throw .invalid(key: "the file", expected: "a mapping of keys") }
        let version = reader.take("schemaVersion")
        if case .number? = version { throw .invalid(key: "schemaVersion", expected: "the quoted string \"\(schemaVersion)\"") }
        guard case .string(let versionText)? = version, versionText == schemaVersion else {
            throw .unsupportedVersion(version.map(\.plainText))
        }
        var file = SbxEnvFile(agent: try reader.requiredString("agent"))
        file.name = try reader.string("name")
        file.entrypoint = try reader.strings("entrypoint")
        file.cmd = try reader.strings("cmd")
        file.kits = try reader.array("kits").enumerated().map { index, item throws(SbxEnvFileError) in
            try kitEntry(item, path: "kits[\(index)]")
        }
        switch reader.take("workspace") {
        case nil, .null?: file.workspace = nil
        case .string(let path)?: file.workspace = path
        case .object?: file.otherKeys.insert("workspace")
        default: throw .invalid(key: "workspace", expected: "a path")
        }
        file.additionalWorkspaces = try reader.array("additionalWorkspaces").enumerated().map { index, item throws(SbxEnvFileError) in
            var entry = ObjectReader(item, path: "additionalWorkspaces[\(index)]")
            guard entry.isObject else { throw .invalid(key: entry.path, expected: "a mapping with path") }
            let folder = ExtraFolder(path: try entry.requiredString("path"), target: try entry.string("target"),
                                     readOnly: try entry.bool("readOnly") ?? false)
            try entry.finish()
            return folder
        }
        file.env = try reader.stringMap("env")
        file.ports = try reader.array("ports").enumerated().map { index, item throws(SbxEnvFileError) in
            var entry = ObjectReader(item, path: "ports[\(index)]")
            guard entry.isObject else { throw .invalid(key: entry.path, expected: "a mapping with sandbox") }
            let mapping = PortMapping(sandbox: try entry.requiredInt("sandbox"), host: try entry.int("host"),
                                      transport: try entry.string("protocol"), hostIP: try entry.string("hostIP"))
            try entry.finish()
            return mapping
        }
        if case .object(let options)? = reader.take("sandboxOptions") {
            file.sandboxOptions = options
        }
        for key in keptAsPresent where reader.take(key) != nil {
            file.otherKeys.insert(key)
        }
        try reader.finish()
        return file
    }

    private static func kitEntry(_ value: JSONValue, path: String) throws(SbxEnvFileError) -> KitEntry {
        if case .string(let source) = value { return KitEntry(source: source) }
        var entry = ObjectReader(value, path: path)
        guard entry.isObject else { throw .invalid(key: path, expected: "a kit reference or a mapping with source") }
        let source = try entry.requiredString("source")
        var args: [String: JSONValue] = [:]
        if case .object(let given)? = entry.take("args") { args = given }
        try entry.finish()
        return KitEntry(source: source, args: args)
    }
}

extension JSONValue {
    /// The value as a person wrote it, for messages: `1`, `true`, `abc`.
    var plainText: String {
        switch self {
        case .null: "null"
        case .bool(let value): String(value)
        case .number(let value): value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case .string(let value): value
        case .array: "a list"
        case .object: "a mapping"
        }
    }
}

/// Takes keys out of a JSON object one by one, so whatever is left at the end is unknown.
struct ObjectReader {
    let path: String
    private(set) var remaining: [String: JSONValue]
    let isObject: Bool

    init(_ value: JSONValue, path: String) {
        self.path = path
        if case .object(let object) = value {
            remaining = object
            isObject = true
        } else {
            remaining = [:]
            isObject = false
        }
    }

    private func name(_ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }

    mutating func take(_ key: String) -> JSONValue? { remaining.removeValue(forKey: key) }

    mutating func string(_ key: String) throws(SbxEnvFileError) -> String? {
        switch take(key) {
        case nil, .null?: return nil
        case .string(let value)?: return value
        default: throw .invalid(key: name(key), expected: "a string")
        }
    }

    mutating func requiredString(_ key: String) throws(SbxEnvFileError) -> String {
        guard let value = try string(key), !value.isEmpty else { throw .invalid(key: name(key), expected: "set") }
        return value
    }

    mutating func int(_ key: String) throws(SbxEnvFileError) -> Int? {
        switch take(key) {
        case nil, .null?: return nil
        case .number(let value)? where value == value.rounded() && abs(value) < 1e9: return Int(value)
        default: throw .invalid(key: name(key), expected: "a whole number")
        }
    }

    mutating func requiredInt(_ key: String) throws(SbxEnvFileError) -> Int {
        guard let value = try int(key) else { throw .invalid(key: name(key), expected: "set") }
        return value
    }

    mutating func bool(_ key: String) throws(SbxEnvFileError) -> Bool? {
        switch take(key) {
        case nil, .null?: return nil
        case .bool(let value)?: return value
        default: throw .invalid(key: name(key), expected: "true or false")
        }
    }

    mutating func array(_ key: String) throws(SbxEnvFileError) -> [JSONValue] {
        switch take(key) {
        case nil, .null?: return []
        case .array(let items)?: return items
        default: throw .invalid(key: name(key), expected: "a list")
        }
    }

    mutating func strings(_ key: String) throws(SbxEnvFileError) -> [String]? {
        guard remaining[key] != nil else { return nil }
        return try array(key).map { item throws(SbxEnvFileError) in
            guard case .string(let text) = item else { throw .invalid(key: name(key), expected: "a list of strings") }
            return text
        }
    }

    mutating func stringMap(_ key: String) throws(SbxEnvFileError) -> [String: String] {
        switch take(key) {
        case nil, .null?: return [:]
        case .object(let object)?:
            var result: [String: String] = [:]
            for (entryKey, value) in object {
                switch value {
                case .string(let text): result[entryKey] = text
                case .number(let number): result[entryKey] = number == number.rounded() ? String(Int(number)) : String(number)
                case .bool(let flag): result[entryKey] = String(flag)
                default: throw .invalid(key: name("\(key).\(entryKey)"), expected: "a string")
                }
            }
            return result
        default: throw .invalid(key: name(key), expected: "a mapping of strings")
        }
    }

    /// Throws for the first key nothing took.
    func finish() throws(SbxEnvFileError) {
        if let key = remaining.keys.sorted().first { throw .unknownKey(name(key)) }
    }
}
