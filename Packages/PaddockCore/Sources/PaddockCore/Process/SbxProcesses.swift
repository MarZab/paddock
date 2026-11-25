import Foundation

/// sbx's and Paddock's processes on the Mac, by what they are (backlog doc UI, Processes; PAD-31).
/// Leftover sbx tools cost a lot unnoticed: four `sbx` dashboards whose terminals were gone ran for
/// four days at up to 1.3 cores. Only the current user's processes, and only sbx's and Paddock's:
/// anything else is Activity Monitor's.
public enum SbxProcessKind: Sendable, Equatable {
    /// A watcher of this or another running Paddock (`SandboxWatchers`).
    case watcher
    /// A watcher whose Paddock is gone; Paddock stops these itself at launch.
    case leftoverWatcher
    /// An sbx command whose parent is gone (a closed terminal): a dashboard, an `exec`, a `run`.
    case orphanedTool
    /// An sbx command with its parent (a terminal) still there.
    case toolInUse
    case daemon
    case llmman
    /// A sandbox's virtual machine, by the container ID sbx gives it.
    case sandboxVM(containerID: String)
    /// Another of sbx's helpers (Sbx.app's own programs).
    case helper(String)

    /// Only these may be stopped from Paddock: they have no terminal or app left to stop them.
    public var isStoppable: Bool {
        switch self {
        case .orphanedTool, .leftoverWatcher: true
        default: false
        }
    }
}

public struct SbxProcess: Sendable, Equatable, Identifiable {
    public let process: HostProcess
    public let kind: SbxProcessKind
    public var id: Int32 { process.pid }

    /// The sandbox an sbx command or watcher works on (PAD-154), which for Paddock is its project;
    /// nil for the rest. A sandbox machine has none: sbx does not link its container id to a sandbox.
    public var sandbox: String? {
        switch kind {
        case .orphanedTool, .toolInUse, .watcher, .leftoverWatcher: SbxProcesses.sandbox(of: process.command)
        case .daemon, .llmman, .sandboxVM, .helper: nil
        }
    }
}

public enum SbxProcesses {
    /// The current user's sbx-related processes, by kind; everything else is left out.
    public static func classify(_ processes: [HostProcess], user: String) -> [SbxProcess] {
        processes.compactMap { process in
            guard process.user == user, let kind = kind(of: process) else { return nil }
            return SbxProcess(process: process, kind: kind)
        }
    }

    /// The options that take a value, so the word after them is not the sandbox: `sbx exec`'s (as
    /// its help lists them; sbx's global options take none).
    static let execValueOptions: Set<String> = ["-e", "--env", "--env-file", "-u", "--user", "-w", "--workdir", "--detach-keys"]

    /// The sandbox in an `sbx exec [OPTIONS] SANDBOX ...` or `sbx run ... --name SANDBOX` command
    /// line (as `ps` prints it, words split on spaces); nil for other commands, a `--cloud` one (no
    /// local sandbox), or a `run` without `--name`.
    public static func sandbox(of command: String) -> String? {
        let words = command.split(separator: " ").map(String.init)
        guard let first = words.first, (first as NSString).lastPathComponent == "sbx" else { return nil }
        var rest = words.dropFirst()
        // Global options come before the command.
        while let word = rest.first, word.hasPrefix("-") {
            if word == "--cloud" { return nil }
            rest = rest.dropFirst()
        }
        guard let verb = rest.first else { return nil }
        rest = rest.dropFirst()
        switch verb {
        case "run":
            var iterator = rest.makeIterator()
            while let word = iterator.next() {
                if word == "--" { return nil }
                if word == "--name" { return iterator.next().flatMap(plainName) }
                if word.hasPrefix("--name=") { return plainName(String(word.dropFirst("--name=".count))) }
            }
            return nil
        case "exec":
            var iterator = rest.makeIterator()
            while let word = iterator.next() {
                guard word.hasPrefix("-") else { return plainName(word) }
                if word.contains("=") { continue }
                // `-e X`, `--user X`, and short flags together ending in one that takes a value (`-iu X`).
                let takesValue = execValueOptions.contains(word)
                    || (!word.hasPrefix("--") && word.count > 2 && execValueOptions.contains("-" + String(word.suffix(1))))
                if takesValue { _ = iterator.next() }
            }
            return nil
        default:
            return nil
        }
    }

    /// A sandbox name as sbx takes it; nil for anything else.
    static func plainName(_ word: String) -> String? {
        guard !word.isEmpty, word.utf8.count <= 128, !word.hasPrefix("-"),
              word.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }) else { return nil }
        return word
    }

    static func kind(of process: HostProcess) -> SbxProcessKind? {
        let words = process.command.split(separator: " ").map(String.init)
        guard let first = words.first else { return nil }
        let program = (first as NSString).lastPathComponent
        if program == "sbx" {
            if SandboxWatchers.isWatcherExec(process.command) { return process.isOrphan ? .leftoverWatcher : .watcher }
            // `sbx daemon start` belongs to launchd by design; global options come before the command.
            if words.dropFirst().first(where: { !$0.hasPrefix("-") }) == "daemon" { return .daemon }
            return process.isOrphan ? .orphanedTool : .toolInUse
        }
        guard first.contains("/Sbx.app/Contents/") else { return nil }
        if program == "llmman" { return .llmman }
        if program.hasPrefix("containerd-shim"), let index = words.firstIndex(of: "-id"), index + 1 < words.count {
            return .sandboxVM(containerID: words[index + 1])
        }
        return .helper(program)
    }

    /// Stops `chosen` with SIGTERM, each only if it is still the same stoppable process: the list is
    /// read again first, so a pid reused since (by anything) is never signalled. Returns the stopped.
    public static func stop(_ chosen: [SbxProcess], runner: ProcessRunner, user: String,
                            signal: (Int32) -> Bool = { kill($0, SIGTERM) == 0 }) async throws -> [SbxProcess] {
        let now = classify(try await HostProcesses.read(runner: runner), user: user)
        let still = Dictionary(now.map { ($0.process.pid, $0) }, uniquingKeysWith: { first, _ in first })
        return chosen.filter { old in
            guard let current = still[old.process.pid], current.kind.isStoppable,
                  current.process.command == old.process.command else { return false }
            return signal(old.process.pid)
        }
    }
}
