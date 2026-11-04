import Foundation

/// What a project's browser tab may load (backlog doc Browser). The tab shows playwright-cli's
/// dashboard, published by sbx on the Mac's loopback. **Untrusted:** the dashboard's page comes
/// from the sandbox, where the agent can change it, so the web view may reach only that one origin
/// (the sandbox itself): not llmman, a gateway, another port, or the internet. The app enforces it
/// twice, like `LlmmanWebPolicy`: WebKit content rules for every load (WebSockets included), and
/// the navigation delegate for page navigations, in a web view that keeps no data.
public struct BrowserWebPolicy: Sendable, Equatable {
    public let host = Ports.hostIP
    public let port: Int

    /// - Parameter dashboard: `BrowserKit.dashboardURL`; only a loopback URL with a port is accepted.
    public init?(dashboard: URL) {
        guard dashboard.scheme == "http", dashboard.host == Ports.hostIP, let port = dashboard.port else { return nil }
        self.port = port
    }

    public var homeURL: URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/"
        // Built from checked parts, so it always forms a URL; the fallback only satisfies the type.
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// A page navigation inside the web view: only the dashboard. Nothing opens on the Mac, not
    /// even a link the operator clicked: a page in the sandbox names the sandbox's own hosts
    /// (`localhost` there is not this Mac).
    public func allows(_ url: URL) -> Bool {
        url.absoluteString == "about:blank" || isDashboard(url)
    }

    func isDashboard(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "ws"].contains(scheme) else { return false }
        return url.host == host && url.port == port
    }

    /// WebKit content rules (JSON). Later rules win: block everything, then let the dashboard's
    /// origin (and inline `data:` / `blob:` resources, the screencast frames) through.
    public var contentRules: String {
        let escapedHost = host.replacingOccurrences(of: ".", with: "\\\\.")
        var rules = [#"{"trigger":{"url-filter":".*"},"action":{"type":"block"}}"#]
        for origin in ["http://\(escapedHost):\(port)/", "ws://\(escapedHost):\(port)/"] {
            rules.append(#"{"trigger":{"url-filter":"^\#(origin)"},"action":{"type":"ignore-previous-rules"}}"#)
        }
        for inline in ["^data:", "^blob:"] {
            rules.append(#"{"trigger":{"url-filter":"\#(inline)"},"action":{"type":"ignore-previous-rules"}}"#)
        }
        return "[" + rules.joined(separator: ",") + "]"
    }

    /// The content rule list's identifier, one per port.
    public var ruleListIdentifier: String { "paddock-browser-\(port)" }
}
