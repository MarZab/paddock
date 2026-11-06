import Crypto
import Foundation

/// What a sandbox was created from, piece by piece (PAD-103): each top-level key of
/// `sbxenv.yaml` (by its parsed value, so comments and formatting do not count) and each file of
/// the project's own kits, by hash. `ProjectEnvironment.fingerprint` says only that something
/// differs; comparing two records says what.
public struct EnvironmentRecord: Sendable, Equatable, Codable {
    /// Piece name to a SHA-256 prefix: `sbxenv.yaml:<key>`, or `<kit source>` and the file's path
    /// in the kit, joined by `kitSeparator`.
    public var pieces: [String: String]

    public init(pieces: [String: String] = [:]) {
        self.pieces = pieces
    }

    static let filePrefix = SbxEnvFile.fileName + ":"
    static let kitSeparator = "\t"
    /// Files Finder writes into folders; never part of a kit.
    static let ignoredFiles: Set<String> = [".DS_Store"]

    /// The record of an `sbxenv.yaml` (`data`) and its local kits' files (`kits`: each kit's
    /// source and its files by path in the kit). A file that does not parse counts as one piece.
    static func of(data: Data, kits: [(source: String, files: [(String, Data)])]) -> EnvironmentRecord {
        var pieces: [String: String] = [:]
        if case .object(let keys)? = try? YAMLCoding.value(fromYAML: data) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            for (key, value) in keys {
                pieces[filePrefix + key] = digest((try? encoder.encode(value)) ?? Data())
            }
        } else {
            pieces[SbxEnvFile.fileName] = digest(data)
        }
        for kit in kits {
            for (path, data) in kit.files where !ignoredFiles.contains((path as NSString).lastPathComponent) {
                pieces[kit.source + kitSeparator + path] = digest(data)
            }
        }
        return EnvironmentRecord(pieces: pieces)
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// What differs from `earlier`, one phrase per file, for the sync item; empty when nothing does.
    /// "sbxenv.yaml (kits, network)", "kit ./tools/sandbox/app (install.sh changed, run.sh added)".
    public func changes(since earlier: EnvironmentRecord) -> [String] {
        let names = Set(pieces.keys).union(earlier.pieces.keys).filter { pieces[$0] != earlier.pieces[$0] }
        guard !names.isEmpty else { return [] }
        var phrases: [String] = []
        let keys = names.filter { $0.hasPrefix(Self.filePrefix) }.map { String($0.dropFirst(Self.filePrefix.count)) }.sorted()
        if !keys.isEmpty || names.contains(SbxEnvFile.fileName) {
            phrases.append(keys.isEmpty ? SbxEnvFile.fileName : "\(SbxEnvFile.fileName) (\(keys.joined(separator: ", ")))")
        }
        var byKit: [String: [String]] = [:]
        for name in names where !name.hasPrefix(Self.filePrefix) && name != SbxEnvFile.fileName {
            let parts = name.components(separatedBy: Self.kitSeparator)
            let what = earlier.pieces[name] == nil ? "added" : pieces[name] == nil ? "removed" : "changed"
            byKit[parts[0], default: []].append("\(parts.dropFirst().joined(separator: Self.kitSeparator)) \(what)")
        }
        for kit in byKit.keys.sorted() {
            phrases.append("kit \(kit) (\(byKit[kit, default: []].sorted().joined(separator: ", ")))")
        }
        return phrases
    }
}
