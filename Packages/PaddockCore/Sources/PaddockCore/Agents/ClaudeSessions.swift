import Foundation

/// Why Claude's sessions folder cannot be mounted.
public enum ClaudeSessionsProblem: Error, Equatable, CustomStringConvertible {
    /// A part of the folder's path inside Paddock's data folder is a link or not a folder.
    case notPaddocksFolder(String)
    case folder(FolderPolicyViolation)
    case cannotCreate(String)
    /// sbx mounted something else at the sessions path (another project's sessions, or sbx's own
    /// folder that every sandbox with the kit shares).
    case mountedElsewhere(String?)

    public var description: String {
        switch self {
        case .notPaddocksFolder(let path): "\(path) is a link or not a folder; Paddock mounts only a folder it made"
        case .folder(let violation): violation.description
        case .cannotCreate(let message): "the sessions folder cannot be made: \(message)"
        case .mountedElsewhere(let host): "sbx mounted \(host ?? "nothing") at Claude's sessions, not the project's folder"
        }
    }
}

/// Claude Code's sessions (`~/.claude/projects`: what `claude --resume` finds) kept on this Mac,
/// when the operator chose so for a project (PAD-127, backlog doc Security rules, Claude sessions).
/// A sandbox loses them at every recreate otherwise; sbx 0.51 keeps no volume across one.
///
/// A mixin kit declares `host-mount@1` at `target`, and `sbx create --mount` gives it the project's
/// own folder in Paddock's data folder. Without `--mount`, sbx would use a folder of its own that
/// every sandbox with the kit shares, so the kit never goes without one, and the mount is read back.
/// The agent writes the folder, links included (they show as links on the Mac), so Paddock never
/// follows anything in it.
public enum ClaudeSessions {
    /// Where Claude Code keeps its sessions in the sandbox.
    public static let target = "/home/agent/.claude/projects"
    static let directoryName = "paddock-claude-sessions"

    public static func kitDirectory(in paths: PaddockPaths) -> String {
        paths.kits + "/" + directoryName
    }

    public static var spec: String {
        #"""
        # syntax=docker/sandbox-kit:3
        # Written by Paddock. Changes are overwritten when Paddock creates a sandbox.
        schemaVersion: "3"
        kind: mixin
        version: "\#(KitFile.version)"
        displayName: Claude sessions on this Mac (Paddock)
        description: Keeps Claude Code's sessions in a folder on the Mac, so a recreated sandbox keeps them.
        provides: [paddock-claude-sessions]

        capabilities:
          - type: com.docker.sandbox/host-mount@1
            config:
              path: \#(target)
        """#
    }

    @discardableResult
    public static func installKit(in paths: PaddockPaths) throws -> String {
        try KitFile.write(spec, to: kitDirectory(in: paths))
    }

    /// The project's folder: `<data>/sessions/<project>/claude`.
    public static func folder(project: String, paths: PaddockPaths) -> String {
        paths.sessions + "/" + project + "/claude"
    }

    /// `sbx create --mount` for the folder.
    public static func mountArgument(folder: String) -> String {
        folder + ":" + target
    }

    /// Makes the project's folder if missing (owner only) and checks it before every create: from
    /// Paddock's data folder down, each part a real folder, not a link; and the folder passes
    /// `FolderPolicy` (not the home folder, nothing sensitive, not overlapping Paddock's config).
    public static func prepare(project: String, paths: PaddockPaths, policy: FolderPolicy) throws(ClaudeSessionsProblem) -> String {
        let folder = folder(project: project, paths: paths)
        // What is above Paddock's data folder (`~/.local/share`) is the operator's: made when
        // missing, not judged; from Paddock's data folder down every part is checked.
        let above = (paths.dataDirectory as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: above) {
            do {
                try FileManager.default.createDirectory(atPath: above, withIntermediateDirectories: true)
            } catch {
                throw .cannotCreate(error.localizedDescription)
            }
        }
        var path = paths.dataDirectory
        let parts = String(folder.dropFirst(paths.dataDirectory.count)).split(separator: "/")
        for part in [""] + parts.map(String.init) {
            if !part.isEmpty { path += "/" + part }
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil { throw .notPaddocksFolder(path) }
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) {
                guard isFolder.boolValue else { throw .notPaddocksFolder(path) }
            } else {
                do {
                    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false,
                                                            attributes: [.posixPermissions: 0o700])
                } catch {
                    throw .cannotCreate(error.localizedDescription)
                }
            }
        }
        do throws(FolderPolicyViolation) {
            try policy.check(folder)
        } catch {
            throw .folder(error)
        }
        return folder
    }

    /// The Mac folder sbx mounts at `target`, from `SbxSandbox.mounts`; nil when none.
    public static func mounted(in mounts: [String]) -> String? {
        for mount in mounts {
            let entry = mount.hasSuffix(":ro") ? String(mount.dropLast(3)) : mount
            if entry.hasSuffix(":" + target) { return String(entry.dropLast(target.count + 1)) }
        }
        return nil
    }

    /// How many sessions the folder holds and their size, without following links; nil when the
    /// folder is missing.
    public struct Summary: Sendable, Equatable {
        public let sessions: Int
        public let bytes: Int64
    }

    public static func summary(folder: String) -> Summary? {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isFolder), isFolder.boolValue else { return nil }
        var sessions = 0
        var bytes: Int64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        // The enumerator does not descend into links to folders.
        let items = FileManager.default.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: keys)
        while let url = items?.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            bytes += Int64(values.fileSize ?? 0)
            if url.pathExtension == "jsonl" { sessions += 1 }
        }
        return Summary(sessions: sessions, bytes: bytes)
    }

    /// Removes everything in the folder and keeps the folder. A link is removed as a link: what it
    /// points to is never touched.
    public static func clear(folder: String) throws {
        let manager = FileManager.default
        for name in try manager.contentsOfDirectory(atPath: folder) {
            try manager.removeItem(atPath: folder + "/" + name)
        }
    }
}
