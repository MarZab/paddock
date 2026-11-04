import Foundation

/// How a `paddock --native` tab renders on the operator's Mac (backlog doc Browser). **Untrusted:**
/// the file comes from the sandbox. The agent asks for it explicitly, the tab has a color of its
/// own, and nothing loads until the operator opens it. Plain text renders natively (no web view).
/// Anything else, Markdown included, renders in a web view that keeps no data and loads only
/// through its own URL scheme, `paddock-file://<tab id>/<path>`: each request reads
/// one file through `sbx exec` (`BrowserShow.readCommand`), only the shown file or one beside it
/// (the sandbox checks the real path too), and WebKit content rules block every other load,
/// network and WebSockets included. A Markdown file is served as a page Paddock renders
/// (`MarkdownPage`: raw HTML shown as text, a CSP without scripts), and a Markdown tab's web view
/// runs no JavaScript at all.
public struct NativeShowPolicy: Sendable, Equatable {
    public static let scheme = "paddock-file"

    public enum Rendering: Sendable, Equatable {
        case web
        case markdown
        case text
    }

    public let showID: String
    /// The shown file's name, the page the web view starts from.
    public let fileName: String

    public init?(showID: String, fileName: String) {
        guard BrowserShow.isShowID(showID), Self.isRelativePath(fileName), !fileName.isEmpty, !fileName.contains("/") else { return nil }
        self.showID = showID
        self.fileName = fileName
    }

    public var rendering: Rendering {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "md", "markdown": .markdown
        case "txt", "log", "csv", "tsv": .text
        default: .web
        }
    }

    /// Whether the tab's web view may run JavaScript: not for Markdown, whose page is Paddock's.
    public var allowsJavaScript: Bool { rendering != .markdown }

    public static func isMarkdown(_ path: String) -> Bool {
        ["md", "markdown"].contains((path as NSString).pathExtension.lowercased())
    }

    /// What the web view gets for a file it asked for: Markdown as Paddock's rendered page,
    /// anything else as it is with its type.
    public static func response(for path: String, data: Data) -> (data: Data, mimeType: String) {
        guard isMarkdown(path) else { return (data, mimeType(for: path)) }
        return (MarkdownPage.html(from: data, title: (path as NSString).lastPathComponent), "text/html")
    }

    public var homeURL: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = showID
        components.path = "/" + fileName
        return components.url
    }

    /// The path under the shown file's folder a request names; nil for anything that is not this
    /// tab's scheme and show, or a path Paddock would not ask the sandbox for.
    public func relativePath(of url: URL) -> String? {
        guard url.scheme?.lowercased() == Self.scheme, url.host?.lowercased() == showID else { return nil }
        let path = String(url.path.drop { $0 == "/" })
        return Self.isRelativePath(path) && !path.isEmpty ? path : nil
    }

    /// No leading `/`, no `..` or `.` parts, no backslash or NUL, at most 1024 bytes.
    public static func isRelativePath(_ path: String) -> Bool {
        guard path.utf8.count <= 1024, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0 == "." }
    }

    public static func mimeType(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": "text/html"
        case "css": "text/css"
        case "js", "mjs": "text/javascript"
        case "json", "map": "application/json"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "ico": "image/x-icon"
        case "pdf": "application/pdf"
        case "woff": "font/woff"
        case "woff2": "font/woff2"
        case "ttf": "font/ttf"
        case "txt", "log", "md", "markdown", "csv", "tsv": "text/plain"
        default: "application/octet-stream"
        }
    }

    /// WebKit content rules (JSON). Later rules win: block everything, then let this show's own
    /// URLs (and inline `data:` / `blob:` resources) through.
    public var contentRules: String {
        let rules = [
            #"{"trigger":{"url-filter":".*"},"action":{"type":"block"}}"#,
            #"{"trigger":{"url-filter":"^\#(Self.scheme)://\#(showID)/"},"action":{"type":"ignore-previous-rules"}}"#,
            #"{"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}}"#,
            #"{"trigger":{"url-filter":"^blob:"},"action":{"type":"ignore-previous-rules"}}"#,
        ]
        return "[" + rules.joined(separator: ",") + "]"
    }

    public var ruleListIdentifier: String { "paddock-file-\(showID)" }

    /// The largest file Paddock decodes (the sandbox refuses larger ones too).
    public static let maxFileBytes = 20 * 1024 * 1024
}
