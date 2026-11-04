import Foundation

/// The files Paddock writes for a project's sandbox when the operator asks (New Project's "Create
/// sbxenv.yaml"): `sbxenv.yaml` at the root and a v3 mixin kit at `tools/sandbox/<kit>/<kit>.yaml`
/// (backlog doc Project config file). The files name nothing of Paddock's: what an agent should
/// know about Paddock's rules and the build-output guidance (PAD-71) is the agent-context of
/// Paddock's `status` kit (`SandboxGuide`). Everything generated passes `ProjectEnvironment`'s checks.
public enum SandboxFiles {
    public struct File: Sendable, Equatable {
        /// Relative to the project folder.
        public var path: String
        public var contents: String
        /// Written with the execute bit (a script the operator runs).
        public var executable = false
    }

    /// What goes into the files.
    public struct Input: Sendable, Equatable {
        /// The sandbox's name (shared by `sbx env run` and Paddock).
        public var name: String
        /// sbx's agent name for the workload (a v3 workload's is its repository name).
        public var agent: String
        /// The agent's v3 workload kit reference, or nil for an sbx agent that names its own
        /// (`claude` is `docker.io/sbx/claude` in sbx 0.51, backlog doc M0 findings).
        public var workload: String?
        public var publish: [Int]
        public var allow: [String]
        public var deny: [String]

        public init(name: String, agent: String, workload: String? = nil, publish: [Int] = [],
                    allow: [String] = [], deny: [String] = []) {
            self.name = name
            self.agent = agent
            self.workload = workload
            self.publish = publish
            self.allow = allow
            self.deny = deny
        }
    }

    public enum WriteError: Error, Equatable, CustomStringConvertible {
        case exists(String)

        public var description: String {
            switch self {
            case .exists(let path): "\(path) exists already; Paddock does not overwrite a project's files"
            }
        }
    }

    public static let docsURL = "https://docs.docker.com/ai/sandboxes/"
    public static let environmentFilesURL = "https://docs.docker.com/ai/sandboxes/configuration/environment-files/"
    public static let kitsURL = "https://docs.docker.com/ai/sandboxes/customize/kits-v2/"
    public static let kitSpecURL = "https://github.com/docker/sandbox-kit-spec"

    /// The kit's folder name: the sandbox name as a kit name (lowercase letters, digits, hyphens).
    public static func kitName(for name: String) -> String {
        var cleaned = ""
        for scalar in name.lowercased().unicodeScalars {
            if CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains(scalar) {
                cleaned.unicodeScalars.append(scalar)
            } else if !cleaned.isEmpty, !cleaned.hasSuffix("-") {
                cleaned += "-"
            }
        }
        while cleaned.hasSuffix("-") { cleaned.removeLast() }
        return cleaned.isEmpty ? "project" : cleaned
    }

    public static func kitPath(for name: String) -> String { "tools/sandbox/\(kitName(for: name))" }

    /// The helper for trying the project's files, beside the kit's folder.
    public static let runScriptPath = "tools/sandbox/run.sh"

    public static func files(_ input: Input) -> [File] {
        let kit = kitName(for: input.name)
        return [
            File(path: SbxEnvFile.fileName, contents: environmentFile(input, kitPath: "./" + kitPath(for: input.name))),
            File(path: "\(kitPath(for: input.name))/\(kit).yaml", contents: kitFile(input)),
            File(path: runScriptPath, contents: runScript, executable: true),
        ]
    }

    /// Writes `files` into `folder`; refuses before writing anything when one exists.
    public static func write(_ files: [File], into folder: String) throws {
        let manager = FileManager.default
        for file in files where manager.fileExists(atPath: folder + "/" + file.path) {
            throw WriteError.exists(file.path)
        }
        for file in files {
            let path = folder + "/" + file.path
            try manager.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try Data(file.contents.utf8).write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)
            if file.executable { try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }
        }
    }

    // MARK: - The files

    private static func quoted(_ text: String) -> String { PaddockOverlay.quoted(text) }

    static func environmentFile(_ input: Input, kitPath: String) -> String {
        var lines = [
            "# This project's sandbox, as an sbx environment file (\(environmentFilesURL)).",
            "# Run it with `sbx env run` in this folder (sbx 0.51 or later).",
            "schemaVersion: \(quoted(SbxEnvFile.schemaVersion))",
            "name: \(quoted(input.name))",
            "agent: \(quoted(input.agent))",
            "workspace: \".\"",
            "",
            "kits:",
        ]
        if let workload = input.workload {
            lines.append("  - \(quoted(workload))")
        }
        lines += [
            "  # This project's own kit: tools, hosts, and what the agent should know.",
            "  - \(quoted(kitPath))",
        ]
        if !input.publish.isEmpty {
            lines += ["", "# Sandbox ports published on this Mac's 127.0.0.1.", "ports:"]
            lines += input.publish.map { "  - { sandbox: \($0), host: \($0) }" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Runs the project's files the way the app that manages them does, by hand from a terminal on
    /// the Mac: its sandbox name and, when the file exists, the overlay it adds. This script is the
    /// one generated file that names that overlay's folder; it is a default, set by RUN_SANDBOX_OVERLAY.
    static let runScript = #"""
        #!/bin/sh
        #MISE description="Plan, create, or run this project's sandbox as its manager does"
        # Usage: tools/sandbox/run.sh [plan|create|run|rm]   (default: plan)
        #   plan    what the files would change; changes nothing
        #   create  make the sandbox
        #   run     create it if needed and attach
        #   rm      remove it
        # It uses the name in sbxenv.yaml and, when it exists, the overlay the manager keeps in
        # ~/.config/paddock/projects/NAME.sbxenv.yaml, so the sandbox is the one it would create.
        # create and run pass --force: they REPLACE a sandbox of that name. To try without that, set
        # RUN_SANDBOX_NAME=other. RUN_SANDBOX_OVERLAY=FILE picks another overlay; empty means none.
        # Nothing from the files runs on this Mac (--skip-host-commands).
        # A mise file task as well: with `[task_config] includes = ["tools/sandbox"]` in mise.toml,
        # `mise tasks` lists it and `mise run` runs it, arguments after `--`.
        set -eu
        cd "$(dirname "$0")/../.."
        cmd="${1:-plan}"
        name="${RUN_SANDBOX_NAME:-$(sed -n 's/^name: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' sbxenv.yaml | head -n 1)}"
        [ -n "$name" ] || { echo "no name: in sbxenv.yaml; set RUN_SANDBOX_NAME" >&2; exit 1; }
        overlay="${RUN_SANDBOX_OVERLAY-${XDG_CONFIG_HOME:-$HOME/.config}/paddock/projects/$name.sbxenv.yaml}"
        if [ -f "$overlay" ]; then set -- sbxenv.yaml "$overlay"; else set -- sbxenv.yaml; fi
        echo "sandbox $name from: $*" >&2
        case "$cmd" in
          plan) sbx env plan "$@" --name "$name" ;;
          create) sbx env create "$@" --name "$name" --skip-host-commands --force ;;
          run) sbx env run "$@" --name "$name" --skip-host-commands ;;
          rm) sbx env rm "$@" --name "$name" ;;
          *) echo "usage: $0 plan|create|run|rm" >&2; exit 2 ;;
        esac

        """#

    static func kitFile(_ input: Input) -> String {
        let kit = kitName(for: input.name)
        var lines = [
            "# syntax=docker/sandbox-kit:3",
            "# This project's own sbx kit, a v3 mixin over the agent's workload (\(kitSpecURL)).",
            "# Files and environment it adds go in a \(kit).dockerfile beside this file (its last stage",
            "# FROM scratch; only what it copies in is added). System packages go in an install hook.",
            "# sbx reads a kit only when it creates the sandbox: a change needs a recreate.",
            "schemaVersion: \"3\"",
            "kind: mixin",
            "displayName: \(quoted(input.name))",
            "version: \"0.1.0\"  # sbx requires a version for provides; bump it with each change",
            "provides: [\(quoted(kit))]",
            "",
            "capabilities:",
        ]
        if input.allow.isEmpty && input.deny.isEmpty {
            lines[lines.count - 1] = "capabilities: []  # tools, hosts, and notes for the agent go here (\(kitsURL))"
        } else {
            lines += ["  - type: com.docker.sandbox/network-policy@2", "    config:", "      runtime:"]
            if !input.allow.isEmpty { lines.append("        allow: [\(input.allow.map(quoted).joined(separator: ", "))]") }
            if !input.deny.isEmpty { lines.append("        deny: [\(input.deny.map(quoted).joined(separator: ", "))]") }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
