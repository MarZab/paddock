import Foundation

/// How an A2UI tab renders (PAD-152; backlog doc Browser, interactive tabs): the page in `App/A2UI`
/// (CopilotKit's renderer and the A2UI Playground's catalog, `mise run vendor:a2ui-web`) in a web
/// view of its own. Everything it loads comes from the app through `paddock-a2ui://app/`: the files
/// its `manifest.json` lists, and `__media/<kind>/<URL, base64url>` (its `media.ts`), which the app
/// answers through the sandbox (`A2UIMedia`). WebKit content rules block every other load. The
/// agent's messages are data: Paddock hands them to the page as one JSON string (`renderScript`).
/// The page answers through one message handler (`A2UIWebMessage`).
public enum A2UIWebPolicy {
    public static let scheme = "paddock-a2ui"
    public static let host = "app"
    /// The name of the page's message handler (`window.webkit.messageHandlers.paddock`).
    public static let messageHandler = "paddock"
    public static let ruleListIdentifier = "paddock-a2ui"
    static let mediaPrefix = "__media/"

    public static var homeURL: URL? { URL(string: "\(scheme)://\(host)/index.html") }

    /// What the page may load, by path: `App/A2UI/manifest.json`'s `files` (path to MIME type).
    public struct Manifest: Sendable, Equatable, Decodable {
        public let files: [String: String]

        public init(files: [String: String]) {
            self.files = files
        }

        public init(data: Data) throws {
            self = try JSONDecoder().decode(Manifest.self, from: data)
        }
    }

    /// What a request of the page asks for.
    public enum Request: Sendable, Equatable {
        /// One of the page's own files (a path under `App/A2UI`) and its MIME type.
        case file(String, mimeType: String)
        /// A picture, video, or audio clip the page wants, as its component named it.
        case media(A2UIMedia.Kind, String)
    }

    /// The request a URL of the page makes, or nil for anything not on its origin, not in the
    /// manifest, or not a valid media path.
    public static func request(for url: URL, manifest: Manifest) -> Request? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == host else { return nil }
        let path = String(url.path.drop { $0 == "/" })
        if path.hasPrefix(mediaPrefix) {
            let parts = path.dropFirst(mediaPrefix.count).split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, let kind = A2UIMedia.Kind(rawValue: String(parts[0])),
                  let original = base64URLDecoded(String(parts[1])) else { return nil }
            return .media(kind, original)
        }
        guard NativeShowPolicy.isRelativePath(path), let mimeType = manifest.files[path] else { return nil }
        return .file(path, mimeType: mimeType)
    }

    static func base64URLDecoded(_ text: String) -> String? {
        guard !text.isEmpty, text.utf8.count <= 64 * 1024,
              text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), let decoded = String(data: data, encoding: .utf8) else { return nil }
        return decoded
    }

    /// The bytes a media request's `Range` header asks for (video and audio ask in parts) of a body
    /// of `count` bytes: nil for the whole body (no header, or one Paddock does not take), an empty
    /// range for one past the end (416).
    public static func byteRange(_ header: String?, count: Int) -> Range<Int>? {
        guard let header, header.hasPrefix("bytes="), !header.contains(",") else { return nil }
        let spec = header.dropFirst("bytes=".count).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard spec.count == 2 else { return nil }
        let first = spec[0].trimmingCharacters(in: .whitespaces)
        let last = spec[1].trimmingCharacters(in: .whitespaces)
        if first.isEmpty {
            // The last N bytes.
            guard let suffix = Int(last), suffix > 0 else { return nil }
            return max(0, count - suffix)..<count
        }
        guard let start = Int(first), start >= 0 else { return nil }
        guard start < count else { return count..<count }
        guard !last.isEmpty else { return start..<count }
        guard let end = Int(last), end >= start else { return nil }
        return start..<min(end + 1, count)
    }

    /// Where a navigation of the page goes instead (a link the operator clicked, or `openUrl`'s
    /// new window): a sandbox page or a file next to the messages; nil opens nothing. The page
    /// itself navigates nowhere.
    public static func link(for url: URL) -> A2UILink? {
        if url.scheme?.lowercased() == scheme {
            guard url.host?.lowercased() == host else { return nil }
            // A relative link resolves against the page: what is left is the path the agent wrote.
            let path = String(url.path.drop { $0 == "/" })
            guard path != "index.html", !path.hasPrefix(mediaPrefix) else { return nil }
            return A2UILink(path)
        }
        return A2UILink(url.absoluteString)
    }

    /// WebKit content rules (JSON): block everything, then let the page's own URLs (and inline
    /// `data:` and `blob:` resources) through.
    public static var contentRules: String {
        let rules = [
            #"{"trigger":{"url-filter":".*"},"action":{"type":"block"}}"#,
            #"{"trigger":{"url-filter":"^\#(scheme)://\#(host)/"},"action":{"type":"ignore-previous-rules"}}"#,
            #"{"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}}"#,
            #"{"trigger":{"url-filter":"^blob:"},"action":{"type":"ignore-previous-rules"}}"#,
        ]
        return "[" + rules.joined(separator: ",") + "]"
    }

    /// The call that renders `messages` (each one a JSON object, from `A2UIInbox`): one JSON array,
    /// passed as a JSON string, so the messages are only ever a string to the page.
    public static func renderScript(messages: [Data]) -> String? {
        let array = "[" + messages.map { String(decoding: $0, as: UTF8.self) }.joined(separator: ",") + "]"
        guard let literal = try? JSONEncoder().encode(array) else { return nil }
        return "window.paddockA2UI && window.paddockA2UI.render(\(String(decoding: literal, as: UTF8.self)));"
    }
}

/// What the page posts to Paddock (`tools/tasks/lib/a2ui-web/host.tsx`), checked before anything
/// uses it: the page is Paddock's, but what the operator typed and what the messages hold are not.
public enum A2UIWebMessage: Sendable, Equatable {
    /// The page is up: it can render.
    case ready
    /// What the operator did: an A2UI action message, for `A2UIPolicy.lineForAgent`.
    case action(Data)
    /// What the renderer refused or could not draw: an A2UI error message, for the agent too.
    case error(Data)
    /// The page itself failed (not the agent's messages): for the app's log.
    case problem(String)

    /// The most a post may hold.
    public static let maxBytes = A2UIPolicy.maxOutboundBytes + 1024

    public init?(_ body: String) {
        guard body.utf8.count <= Self.maxBytes,
              case .object(let object)? = try? JSONDecoder().decode(JSONValue.self, from: Data(body.utf8)),
              let kind = object["kind"]?.stringValue else { return nil }
        switch kind {
        case "ready":
            self = .ready
        case "action", "error":
            guard case .object(let message)? = object["message"], message[kind] != nil,
                  let data = A2UIPolicy.compact(.object(message)) else { return nil }
            self = kind == "action" ? .action(data) : .error(data)
        case "problem":
            let text = (object["text"]?.stringValue ?? "").filter { !$0.isNewline }
            self = .problem(String(text.prefix(500)))
        default:
            return nil
        }
    }
}
