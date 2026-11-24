import A2UICore
import A2UISwiftUI
import Foundation
import OrderedJSON
import PaddockCore
@testable import PaddockA2UI
import Testing

/// What a tab asked of the sandbox.
actor FakeLink: A2UITabLink {
    private(set) var delivered: [Data] = []
    private(set) var asked: [A2UIMedia.Source] = []
    private(set) var opened: [URL] = []
    var answer: (mimeType: String, data: Data)?

    func deliver(_ line: Data) async throws { delivered.append(line) }

    func media(_ source: A2UIMedia.Source, kind: A2UIMedia.Kind) async throws -> (mimeType: String, data: Data) {
        asked.append(source)
        guard let answer else { throw URLError(.cannotFindHost) }
        return answer
    }

    func openInSandbox(_ url: URL) async throws { opened.append(url) }

    func setAnswer(_ answer: (mimeType: String, data: Data)?) { self.answer = answer }

    /// The delivered lines, decoded.
    func messages() -> [PaddockCore.JSONValue] {
        delivered.compactMap { try? JSONDecoder().decode(PaddockCore.JSONValue.self, from: $0) }
    }
}

/// PAD-146.3: A2UI tabs with A2UI's own Swift renderer, fed PaddockCore's A2UI fixtures
/// (`Packages/PaddockCore/Tests/PaddockCoreTests/Fixtures/a2ui`). Runs on the Mac only.
@MainActor
@Suite("A2UI tab")
struct A2UITabTests {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("PaddockCore/Tests/PaddockCoreTests/Fixtures/a2ui")

    func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("paddock-a2ui-tests-" + UUID().uuidString)
    }

    /// An example's messages as the sandbox's log holds them: one line each.
    func log(_ example: String) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.fixtures.appendingPathComponent(example))) as? [String: Any]
        return try (object?["messages"] as? [Any] ?? []).reduce(into: Data()) { log, message in
            log += try JSONSerialization.data(withJSONObject: message) + Data([0x0A])
        }
    }

    /// Lets the tab's deliveries (tasks, in order) reach the link.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(100))
    }

    func nodes(_ node: Node?) -> [Node] {
        guard let node else { return [] }
        return [node] + node.allChildNodes.flatMap { nodes($0) }
    }

    func node(_ id: String, in tab: A2UITab) -> Node? {
        tab.surfaces.flatMap { nodes($0.rootNode) }.first { $0.id == id }
    }

    @Test func theCatalogIsTheWholeBasicCatalog() throws {
        let tab = A2UITab(id: "tab-a3f9", link: FakeLink(), folder: folder())
        #expect(tab.catalog.id == A2UIPolicy.basicCatalogID)
        let basic = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.fixtures.appendingPathComponent("catalog.json"))) as? [String: Any]
        let components = Set((basic?["components"] as? [String: Any] ?? [:]).keys)
        let functions = Set((basic?["functions"] as? [String: Any] ?? [:]).keys)
        #expect(components.count == 18 && functions.count == 14)
        #expect(Set(tab.catalog.components.keys) == components)
        #expect(functions.isSubset(of: Set(tab.catalog.functions.keys)))
    }

    @Test func everyExampleRendersWithoutAnError() async throws {
        let examples = try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.appendingPathComponent("examples").path)
            .filter { $0.hasSuffix(".json") }.sorted().map { "examples/" + $0 } + ["agent/media.json", "agent/functions.json"]
        #expect(examples.count == 45)
        for example in examples {
            let link = FakeLink()
            let tab = A2UITab(id: "tab-a3f9", link: link, folder: folder())
            #expect(tab.take(try log(example)).isEmpty, "\(example)")
            await settle()
            #expect(!tab.surfaces.isEmpty, "\(example)")
            #expect(tab.surfaces.allSatisfy { $0.rootNode != nil }, "\(example)")
            let sent = await link.messages()
            #expect(sent.isEmpty, "\(example): \(sent)")
            tab.dispose()
        }
    }

    /// The Linux capture cannot check pluralize (Fixtures/a2ui/README.md); the Mac can.
    @Test func pluralizeFormatsForTheCount() async throws {
        let tab = A2UITab(id: "tab-a3f9", link: FakeLink(), folder: folder())
        tab.take(try log("agent/functions.json"))
        await settle()
        #expect(node("replicas_label", in: tab)?.string(for: "text") == "Several replicas")
        tab.surfaces.first?.dataModel.set("/replicas", value: .integer(1))
        await settle()
        #expect(node("replicas_label", in: tab)?.string(for: "text") == "One replica")
    }

    @Test func anActionReachesTheAgentWithWhatTheOperatorTyped() async throws {
        let link = FakeLink()
        let tab = A2UITab(id: "tab-a3f9", link: link, folder: folder())
        tab.take(try log("examples/login-form.json"))
        await settle()
        let surface = try #require(tab.surfaces.first)
        surface.dataModel.set("/email", value: .string("ann@example.com"))
        surface.dataModel.set("/password", value: .string("correct horse"))
        await settle()
        node("login_btn", in: tab)?.action(for: "action", userActivation: true)?()
        await settle()
        let action = try #require(await link.messages().first?["action"])
        #expect(action["name"]?.stringValue == "login")
        #expect(action["context"]?["email"]?.stringValue == "ann@example.com")
        #expect(tab.notice?.ok == true && tab.notice?.text == "Sent to the agent")
    }

    @Test func aRefusedLineIsToldToTheAgentAndTheRestRenders() async throws {
        let link = FakeLink()
        let tab = A2UITab(id: "tab-a3f9", link: link, folder: folder())
        let refused = tab.take(Data("{not json\n".utf8) + (try log("examples/login-form.json")))
        await settle()
        #expect(refused.map(\.line) == [1])
        #expect(tab.surfaces.count == 1)
        #expect(await link.messages().first?["paddock"]?.stringValue == "refused")
    }

    /// A function the catalog lacks goes to the agent; the tab waits until it answers.
    @Test func aCallToTheAgentWaitsForItsAnswer() async throws {
        let link = FakeLink()
        let tab = A2UITab(id: "tab-a3f9", link: link, folder: folder())
        let create = #"{"version":"1.0","createSurface":{"surfaceId":"s","catalogId":"\#(A2UIPolicy.basicCatalogID)"}}"#
        let text = #"{"version":"1.0","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Text","text":{"@call":"lookupGreeting","args":{"name":"Ann"}}}]}}"#
        tab.take(Data((create + "\n" + text + "\n").utf8))
        await settle()
        let call = try #require(await link.messages().first?["callAgentFunction"])
        let id = try #require(call["functionCallId"]?.stringValue)
        #expect(tab.waitingCalls == [id])
        let answer = #"{"version":"1.0","agentFunctionResponse":{"functionCallId":"\#(id)","value":"Hello, Ann"}}"#
        tab.take(Data((answer + "\n").utf8))
        await settle()
        #expect(tab.waitingCalls.isEmpty)
        #expect(node("root", in: tab)?.string(for: "text") == "Hello, Ann")
    }

    @Test func mediaComesThroughTheSandboxOrFromDataURLs() async throws {
        let link = FakeLink()
        let files = folder()
        let tab = A2UITab(id: "tab-a3f9", link: link, folder: files)
        let png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let inline = try await tab.media.load(png, kind: .image).get()
        #expect(inline.url.pathExtension == "png" && FileManager.default.fileExists(atPath: inline.url.path))
        #expect(await link.asked.isEmpty)
        // A web URL is the sandbox's to fetch; without an answer, the reason shows.
        guard case .failure(let refusal) = await tab.media.load("https://images.example.com/photo.jpg", kind: .image) else {
            Issue.record("loaded without the sandbox")
            return
        }
        #expect(refusal.reason.contains("sandbox"))
        await link.setAnswer(("video/mp4", Data([0, 0, 0, 0x18])))
        let video = try await tab.media.load("recordings/demo.mp4", kind: .video).get()
        #expect(video.url.pathExtension == "mp4")
        let photo = try #require(URL(string: "https://images.example.com/photo.jpg"))
        #expect(await link.asked == [.sandboxFetch(photo), .sandboxFile("recordings/demo.mp4")])
        // Once per URL.
        _ = await tab.media.load("recordings/demo.mp4", kind: .video)
        #expect(await link.asked.count == 2)
        #expect((try? await tab.media.load("javascript:alert(1)", kind: .image).get()) == nil)
        tab.dispose()
        #expect(!FileManager.default.fileExists(atPath: files.path))
    }

    @Test func openURLOpensInTheSandbox() async throws {
        let link = FakeLink()
        let tab = A2UITab(id: "tab-a3f9", link: link, folder: folder())
        tab.take(try log("agent/media.json"))
        await settle()
        node("open_docs", in: tab)?.action(for: "action", userActivation: true)?()
        await settle()
        let docs = try #require(URL(string: "https://docs.example.com/a2ui"))
        #expect(await link.opened == [docs])
        #expect(tab.notice?.ok == true)
    }
}
