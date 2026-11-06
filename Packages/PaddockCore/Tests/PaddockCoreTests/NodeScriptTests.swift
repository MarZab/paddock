import Foundation
import Testing
@testable import PaddockCore

/// The kits' Node scripts start with whatever node works (backlog doc Kits, Node scripts; PAD-60).
@Suite("NodeScript")
struct NodeScriptTests {
    /// The node binary itself, for the tests that run one; nil skips them. The first node on PATH
    /// may be a version manager's shim (mise, asdf), which needs its manager on the PATH and fails
    /// with 127 under the tests' short PATHs, so the binary is asked for its own path (PAD-112).
    static let realNode: String? = (ProcessInfo.processInfo.environment["PATH"] ?? "")
        .split(separator: ":")
        .map { "\($0)/node" }
        .filter { FileManager.default.isExecutableFile(atPath: $0) }
        .lazy.compactMap { executablePath(of: $0) }.first

    /// What `node -p process.execPath` prints, or nil when that node does not run.
    private static func executablePath(of node: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = ["-p", "process.execPath"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// The folder of the node on PATH.
    static var realNodeFolder: String {
        realNode.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path } ?? "/nonexistent"
    }

    struct Result {
        let out: String
        let err: String
        let status: Int32
    }

    struct Folder {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-node-\(UUID())")

        init() throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        /// An executable file `name` in sub-folder `dir`.
        @discardableResult
        func executable(_ dir: String, _ name: String, _ text: String) throws -> URL {
            let folder = url.appendingPathComponent(dir)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(name)
            try text.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            return file
        }
    }

    /// A broken version manager's shim: says why on stderr and fails, as mise did for a version it
    /// could not install. It also swallows stdin, which the script must still get.
    static let brokenShim = """
        #!/bin/sh
        cat >/dev/null
        echo 'mise ERROR Failed to install core:node@26.12.1' >&2
        exit 1

        """

    /// The script reads stdin and its arguments, so both are checked to arrive.
    static let script = NodeScript.wrap("""
        'use strict';
        const input = require('fs').readFileSync(0, 'utf8').trim();
        console.log(input + ':' + process.argv.slice(2).join(','));
        """)

    func run(_ path: String, _ arguments: [String], path searchPath: String, stdin: String) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ["PATH": searchPath]
        let input = Pipe(), output = Pipe(), error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        try Self.runRetryingBusyText(process)
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(out: String(bytes: out, encoding: .utf8) ?? "", err: String(bytes: err, encoding: .utf8) ?? "",
                      status: process.terminationStatus)
    }

    /// Linux refuses to run a file another process still has open for writing (ETXTBSY): a test
    /// that forks while this one writes its script lends the child that descriptor until the
    /// child's exec. That ends in moments, so the run is tried again.
    static func runRetryingBusyText(_ process: Process) throws {
        for attempt in 1... {
            do {
                return try process.run()
            } catch let error as NSError where attempt < 50
                && (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(ETXTBSY) {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    @Test func theHeaderIsShellThenJavaScript() {
        let lines = NodeScript.header.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines.first == "#!/bin/sh")
        // To Node, the second line is a string and a comment; nothing in it ends the comment early.
        #expect(lines.last?.hasPrefix("':' //;") == true)
        #expect(NodeScript.wrap("x").hasSuffix("\nx"))
    }

    @Test(.enabled(if: realNode != nil))
    func aBrokenShimFirstOnPathIsSkipped() throws {
        let folder = try Folder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.executable("shims", "node", Self.brokenShim)
        let script = try folder.executable("bin", "paddock-test", Self.script)
        let searchPath = "\(folder.url.path)/shims:\(Self.realNodeFolder):/bin"
        let result = try run(script.path, ["a", "b c"], path: searchPath, stdin: "hello\n")
        #expect(result.status == 0)
        #expect(result.out == "hello:a,b c\n")
        #expect(!result.err.contains("mise"))
    }

    /// The kits' install steps run the settings merge with `sh FILE`, not through its `#!`.
    @Test(.enabled(if: realNode != nil))
    func runsWithShToo() throws {
        let folder = try Folder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let script = try folder.executable("bin", "merge.js", Self.script)
        let result = try run("/bin/sh", [script.path, "x"], path: Self.realNodeFolder, stdin: "in")
        #expect(result.out == "in:x\n")
    }

    /// Only broken nodes on PATH: the fixed places come next; with none there either, a clear
    /// error and 127 instead of the shim's.
    @Test func onlyBrokenNodesEndsWithAClearError() throws {
        let fixedPlaces = ["/usr/local/bin/node", "/usr/bin/node"]
            .contains { FileManager.default.isExecutableFile(atPath: $0) }
        let folder = try Folder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.executable("shims", "node", Self.brokenShim)
        let script = try folder.executable("bin", "paddock-test", Self.script)
        let result = try run(script.path, [], path: "\(folder.url.path)/shims:/bin", stdin: "hi")
        if fixedPlaces {
            #expect(result.status == 0 && result.out == "hi:\n")
        } else {
            #expect(result.status == 127)
            #expect(result.err.contains("paddock-test: no node that runs"))
        }
    }

    @Test func everyKitNodeScriptHasTheHeader() {
        for script in [VoiceKit.script, BrowserShow.script, BrowserActivity.watcher, AgentStatusKit.claudeMergeScript] {
            #expect(script.hasPrefix(NodeScript.header + "\n"))
            #expect(!script.contains("#!/usr/bin/env node"))
        }
        #expect(AgentStatusKit.spec.contains("HOME=/home/agent sh /tmp/paddock-status-merge.js"))
        #expect(VoiceKit.spec.contains("HOME=/home/agent sh /tmp/paddock-voice-merge.js"))
    }
}
