import Foundation
import Testing
@testable import PaddockCore

/// Security rule: only a safe, operator-chosen folder may be mounted (CLAUDE.md, Security rules).
@Suite("FolderPolicy")
struct FolderPolicyTests {
    /// A throwaway fake home: <tmp>/home with .config/paddock and Projects/app inside.
    struct Sandbox {
        let root: String
        let home: String
        let config: String
        let project: String
        let policy: FolderPolicy

        init() throws {
            root = FolderPolicy.canonical(NSTemporaryDirectory()) + "/paddock-tests-" + UUID().uuidString
            home = root + "/home"
            config = home + "/.config/paddock"
            project = home + "/Projects/app"
            for dir in [config, project] {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
            policy = FolderPolicy(home: home, paddockConfigDirectory: config)
        }

        func mkdir(_ path: String) throws {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }

        func cleanup() {
            try? FileManager.default.removeItem(atPath: root)
        }
    }

    @Test func acceptsAProjectFolder() throws {
        let fs = try Sandbox()
        defer { fs.cleanup() }
        try fs.policy.check(fs.project)
    }

    @Test func rejectsRoot() throws {
        let fs = try Sandbox()
        defer { fs.cleanup() }
        #expect(throws: FolderPolicyViolation.root) { try fs.policy.check("/") }
    }

    @Test func rejectsHome() throws {
        let fs = try Sandbox()
        defer { fs.cleanup() }
        #expect(throws: FolderPolicyViolation.home) { try fs.policy.check(fs.home) }
        #expect(throws: FolderPolicyViolation.home) { try fs.policy.check(fs.home + "/") }
        #expect(throws: FolderPolicyViolation.home) { try fs.policy.check(fs.project + "/../..") }
    }

    @Test func rejectsAFolderThatContainsHome() throws {
        let fs = try Sandbox()
        defer { fs.cleanup() }
        #expect(throws: FolderPolicyViolation.containsHome) { try fs.policy.check(fs.root) }
    }

    @Test func rejectsASymlinkToHome() throws {
        let fs = try Sandbox()
        defer { fs.cleanup() }
        let link = fs.root + "/link-to-home"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: fs.home)
        #expect(throws: FolderPolicyViolation.home) { try fs.policy.check(link) }
    }

    @Test(arguments: FolderPolicy.sensitiveEntries)
    func rejectsFoldersWithSensitiveEntries(entry: String) throws {
        let fs = try Sandbox()
        defer { fs.cleanup() }
        try fs.mkdir(fs.project + "/" + entry)
        #expect(throws: FolderPolicyViolation.containsSensitiveEntry(entry)) { try fs.policy.check(fs.project) }
    }

    @Test(arguments: FolderPolicy.sensitiveEntries)
    func rejectsFoldersInsideSensitiveEntries(entry: String) throws {
        let fs = try Sandbox()
        defer { fs.cleanup() }
        try fs.mkdir(fs.home + "/" + entry + "/keys/deep")
        #expect(throws: FolderPolicyViolation.insideSensitiveEntry(entry)) { try fs.policy.check(fs.home + "/" + entry) }
        #expect(throws: FolderPolicyViolation.insideSensitiveEntry(entry)) { try fs.policy.check(fs.home + "/" + entry + "/keys/deep") }
    }

    @Test func rejectsASymlinkIntoASensitiveFolder() throws {
        let fs = try Sandbox()
        defer { fs.cleanup() }
        try fs.mkdir(fs.home + "/.aws/profiles")
        let link = fs.root + "/innocent"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: fs.home + "/.aws/profiles")
        #expect(throws: FolderPolicyViolation.insideSensitiveEntry(".aws")) { try fs.policy.check(link) }
    }

    @Test func sensitiveNamesElsewhereAreNotInsideHome() throws {
        let fs = try Sandbox()
        defer { fs.cleanup() }
        try fs.mkdir(fs.root + "/other/.ssh-notes/x")
        try fs.policy.check(fs.root + "/other/.ssh-notes/x")
    }

    @Test func sensitiveEntriesDeeperDownAreAllowed() throws {
        let fs = try Sandbox()
        defer { fs.cleanup() }
        try fs.mkdir(fs.project + "/fixtures/.ssh")
        try fs.policy.check(fs.project)
    }

    @Test func rejectsPaddockConfigInsideAndAbove() throws {
        let fs = try Sandbox()
        defer { fs.cleanup() }
        try fs.mkdir(fs.config + "/sub")
        #expect(throws: FolderPolicyViolation.overlapsPaddockConfig) { try fs.policy.check(fs.config) }
        #expect(throws: FolderPolicyViolation.overlapsPaddockConfig) { try fs.policy.check(fs.config + "/sub") }
        #expect(throws: FolderPolicyViolation.overlapsPaddockConfig) { try fs.policy.check(fs.home + "/.config") }
    }

    @Test func similarNamesAreNotParents() {
        #expect(FolderPolicy.isAncestor("/a/b", of: "/a/b/c"))
        #expect(!FolderPolicy.isAncestor("/a/b", of: "/a/bc"))
        #expect(!FolderPolicy.isAncestor("/a/b", of: "/a/b"))
    }

    @Test func rejectsMissingFoldersAndFiles() throws {
        let fs = try Sandbox()
        defer { fs.cleanup() }
        let file = fs.project + "/README.md"
        _ = FileManager.default.createFile(atPath: file, contents: Data())
        #expect(throws: FolderPolicyViolation.notADirectory(file)) { try fs.policy.check(file) }
        #expect(throws: FolderPolicyViolation.notADirectory(fs.root + "/nope")) { try fs.policy.check(fs.root + "/nope") }
    }

    /// Inside ~/Library, only ~/Library/Logs, and only when asked for (an operator's extra folder, PAD-125).
    @Test func logsPassOnlyWhenAllowedAndNothingElseInLibraryDoes() throws {
        let fs = try Sandbox()
        defer { fs.cleanup() }
        let logs = fs.home + "/Library/Logs"
        for dir in [logs + "/Paddock/hangs", fs.home + "/Library/Keychains", fs.home + "/Library/Cookies", fs.home + "/.ssh"] {
            try fs.mkdir(dir)
        }
        // A project folder, or a project's file: refused as before.
        #expect(throws: FolderPolicyViolation.insideSensitiveEntry("Library")) { try fs.policy.check(logs + "/Paddock") }
        // An operator's extra folder: allowed, and known as one.
        try fs.policy.check(logs + "/Paddock", allowingLogs: true)
        try fs.policy.check(logs + "/Paddock/hangs", allowingLogs: true)
        #expect(fs.policy.isInsideLogs(logs + "/Paddock"))
        // Not ~/Library/Logs itself, nor the rest of ~/Library, nor a way out of Logs.
        for path in [logs, fs.home + "/Library", fs.home + "/Library/Keychains", logs + "/../Cookies"] {
            #expect(throws: FolderPolicyViolation.insideSensitiveEntry("Library")) { try fs.policy.check(path, allowingLogs: true) }
        }
        // A link inside Logs is followed first: one to ~/.ssh is ~/.ssh.
        try FileManager.default.createSymbolicLink(atPath: logs + "/keys", withDestinationPath: fs.home + "/.ssh")
        #expect(throws: FolderPolicyViolation.insideSensitiveEntry(".ssh")) { try fs.policy.check(logs + "/keys", allowingLogs: true) }
        #expect(!fs.policy.isInsideLogs(logs + "/keys"))
        // Case does not open a way around it.
        #expect(fs.policy.isInsideLogs(fs.home + "/LIBRARY/LOGS/Paddock") == fs.policy.isInsideLogs(logs + "/Paddock"))
    }
}
