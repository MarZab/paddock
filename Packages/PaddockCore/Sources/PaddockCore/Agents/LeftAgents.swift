import Foundation

/// Agents Paddock left running (PAD-153; backlog doc UI, Agents left running). When Paddock quits,
/// or an agent tab closes, only `sbx` on the Mac ends: the agent in the sandbox keeps running with
/// no terminal, and sbx cannot attach to it again. The status kit reports each agent's session,
/// tab, and process (`AgentState`), so Paddock finds the ones it opened, resumes their conversation
/// in a new tab (`resumeArguments`), and stops the old process (`stopCommand`).
///
/// Only tabs this app opened count (`OpenedTabs`): Paddock Dev and the installed Paddock share
/// sandboxes, and an agent started outside Paddock is someone's terminal.
public enum LeftAgents {
    /// The sessions left running: their tab is one this app opened and no longer has open, and the
    /// kit knows their process (the watcher ends them once it is gone). Oldest state first.
    public static func find(states: AgentStates, openTabs: Set<UUID>, opened: OpenedTabs, project: String) -> [AgentState] {
        states.sessions.values
            .filter { state in
                guard let tab = state.tab, state.pid != nil, state.kind != .ended else { return false }
                return !openTabs.contains(tab) && opened.contains(tab, in: project)
            }
            .sorted { ($0.time, $0.session) < ($1.time, $1.session) }
    }

    /// The agent's arguments for a new agent tab that takes the session over (`sbx run --name N --
    /// ARGS`): Claude's own session by its id, else the agent's most recent one. Only a Claude
    /// session id that is a UUID is passed on, so nothing from the sandbox becomes an option.
    public static func resumeArguments(_ state: AgentState) -> [String] {
        switch state.agent {
        case .claude:
            if let id = UUID(uuidString: state.session) { return ["--resume", id.uuidString.lowercased()] }
            return ["--continue"]
        case .opencode:
            return ["--continue"]
        case nil:
            return []
        }
    }

    /// Ends a left-running session's process, only while it is still that session: its environment
    /// has the tab's `PADDOCK_TAB` (a reused pid has another). TERM, then KILL after five seconds.
    /// Nil for a session without a tab or a process.
    public static func stopCommand(sandbox: String, state: AgentState) -> [String]? {
        guard let tab = state.tab, let pid = state.pid, pid > 1 else { return nil }
        return ["exec", sandbox, "sh", "-c", stopScript, "paddock-stop", String(pid), "tab", tab.uuidString]
    }

    /// Ends a sandbox process the operator picked in its Processes tab, only while its pid still
    /// has the same name (`comm`). Nil for pid 1 (it would end the sandbox) or a name that is not
    /// a process name.
    public static func stopProcessCommand(sandbox: String, pid: Int32, name: String) -> [String]? {
        guard pid > 1, !name.isEmpty, name.utf8.count <= 64,
              name.allSatisfy({ !$0.isNewline && $0 != "\0" }) else { return nil }
        return ["exec", sandbox, "sh", "-c", stopScript, "paddock-stop", String(pid), "name", name]
    }

    /// `$1` the pid, `$2` what identifies it (`tab` or `name`), `$3` its value, `$4` tenths of a second
    /// to wait after TERM before KILL (50 when not given). Prints `stopped`, or
    /// `gone` when it already ended; exits 3 when the pid is another process now. Needs only sh,
    /// cat, tr, kill, and sleep.
    static let stopScript = #"""
        pid=$1; how=$2; want=$3
        case "$pid" in ""|*[!0-9]*|0|1) echo "not a process" >&2; exit 2 ;; esac
        [ -d "/proc/$pid" ] || { echo gone; exit 0; }
        if [ "$how" = tab ]; then
          nl='
        '
          env=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null)
          case "$nl$env$nl" in *"${nl}PADDOCK_TAB=$want$nl"*) ;; *) echo "process $pid is another session now" >&2; exit 3 ;; esac
        else
          [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = "$want" ] || { echo "process $pid is not $want now" >&2; exit 3; }
        fi
        # Running: its /proc entry is there and not a zombie (ended, waiting for its parent).
        alive() {
          line=$(cat "/proc/$pid/stat" 2>/dev/null) || return 1
          rest=${line##*) }
          [ "${rest%% *}" != Z ]
        }
        kill -TERM "$pid" 2>/dev/null || { echo gone; exit 0; }
        i=0
        grace=${4:-50}
        case "$grace" in ""|*[!0-9]*) grace=50 ;; esac
        while [ "$i" -lt "$grace" ] && alive; do sleep 0.1; i=$((i + 1)); done
        alive && kill -KILL "$pid" 2>/dev/null
        echo stopped
        """#
}

/// The agent tabs this app opened, per project, so `LeftAgents` knows its own (PAD-153). Kept in
/// Paddock's data folder, one file per app: Paddock Dev and the installed Paddock share that
/// folder and the sandboxes, and each must leave the other's agents alone.
public struct OpenedTabs: Codable, Sendable, Equatable {
    /// Project name to tab id to when it was opened.
    public private(set) var projects: [String: [UUID: Date]] = [:]

    /// How long a tab is remembered without its session being seen.
    public static let kept: TimeInterval = 14 * 86_400

    public init() {}

    public func contains(_ tab: UUID, in project: String) -> Bool {
        projects[project]?[tab] != nil
    }

    public mutating func add(_ tab: UUID, in project: String, at date: Date) {
        projects[project, default: [:]][tab] = date
    }

    /// Forgets the project's tabs that no reported session names and that are older than `kept`,
    /// and the tabs of projects that are gone. A tab whose session still runs stays, however old.
    public mutating func prune(project: String, reported: Set<UUID>, now: Date) {
        guard var tabs = projects[project] else { return }
        tabs = tabs.filter { reported.contains($0.key) || now.timeIntervalSince($0.value) < Self.kept }
        projects[project] = tabs.isEmpty ? nil : tabs
    }

    public mutating func keepOnly(projects names: Set<String>) {
        projects = projects.filter { names.contains($0.key) }
    }

    /// `<data folder>/tabs/<bundle id>.json`; nil for a bundle id that is not a plain reverse-DNS name.
    public static func path(in paths: PaddockPaths, bundleID: String) -> String? {
        guard !bundleID.isEmpty, bundleID.utf8.count <= 128, !bundleID.hasPrefix("."), !bundleID.contains(".."),
              bundleID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else { return nil }
        return paths.dataDirectory + "/tabs/" + bundleID + ".json"
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// What the file holds; empty when it is missing or unreadable.
    public static func load(from path: String) -> OpenedTabs {
        guard let data = FileManager.default.contents(atPath: path),
              let tabs = try? decoder.decode(OpenedTabs.self, from: data) else { return OpenedTabs() }
        return tabs
    }

    /// Writes the file atomically, owner-only.
    public func save(to path: String) throws {
        let folder = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try Self.encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}
