// Records renderer-to-agent messages from the real A2UI Swift core, for PaddockCore's fixtures
// (PAD-146.1). Built and run by tools/tasks/capture/a2ui.sh against the pinned A2UI release; never
// part of Paddock.
//
//   Capture actions FILE OUT   process an example (JSON with "messages"), press every Button once
//   Capture typed FILE OUT     the login example after typing an email and a password
//   Capture errors OUT         malformed agent messages, and the errors the core reports for them
//   Capture calls FILE OUT     a surface, then each line of FILE (JSONL), and a Text calling a function
//                              the renderer does not have (which the core sends to the agent)
//
// Each run writes one JSON line per outbound message to OUT. One example per run, so a crash in one
// (pluralize on Linux) loses only that one.
import A2UICore
import BasicCatalog
import Foundation
import OrderedJSON

final class Outbox: @unchecked Sendable { var messages: [RendererToAgentMessage] = [] }

@MainActor
func record(to out: String, settle: TimeInterval = 0, _ body: (MessageProcessor) throws -> Void) throws {
    let processor = MessageProcessor(catalogs: BasicCatalog.allCatalogs)
    let outbox = Outbox()
    processor.outboundListener = { message in MainActor.assumeIsolated { outbox.messages.append(message) } }
    try body(processor)
    // Function calls answer asynchronously, on the main run loop.
    if settle > 0 { RunLoop.main.run(until: Date().addingTimeInterval(settle)) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let lines = try outbox.messages.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
    try lines.map { $0 + "\n" }.joined().write(toFile: out, atomically: true, encoding: .utf8)
    FileHandle.standardError.write(Data("\(out): \(lines.count)\n".utf8))
}

func messages(in file: String) throws -> JSONValue {
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: file)))
    let list = (object as? [String: Any])?["messages"] ?? []
    return try JSONDecoder().decode(JSONValue.self, from: JSONSerialization.data(withJSONObject: list))
}

@MainActor
func nodes(_ root: Node?) -> [Node] {
    guard let root else { return [] }
    return [root] + root.allChildNodes.flatMap { nodes($0) }
}

@MainActor
func pressButtons(_ processor: MessageProcessor) {
    for (_, surface) in processor.surfaceGroupModel.allSurfaces().sorted(by: { $0.key < $1.key }) {
        for node in nodes(surface.nodeResolver.resolveTree()) where node.type == "Button" {
            node.action(for: "action", userActivation: true)?()
        }
    }
}

@MainActor
func main() throws {
    let args = CommandLine.arguments
    let catalog = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
    switch args.count > 1 ? args[1] : "" {
    case "actions" where args.count == 4:
        try record(to: args[3]) { processor in
            try processor.processMessages(messages(in: args[2]))
            pressButtons(processor)
        }
    case "typed" where args.count == 4:
        try record(to: args[3]) { processor in
            try processor.processMessages(messages(in: args[2]))
            let surface = processor.surfaceGroupModel["gallery-login-form"]
            surface?.dataModel.set("/email", value: .string("ann@example.com"))
            surface?.dataModel.set("/password", value: .string("correct horse"))
            pressButtons(processor)
        }
    case "errors" where args.count == 3:
        let cases = [
            #"[{"version":"1.0","createSurface":{"surfaceId":"s1","catalogId":"https://example.com/unknown.json"}}]"#,
            #"[{"version":"1.0","createSurface":{"surfaceId":"s2","catalogId":"\#(catalog)"}},{"version":"1.0","updateComponents":{"surfaceId":"s2","components":[{"id":"root","component":"NoSuchThing"}]}}]"#,
            #"[{"version":"1.0","updateComponents":{"surfaceId":"missing","components":[{"id":"root","component":"Text","text":"x"}]}}]"#,
            #"[{"version":"1.0","createSurface":{"surfaceId":"s3","catalogId":"\#(catalog)"}},{"version":"1.0","updateComponents":{"surfaceId":"s3","components":[{"id":"root","component":"Text","text":42}]}}]"#,
            #"[{"version":"9.9","createSurface":{"surfaceId":"s4","catalogId":"\#(catalog)"}}]"#,
        ]
        try record(to: args[2]) { processor in
            for json in cases {
                // The core reports each through outboundListener and also throws; the report is what we keep.
                try? processor.processMessages(JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
            }
        }
    case "calls" where args.count == 4:
        let surface = #"{"version":"1.0","createSurface":{"surfaceId":"surface_1","catalogId":"\#(catalog)"}}"#
        let agentCall = #"{"version":"1.0","updateComponents":{"surfaceId":"surface_1","components":[{"id":"root","component":"Text","text":{"@call":"lookupGreeting","args":{"name":"Ann"}}}]}}"#
        let lines = try String(contentsOfFile: args[2], encoding: .utf8).split(separator: "\n").map(String.init)
        try record(to: args[3], settle: 2) { processor in
            for json in [surface] + lines + [agentCall] {
                try? processor.processMessages(JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
            }
        }
    default:
        FileHandle.standardError.write(Data("usage: Capture actions|typed|calls FILE OUT, Capture errors OUT\n".utf8))
        exit(2)
    }
}

try MainActor.assumeIsolated { try main() }
