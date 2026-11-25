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
        #expect(!BaseKit.spec.contains("tab-k3f9") && BaseKit.spec.contains("tab-a3f9") && !BrowserKit.spec.contains("tab-k3f9"))
        #expect(!BrowserShow.script.contains("tab-k3f9"))
        #expect(BrowserShow.isShowID("tab-a3f9") && !BrowserShow.isShowID("tab-k3f9"))
    }

    /// PAD-147: paddock is the base kit's; live pages need the browser kit's playwright-cli, and
    /// say so without it. Native tabs work without it.
    @Test func livePagesNeedTheBrowserKitAndFilesDoNot() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try "# Plan\n".write(to: work.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
        for page in [["open", "http://localhost:3000"], ["open", "plan.md"], ["http://localhost:3000"]] {
            let refused = try paddock(page)
            #expect(refused.status != 0 && refused.err.contains("needs Paddock's browser kit"), "\(page): \(refused.err)")
        }
        let native = try paddock(["open", "plan.md", "--native"])
        #expect(native.status == 0, "\(native.err)")
        let id = try tabID(native)
        #expect(try paddock(["goto", id, "plan.md"]).status == 0)
        let records = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("tabs/shows").path)
        #expect(records == ["\(id).json"])
    }
}
