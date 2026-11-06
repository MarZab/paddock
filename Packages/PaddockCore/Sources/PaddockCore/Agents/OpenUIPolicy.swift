import Foundation

/// How an interactive tab (`paddock ui`) renders: OpenUI's renderer, vendored in the app
/// (`App/OpenUI`, `tools/tasks/vendor/openui.sh`), in a web view of its own (backlog doc Browser, OpenUI
/// tabs). Everything the page loads comes from the app through `paddock-ui://renderer/`, from a
/// fixed list of files; WebKit content rules block every other load. The agent's document is
/// data: Paddock hands it to the page as a JSON string (`renderScript`), and OpenUI runs no code
/// from it and renders no raw HTML. The page answers through one message handler (`OpenUIMessage`).
public enum OpenUIPolicy {
    public static let scheme = "paddock-ui"
    public static let host = "renderer"
    /// The name of the page's message handler (`window.webkit.messageHandlers.paddock`).
    public static let messageHandler = "paddock"

    /// The app's files the page may load, by path under `App/OpenUI`.
    public static let files: [String: String] = [
        "index.html": "text/html",
        "host.js": "text/javascript",
        "vendor/openui-bundle.min.js": "text/javascript",
        "vendor/openui-styles.css": "text/css",
    ]

    public static var homeURL: URL? { URL(string: "\(scheme)://\(host)/index.html") }

    /// The app file a request names, or nil for anything not on the list.
    public static func file(for url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == host else { return nil }
        let path = String(url.path.drop { $0 == "/" })
        return files[path] == nil ? nil : path
    }

    /// WebKit content rules (JSON): block everything, then let the renderer's own URLs (and
    /// inline `data:` / `blob:` resources) through.
    public static var contentRules: String {
        let rules = [
            #"{"trigger":{"url-filter":".*"},"action":{"type":"block"}}"#,
            #"{"trigger":{"url-filter":"^\#(scheme)://\#(host)/"},"action":{"type":"ignore-previous-rules"}}"#,
            #"{"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}}"#,
            #"{"trigger":{"url-filter":"^blob:"},"action":{"type":"ignore-previous-rules"}}"#,
        ]
        return "[" + rules.joined(separator: ",") + "]"
    }

    public static let ruleListIdentifier = "paddock-ui"

    /// The largest document Paddock renders (`paddock ui` refuses larger ones too).
    public static let maxDocumentBytes = 512 * 1024

    /// The call that renders `document` with the form state Paddock kept (`OpenUIMessage.state`).
    /// Both go in as JSON, so the document is only ever a string to the page.
    public static func renderScript(document: String, state: String?) -> String? {
        guard document.utf8.count <= maxDocumentBytes, let data = try? JSONEncoder().encode(document) else { return nil }
        let stateJSON = state.flatMap(OpenUIMessage.normalizedJSON) ?? "null"
        return "window.paddockRender(\(String(decoding: data, as: UTF8.self)), \(stateJSON));"
    }
}

/// What the renderer's page posts to Paddock (`App/OpenUI/host.js`), checked before anything uses
/// it: the page is Paddock's, but what the operator typed and what the document holds are not.
public enum OpenUIMessage: Sendable, Equatable {
    /// The page is ready for `paddockRender`.
    case ready
    /// A button or a submitted form: the action as compact JSON, for the sandbox.
    case action(String)
    /// What the renderer could not draw, as compact JSON (a list), for the sandbox.
    case problems(String)
    /// The renderer's state, as JSON, kept by Paddock for the next render.
    case state(String)

    public static let maxActionBytes = 64 * 1024
    public static let maxStateBytes = 256 * 1024
    public static let maxProblems = 20

    public init?(_ body: String) {
        guard body.utf8.count <= Self.maxStateBytes + 1024,
              let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let kind = object["kind"] as? String else { return nil }
        switch kind {
        case "ready":
            self = .ready
        case "action":
            guard let action = object["action"] as? [String: Any], action["type"] is String,
                  let json = Self.compact(action), json.utf8.count <= Self.maxActionBytes else { return nil }
            self = .action(json)
        case "problems":
            guard let list = object["problems"] as? [Any] else { return nil }
            let problems = list.prefix(Self.maxProblems).compactMap { $0 as? [String: Any] }.map { problem in
                problem.compactMapValues { value -> Any? in
                    guard let text = value as? String else { return nil }
                    return String(text.prefix(400))
                }
            }
            guard let json = Self.compact(problems) else { return nil }
            self = .problems(json)
        case "state":
            guard let state = object["state"], let json = Self.compact(state), json.utf8.count <= Self.maxStateBytes else { return nil }
            self = .state(json)
        default:
            return nil
        }
    }

    /// `json` parsed and written again (sorted keys), or nil when it is not JSON.
    public static func normalizedJSON(_ json: String) -> String? {
        guard let value = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]) else { return nil }
        return compact(value)
    }

    static func compact(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value) || value is NSNull,
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
