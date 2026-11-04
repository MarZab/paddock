import Foundation

/// Paddock's status kit: each agent's own signal for "working", "waiting on you", and "idle",
/// written to one state file in the sandbox that a watcher streams to the app (`AgentState`;
/// backlog doc Kits, Agent status). There is no standard across agents, so the kit installs
/// Claude Code's hooks (code.claude.com/docs/en/hooks) and an OpenCode plugin
/// (opencode.ai/docs/plugins), and both call `paddock-agent-state`.
///
/// The state is display-only data from inside the sandbox: the app checks it against a fixed set of
/// states and never uses it for rules, mounts, or any other decision.
public enum AgentStatusKit {
    /// sbx names a local kit after its folder, and the names in one sandbox must differ, so not
    /// `status` (sbx 0.51 ships an `opencode` kit of its own; PAD-73.2).
    public static let directoryName = "paddock-status"
    /// The helper the hooks and the plugin call: `paddock-agent-state STATE [AGENT]`.
    public static let stateCommand = "paddock-agent-state"
    public static let watchCommand = "paddock-agent-watch"
    public static let stateDirectory = "/tmp/paddock-agent"
    public static let stateFile = stateDirectory + "/state"
    static let opencodePluginPath = "/home/agent/.config/opencode/plugins/paddock-status.js"

    public static func directory(in paths: PaddockPaths) -> String {
        paths.kits + "/" + directoryName
    }

    /// `sbx exec` command Paddock follows; it replaces older watchers there (`SandboxWatchers`).
    public static func watchArguments(sandbox: String) -> [String] { SandboxWatchers.arguments(sandbox: sandbox, command: watchCommand) }

    /// Whether a project's sandbox gets this kit, so Paddock follows its agents.
    public static func isChosen(by project: Project, app: AppConfig) -> Bool {
        project.chosenKits(app).contains { app.kits[$0]?.source == .builtin(.status) }
    }

    /// One file per agent session, `sessions/<session>.json`, holding
    /// `{"session","state","agent","tab","pid","time"}`; `pid` is the agent's process (0 when not found),
    /// so the watcher can tell a session whose agent is gone. The session is Claude Code's `session_id` (read from the
    /// hook's stdin) or the third argument; the tab is `$PADDOCK_TAB`, which the app sets when it opens the
    /// tab (`sbx run -e`). Written atomically, only when the state changed, never prints, never fails (a hook
    /// that prints or exits 2 would change what the agent does).
    static let stateScript = #"""
    #!/bin/sh
    # Written by Paddock. Usage: paddock-agent-state working|waiting|idle|ended [claude|opencode] [SESSION]
    input=""
    [ -t 0 ] || input=$(cat 2>/dev/null)
    state="${1:-}"
    case "$state" in working|waiting|idle|ended) ;; *) exit 0 ;; esac
    case "${2:-}" in claude|opencode) agent="$2" ;; *) agent=unknown ;; esac
    session="${3:-}"
    if [ -z "$session" ]; then
      session=$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[A-Za-z0-9_-]*"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
    fi
    case "$session" in ""|*[!A-Za-z0-9_-]*) session=default ;; esac
    [ "${#session}" -le 64 ] || session=default
    tab="${PADDOCK_TAB:-}"
    case "$tab" in *[!A-Za-z0-9-]*) tab="" ;; esac
    [ "${#tab}" -le 64 ] || tab=""
    # The agent's process: the first parent that is not a shell (the hook's sh -c, say), 0 if none.
    pid=$PPID
    i=0
    while [ "$i" -lt 8 ] && [ -r "/proc/$pid/stat" ]; do
      case "$(cat "/proc/$pid/comm" 2>/dev/null)" in sh|dash|bash|zsh|ash|busybox|env|timeout) ;; *) break ;; esac
      pid=$(sed 's/.*) [A-Za-z] //;s/ .*//' "/proc/$pid/stat" 2>/dev/null)
      i=$((i + 1))
    done
    case "$pid" in ""|*[!0-9]*|0|1) pid=0 ;; esac
    [ -r "/proc/$pid/stat" ] || pid=0
    dir="${PADDOCK_AGENT_DIR:-\#(stateDirectory)}/sessions"
    mkdir -p "$dir" 2>/dev/null || exit 0
    file="$dir/$session.json"
    # The same state from the same process changes nothing (time is when the state began).
    if [ -f "$file" ] && grep -q "\"state\":\"$state\".*\"pid\":$pid," "$file" 2>/dev/null; then exit 0; fi
    tmp="$dir/.$session.$$"
    printf '{"session":"%s","state":"%s","agent":"%s","tab":"%s","pid":%s,"time":%s}\n' \
      "$session" "$state" "$agent" "$tab" "$pid" "$(date +%s)" >"$tmp" 2>/dev/null \
      && mv -f "$tmp" "$file" 2>/dev/null
    exit 0

    """#

    /// Prints every session's line when it changes, and all of them once at start, for `sbx exec`. An
    /// ended session is printed once and forgotten; so is one whose agent process is gone (PAD-64);
    /// a file nobody touched for a day is dropped.
    static let watchScript = #"""
    #!/bin/sh
    # Written by Paddock. Follows the agents' session files.
    dir="${PADDOCK_AGENT_DIR:-\#(stateDirectory)}/sessions"
    mkdir -p "$dir" 2>/dev/null
    seen=$(mktemp -d)
    trap 'rm -rf "$seen"' EXIT
    trap 'exit 0' INT TERM HUP
    while :; do
      for file in "$dir"/*.json; do
        [ -f "$file" ] || continue
        cur=$(cat "$file" 2>/dev/null)
        [ -n "$cur" ] || continue
        id=$(basename "$file" .json)
        # An agent that is gone without saying so (killed, its terminal closed) has ended.
        pid=$(printf '%s' "$cur" | sed -n 's/.*"pid":\([0-9]*\),.*/\1/p')
        if [ -n "$pid" ] && [ "$pid" != 0 ] && [ -d /proc/1 ] && [ ! -d "/proc/$pid" ]; then
          cur=$(printf '%s' "$cur" | sed 's/"state":"[a-z]*"/"state":"ended"/')
        fi
        if [ "$cur" != "$(cat "$seen/$id" 2>/dev/null)" ]; then
          printf '%s\n' "$cur"
          printf '%s' "$cur" >"$seen/$id"
        fi
        case "$cur" in *'"state":"ended"'*) rm -f "$file" "$seen/$id" ;; esac
      done
      find "$dir" -name '*.json' -mmin +1440 -delete 2>/dev/null
      sleep 1
    done

    """#

    /// Claude Code hooks, merged into `~/.claude/settings.json` (hook entries from several settings
    /// levels add up). `PermissionRequest` fires the moment Claude asks; the `Notification`
    /// `permission_prompt` waits about six seconds, so it is not used. A tool's start means
    /// working again after an answer, except the tools that ask the operator something.
    private static func claudeHooks() -> [String: [[String: Any]]] {
        func group(_ state: String, matcher: String? = nil) -> [String: Any] {
            var group: [String: Any] = ["hooks": [["type": "command", "command": "\(stateCommand) \(state) claude", "timeout": 5]]]
            if let matcher { group["matcher"] = matcher }
            return group
        }
        let asking = "AskUserQuestion|ExitPlanMode"
        return [
            "SessionStart": [group("idle")],
            "UserPromptSubmit": [group("working")],
            "PreToolUse": [group("working", matcher: "^(?!(AskUserQuestion|ExitPlanMode)$)"), group("waiting", matcher: asking)],
            "PermissionRequest": [group("waiting")],
            "Notification": [group("waiting", matcher: "elicitation_dialog|elicitation_url_dialog")],
            "PostToolUse": [group("working")],
            "PostToolUseFailure": [group("working")],
            "PermissionDenied": [group("working")],
            "Stop": [group("idle")],
            "StopFailure": [group("idle")],
            "SessionEnd": [group("ended")]
        ]
    }

    static var claudeHooksJSON: String {
        let data = (try? JSONSerialization.data(withJSONObject: claudeHooks(), options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// Adds the hooks to `settings.json` without touching anything else; a hook already there is not
    /// added twice. A settings file that cannot be read is left alone.
    static let claudeMergeScript = NodeScript.wrap(#"""
    const fs = require("fs");
    const path = require("path");
    const file = path.join(process.env.HOME, ".claude", "settings.json");
    const add = JSON.parse(Buffer.from(process.argv[2], "base64").toString());
    let settings = {};
    try {
      settings = JSON.parse(fs.readFileSync(file, "utf8"));
    } catch (error) {
      if (error.code !== "ENOENT") {
        console.error("Paddock: cannot read " + file + "; the status hooks are not installed");
        process.exit(0);
      }
    }
    settings.hooks = settings.hooks || {};
    for (const [event, groups] of Object.entries(add)) {
      const current = (settings.hooks[event] = settings.hooks[event] || []);
      for (const group of groups) {
        if (!current.some((have) => JSON.stringify(have) === JSON.stringify(group))) current.push(group);
      }
    }
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(settings, null, 2) + "\n");

    """#)

    /// OpenCode loads every file in `~/.config/opencode/plugins`. Busy and waiting sessions are tracked by
    /// ID, so a child session going idle does not hide its parent.
    static let opencodePlugin = #"""
    // Written by Paddock. Reports OpenCode's state to paddock-agent-state (display only).
    import { execFile } from "node:child_process"

    export const PaddockStatus = async () => {
      const busy = new Set()
      const waiting = new Set()
      // One entry per OpenCode process (its tab when Paddock started it); its sessions are combined.
      const key = "oc-" + (process.env.PADDOCK_TAB ?? process.pid)
      let last = ""
      const report = () => {
        const next = waiting.size > 0 ? "waiting" : busy.size > 0 ? "working" : "idle"
        if (next === last) return
        last = next
        execFile("\#(stateCommand)", [next, "opencode", key], () => {})
      }
      report()
      return {
        event: async ({ event }) => {
          const props = event.properties ?? {}
          const session = props.sessionID ?? props.info?.id ?? ""
          switch (event.type) {
            case "session.status":
              if (props.status?.type === "idle") busy.delete(session)
              else if (props.status) busy.add(session)
              break
            case "session.idle":
            case "session.error":
            case "session.deleted":
              busy.delete(session)
              waiting.delete(session)
              break
            case "permission.asked":
            case "permission.updated":
            case "question.asked":
              waiting.add(session)
              break
            case "permission.replied":
            case "question.replied":
            case "question.rejected":
              waiting.delete(session)
              break
            default:
              return
          }
          report()
        },
      }
    }

    """#

    public static var spec: String {
        let state = Data(stateScript.utf8).base64EncodedString()
        let watch = Data(watchScript.utf8).base64EncodedString()
        let merge = Data(claudeMergeScript.utf8).base64EncodedString()
        let hooks = Data(claudeHooksJSON.utf8).base64EncodedString()
        let plugin = Data(opencodePlugin.utf8).base64EncodedString()
        // Indented for `content: |` (16 spaces in the file); an interpolation keeps its own indent.
        let guide = SandboxGuide.context.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "                \($0)" }.joined(separator: "\n")
        return #"""
        # syntax=docker/sandbox-kit:3
        # Written by Paddock. Changes are overwritten when Paddock creates a sandbox.
        schemaVersion: "3"
        kind: mixin
        version: "\#(KitFile.version)"
        displayName: Agent status (Paddock)
        description: Tell Paddock when the agent is working, waiting on the operator, or idle, and what to know about this sandbox.
        provides: [paddock-status]

        capabilities:
          - type: com.docker.sandbox/lifecycle@1
            config:
              install:
                - command: |
                    set -eu
                    printf '%s' '\#(state)' | base64 -d > /usr/local/bin/\#(stateCommand)
                    printf '%s' '\#(watch)' | base64 -d > /usr/local/bin/\#(watchCommand)
                    chmod 755 /usr/local/bin/\#(stateCommand) /usr/local/bin/\#(watchCommand)
                  user: "0"
                  description: Install Paddock's agent state helper and watcher
                # After sbx's own Claude kit seeded settings.json (a workload's hooks run first); the
                # merge keeps its hooks and adds Paddock's. HOME is set here: a hook sees only the
                # environment it names.
                - command: |
                    set -eu
                    printf '%s' '\#(merge)' | base64 -d > /tmp/paddock-status-merge.js
                    HOME=/home/agent sh /tmp/paddock-status-merge.js '\#(hooks)' || echo "Paddock: Claude Code hooks not installed" >&2
                    rm -f /tmp/paddock-status-merge.js
                    mkdir -p "$(dirname \#(opencodePluginPath))"
                    printf '%s' '\#(plugin)' | base64 -d > \#(opencodePluginPath)
                  user: "1000"
                  env: [PATH]
                  description: Add the status hooks to Claude Code and the status plugin to OpenCode

          # What the agent should know about this sandbox and Paddock's rules, so a project's own
          # files need not say it (PAD-71, backlog doc Kits). @1, as sbx's own kits use.
          - type: com.docker.sandbox/agent-context@1
            config:
              content: |
        \#(guide)

        """#
    }

    /// Writes the kit if it is missing or differs. Returns the kit directory.
    @discardableResult
    public static func install(in paths: PaddockPaths) throws -> String {
        try KitFile.write(spec, to: directory(in: paths))
    }
}

/// One line of `paddock-agent-watch`: what one agent session says it is doing. Display only;
/// anything the sandbox sends that is not exactly this shape is dropped.
public struct AgentState: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case working
        case waiting
        case idle
        case ended
    }

    public enum Agent: String, Sendable, Equatable {
        case claude
        case opencode
    }

    /// The agent's session (Claude Code's `session_id`, or `oc-` and the tab for OpenCode).
    public let session: String
    public let kind: Kind
    public let agent: Agent?
    /// The tab the app opened the agent in (`PADDOCK_TAB`), when it did.
    public let tab: UUID?
    /// The agent's process in the sandbox, when the kit found it (since PAD-64; nil before), so the
    /// watcher ends the session once it is gone.
    public let pid: Int?
    public let time: Date

    static let maxLineLength = 512

    public init(session: String, kind: Kind, agent: Agent?, tab: UUID?, pid: Int? = nil, time: Date) {
        self.session = session
        self.kind = kind
        self.agent = agent
        self.tab = tab
        self.pid = pid
        self.time = time
    }

    public init?(line: String) {
        guard line.utf8.count <= Self.maxLineLength,
              let raw = try? JSONDecoder().decode(Raw.self, from: Data(line.utf8)),
              let kind = Kind(rawValue: raw.state), raw.time >= 0, Self.isID(raw.session) else { return nil }
        self.init(session: raw.session, kind: kind, agent: Agent(rawValue: raw.agent), tab: UUID(uuidString: raw.tab),
                  pid: raw.pid.flatMap { $0 > 0 ? $0 : nil }, time: Date(timeIntervalSince1970: TimeInterval(raw.time)))
    }

    private static func isID(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 64
            && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    private struct Raw: Decodable {
        let session: String
        let state: String
        let agent: String
        let tab: String
        let pid: Int?
        let time: Int
    }
}

/// What an agent's state asks of the display: nothing (idle, ended, or unknown), a pulse while it
/// works, or a mark while it waits for the operator. Ordered by how much it should be noticed.
public enum AgentActivity: Int, Sendable, Equatable, Comparable {
    case none
    case working
    case waiting

    public init(_ kind: AgentState.Kind) {
        switch kind {
        case .working: self = .working
        case .waiting: self = .waiting
        case .idle, .ended: self = .none
        }
    }

    public static func < (lhs: AgentActivity, rhs: AgentActivity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The state of each agent session the sandbox reported, by session. A tab shows the session that
/// carries its ID.
public struct AgentStates: Sendable, Equatable {
    public private(set) var sessions: [String: AgentState] = [:]
    /// The sessions a restarted watcher reported so far, while `beginResync()` is open.
    private var resynced: Set<String>?

    public init() {}

    public mutating func apply(line: String) {
        guard let state = AgentState(line: line) else { return }
        resynced?.insert(state.session)
        if state.kind == .ended {
            sessions[state.session] = nil
        } else {
            sessions[state.session] = state
        }
    }

    /// The watcher starts again (PAD-61): what it reported stays on show, so the marks do not blink,
    /// while the new one prints every session once.
    public mutating func beginResync() {
        resynced = []
    }

    /// The new watcher's first pass is done: a session it did not report is gone (it ended while
    /// nobody was following).
    public mutating func endResync() {
        guard let resynced else { return }
        sessions = sessions.filter { resynced.contains($0.key) }
        self.resynced = nil
    }

    /// What the tab with this ID shows: its most recent session's state, or nil when none reported.
    public func state(ofTab tab: UUID) -> AgentState? {
        sessions.values.filter { $0.tab == tab }.max { $0.time < $1.time }
    }

    /// What the tab with this ID shows.
    public func activity(ofTab tab: UUID) -> AgentActivity {
        state(ofTab: tab).map { AgentActivity($0.kind) } ?? .none
    }

    /// The project as a whole, for its sidebar row: waiting beats working beats nothing, across every
    /// session, a tab's or not (a session from a terminal the app did not open counts too).
    public var overall: AgentActivity {
        sessions.values.map { AgentActivity($0.kind) }.max() ?? .none
    }
}
