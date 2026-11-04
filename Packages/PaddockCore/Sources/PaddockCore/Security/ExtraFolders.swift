import Foundation

/// Why a folder cannot be a project's extra folder.
public enum ExtraFolderProblem: Error, Equatable, CustomStringConvertible {
    case folder(FolderPolicyViolation)
    /// The project folder, or a folder inside or around it: it is mounted already.
    case overlapsProject
    /// Inside or around another of the project's extra folders.
    case overlapsExtra(String)
    /// sbx reads `PATH:ro`, so a colon in the path would change what it mounts.
    case colon

    public var description: String {
        switch self {
        case .folder(let violation): violation.description
        case .overlapsProject: "the folder is, holds, or is inside the project folder"
        case .overlapsExtra(let path): "the folder is, holds, or is inside the extra folder \(path)"
        case .colon: "a folder with a colon in its path cannot be mounted"
        }
    }
}

/// A project's extra folders (backlog doc Security rules, PAD-73.5): folders mounted besides the
/// project folder, at their own path, read-only unless the operator chose otherwise. Only the
/// operator adds one, in Paddock (never from a file in the project), and each is checked like a
/// project folder (`FolderPolicy`), when added and again at every create.
public enum ExtraFolders {
    /// `folder` checked for `project` (its other extra folders excluded `except`); returns it canonical.
    public static func check(_ folder: String, for project: Project, policy: FolderPolicy,
                             except: String? = nil) throws(ExtraFolderProblem) -> String {
        let path = FolderPolicy.canonical(folder)
        guard !path.contains(":") else { throw .colon }
        do throws(FolderPolicyViolation) {
            try policy.check(path)
        } catch {
            throw .folder(error)
        }
        let projectFolder = FolderPolicy.canonical(project.folder)
        if overlaps(path, projectFolder) { throw .overlapsProject }
        for extra in project.extraFolders where extra.path != except && overlaps(path, FolderPolicy.canonical(extra.path)) {
            throw .overlapsExtra(extra.path)
        }
        return path
    }

    /// Every extra folder of `project` checked again (a folder can change after it was added, or
    /// become a link); the first problem stops a create.
    public static func checkAll(_ project: Project, policy: FolderPolicy) throws(ExtraFolderProblem) -> [Project.ExtraFolder] {
        var checked: [Project.ExtraFolder] = []
        for extra in project.extraFolders {
            var others = project
            others.extraFolders = checked
            checked.append(Project.ExtraFolder(path: try check(extra.path, for: others, policy: policy), readOnly: extra.readOnly))
        }
        return checked
    }

    /// What `sbx create` takes after the project folder: `PATH`, or `PATH:ro`.
    public static func argument(_ folder: Project.ExtraFolder) -> String {
        folder.readOnly ? folder.path + ":ro" : folder.path
    }

    /// The extra folders a sandbox has, from sbx's `workspaces` (the project folder first, then
    /// these, `:ro` when read-only). sbx's own read-only mount of an environment file is left out.
    public static func inSandbox(_ workspaces: [String]) -> [Project.ExtraFolder] {
        workspaces.dropFirst().compactMap { entry in
            let readOnly = entry.hasSuffix(":ro")
            let path = readOnly ? String(entry.dropLast(3)) : entry
            if path.hasSuffix("/" + SbxEnvFile.fileName) { return nil }
            return Project.ExtraFolder(path: path, readOnly: readOnly)
        }
    }

    /// The other project whose folder this is, if any: the agent could change that project's files.
    public static func otherProject(_ path: String, in projects: [Project], except name: String) -> String? {
        let canonical = FolderPolicy.canonical(path)
        return projects.first { $0.name != name && FolderPolicy.canonical($0.folder) == canonical }?.name
    }

    static func overlaps(_ a: String, _ b: String) -> Bool {
        a == b || FolderPolicy.isAncestor(a, of: b) || FolderPolicy.isAncestor(b, of: a)
    }
}
