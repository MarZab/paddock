import Foundation

/// How Paddock's Node scripts in a sandbox start (backlog doc Kits, Node scripts). The project's
/// image decides what `node` on PATH is, and it may be a version manager's shim that fails for this
/// folder (one that tries to install a version it cannot). Paddock does not care what manages
/// node there: its scripts start with a header that is a `/bin/sh` script and, from the second
/// line on, JavaScript (the shell sees one command line, Node a string and a comment). The shell
/// tries each `node` on PATH, then /usr/local/bin and /usr/bin, and runs the script with the first
/// that starts; stdin stays for the script. None: a clear error and 127.
public enum NodeScript {
    public static let header = "#!/bin/sh\n"
        + #"':' //; set -f; IFS=:; for d in $PATH /usr/local/bin /usr/bin; do n="${d:-.}/node"; "#
        + #"if [ -x "$n" ] && "$n" -e 0 </dev/null >/dev/null 2>&1; then exec "$n" "$0" "$@"; fi; done; "#
        + #"echo "${0##*/}: no node that runs on PATH, /usr/local/bin, or /usr/bin" >&2; exit 127"#

    /// `body` (JavaScript, without a `#!` line) as a script that runs with the first working node.
    public static func wrap(_ body: String) -> String {
        header + "\n" + body
    }
}
