import Foundation

/// Why a folder may not be mounted into a sandbox.
public enum FolderPolicyViolation: Error, Equatable, CustomStringConvertible {
    case notADirectory(String)
    case root
    case home
    /// The folder contains the home directory (for example `/Users`).
    case containsHome
    /// The folder has a direct child such as `.ssh` or `Library`.
    case containsSensitiveEntry(String)
    /// The folder is, or is inside, a sensitive folder of the home directory (`~/.ssh/keys`, say).
    case insideSensitiveEntry(String)
    /// The folder is, contains, or is inside Paddock's config directory.
    case overlapsPaddockConfig

    public var description: String {
        switch self {
        case .notADirectory(let path): "\(path) is not a folder"
        case .root: "the root folder cannot be a project"
        case .home: "the home folder cannot be a project"
        case .containsHome: "the folder contains the home folder"
        case .containsSensitiveEntry(let name): "the folder contains \(name)"
        case .insideSensitiveEntry(let name): "the folder is inside ~/\(name)"
        case .overlapsPaddockConfig: "the folder overlaps Paddock's config folder"
        }
    }
}

/// Decides whether a folder may be a project. sbx itself allows mounting any path,
/// so this is the only guard (see backlog doc Security rules).
public struct FolderPolicy: Sendable {
    /// Direct children that mark a folder as holding credentials or personal data.
    /// Also refused when the folder is inside one of them under the home directory (PAD-83).
    public static let sensitiveEntries = [
        ".ssh", ".aws", ".gnupg", "Library",
        ".kube", ".docker", ".azure", ".config/gh", ".config/gcloud",
    ]

    public let home: String
    public let paddockConfigDirectory: String

    public init(home: String, paddockConfigDirectory: String) {
        self.home = Self.canonical(home)
        self.paddockConfigDirectory = Self.canonical(paddockConfigDirectory)
    }

    /// Inside `~/Library`, the one place a folder may be: `~/Library/Logs` (Paddock's own logs and
    /// hang captures, other apps' logs), and only when the operator adds it in Paddock as an extra
    /// folder, which then stays read-only (`ExtraFolders`, PAD-125). Never a project folder, and
    /// never from a project's file.
    public static let readOnlyLogs = "Library/Logs"

    /// Whether `folder` (symlinks resolved) is inside `~/Library/Logs`.
    public func isInsideLogs(_ folder: String) -> Bool {
        Self.canonical(folder).lowercased().hasPrefix((home + "/" + Self.readOnlyLogs + "/").lowercased())
    }

    /// Checks `folder` after resolving symlinks, so a link to `$HOME` is treated as `$HOME`.
    /// `allowingLogs`: a folder inside `~/Library/Logs` passes (an operator's read-only extra folder).
    public func check(_ folder: String, allowingLogs: Bool = false) throws(FolderPolicyViolation) {
        let path = Self.canonical(folder)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw .notADirectory(folder)
        }
        if path == "/" { throw .root }
        if path == home { throw .home }
        if Self.isAncestor(path, of: home) { throw .containsHome }
        if path == paddockConfigDirectory
            || Self.isAncestor(path, of: paddockConfigDirectory)
            || Self.isAncestor(paddockConfigDirectory, of: path) {
            throw .overlapsPaddockConfig
        }
        // Case-insensitive, like the Mac's usual volumes: `~/.SSH` is `~/.ssh`.
        let lowered = path.lowercased()
        for entry in Self.sensitiveEntries {
            let root = (home + "/" + entry).lowercased()
            if lowered == root || lowered.hasPrefix(root + "/") {
                if allowingLogs, isInsideLogs(path) { continue }
                throw .insideSensitiveEntry(entry)
            }
        }
        for entry in Self.sensitiveEntries
        where FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(entry)) {
            throw .containsSensitiveEntry(entry)
        }
    }

    static func canonical(_ path: String) -> String {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        return resolved.count > 1 && resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
    }

    /// True when `ancestor` is a strict parent of `path` (component-wise, so `/a/b` is not a parent of `/a/bc`).
    static func isAncestor(_ ancestor: String, of path: String) -> Bool {
        if ancestor == "/" { return path != "/" }
        return path.hasPrefix(ancestor + "/")
    }
}
