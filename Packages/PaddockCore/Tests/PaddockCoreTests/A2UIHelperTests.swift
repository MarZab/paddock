import Foundation
@testable import PaddockCore
import Testing

/// PAD-152.2: the sandbox's `paddock` for A2UI tabs (`BrowserShow.script`), run under Node with its
/// folders in a temporary one, and its answers read with PaddockCore's A2UI rules.
@Suite("A2UI helper", .enabled(if: NodeScriptTests.realNode != nil))
struct A2UIHelperTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-a2ui-helper-\(UUID())")
    var work: URL { root.appendingPathComponent("work") }

    struct Run {
        let out: String
        let err: String
        let status: Int32
        var data: Data { Data(out.utf8) }
    }

    init() throws {
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let script = BrowserShow.script
            .replacingOccurrences(of: "/tmp/paddock-tabs", with: root.path + "/tabs")
            .replacingOccurrences(of: "/tmp/paddock-browser", with: root.path + "/browser")
        try script.write(to: root.appendingPathComponent("paddock"), atomically: true, encoding: .utf8)
    }

    @discardableResult
    func paddock(_ arguments: [String], stdin: String = "") throws -> Run {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [root.appendingPathComponent("paddock").path] + arguments
        process.currentDirectoryURL = work
        process.environment = ["PATH": NodeScriptTests.realNodeFolder + ":/usr/bin:/bin", "HOME": root.path]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(out: String(decoding: out, as: UTF8.self), err: String(decoding: err, as: UTF8.self), status: process.terminationStatus)
    }

    func write(_ name: String, _ text: String) throws {
        try text.write(to: work.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func fixture(_ path: String) throws -> Data {
        let folder = try #require(Bundle.module.url(forResource: "a2ui-web", withExtension: nil, subdirectory: nil))
        return try Data(contentsOf: folder.appendingPathComponent(path))
    }

    func tabID(_ run: Run) throws -> String {
        try #require(run.out.firstMatch(of: /tab-[0-9a-f]{4}/)).output.description
    }

    @Test func aTabKeepsTheAgentsMessagesOnePerLine() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        // A file as the agent may write it: pretty-printed, with its messages in "messages".
        let dashboard = try String(decoding: fixture("agent/paddock-dashboard.jsonl"), as: UTF8.self).split(separator: "\n").map {
            try JSONSerialization.jsonObject(with: Data($0.utf8))
        }
        try JSONSerialization.data(withJSONObject: ["messages": dashboard], options: .prettyPrinted).write(to: work.appendingPathComponent("login.json"))
        let opened = try paddock(["ui", "login.json", "--title", "Sign in"])
        #expect(opened.status == 0, "\(opened.err)")
        let id = try tabID(opened)
        let first = try paddock(["--messages", id, "0"])
        let log = try #require(A2UICommands.decodeMessages(first.data))
        var inbox = A2UIInbox()
        let intake = inbox.take(log)
        #expect(intake.refusals == [] && intake.messages.count == 3)
        #expect(inbox.offset == log.count)

        // More messages, as JSONL from stdin: appended, and only they come from the offset on.
        let more = String(decoding: try fixture("agent/samples-charts.jsonl"), as: UTF8.self)
        let count = more.split(separator: "\n").count
        let sent = try paddock(["ui", id, "-"], stdin: more)
        #expect(sent.status == 0 && sent.out.contains("Sent \(count) messages"), "\(sent.err)")
        let next = try #require(A2UICommands.decodeMessages(try paddock(["--messages", id, String(inbox.offset)]).data))
        #expect(inbox.take(next).messages.count == count)
        let record = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("tabs/shows/\(id).json"))) as? [String: Any]
        #expect(record?["revision"] as? Int == 1 && record?["mode"] as? String == "ui")
        #expect(try paddock(["--messages", id, "999999"]).out.isEmpty)
    }

    @Test func badMessagesAreRefusedBeforeATabOpens() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("notjson.jsonl", "{\"version\":\"1.0\",\"deleteSurface\":{\"surfaceId\":\"s\"}}\n{nope\n")
        let notJSON = try paddock(["ui", "notjson.jsonl"])
        #expect(notJSON.status != 0 && notJSON.err.contains("line 2"))
        try write("old.json", #"{"version":"0.9","createSurface":{"surfaceId":"s"}}"#)
        #expect(try paddock(["ui", "old.json"]).err.contains(#""version": "1.0""#))
        try write("empty.json", "  \n")
        #expect(try paddock(["ui", "empty.json"]).status != 0)
        try write("big.json", #"{"version":"1.0","updateDataModel":{"surfaceId":"s","value":""# + String(repeating: "x", count: 600 * 1024) + #""}}"#)
        #expect(try paddock(["ui", "big.json"]).err.contains("KB"))
        // None of them opened a tab.
        #expect((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("tabs/shows").path)) ?? [] == [])
    }

    @Test func whatTheTabSendsIsWhatWaitPrints() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("form.jsonl", String(decoding: try fixture("agent/paddock-dashboard.jsonl"), as: UTF8.self))
        let id = try tabID(try paddock(["ui", "form.jsonl"]))
        let action = try fixtureLine("renderer/paddock-dashboard.jsonl")
        let refused = String(decoding: A2UIEvent.refused(line: 2, reason: "the line is not JSON").json, as: UTF8.self)
        let delivery = try #require(A2UICommands.deliver(sandbox: "web", id: id, line: Data(action.utf8)))
        // What Paddock runs: --operator ID a2ui, the line on stdin.
        let arguments = Array(delivery.arguments.drop { $0 != "--operator" })
        #expect(try paddock(arguments, stdin: String(decoding: delivery.stdin ?? Data(), as: UTF8.self)).status == 0)
        #expect(try paddock(["--operator", id, "a2ui"], stdin: refused + "\n").status == 0)
        let waited = try paddock(["wait", id, "--timeout", "1"])
        #expect(waited.out == action + "\n" + refused + "\n")
        // Not one line of JSON, or too large: refused.
        #expect(try paddock(["--operator", id, "a2ui"], stdin: "{}\n{}\n").status != 0)
        #expect(try paddock(["--operator", id, "a2ui"], stdin: "nope").status != 0)
        #expect(try paddock(["--operator", id, "a2ui"], stdin: "\"" + String(repeating: "y", count: A2UIPolicy.maxOutboundBytes) + "\"").status != 0)
    }

    func fixtureLine(_ path: String) throws -> String {
        try #require(String(decoding: try fixture(path), as: UTF8.self).split(separator: "\n").first).description
    }

    @Test func mediaFilesComeFromBesideTheMessagesOnly() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: work.appendingPathComponent("shots"), withIntermediateDirectories: true)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try png.write(to: work.appendingPathComponent("shots/home.png"))
        try "secret".write(to: root.appendingPathComponent("outside.txt"), atomically: true, encoding: .utf8)
        try fixture("agent/paddock-dashboard.jsonl").write(to: work.appendingPathComponent("media.jsonl"))
        let id = try tabID(try paddock(["ui", "media.jsonl"]))
        let read = try paddock(["--read", id, "shots/home.png"])
        #expect(Data(base64Encoded: read.out) == png)
        #expect(try paddock(["--read", id, "../outside.txt"]).status != 0)
        #expect(try paddock(["--read", id, ""]).status != 0)
        try FileManager.default.createSymbolicLink(at: work.appendingPathComponent("link.txt"), withDestinationURL: root.appendingPathComponent("outside.txt"))
        #expect(try paddock(["--read", id, "link.txt"]).status != 0)
        // A fetch is the sandbox's, and http(s) only.
        for url in ["file:///etc/passwd", "ftp://example.com/a.png", "", "gopher://x"] {
            #expect(try paddock(["--fetch", id, url]).status != 0, "\(url)")
        }
    }

    @Test func gotoSendsAndOnlyTheOperatorRedraws() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("one.jsonl", #"{"version":"1.0","createSurface":{"surfaceId":"s","catalogId":"\#(A2UIPolicy.catalogID)"}}"# + "\n")
        try write("two.jsonl", #"{"version":"1.0","deleteSurface":{"surfaceId":"s"}}"# + "\n")
        let id = try tabID(try paddock(["ui", "one.jsonl"]))
        #expect(try paddock(["goto", id, "two.jsonl"]).out.contains("Sent 1 message"))
        #expect(try paddock(["reload", id]).status != 0)
        #expect(try paddock(["back", id]).status != 0)
        #expect(try paddock(["--operator", id, "reload"]).status == 0)
        #expect(try paddock(["status", id]).out.contains("the operator drew it again"))
        let log = try #require(A2UICommands.decodeMessages(try paddock(["--messages", id, "0"]).data))
        #expect(String(decoding: log, as: UTF8.self).split(separator: "\n").count == 2)
    }

    /// A file link the operator clicks in a tab opens that file, next to the tab's messages, as a native tab.
    @Test func aFileLinkOpensANativeTab() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: work.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try write("notes/plan.md", "# Plan\n")
        try "secret".write(to: root.appendingPathComponent("outside.md"), atomically: true, encoding: .utf8)
        try fixture("agent/paddock-dashboard.jsonl").write(to: work.appendingPathComponent("media.jsonl"))
        let id = try tabID(try paddock(["ui", "media.jsonl"]))
        let opened = try paddock(["--show-file", id, "notes/plan.md"])
        #expect(opened.status == 0, "\(opened.err)")
        let native = try tabID(opened)
        let record = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("tabs/shows/\(native).json"))) as? [String: Any]
        #expect(record?["mode"] as? String == "native")
        #expect((record?["path"] as? String)?.hasSuffix("/work/notes/plan.md") == true)
        for refused in ["../outside.md", "", "notes", "missing.md"] {
            #expect(try paddock(["--show-file", id, refused]).status != 0, "\(refused)")
        }
        // only from an interactive tab
        #expect(try paddock(["--show-file", native, "plan.md"]).status != 0)
    }
}
