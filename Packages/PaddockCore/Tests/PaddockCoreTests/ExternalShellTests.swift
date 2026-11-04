import Foundation
import Testing
@testable import PaddockCore

/// The toolbar's Terminal button: a shell in the sandbox in the operator's own terminal app.
@Suite("ExternalShell")
struct ExternalShellTests {
    @Test func theScriptRunsTheShellTabsCommandAndRemovesItself() throws {
        let dir = NSTemporaryDirectory() + "paddock-shell-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir + "/bin dir", withIntermediateDirectories: true)
        // A fake sbx in a path with a space and a quote, recording its arguments.
        let sbx = dir + "/bin dir/sb'x"
        try Data("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"\(dir)/args\"\n".utf8).write(to: URL(fileURLWithPath: sbx))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sbx)
        let file = dir + "/" + ExternalShell.fileName(sandbox: "paddock-app")
        try Data(try ExternalShell.script(sbx: sbx, sandbox: "paddock-app").utf8).write(to: URL(fileURLWithPath: file))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [file]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let args = String(decoding: FileManager.default.contents(atPath: dir + "/args") ?? Data(), as: UTF8.self)
        #expect(args == "exec\n-it\npaddock-app\nbash\n")
        #expect(!FileManager.default.fileExists(atPath: file))
    }

    @Test func theHostScriptStartsTheShellInTheProjectFolder() throws {
        let dir = NSTemporaryDirectory() + "paddock-host-shell-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }
        // A folder with a space, a quote, and a would-be command substitution.
        let folder = dir + "/it's $(touch pwned) here"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        // The "shell" records where it started.
        let shell = dir + "/shell"
        try Data("#!/bin/sh\npwd > \"\(dir)/cwd\"\n".utf8).write(to: URL(fileURLWithPath: shell))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell)
        let file = dir + "/" + ExternalShell.hostFileName(project: "paddock-app")
        let script = try ExternalShell.hostScript(folder: folder, project: "paddock-app")
        try Data(script.utf8).write(to: URL(fileURLWithPath: file))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [file]
        process.environment = ["SHELL": shell]
        // Where an unquoted $(touch pwned) would land.
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let cwd = String(decoding: FileManager.default.contents(atPath: dir + "/cwd") ?? Data(), as: UTF8.self)
        #expect(cwd == URL(fileURLWithPath: folder).resolvingSymlinksInPath().path + "\n" || cwd == folder + "\n")
        #expect(!FileManager.default.fileExists(atPath: dir + "/pwned"))
        #expect(!FileManager.default.fileExists(atPath: file))
    }

    @Test func onlySandboxNamesSbxAccepts() {
        #expect(throws: ExternalShell.Problem.invalidSandboxName("x'; rm -rf ~")) {
            try ExternalShell.script(sbx: "/opt/homebrew/bin/sbx", sandbox: "x'; rm -rf ~")
        }
        #expect(ExternalShell.fileName(sandbox: "paddock-app") == "paddock-shell-paddock-app.command")
    }
}
