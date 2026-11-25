import Foundation
@testable import PaddockCore
import Testing

/// PAD-152.2: what crosses between a sandbox and an A2UI tab (backlog doc Browser, interactive
/// tabs), checked with the A2UI fixtures (`Fixtures/a2ui-web/README.md`).
@Suite("A2UI policy")
struct A2UIPolicyTests {
    func fixture(_ path: String) throws -> Data {
        guard let folder = Bundle.module.url(forResource: "a2ui-web", withExtension: nil, subdirectory: nil) else {
            throw FixtureError.missing("a2ui-web")
        }
        return try Data(contentsOf: folder.appendingPathComponent(path))
    }

    func fixtureLines(_ path: String) throws -> [Data] {
        try fixture(path).split(separator: 0x0A).map { Data($0) }
    }

    /// The JSONL fixtures of a folder, as paths under the fixture root.
    func jsonl(_ folder: String) throws -> [String] {
        let root = try #require(Bundle.module.url(forResource: "a2ui-web", withExtension: nil, subdirectory: nil))
        return try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)
            .filter { $0.hasSuffix(".jsonl") }.sorted().map { folder + "/" + $0 }
    }

    func log(_ lines: [Data]) -> Data {
        lines.reduce(into: Data()) { $0 += $1 + Data([0x0A]) }
    }

    func line(_ text: String) -> Data { Data(text.utf8) }

    static let create = #"{"version":"1.0","createSurface":{"surfaceId":"s","catalogId":"https://copilotkit.ai/a2ui/catalogs/playground/v1"}}"#
    static let text = #"{"version":"1.0","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Text","text":"Hi"}]}}"#

    // MARK: - From the sandbox

    @Test func everyAgentFixtureGoesThroughUnchanged() throws {
        let lines = try jsonl("agent").flatMap(fixtureLines)
        #expect(lines.count > 100)
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
        #expect(intake.refusals[4].reason.contains(A2UIPolicy.catalogID))
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
        let lines = try jsonl("renderer").flatMap(fixtureLines)
        #expect(lines.count >= 7)
        #expect(lines.allSatisfy { (try? JSONDecoder().decode(JSONValue.self, from: $0))?["action"] != nil })
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

    /// Every picture URL in the playground's samples is a web URL the sandbox fetches.
    @Test func samplePicturesComeThroughTheSandbox() throws {
        var urls: [String] = []
        func walk(_ value: JSONValue) {
            switch value {
            case .object(let object):
                for (key, inner) in object {
                    if ["url", "src", "image", "avatar", "poster", "photo"].contains(key), let text = inner.stringValue, text.hasPrefix("http") {
                        urls.append(text)
                    }
                    walk(inner)
                }
            case .array(let array): array.forEach(walk)
            default: break
            }
        }
        for line in try jsonl("agent").flatMap(fixtureLines) {
            walk(try JSONDecoder().decode(JSONValue.self, from: line))
        }
        #expect(urls.count >= 5)
        for url in urls {
            guard case .success(.sandboxFetch(let parsed)) = A2UIMedia.source(for: url, kind: .image) else {
                Issue.record("\(url) is not a sandbox fetch")
                continue
            }
            #expect(parsed.absoluteString == url)
        }
        #expect(A2UIMedia.source(for: "screenshots/home.png", kind: .image) == .success(.sandboxFile("screenshots/home.png")))
    }

    /// Links the operator clicks (PAD-152): a sandbox page or a file next to the messages, nothing else.
    @Test func linksOpenTheSandboxsPageOrAFileNextToTheMessages() throws {
        #expect(A2UILink("https://docs.example.com/a2ui") == .web(try #require(URL(string: "https://docs.example.com/a2ui"))))
        #expect(A2UILink("notes/plan.md#step-2") == .file("notes/plan.md"))
        #expect(A2UILink("report%20one.html") == .file("report one.html"))
        for dead in ["mailto:a@b.c", "file:///etc/passwd", "javascript:alert(1)", "/etc/hosts", "../secret.md", "./x.md", "", "http://", "ftp://x/y"] {
            #expect(A2UILink(dead) == nil, "\(dead)")
        }
        #expect(A2UICommands.openFile(sandbox: "web", id: "tab-a3f9", relativePath: "notes/plan.md")?.arguments
            == ["exec", "web", "paddock", "--show-file", "tab-a3f9", "notes/plan.md"])
        #expect(A2UICommands.openFile(sandbox: "web", id: "tab-a3f9", relativePath: "../x") == nil)
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

    // MARK: - Through sbx

    func runner() -> (FakeRunner, ProjectRunner, Project) {
        let fake = FakeRunner()
        let runner = ProjectRunner(sbx: SbxService(runner: fake, sbx: URL(fileURLWithPath: "/sbx")), paths: PaddockPaths(configDirectory: "/tmp/p"))
        return (fake, runner, Project(name: "web", folder: "/a"))
    }

    @Test func theRunnerReadsTheLogAndDeliversOnStdin() async throws {
        let (fake, runner, project) = runner()
        let log = log([line(Self.create)])
        fake.respond(to: ["exec", "web", "paddock", "--messages", "tab-a3f9", "0"], with: Data(log.base64EncodedString().utf8))
        #expect(try await runner.a2uiMessages(show: "tab-a3f9", from: 0, of: project) == log)
        let action = line(#"{"action":{"context":{"password":"correct horse"},"name":"login"},"version":"1.0"}"#)
        fake.respond(to: ["exec", "-i", "web", "paddock", "--operator", "tab-a3f9", "a2ui"], with: Data())
        try await runner.a2uiDeliver(action, show: "tab-a3f9", of: project)
        #expect(fake.calls.last == ["exec", "-i", "web", "paddock", "--operator", "tab-a3f9", "a2ui"])
        #expect(fake.stdins.last == action + Data([0x0A]))
        await #expect(throws: (any Error).self) { try await runner.a2uiDeliver(action, show: "nope", of: project) }
    }

    @Test func theRunnerGetsMediaFromTheSandboxOnly() async throws {
        let (fake, runner, project) = runner()
        let url = try #require(URL(string: "https://images.example.com/photo.jpg"))
        fake.respond(to: ["exec", "web", "paddock", "--fetch", "tab-a3f9", url.absoluteString], with: Data("image/jpeg\n/9j/4A==".utf8))
        let fetched = try await runner.a2uiMedia(.sandboxFetch(url), kind: .image, show: "tab-a3f9", of: project)
        #expect(fetched.mimeType == "image/jpeg" && fetched.data == Data([0xFF, 0xD8, 0xFF, 0xE0]))
        await #expect(throws: A2UIMedia.Refusal.self) { try await runner.a2uiMedia(.sandboxFetch(url), kind: .video, show: "tab-a3f9", of: project) }
        fake.respond(to: ["exec", "web", "paddock", "--read", "tab-a3f9", "audio/notes.m4a"], with: Data("AAAA".utf8))
        let file = try await runner.a2uiMedia(.sandboxFile("audio/notes.m4a"), kind: .audio, show: "tab-a3f9", of: project)
        #expect(file.mimeType == "audio/mp4" && file.data == Data([0, 0, 0]))
        // A picture's name for an audio clip: refused, whatever its bytes.
        fake.respond(to: ["exec", "web", "paddock", "--read", "tab-a3f9", "a.png"], with: Data("AAAA".utf8))
        await #expect(throws: A2UIMedia.Refusal.self) { try await runner.a2uiMedia(.sandboxFile("a.png"), kind: .audio, show: "tab-a3f9", of: project) }
        // Only the sandbox: every call went through sbx exec.
        #expect(fake.calls.allSatisfy { $0.first == "exec" })
    }

    @Test func openURLBecomesASandboxBrowserTab() async throws {
        let (fake, runner, project) = runner()
        let url = try #require(URL(string: "https://docs.example.com/a2ui"))
        fake.respond(to: ["exec", "web", "paddock", "open", "https://docs.example.com/a2ui"], with: Data())
        try await runner.a2uiOpen(url, of: project)
        #expect(fake.calls == [["exec", "web", "paddock", "open", "https://docs.example.com/a2ui"]])
        for other in ["mailto:ann@example.com", "tel:+1555", "file:///etc/passwd", "javascript:alert(1)"] {
            await #expect(throws: (any Error).self) { try await runner.a2uiOpen(try #require(URL(string: other)), of: project) }
        }
        #expect(fake.calls.count == 1)
    }
}
