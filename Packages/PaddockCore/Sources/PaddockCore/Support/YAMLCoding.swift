import Foundation
import Yams

/// sbx's files are YAML: a project's `sbxenv.yaml` and its v3 kit descriptors. Paddock reads them
/// as `JSONValue`, so the checks see exactly what the file says. Scalars keep their YAML type: a
/// quoted `"3"` stays a string and `yes` is the string it looks like (YAML 1.2's core schema).
/// Aliases, merge keys, and duplicate keys are refused rather than resolved, since a reader that
/// resolves them differently from sbx would check a different file than the one sbx runs.
public enum YAMLCoding {
    public enum Problem: Error, Equatable, CustomStringConvertible {
        case syntax(String)
        case empty
        case alias
        case duplicateKey(String)
        case nonStringKey

        public var description: String {
            switch self {
            case .syntax(let message): "not valid YAML: \(message)"
            case .empty: "the file is empty"
            case .alias: "anchors, aliases, and merge keys (&name, *name, <<) are not supported"
            case .duplicateKey(let key): "\(key) appears twice"
            case .nonStringKey: "every key must be a plain string"
            }
        }
    }

    public static func value(fromYAML data: Data) throws(Problem) -> JSONValue {
        // The parser holds the anchors its nodes point at weakly, so it stays alive while the
        // tree is read: an anchored node (the target of an alias or a merge) is then visible.
        let parser: Parser
        let node: Node?
        do {
            parser = try Parser(yaml: String(decoding: data, as: UTF8.self), resolver: coreSchema)
            node = try parser.singleRoot()
        } catch {
            throw .syntax(String(describing: error))
        }
        guard let node else { throw .empty }
        return try withExtendedLifetime(parser) { () throws(Problem) -> JSONValue in try value(of: node) }
    }

    /// YAML 1.2's core schema (as Go's yaml.v3, which sbx is written with, reads it): only
    /// true/false are booleans, so `yes`, `no`, `on`, and `off` stay strings.
    /// The patterns are constants; were one ever refused, every scalar would read as a string and
    /// the typed checks after this would refuse the file rather than misread it.
    static let coreSchema = (try? Resolver.basic
        .appending(Resolver.Rule(.null, "^(?:~|null|Null|NULL|)$"))
        .appending(Resolver.Rule(.bool, "^(?:true|True|TRUE|false|False|FALSE)$"))
        .appending(Resolver.Rule(.int, "^(?:[-+]?[0-9]+|0o[0-7]+|0x[0-9a-fA-F]+)$"))
        .appending(Resolver.Rule(.float, "^(?:[-+]?(?:\\.[0-9]+|[0-9]+(?:\\.[0-9]*)?)(?:[eE][-+]?[0-9]+)?|[-+]?\\.(?:inf|Inf|INF)|\\.(?:nan|NaN|NAN))$"))) ?? Resolver.basic

    static func value(of node: Node) throws(Problem) -> JSONValue {
        switch node {
        case .alias:
            throw .alias
        case .scalar(let scalar):
            guard scalar.anchor == nil else { throw .alias }
            return scalarValue(scalar)
        case .sequence(let sequence):
            guard sequence.anchor == nil else { throw .alias }
            var items: [JSONValue] = []
            for item in sequence { items.append(try value(of: item)) }
            return .array(items)
        case .mapping(let mapping):
            guard mapping.anchor == nil else { throw .alias }
            var object: [String: JSONValue] = [:]
            for (key, item) in mapping {
                guard case .scalar(let keyScalar) = key, case .string = scalarValue(keyScalar) else { throw .nonStringKey }
                if keyScalar.string == "<<" { throw .alias }
                guard object[keyScalar.string] == nil else { throw .duplicateKey(keyScalar.string) }
                object[keyScalar.string] = try value(of: item)
            }
            return .object(object)
        }
    }

    /// A quoted or block scalar is a string; a plain one is resolved by the core schema.
    private static func scalarValue(_ scalar: Node.Scalar) -> JSONValue {
        let node = Node.scalar(scalar)
        guard scalar.style == .plain || scalar.style == .any else { return .string(scalar.string) }
        switch coreSchema.resolveTag(of: node) {
        case .null: return .null
        case .bool: return node.bool.map(JSONValue.bool) ?? .string(scalar.string)
        case .int: return node.int.map { .number(Double($0)) } ?? .string(scalar.string)
        case .float: return node.float.map(JSONValue.number) ?? .string(scalar.string)
        default: return .string(scalar.string)
        }
    }
}
