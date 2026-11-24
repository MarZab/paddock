import Foundation
@testable import PaddockCore
import Testing

/// PAD-150: the sandbox's `paddock` (`BrowserShow.script`), run under Node with its folders in a
/// temporary one.
@Suite("paddock helper", .enabled(if: NodeScriptTests.realNode != nil))
struct PaddockHelperTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-helper-\(UUID())")
    var work: URL { root.appendingPathComponent("work") }

    struct Run {
        let out: String
        let err: String
        let status: Int32
    }

    init() throws {
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let script = BrowserShow.script
            .replacingOccurrences(of: "/tmp/paddock-tabs", with: root.path + "/tabs")
            .replacingOccurrences(of: "/tmp/paddock-browser", with: root.path + "/browser")
        try script.write(to: root.appendingPathComponent("paddock"), atomically: true, encoding: .utf8)
    }

    @discardableResult
    func paddock(_ arguments: [String]) throws -> Run {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [root.appendingPathComponent("paddock").path] + arguments
        process.currentDirectoryURL = work
        process.environment = ["PATH": NodeScriptTests.realNodeFolder + ":/usr/bin:/bin", "HOME": root.path]
        let output = Pipe(), errors = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(out: String(decoding: out, as: UTF8.self), err: String(decoding: err, as: UTF8.self), status: process.terminationStatus)
    }

    func tabID(_ run: Run) throws -> String {
        try #require(run.out.firstMatch(of: /tab-[0-9a-f]{4}/)).output.description
    }

    /// What the operator did before the agent called wait is printed, not lost.
    @Test func waitPrintsWhatCameBeforeIt() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try "# Plan\n".write(to: work.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
        let id = try tabID(try paddock(["open", "plan.md", "--native"]))
        #expect(try paddock(["--operator", id, "opened"]).status == 0)
        let waited = try paddock(["wait", id, "--timeout", "1"])
        #expect(waited.status == 0 && waited.out.contains("the operator opened it"), "\(waited.out)")
        // seen now: the next wait has nothing new
        #expect(try paddock(["wait", id, "--timeout", "1"]).status == 3)
    }

    /// A call that fails while it holds the lock frees it: the next call does not wait 30 s.
    @Test func aFailedCallFreesTheLock() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try "x\n".write(to: work.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        for _ in 0..<BrowserShow.maxShows {
            #expect(try paddock(["open", "a.md", "--native"]).status == 0)
        }
        let refused = try paddock(["open", "a.md", "--native"])
        #expect(refused.status != 0 && refused.err.contains("tabs are open"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("tabs/lock").path))
        let start = Date()
        #expect(try paddock(["open", "a.md", "--native"]).status != 0)
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test func theGuideAndTheHelpShowAValidID() {
        #expect(!BrowserKit.spec.contains("tab-k3f9") && BrowserKit.spec.contains("tab-a3f9"))
        #expect(!BrowserShow.script.contains("tab-k3f9"))
        #expect(BrowserShow.isShowID("tab-a3f9") && !BrowserShow.isShowID("tab-k3f9"))
    }
}
