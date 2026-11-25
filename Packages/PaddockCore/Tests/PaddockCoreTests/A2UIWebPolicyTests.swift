import Foundation
@testable import PaddockCore
import Testing

/// PAD-152.3: what the A2UI tab's web view may load and what its page may send (backlog doc Browser,
/// interactive tabs), against the page the app ships (`App/A2UI/manifest.json`).
@Suite("A2UI web policy")
struct A2UIWebPolicyTests {
    /// The app's page, from this checkout (`mise run vendor:a2ui-web` writes it).
    func manifest() throws -> A2UIWebPolicy.Manifest {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App/A2UI/manifest.json").standardizedFileURL
        return try A2UIWebPolicy.Manifest(data: Data(contentsOf: root))
    }

    func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    func base64url(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    @Test func theShippedPageIsWhollyInItsManifest() throws {
        let files = try manifest().files
        #expect(files["index.html"] == "text/html")
        #expect(files["host.js"] == "text/javascript")
        #expect(files["map-style.json"] != nil)
        #expect(files.keys.allSatisfy { NativeShowPolicy.isRelativePath($0) && !$0.hasPrefix("__media/") })
        let home = try #require(A2UIWebPolicy.homeURL)
        #expect(A2UIWebPolicy.request(for: home, manifest: try manifest()) == .file("index.html", mimeType: "text/html"))
    }

    @Test func onlyTheManifestsFilesAreServed() throws {
        let manifest = try manifest()
        #expect(A2UIWebPolicy.request(for: try url("paddock-a2ui://app/host.js"), manifest: manifest)
            == .file("host.js", mimeType: "text/javascript"))
        for refused in [
            "paddock-a2ui://app/manifest.json",
            "paddock-a2ui://app/VERSION",
            "paddock-a2ui://app/../Info.plist",
            "paddock-a2ui://app/%2E%2E/Info.plist",
            "paddock-a2ui://other/host.js",
            "https://app/host.js",
            "paddock-file://app/host.js",
            "paddock-a2ui://app/",
        ] {
            #expect(A2UIWebPolicy.request(for: try url(refused), manifest: manifest) == nil, "\(refused)")
        }
    }

    @Test func mediaComesBackAsTheURLTheComponentNamed() throws {
        let manifest = try manifest()
        for (kind, original) in [("image", "https://example.com/a b.png?x=1"), ("video", "clips/demo.mp4"), ("audio", "šum.ogg")] {
            let request = A2UIWebPolicy.request(for: try url("paddock-a2ui://app/__media/\(kind)/\(base64url(original))"), manifest: manifest)
            #expect(request == .media(try #require(A2UIMedia.Kind(rawValue: kind)), original))
        }
        for refused in [
            "paddock-a2ui://app/__media/script/\(base64url("a.js"))",
            "paddock-a2ui://app/__media/image/",
            "paddock-a2ui://app/__media/image/a+b",
            "paddock-a2ui://app/__media/image/\(base64url("a.png"))/more",
            "paddock-a2ui://app/__media/image/\(String(repeating: "A", count: 70000))",
        ] {
            #expect(A2UIWebPolicy.request(for: try url(refused), manifest: manifest) == nil, "\(refused.prefix(80))")
        }
    }

    @Test func mediaRangesAreTheBytesAskedFor() {
        #expect(A2UIWebPolicy.byteRange(nil, count: 100) == nil)
        #expect(A2UIWebPolicy.byteRange("bytes=0-1", count: 100) == 0..<2)
        #expect(A2UIWebPolicy.byteRange("bytes=10-", count: 100) == 10..<100)
        #expect(A2UIWebPolicy.byteRange("bytes=90-500", count: 100) == 90..<100)
        #expect(A2UIWebPolicy.byteRange("bytes=-20", count: 100) == 80..<100)
        #expect(A2UIWebPolicy.byteRange("bytes=-500", count: 100) == 0..<100)
        #expect(A2UIWebPolicy.byteRange("bytes=100-", count: 100) == 100..<100)
        for whole in ["items=0-1", "bytes=0-1,5-6", "bytes=5-2", "bytes=x-", "bytes=-0", "bytes=-"] {
            #expect(A2UIWebPolicy.byteRange(whole, count: 100) == nil, "\(whole)")
        }
    }

    @Test func clickedLinksOpenInTheSandbox() throws {
        #expect(A2UIWebPolicy.link(for: try url("https://example.com/docs")) == .web(try url("https://example.com/docs")))
        #expect(A2UIWebPolicy.link(for: try url("paddock-a2ui://app/reports/today.md")) == .file("reports/today.md"))
        #expect(A2UIWebPolicy.link(for: try url("paddock-a2ui://app/notes%20one.md#top")) == .file("notes one.md"))
        for refused in [
            "paddock-a2ui://app/index.html",
            "paddock-a2ui://app/__media/image/YQ",
            "paddock-a2ui://other/a.md",
            "mailto:someone@example.com",
            "file:///etc/passwd",
            "javascript:alert(1)",
        ] {
            #expect(A2UIWebPolicy.link(for: try url(refused)) == nil, "\(refused)")
        }
    }

    @Test func contentRulesBlockAllButThePage() throws {
        let rules = try JSONDecoder().decode([JSONValue].self, from: Data(A2UIWebPolicy.contentRules.utf8))
        #expect(rules.count == 4)
        #expect(A2UIWebPolicy.contentRules.contains(#""url-filter":".*"},"action":{"type":"block"}"#))
        #expect(A2UIWebPolicy.contentRules.contains("^paddock-a2ui://app/"))
    }

    @Test func messagesReachThePageAsOneString() throws {
        let hostile = Data(#"{"version":"1.0","updateDataModel":{"surfaceId":"s","path":"/x","value":"\");alert(1);//</script>"}}"#.utf8)
        let script = try #require(A2UIWebPolicy.renderScript(messages: [Data(A2UIPolicyTests.create.utf8), hostile]))
        #expect(script.hasPrefix("window.paddockA2UI && window.paddockA2UI.render(\""))
        #expect(script.hasSuffix("\");"))
        // The argument is one JSON string; decoded, it is the array of messages as they came.
        let literal = String(script.dropFirst("window.paddockA2UI && window.paddockA2UI.render(".count).dropLast(2))
        let array = try JSONDecoder().decode(String.self, from: Data(literal.utf8))
        let decoded = try JSONDecoder().decode([JSONValue].self, from: Data(array.utf8))
        #expect(decoded.count == 2)
        #expect(A2UIWebPolicy.renderScript(messages: []) == #"window.paddockA2UI && window.paddockA2UI.render("[]");"#)
    }

    @Test func whatThePagePostsIsChecked() throws {
        #expect(A2UIWebMessage(#"{"kind":"ready"}"#) == .ready)
        let action = #"{"kind":"action","message":{"version":"1.0","action":{"name":"approve","surfaceId":"budget","sourceComponentId":"go","timestamp":"2026-11-25T10:00:00Z","context":{"notes":"ok"}}}}"#
        guard case .action(let data)? = A2UIWebMessage(action) else {
            Issue.record("the action was refused")
            return
        }
        #expect(!data.contains(0x0A))
        #expect(String(decoding: data, as: UTF8.self).contains(#""name":"approve""#))
        let error = #"{"kind":"error","message":{"version":"1.0","error":{"code":"RENDER_FAILED","surfaceId":"s","message":"no"}}}"#
        guard case .error? = A2UIWebMessage(error) else {
            Issue.record("the error was refused")
            return
        }
        #expect(A2UIWebMessage(#"{"kind":"problem","text":"boom\nagain"}"#) == .problem("boomagain"))
        for refused in [
            "",
            "[]",
            #"{"kind":"eval","text":"x"}"#,
            #"{"kind":"action","message":{"version":"1.0","error":{}}}"#,
            #"{"kind":"action","message":"{}"}"#,
            #"{"kind":"action","message":{"version":"1.0","action":{"name":"\#(String(repeating: "x", count: A2UIWebMessage.maxBytes))"}}}"#,
        ] {
            #expect(A2UIWebMessage(refused) == nil, "\(refused.prefix(60))")
        }
    }

    /// Every action the renderer sent in the headless check (`Fixtures/a2ui-web/renderer`) passes,
    /// and comes out a line the agent may read.
    @Test func everyRendererFixturePasses() throws {
        let tests = A2UIPolicyTests()
        let lines = try tests.jsonl("renderer").flatMap(tests.fixtureLines)
        #expect(!lines.isEmpty)
        for line in lines {
            let body = #"{"kind":"action","message":"# + String(decoding: line, as: UTF8.self) + "}"
            guard case .action(let data)? = A2UIWebMessage(body) else {
                Issue.record("refused: \(String(decoding: line.prefix(120), as: UTF8.self))")
                continue
            }
            #expect(try JSONDecoder().decode(JSONValue.self, from: data) == JSONDecoder().decode(JSONValue.self, from: line))
        }
    }
}
