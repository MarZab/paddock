import Foundation

/// A shell in the operator's own terminal app (the toolbar's shell menu): in a project's sandbox,
/// the same `sbx exec -it N bash` as the shell tab, or on the Mac in the project folder. Paddock
/// writes it as a `.command` file and opens that, so macOS starts the app `.command` files open
/// with (Terminal by default), without asking for Automation access.
public enum ExternalShell {
    public enum Problem: Error, Equatable, CustomStringConvertible {
        case invalidSandboxName(String)

        public var description: String {
            switch self {
            case .invalidSandboxName(let name): "\(name) is not a valid sandbox name"
            }
        }
    }

    /// The `.command` file's script. Every value is single-quoted for the shell, and the sandbox
    /// name must be one sbx accepts.
    public static func script(sbx: String, sandbox: String) throws(Problem) -> String {
        guard ProjectList.isValidSandboxName(sandbox) else { throw .invalidSandboxName(sandbox) }
        return """
            #!/bin/sh
            # Written by Paddock: a shell in the sandbox \(sandbox).
            rm -f "$0"
            exec \(quoted(sbx)) exec -it \(quoted(sandbox)) bash

            """
    }

    /// The file name for a sandbox's script, in a folder of Paddock's own.
    public static func fileName(sandbox: String) -> String { "paddock-shell-\(sandbox).command" }

    /// A login shell on the Mac in the project folder: the operator's own shell (`$SHELL`, which
    /// the terminal app sets), not a sandbox. The folder is single-quoted for the shell.
    public static func hostScript(folder: String, project: String) throws(Problem) -> String {
        guard ProjectList.isValidSandboxName(project) else { throw .invalidSandboxName(project) }
        return """
            #!/bin/sh
            # Written by Paddock: a shell on this Mac in the folder of \(project).
            rm -f "$0"
            cd \(quoted(folder)) || exit 1
            exec "${SHELL:-/bin/zsh}" -l

            """
    }

    /// The file name for a project's host shell script.
    public static func hostFileName(project: String) -> String { "paddock-host-shell-\(project).command" }

    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
