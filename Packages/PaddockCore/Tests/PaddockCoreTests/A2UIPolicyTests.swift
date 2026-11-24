import Foundation
@testable import PaddockCore
import Testing

/// PAD-146.2: what crosses between a sandbox and an A2UI tab (backlog doc Browser, interactive
/// tabs), checked with the A2UI fixtures (`Fixtures/a2ui/README.md`).
@Suite("A2UI policy")
struct A2UIPolicyTests {
    func fixture(_ path: String) throws -> Data {
        guard let folder = Bundle.module.url(forResource: "a2ui", withExtension: nil, subdirectory: nil) else {
            throw FixtureError.missing("a2ui")
        }
        return try Data(contentsOf: folder.appendingPathComponent(path))
    }

    func fixtureLines(_ path: String) throws -> [Data] {
        try fixture(path).split(separator: 0x0A).map { Data($0) }
    }

    /// An example's messages, one compact line each, as the sandbox's log holds them.
    func exampleLines(_ path: String) throws -> [Data] {
        let object = try JSONSerialization.jsonObject(with: fixture(path)) as? [String: Any]
        let messages = object?["messages"] as? [Any] ?? []
        return try messages.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes]) }
    }

    func log(_ lines: [Data]) -> Data {
        lines.reduce(into: Data()) { $0 += $1 + Data([0x0A]) }
    }

    func line(_ text: String) -> Data { Data(text.utf8) }

    static let create = #"{"version":"1.0","createSurface":{"surfaceId":"s","catalogId":"https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"}}"#
    static let text = #"{"version":"1.0","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Text","text":"Hi"}]}}"#

    // MARK: - From the sandbox

    @Test func everyAgentFixtureGoesThroughUnchanged() throws {
        let folder = try #require(Bundle.module.url(forResource: "a2ui", withExtension: nil, subdirectory: nil))
        let examples = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("examples").path)
            .filter { $0.hasSuffix(".json") }.sorted().map { "examples/" + $0 }
        var lines = try (examples + ["agent/media.json", "agent/functions.json"]).flatMap(exampleLines)
        lines += try fixtureLines("agent/contact-form.jsonl") + fixtureLines("agent/calls.jsonl")
        var inbox = A2UIInbox()
        let intake = inbox.take(log(lines))
        #expect(intake.refusals == [])
        #expect(intake.messages == lines)
        #expect(inbox.lines == lines.count)
        #expect(inbox.offset == log(lines).count)
    }

    @Test func refusesEachBadLineAndKeepsTheRest() {
        let lines = [
            Self.create,
            "",
            "{not json",
            #"{"version":"0.9","createSurface":{"surfaceId":"t","catalogId":"x"}}"#,
            #"{"version":"1.0","beginRendering":{"surfaceId":"s"}}"#,
            #"{"version":"1.0","updateDataModel":{"surfaceId":"s"},"deleteSurface":{"surfaceId":"s"}}"#,
            #"{"version":"1.0","createSurface":{"surfaceId":"u","catalogId":"https://example.com/catalog.json"}}"#,
            #"{"version":"1.0","callRendererFunction":{"functionCallId":"c","callFunction":{"@call":"openUrl","catalogId":"https://example.com/c.json","args":{}}}}"#,
            #"["version","1.0"]"#,
            Self.text + "\r",
        ]
        var inbox = A2UIInbox()
        let intake = inbox.take(log(lines.map(line)))
        #expect(intake.messages == [line(Self.create), line(Self.text)])
        #expect(intake.refusals.map(\.line) == [3, 4, 5, 6, 7, 8, 9])
        #expect(intake.refusals.allSatisfy { $0.paddock == "refused" && !$0.reason.isEmpty })
        #expect(intake.refusals[0].reason.contains("not JSON"))
        #expect(intake.refusals[1].reason.contains(#""version": "1.0""#))
        #expect(intake.refusals[4].reason.contains(A2UIPolicy.basicCatalogID))
        #expect(inbox.lines == 10)
    }

    @Test func aLineStillBeingWrittenWaitsForTheNextRead() {
        var inbox = A2UIInbox()
        let whole = log([line(Self.create), line(Self.text)])
        let cut = whole.count - 10
        let first = inbox.take(whole.prefix(cut))
        #expect(first.messages == [line(Self.create)])
        #expect(inbox.offset == Self.create.utf8.count + 1)
        let second = inbox.take(whole.suffix(from: inbox.offset))
        #expect(second.messages == [line(Self.text)])
        #expect(inbox.offset == whole.count)
    }

    @Test func refusesAMessageOverTheCap() {
        let big = #"{"version":"1.0","updateDataModel":{"surfaceId":"s","value":""# + String(repeating: "x", count: A2UIPolicy.maxMessageBytes) + #""}}"#
        var inbox = A2UIInbox()
        let intake = inbox.take(log([line(big), line(Self.text)]))
        #expect(intake.messages == [line(Self.text)])
        #expect(intake.refusals.map(\.line) == [1])
        #expect(intake.refusals.first?.reason.contains("KB") == true)
        // Without its newline it is refused too, instead of being waited for forever.
        var waiting = A2UIInbox()
        let unterminated = waiting.take(line(big))
        #expect(unterminated.refusals.map(\.line) == [1])
        #expect(waiting.offset == big.utf8.count)
    }

    @Test func refusesWhatComesPastATabsWorth() {
        let filler = #"{"version":"1.0","updateDataModel":{"surfaceId":"s","value":""# + String(repeating: "x", count: 400 * 1024) + #""}}"#
        let count = A2UIPolicy.maxTabBytes / filler.utf8.count + 3
        var inbox = A2UIInbox()
        let intake = inbox.take(log(Array(repeating: line(filler), count: count)))
        #expect(intake.messages.count == A2UIPolicy.maxTabBytes / (filler.utf8.count + 1))
        #expect(!intake.refusals.isEmpty)
        #expect(intake.refusals.allSatisfy { $0.reason.contains("open a new tab") })
        #expect(intake.messages.count + intake.refusals.count == count)
    }

    // MARK: - To the sandbox

    @Test func everyRendererFixtureGoesBackUnchanged() throws {
        let lines = try fixtureLines("renderer/actions.jsonl") + fixtureLines("renderer/checks.jsonl")
            + fixtureLines("renderer/errors.jsonl") + fixtureLines("renderer/calls.jsonl")
            + fixtureLines("renderer/library-calls.jsonl")
        #expect(lines.count > 40)
        for message in lines {
            #expect(A2UIPolicy.lineForAgent(message) == message)
        }
    }

    @Test func tooLargeOrForeignMessagesBecomeEvents() throws {
        let value = String(repeating: "y", count: A2UIPolicy.maxOutboundBytes)
        let big = line(#"{"version":"1.0","action":{"name":"save","surfaceId":"s","sourceComponentId":"b","timestamp":"2026-11-24T20:30:51Z","context":{"notes":"\#(value)"}}}"#)
        let event = try JSONDecoder().decode(A2UIEvent.self, from: A2UIPolicy.lineForAgent(big))
        #expect(event.paddock == "too-large")
        #expect(event.kind == "action")
        #expect(event.bytes == big.count)
        // An agent-side message, or no message at all, is not something a tab sends.
        for foreign in [line(Self.create), line("[]"), line("nope")] {
            #expect(try JSONDecoder().decode(A2UIEvent.self, from: A2UIPolicy.lineForAgent(foreign)).paddock == "dropped")
        }
        // A message over several lines comes back on one.
        let pretty = line("{\n  \"version\": \"1.0\",\n  \"action\": {\"name\": \"go\"}\n}")
        let compact = A2UIPolicy.lineForAgent(pretty)
        #expect(!compact.contains(0x0A))
        #expect(String(decoding: compact, as: UTF8.self) == #"{"action":{"name":"go"},"version":"1.0"}"#)
    }

    @Test func eventsAreOneLineOfTheirOwnShape() {
        #expect(String(decoding: A2UIEvent.refused(line: 3, reason: "the line is not JSON").json, as: UTF8.self)
            == #"{"line":3,"paddock":"refused","reason":"the line is not JSON"}"#)
        #expect(String(decoding: A2UIEvent.dropped(reason: "x").json, as: UTF8.self) == #"{"paddock":"dropped","reason":"x"}"#)
    }

    // MARK: - Commands

    @Test func commandsNameTheTabAndNothingElse() throws {
        #expect(A2UICommands.messages(sandbox: "web", id: "tab-a3f9", from: 120)?.arguments
            == ["exec", "web", "paddock", "--messages", "tab-a3f9", "120"])
        #expect(A2UICommands.messages(sandbox: "web", id: "tab-a3f9", from: -1) == nil)
        let url = try #require(URL(string: "https://images.example.com/photo.jpg"))
        #expect(A2UICommands.fetch(sandbox: "web", id: "tab-a3f9", url: url)?.arguments
            == ["exec", "web", "paddock", "--fetch", "tab-a3f9", "https://images.example.com/photo.jpg"])
        #expect(A2UICommands.fetch(sandbox: "web", id: "tab-a3f9", url: try #require(URL(string: "file:///etc/passwd"))) == nil)
        #expect(A2UICommands.read(sandbox: "web", id: "tab-a3f9", relativePath: "audio/notes.m4a")?.arguments
            == ["exec", "web", "paddock", "--read", "tab-a3f9", "audio/notes.m4a"])
        #expect(A2UICommands.read(sandbox: "web", id: "tab-a3f9", relativePath: "../secret") == nil)
        for bad in ["tab-A3F9", "tab-k3f9", "a3f9", "tab-a3f9; rm -rf /", ""] {
            #expect(A2UICommands.messages(sandbox: "web", id: bad, from: 0) == nil)
            #expect(A2UICommands.deliver(sandbox: "web", id: bad, line: line("{}")) == nil)
            #expect(A2UICommands.fetch(sandbox: "web", id: bad, url: url) == nil)
        }
    }

    /// What the operator typed (an obscured field's password, say) goes on stdin, never into argv.
    @Test func deliveredLinesGoOnStdinOnly() throws {
        let action = line(#"{"action":{"context":{"password":"correct horse"},"name":"login","sourceComponentId":"b","surfaceId":"s","timestamp":"2026-11-24T20:30:51Z"},"version":"1.0"}"#)
        let command = try #require(A2UICommands.deliver(sandbox: "web", id: "tab-a3f9", line: A2UIPolicy.lineForAgent(action)))
        #expect(command.arguments == ["exec", "-i", "web", "paddock", "--operator", "tab-a3f9", "a2ui"])
        #expect(!command.arguments.joined(separator: " ").contains("correct horse"))
        #expect(command.stdin == action + Data([0x0A]))
        #expect(A2UICommands.deliver(sandbox: "web", id: "tab-a3f9", line: line("{}\n{}")) == nil)
    }

    @Test func decodesTheMessageLog() {
        let bytes = log([line(Self.create)])
        #expect(A2UICommands.decodeMessages(Data(bytes.base64EncodedString().utf8)) == bytes)
        #expect(A2UICommands.decodeMessages(Data("***".utf8)) == nil)
        #expect(A2UICommands.decodeMessages(Data(count: A2UICommands.base64Length(A2UIPolicy.maxTabBytes) + 1)) == nil)
    }

    // MARK: - Media

    @Test func mediaFixtureResolvesEveryURLToOneSource() throws {
        let messages = try exampleLines("agent/media.json")
        let components = try JSONDecoder().decode(JSONValue.self, from: messages[1])["updateComponents"]?["components"]
        guard case .array(let list)? = components else {
            Issue.record("no components")
            return
        }
        var sources: [String: A2UIMedia.Source] = [:]
        for component in list {
            guard let type = component["component"]?.stringValue else { continue }
            let kind: A2UIMedia.Kind? = switch type {
            case "Image": .image
            case "Video": .video
            case "AudioPlayer": .audio
            default: nil
            }
            guard let kind, let id = component["id"]?.stringValue else { continue }
            // A URL bound to the data model resolves when the tab draws it.
            if let url = component["url"]?.stringValue {
                sources[id] = try A2UIMedia.source(for: url, kind: kind).get()
            }
            if let poster = component["posterUrl"]?.stringValue {
                sources[id + ".poster"] = try A2UIMedia.source(for: poster, kind: .image).get()
            }
        }
        #expect(sources["img_https"] == .sandboxFetch(try #require(URL(string: "https://images.example.com/photo.jpg"))))
        #expect(sources["img_relative"] == .sandboxFile("screenshots/home.png"))
        #expect(sources["video"] == .sandboxFile("recordings/demo.mp4"))
        #expect(sources["video.poster"] == .sandboxFetch(try #require(URL(string: "https://images.example.com/poster.jpg"))))
        #expect(sources["audio_relative"] == .sandboxFile("audio/notes.m4a"))
        guard case .inline(let png, let pngData)? = sources["img_data"], case .inline(let wav, let wavData)? = sources["audio_data"] else {
            Issue.record("data: URLs did not decode: \(sources)")
            return
        }
        #expect(png == "image/png")
        #expect(pngData.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(wav == "audio/wav")
        #expect(wavData.prefix(4) == Data("RIFF".utf8))
        #expect(sources.count == 7)
    }

    @Test func refusesEveryOtherSource() {
        let refused: [(String, A2UIMedia.Kind)] = [
            ("", .image),
            ("   ", .image),
            ("file:///etc/passwd", .image),
            ("javascript:alert(1)", .image),
            ("blob:https://example.com/1", .video),
            ("ftp://example.com/a.mp3", .audio),
            ("paddock-file://tab-a3f9/a.png", .image),
            ("http://", .image),
            ("//example.com/a.png", .image),
            ("/etc/hosts", .image),
            ("../outside.png", .image),
            ("shots/./a.png", .image),
            ("data:text/html,<script>alert(1)</script>", .image),
            ("data:image/png;base64,", .image),
            ("data:audio/wav;base64,UklGRg==", .video),
            ("data:image/png", .image),
        ]
        for (url, kind) in refused {
            guard case .failure(let refusal) = A2UIMedia.source(for: url, kind: kind) else {
                Issue.record("\(url) was not refused")
                continue
            }
            #expect(!refusal.reason.isEmpty)
        }
        // A colon inside a path is a path, and a percent-encoded data: URL decodes.
        #expect(A2UIMedia.source(for: "notes/12:30.png", kind: .image) == .success(.sandboxFile("notes/12:30.png")))
        #expect(A2UIMedia.source(for: "data:image/svg+xml,%3Csvg%2F%3E", kind: .image)
            == .success(.inline(mimeType: "image/svg+xml", data: Data("<svg/>".utf8))))
        #expect(A2UIMedia.source(for: "HTTPS://Example.com/a.png", kind: .image)
            == .success(.sandboxFetch(URL(string: "HTTPS://Example.com/a.png") ?? URL(fileURLWithPath: "/"))))
    }

    @Test func fetchedBytesMustBeOfTheirKind() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let answer = Data("image/jpeg; charset=binary\n".utf8) + Data(jpeg.base64EncodedString().utf8)
        let fetched = try A2UIMedia.decodeFetched(answer, kind: .image).get()
        #expect(fetched.mimeType == "image/jpeg")
        #expect(fetched.data == jpeg)
        #expect((try? A2UIMedia.decodeFetched(answer, kind: .video).get()) == nil)
        #expect((try? A2UIMedia.decodeFetched(Data("text/html\nPGh0bWw+".utf8), kind: .image).get()) == nil)
        #expect((try? A2UIMedia.decodeFetched(Data("image/png".utf8), kind: .image).get()) == nil)
        #expect((try? A2UIMedia.decodeFetched(Data("image/png\n".utf8), kind: .image).get()) == nil)
        #expect((try? A2UIMedia.decodeFetched(Data(count: A2UICommands.base64Length(A2UIMedia.maxBytes) + 300), kind: .image).get()) == nil)
    }

    @Test func mediaTypesFollowTheirFamily() {
        #expect(A2UIMedia.accepts("video/mp4", for: .video))
        #expect(A2UIMedia.accepts("Audio/MPEG; rate=44100", for: .audio))
        #expect(!A2UIMedia.accepts("image/", for: .image))
        #expect(!A2UIMedia.accepts("application/octet-stream", for: .image))
        #expect(!A2UIMedia.accepts("imagex/png", for: .image))
        #expect(A2UIMedia.mimeType(forPath: "recordings/demo.mp4") == "video/mp4")
        #expect(A2UIMedia.mimeType(forPath: "audio/notes.m4a") == "audio/mp4")
        #expect(A2UIMedia.mimeType(forPath: "screenshots/home.png") == "image/png")
        #expect(A2UIMedia.accepts(A2UIMedia.mimeType(forPath: "a.flac"), for: .audio))
    }
}
