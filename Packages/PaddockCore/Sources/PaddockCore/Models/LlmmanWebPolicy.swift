import Foundation

/// What the embedded llmman web UI may load (backlog doc UI, Models pane; CLAUDE.md, Security rules).
/// The app enforces it twice: WebKit content rules for every load (including WebSockets), and
/// the navigation delegate for page navigations.
public enum LlmmanWebPolicy {
    public static let host = "127.0.0.1"
    /// One definition for the app: `AppConfig.llmmanPort` (also the gateway upstream and a reserved port).
    public static let port = AppConfig.llmmanPort
    /// llmman's web shell. Never loaded, never connected to, even though sbx turns it off.
    public static let shellPath = "/llmman/shell"

    public static var homeURL: URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/"
        // Built from constants, so it always forms a URL; the fallback only satisfies the type.
        return components.url ?? URL(fileURLWithPath: "/")
    }

    public enum Decision: Sendable, Equatable {
        case allow
        /// A link the operator clicked to another site: open it in the default browser.
        case openExternally
        case block
    }

    /// A page navigation inside the web view.
    public static func decide(url: URL, userClicked: Bool) -> Decision {
        if url.absoluteString == "about:blank" {
            return .allow
        }
        if isLlmman(url) {
            return isShell(url) ? .block : .allow
        }
        if userClicked, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
            return .openExternally
        }
        return .block
    }

    static func isLlmman(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "ws"].contains(scheme),
              let urlHost = url.host?.lowercased() else { return false }
        return (urlHost == host || urlHost == "localhost") && url.port == port
    }

    static func isShell(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path == shellPath || path.hasPrefix(shellPath + "/")
    }

    /// WebKit content rules (JSON). Later rules win: block everything, let llmman's own origin
    /// (and inline `data:` / `blob:` resources) through, then block the shell again. WebKit's
    /// url-filter has no alternation, hence one rule per origin.
    public static var contentRules: String {
        let escapedHost = host.replacingOccurrences(of: ".", with: "\\\\.")
        var rules = [#"{"trigger":{"url-filter":".*"},"action":{"type":"block"}}"#]
        for origin in ["http://\(escapedHost):\(port)/", "ws://\(escapedHost):\(port)/", "http://localhost:\(port)/", "ws://localhost:\(port)/"] {
            rules.append(#"{"trigger":{"url-filter":"^\#(origin)"},"action":{"type":"ignore-previous-rules"}}"#)
        }
        for inline in ["^data:", "^blob:"] {
            rules.append(#"{"trigger":{"url-filter":"\#(inline)"},"action":{"type":"ignore-previous-rules"}}"#)
        }
        rules.append(#"{"trigger":{"url-filter":"\#(shellPath)"},"action":{"type":"block"}}"#)
        return "[" + rules.joined(separator: ",") + "]"
    }
}
