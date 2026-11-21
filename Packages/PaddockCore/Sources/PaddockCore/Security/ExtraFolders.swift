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
        try check(folder, projectFolder: project.folder, extraFolders: project.extraFolders.map(\.path),
                  policy: policy, except: except)
    }

    /// The same check for a project not saved yet (New Project's draft): its folder, and the extra
    /// folders it has so far.
    public static func check(_ folder: String, projectFolder: String, extraFolders: [String], policy: FolderPolicy,
                             except: String? = nil) throws(ExtraFolderProblem) -> String {
        let path = FolderPolicy.canonical(folder)
        guard !path.contains(":") else { throw .colon }
        do throws(FolderPolicyViolation) {
            // The operator's own extra folder may be inside ~/Library/Logs, read-only (PAD-125).
            try policy.check(path, allowingLogs: true)
        } catch {
            throw .folder(error)
        }
        if overlaps(path, FolderPolicy.canonical(projectFolder)) { throw .overlapsProject }
        for extra in extraFolders where extra != except && overlaps(path, FolderPolicy.canonical(extra)) {
            throw .overlapsExtra(extra)
        }
        return path
    }

    /// What the operator pasted or typed into an extra folder field (PAD-124) as a full path, or nil
    /// when it is none. Takes a full path, `~` or `~/...`, a `file://` URL, Finder's Copy as Pathname
    /// (quoted when it has spaces), and a path a terminal escaped (`My\ Folder`). Says nothing about
    /// whether the folder may be mounted: that is `check`, after this.
    public static func path(fromInput input: String, home: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for quote in ["\"", "'"] where text.count >= 2 && text.hasPrefix(quote) && text.hasSuffix(quote) {
            text = String(text.dropFirst().dropLast())
        }
        if text.hasPrefix("file://") {
            // This Mac's files only: no host, or localhost.
            guard let url = URL(string: text), url.isFileURL, [nil, "", "localhost"].contains(url.host) else { return nil }
            text = url.path
        } else if text.contains("\\") {
            // A terminal's escapes: a backslash keeps the next character as it is.
            var unescaped = ""
            var escaping = false
            for character in text {
                if escaping || character != "\\" {
                    unescaped.append(character)
                    escaping = false
                } else {
                    escaping = true
                }
            }
            text = unescaped
        }
        if text == "~" {
            text = home
        } else if text.hasPrefix("~/") {
            text = home + text.dropFirst()
        }
        guard text.hasPrefix("/"), !text.contains("\0") else { return nil }
        return text.count > 1 && text.hasSuffix("/") ? String(text.dropLast()) : text
    }

    /// Every extra folder of `project` checked again (a folder can change after it was added, or
    /// become a link); the first problem stops a create.
    public static func checkAll(_ project: Project, policy: FolderPolicy) throws(ExtraFolderProblem) -> [Project.ExtraFolder] {
        var checked: [Project.ExtraFolder] = []
        for extra in project.extraFolders {
            var others = project
            others.extraFolders = checked
            let path = try check(extra.path, for: others, policy: policy)
            checked.append(Project.ExtraFolder(path: path, readOnly: readOnly(extra.readOnly, path: path, policy: policy)))
        }
        return checked
    }

    /// Whether a folder is mounted read-only: as asked, and always inside `~/Library/Logs`
    /// (PAD-125), whatever a project file says.
    public static func readOnly(_ requested: Bool, path: String, policy: FolderPolicy) -> Bool {
        requested || policy.isInsideLogs(path)
    }

    /// Whether the operator may switch a folder to `readOnly`: anything but writable inside
    /// `~/Library/Logs`, which `readOnly(_:path:policy:)` would mount read-only anyway.
    public static func allows(readOnly requested: Bool, path: String, policy: FolderPolicy) -> Bool {
        readOnly(requested, path: path, policy: policy) == requested
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
