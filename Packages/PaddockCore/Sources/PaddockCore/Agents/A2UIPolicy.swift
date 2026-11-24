import Foundation

/// What may cross between an agent's sandbox and an A2UI tab (PAD-146; backlog doc Browser,
/// interactive tabs). A2UI itself (its message processor and validator) runs only in the app, on
/// the Mac; this is Paddock's own part, which needs no A2UI and is tested on Linux: the protocol
/// version and catalog Paddock renders, the size of what the sandbox may send, and the shape of
/// what goes back. Messages pass through unchanged in both directions; Paddock's own word to the
/// agent is an `A2UIEvent`, a line of its own shape.
public enum A2UIPolicy {
    /// The only A2UI protocol version Paddock renders.
    public static let version = "1.0"
    /// The basic catalog: the only components and functions a tab has.
    public static let basicCatalogID = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
    /// What an agent sends (`paddock ui`).
    public static let agentKinds: Set<String> = [
        "createSurface", "updateComponents", "updateDataModel", "deleteSurface",
        "callRendererFunction", "agentFunctionResponse",
    ]
    /// What a tab sends back (`paddock wait`).
    public static let rendererKinds: Set<String> = ["action", "error", "callAgentFunction", "rendererFunctionResponse"]

    /// Most bytes one message (one line) may have.
    public static let maxMessageBytes = 512 * 1024
    /// Most bytes of messages one tab takes in all; past it, the agent opens a new tab.
    public static let maxTabBytes = 8 * 1024 * 1024
    /// Most bytes of one message a tab sends back (on stdin, so not bound by argv).
    public static let maxOutboundBytes = 256 * 1024

    /// The one key besides `version`, which says what a message is; nil unless there is exactly one.
    static func kind(of message: [String: JSONValue]) -> String? {
        let keys = message.keys.filter { $0 != "version" }
        return keys.count == 1 ? keys.first : nil
    }

    /// Why Paddock does not render an agent's message, or nil when it may go to A2UI.
    static func refusal(of message: JSONValue) -> String? {
        guard case .object(let object) = message else { return "a message is a JSON object" }
        guard object["version"]?.stringValue == version else { return #"a message has "version": "1.0""# }
        guard let kind = kind(of: object), agentKinds.contains(kind) else {
            return "a message has one of " + agentKinds.sorted().joined(separator: ", ") + " next to its version"
        }
        switch kind {
        case "createSurface":
            guard object[kind]?["catalogId"]?.stringValue == basicCatalogID else {
                return "createSurface uses the basic catalog, \"catalogId\": \"\(basicCatalogID)\""
            }
        case "callRendererFunction":
            // The catalog is optional there; when named, it is the basic one.
            if let catalog = object[kind]?["callFunction"]?["catalogId"], catalog.stringValue != basicCatalogID {
                return "callRendererFunction calls functions of the basic catalog only"
            }
        default:
            break
        }
        return nil
    }

    /// The line a tab's message becomes for `paddock wait`: the message itself, or, when it is too
    /// large to deliver or not a renderer message, an `A2UIEvent` saying so. Never contains a newline.
    public static func lineForAgent(_ message: Data) -> Data {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: message),
              case .object(let object) = value,
              let kind = kind(of: object), rendererKinds.contains(kind) else {
            return A2UIEvent.dropped(reason: "the tab sent something that is not an A2UI message").json
        }
        guard message.count <= maxOutboundBytes else {
            return A2UIEvent.tooLarge(kind: kind, bytes: message.count).json
        }
        // A2UI's encoder writes one line; a newline would split the message for the agent.
        guard !message.contains(0x0A) else { return compact(value) ?? A2UIEvent.dropped(reason: "the tab's message spans lines").json }
        return message
    }

    static func compact(_ value: JSONValue) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(value)
    }
}

/// Paddock's own word to the agent about an A2UI tab, printed by `paddock wait` like the tab's
/// messages but with a `paddock` key instead of a `version`.
public struct A2UIEvent: Codable, Sendable, Equatable {
    public var paddock: String
    /// The line of the tab's messages it is about (1 is the first line the agent ever sent).
    public var line: Int?
    public var kind: String?
    public var bytes: Int?
    public var reason: String

    /// A message of the agent's that Paddock did not render; the ones around it were.
    public static func refused(line: Int, reason: String) -> A2UIEvent {
        A2UIEvent(paddock: "refused", line: line, reason: reason)
    }

    /// A message of the tab's that was too large to deliver.
    public static func tooLarge(kind: String, bytes: Int) -> A2UIEvent {
        A2UIEvent(paddock: "too-large", kind: kind, bytes: bytes,
                  reason: "the tab's \(kind) is \(bytes / 1024) KB, over \(A2UIPolicy.maxOutboundBytes / 1024) KB: keep less in the data model it sends")
    }

    public static func dropped(reason: String) -> A2UIEvent {
        A2UIEvent(paddock: "dropped", reason: reason)
    }

    /// The event as the one JSON line `paddock wait` prints.
    public var json: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Four optional fields and two strings always encode.
        return (try? encoder.encode(self)) ?? Data(#"{"paddock":"dropped","reason":"unencodable"}"#.utf8)
    }

    init(paddock: String, line: Int? = nil, kind: String? = nil, bytes: Int? = nil, reason: String) {
        self.paddock = paddock
        self.line = line
        self.kind = kind
        self.bytes = bytes
        self.reason = reason
    }
}

/// One A2UI tab's messages from the sandbox. The sandbox's `paddock` appends what the agent sends
/// to the tab's log, one message per line (JSONL); Paddock reads the log from `offset` and takes
/// whole lines only, so a send still being written waits for the next read.
public struct A2UIInbox: Sendable, Equatable {
    /// Bytes of the log already taken.
    public private(set) var offset = 0
    /// Lines already taken, for the line numbers in `A2UIEvent.refused`.
    public private(set) var lines = 0

    public init() {}

    /// What a read of the log brought.
    public struct Intake: Sendable, Equatable {
        /// The messages for A2UI, each the agent's own bytes, in order.
        public var messages: [Data] = []
        /// One event for each line Paddock did not render, for the agent.
        public var refusals: [A2UIEvent] = []
    }

    /// Takes the whole lines of `chunk`, the log's bytes from `offset`. Each line is checked on
    /// its own: a refused one never stops the ones after it.
    public mutating func take(_ chunk: Data) -> Intake {
        var intake = Intake()
        var rest = chunk[...]
        while let newline = rest.firstIndex(of: 0x0A) {
            take(line: rest[rest.startIndex..<newline], length: newline - rest.startIndex + 1, into: &intake)
            rest = rest[(newline + 1)...]
        }
        // A line longer than any message, still without its newline, will never be taken: refuse
        // it now rather than wait for it forever.
        if rest.count > A2UIPolicy.maxMessageBytes {
            take(line: rest, length: rest.count, into: &intake)
        }
        return intake
    }

    private mutating func take(line: Data.SubSequence, length: Int, into intake: inout Intake) {
        offset += length
        lines += 1
        var text = line
        if text.last == 0x0D { text = text.dropLast() }
        guard !text.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) else { return }
        if text.count > A2UIPolicy.maxMessageBytes {
            intake.refusals.append(.refused(line: lines, reason: "the message is over \(A2UIPolicy.maxMessageBytes / 1024) KB: send its components in more than one updateComponents"))
        } else if offset > A2UIPolicy.maxTabBytes {
            intake.refusals.append(.refused(line: lines, reason: "this tab has had \(A2UIPolicy.maxTabBytes / 1024 / 1024) MB of messages: open a new tab"))
        } else if let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text)) {
            if let reason = A2UIPolicy.refusal(of: value) {
                intake.refusals.append(.refused(line: lines, reason: reason))
            } else {
                intake.messages.append(Data(text))
            }
        } else {
            intake.refusals.append(.refused(line: lines, reason: "the line is not JSON: one message per line"))
        }
    }
}

/// Every `sbx exec` an A2UI tab needs, built here and nowhere else. The sandbox's `paddock`
/// answers them (`BrowserShow.script`). What the operator typed goes on stdin only: an `obscured`
/// text field holds a secret, and argv is logged and shown in errors.
public enum A2UICommands {
    /// An `sbx exec` and what it reads on stdin.
    public struct Command: Sendable, Equatable {
        public var arguments: [String]
        public var stdin: Data?
    }

    /// Prints the tab's message log from byte `offset` on, as base64.
    public static func messages(sandbox: String, id: String, from offset: Int) -> Command? {
        guard BrowserShow.isShowID(id), offset >= 0 else { return nil }
        return Command(arguments: ["exec", sandbox, "paddock", "--messages", id, String(offset)])
    }

    /// The log's bytes from what `messages` printed; nil for output that is not base64 of at most
    /// a tab's worth of messages.
    public static func decodeMessages(_ output: Data) -> Data? {
        guard output.count <= base64Length(A2UIPolicy.maxTabBytes) else { return nil }
        return Data(base64Encoded: output, options: .ignoreUnknownCharacters)
    }

    /// Hands one line for the agent (`A2UIPolicy.lineForAgent` or an `A2UIEvent`) to the sandbox,
    /// where `paddock wait` prints it.
    public static func deliver(sandbox: String, id: String, line: Data) -> Command? {
        guard BrowserShow.isShowID(id), line.count <= A2UIPolicy.maxOutboundBytes, !line.contains(0x0A) else { return nil }
        return Command(arguments: ["exec", "-i", sandbox, "paddock", "--operator", id, "a2ui"], stdin: line + Data([0x0A]))
    }

    /// Fetches a media URL inside the sandbox, where sbx's network rules apply; prints
    /// `A2UIMedia.decodeFetched`'s input.
    public static func fetch(sandbox: String, id: String, url: URL) -> Command? {
        guard BrowserShow.isShowID(id), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return Command(arguments: ["exec", sandbox, "paddock", "--fetch", id, url.absoluteString])
    }

    /// Reads a file next to the tab's messages (a media path relative to them), as base64.
    public static func read(sandbox: String, id: String, relativePath: String) -> Command? {
        BrowserShow.readCommand(sandbox: sandbox, id: id, relativePath: relativePath).map { Command(arguments: $0) }
    }

    /// `openUrl`: opens an http(s) page as a tab of the sandbox's browser (`paddock open`).
    public static func open(sandbox: String, url: URL) -> Command? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { return nil }
        return Command(arguments: ["exec", sandbox, "paddock", "open", url.absoluteString])
    }

    /// A file link in a tab's text (`A2UIMarkdown.Link.file`): opens the file next to the tab's
    /// messages as a native tab (`paddock --show-file`).
    public static func openFile(sandbox: String, id: String, relativePath: String) -> Command? {
        guard BrowserShow.isShowID(id), !relativePath.isEmpty, NativeShowPolicy.isRelativePath(relativePath) else { return nil }
        return Command(arguments: ["exec", sandbox, "paddock", "--show-file", id, relativePath])
    }

    static func base64Length(_ bytes: Int) -> Int { (bytes + 2) / 3 * 4 + 2 }
}
