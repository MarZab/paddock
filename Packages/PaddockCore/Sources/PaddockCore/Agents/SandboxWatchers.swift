import Foundation

/// Paddock's long-running watchers in a sandbox (`paddock-agent-watch`, `paddock-browser-watch`, `paddock-voice-watch`),
/// followed through `sbx exec`. Ending the `sbx exec` on the Mac does not end the watcher in the
/// sandbox, and a crashed Paddock ends neither, so each restart used to add a pair in every
/// sandbox (PAD-30). Now each start first stops the older watchers of its kind in the sandbox,
/// and on launch the app stops its own leftovers on the Mac (backlog doc Kits, Watchers).
public enum SandboxWatchers {
    public static let commands = [AgentStatusKit.watchCommand, BrowserActivity.watchName, VoiceKit.watchCommand]
    /// `$0` of the starting shell, so `ps` on the Mac shows what it is.
    static let label = "paddock-watch"

    /// Stops the other watchers of kind `$1` that app `$2` started, then runs one until Paddock is gone.
    /// A watcher's command line is exactly its interpreter (`node`, `/bin/sh`, or the absolute node that
    /// `NodeScript`'s header found), its path, and `--for=APP` (`owner`; none before PAD-61, and those
    /// go too), so the browser kit's one-off calls (`--captured ...`) and another Paddock's watchers
    /// (Paddock Dev next to the installed one) are left alone (PAD-61). The watchers ignore the argument. Then the watcher runs with empty input,
    /// and a `cat` reads the real input (kept on fd 3: a background job's input is /dev/null) until it
    /// ends, which `sbx exec -i` passes on when Paddock closes it or dies; that stops the watcher. A
    /// watcher that ends by itself ends the script with its status, so Paddock starts it again. Works
    /// with any kit version: it needs sh, tr, cat, and kill. One line, so `ps` shows it whole.
    /// `PADDOCK_WATCH_BIN` is for tests; `sbx exec` passes no environment, so in a sandbox it is
    /// the kits' /usr/local/bin.
    static let replaceScript = #"b=${PADDOCK_WATCH_BIN:-/usr/local/bin}; o="--for=$2"; for p in /proc/[0-9]*; do pid=${p#/proc/}; "#
        + #"[ "$pid" = "$$" ] && continue; case "$(tr '\0' ' ' 2>/dev/null < "$p/cmdline")" in "#
        + #""node $b/$1 "|*"/node $b/$1 "|"/bin/sh $b/$1 "|"node $b/$1 $o "|*"/node $b/$1 $o "|"/bin/sh $b/$1 $o ") "#
        + #"kill "$pid" 2>/dev/null ;; esac; done; "#
        + #"exec 3<&0; "$1" "$o" </dev/null 3<&- & w=$!; (cat <&3 >/dev/null 2>&1; kill "$w" 2>/dev/null) >/dev/null 2>&1 & "#
        + #"c=$!; exec 3<&-; wait "$w"; s=$?; kill "$c" 2>/dev/null; exit "$s""#

    /// `sbx exec -i` arguments that start `command` in `sandbox`, replacing the watchers already
    /// there; the stream must hold its input open (`FoundationLineStreamer(holdsInputOpen:)`).
    public static func arguments(sandbox: String, command: String) -> [String] {
        ["exec", "-i", sandbox, "sh", "-c", replaceScript, label, command, owner]
    }

    /// Which app started a watcher: this app's bundle ID (Paddock and Paddock Dev differ), letters,
    /// digits, `.` and `-` only.
    public static let owner = ownerName(Bundle.main.bundleIdentifier)

    static func ownerName(_ bundleID: String?) -> String {
        guard let bundleID, isOwner(bundleID) else { return "paddock" }
        return bundleID
    }

    static func isOwner(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 128
            && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }

    /// Watchers on the Mac that an earlier Paddock started and left: the current user's, parent gone,
    /// command exactly a watcher's `sbx exec` (this version's or the earlier `sbx exec N WATCHER`).
    /// Nothing else, so stopping them touches no one else's process.
    public static func leftovers(in processes: [HostProcess], user: String) -> [HostProcess] {
        processes.filter { $0.isOrphan && $0.user == user && isWatcherExec($0.command) }
    }

    /// Stops the leftovers (`leftovers(in:user:)`) with SIGTERM and returns them. `signal` sends
    /// one; tests pass a fake.
    public static func stopLeftovers(
        runner: ProcessRunner, user: String, signal: (Int32) -> Bool = { kill($0, SIGTERM) == 0 }
    ) async throws -> [HostProcess] {
        let found = leftovers(in: try await HostProcesses.read(runner: runner), user: user)
        return found.filter { signal($0.pid) }
    }

    static func isWatcherExec(_ command: String) -> Bool {
        let words = command.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard words.count >= 4, URL(fileURLWithPath: words[0]).lastPathComponent == "sbx", words[1] == "exec" else { return false }
        // `-i` since the watchers follow Paddock's input (earlier versions: none).
        let rest = words[2] == "-i" ? Array(words[3...]) : Array(words[2...])
        guard rest.count >= 2, isSandboxName(rest[0]) else { return false }
        if rest.count == 2 { return commands.contains(rest[1]) }
        // `ps` joins the script's words with spaces, so only the start and the end are checked: the
        // label, the watcher, and since PAD-61 the app that started it.
        guard rest.count >= 4, rest[1] == "sh", rest[2] == "-c" else { return false }
        let tail = words.suffix(3)
        let tag = tail[tail.endIndex - 1]
        if tail.count == 3, isOwner(tag), tag.contains(".") || tag == ownerName(nil), tail[tail.startIndex] == label {
            return commands.contains(tail[tail.startIndex + 1])
        }
        return commands.contains { command.hasSuffix(" \(label) \($0)") }
    }

    private static func isSandboxName(_ name: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return !name.isEmpty && name.unicodeScalars.allSatisfy(allowed.contains)
    }
}
