import Foundation
import Testing
@testable import PaddockCore

@Suite("What changed since a create (PAD-103)")
struct EnvironmentRecordTests {
    let file = """
    schemaVersion: "1"
    agent: claude
    kits:
      - ./tools/sandbox/app
    """

    func record(_ yaml: String, kit: [(String, String)] = []) -> EnvironmentRecord {
        EnvironmentRecord.of(data: Data(yaml.utf8),
                             kits: [("./tools/sandbox/app", kit.map { ($0.0, Data($0.1.utf8)) })])
    }

    @Test func commentsFormattingAndFinderFilesAreNoChange() {
        let before = record(file, kit: [("spec.yaml", "a")])
        let reformatted = "# the app's sandbox\nagent:   claude\nschemaVersion: '1'\nkits: [./tools/sandbox/app]\n"
        #expect(record(reformatted, kit: [("spec.yaml", "a"), (".DS_Store", "x")]).changes(since: before).isEmpty)
    }

    @Test func changedKeysAndKitFilesAreNamed() {
        let before = record(file, kit: [("spec.yaml", "a"), ("files/old.sh", "o")])
        let changed = """
        schemaVersion: "1"
        agent: codex
        kits:
          - ./tools/sandbox/app
        env:
          A: "1"
        """
        let after = record(changed, kit: [("spec.yaml", "b"), ("files/install.sh", "i")])
        #expect(after.changes(since: before) == [
            "sbxenv.yaml (agent, env)",
            "kit ./tools/sandbox/app (files/install.sh added, files/old.sh removed, spec.yaml changed)",
        ])
    }

    @Test func aFileThatDoesNotParseIsOnePiece() {
        let before = record(file)
        #expect(record("agent: [").changes(since: before).first == "sbxenv.yaml (agent, kits, schemaVersion)")
        #expect(record("agent: [").changes(since: record("agent: {")) == ["sbxenv.yaml"])
    }

    @Test func theRecordIsKeptInTheProjectFile() throws {
        var project = Project(name: "app", folder: "/src/app")
        project.sandboxEnvironmentRecord = record(file)
        let saved = try ProjectDirectory.decode(file: "app.json", data: try ProjectDirectory.encode(project))
        #expect(saved.sandboxEnvironmentRecord == project.sandboxEnvironmentRecord)
    }

    @Test func theItemSaysWhatChangedAndIsGoneWhenNothingDid() {
        var project = Project(name: "app", folder: "/src/app", approvedEnvironment: "new", sandboxEnvironment: "old")
        // created before Paddock kept a record
        #expect(SandboxSync.environmentSummary(project: project, now: record(file))?.contains("no details") == true)
        project.sandboxEnvironmentRecord = record(file, kit: [("spec.yaml", "a")])
        #expect(SandboxSync.environmentSummary(project: project, now: record(file, kit: [("spec.yaml", "a")])) == nil)
        #expect(SandboxSync.environmentSummary(project: project, now: record(file, kit: [("spec.yaml", "b")]))
            == "Changed since the sandbox was created: kit ./tools/sandbox/app (spec.yaml changed); recreate it to use them")
        // the file changed again after it was confirmed: no record of the confirmed version
        #expect(SandboxSync.environmentSummary(project: project, now: nil)?.contains("review it") == true)
    }

    @Test func kitChangesNameWhatDiffersAndIgnoreOrder() {
        let node = "/Users/op/.config/paddock/kits/paddock-node#aaa"
        let voice = "/Users/op/.config/paddock/kits/paddock-voice#bbb"
        let mise = "docker.io/sbx/mise@sha256:1"
        #expect(SandboxSync.kitChanges(created: [node, mise], now: [mise, node]).isEmpty)
        #expect(SandboxSync.kitChanges(created: [node, mise], now: [node.replacingOccurrences(of: "aaa", with: "ccc"), voice])
            == ["added paddock-voice", "removed docker.io/sbx/mise@sha256:1", "newer paddock-node"])
    }
}
