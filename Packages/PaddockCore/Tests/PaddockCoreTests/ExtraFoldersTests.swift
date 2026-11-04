import Foundation
import Testing
@testable import PaddockCore

/// Folders mounted besides the project folder (backlog doc Security rules, PAD-73.5).
@Suite("ExtraFolders")
struct ExtraFoldersTests {
    struct Home {
        let home: String
        let project: Project

        init() throws {
            home = FolderPolicy.canonical(NSTemporaryDirectory()) + "/paddock-extra-" + UUID().uuidString
            for folder in ["src/app/sub", "src/lib", "src/docs", "src/a:b", ".ssh"] {
                try FileManager.default.createDirectory(atPath: home + "/" + folder, withIntermediateDirectories: true)
            }
            project = Project(name: "app", folder: home + "/src/app")
        }

        var policy: FolderPolicy { FolderPolicy(home: home, paddockConfigDirectory: home + "/.config/paddock") }
        func cleanup() { try? FileManager.default.removeItem(atPath: home) }
    }

    @Test func aFolderIsCheckedLikeAProjectFolder() throws {
        let home = try Home()
        defer { home.cleanup() }
        #expect(try ExtraFolders.check(home.home + "/src/lib", for: home.project, policy: home.policy) == home.home + "/src/lib")
        #expect(throws: ExtraFolderProblem.folder(.home)) { try ExtraFolders.check(home.home, for: home.project, policy: home.policy) }
        #expect(throws: ExtraFolderProblem.folder(.containsHome)) {
            try ExtraFolders.check((home.home as NSString).deletingLastPathComponent, for: home.project, policy: home.policy)
        }
        #expect(throws: ExtraFolderProblem.folder(.notADirectory(home.home + "/nope"))) {
            try ExtraFolders.check(home.home + "/nope", for: home.project, policy: home.policy)
        }
        #expect(throws: ExtraFolderProblem.colon) { try ExtraFolders.check(home.home + "/src/a:b", for: home.project, policy: home.policy) }
        // the project folder, inside it, or around it: mounted already
        for path in ["/src/app", "/src/app/sub", "/src"] {
            #expect(throws: ExtraFolderProblem.overlapsProject) { try ExtraFolders.check(home.home + path, for: home.project, policy: home.policy) }
        }
    }

    @Test func aLinkIsFollowedBeforeTheChecks() throws {
        let home = try Home()
        defer { home.cleanup() }
        try FileManager.default.createSymbolicLink(atPath: home.home + "/src/home-link", withDestinationPath: home.home)
        #expect(throws: ExtraFolderProblem.folder(.home)) {
            try ExtraFolders.check(home.home + "/src/home-link", for: home.project, policy: home.policy)
        }
    }

    @Test func extraFoldersDoNotOverlapEachOther() throws {
        let home = try Home()
        defer { home.cleanup() }
        var project = home.project
        project.extraFolders = [.init(path: home.home + "/src/lib")]
        #expect(throws: ExtraFolderProblem.overlapsExtra(home.home + "/src/lib")) {
            try ExtraFolders.check(home.home + "/src/lib", for: project, policy: home.policy)
        }
        // changing one is checked without itself
        #expect(try ExtraFolders.check(home.home + "/src/lib", for: project, policy: home.policy, except: home.home + "/src/lib")
            == home.home + "/src/lib")
        project.extraFolders.append(.init(path: home.home + "/src/docs", readOnly: false))
        #expect(try ExtraFolders.checkAll(project, policy: home.policy) == project.extraFolders)
        // a folder that became home since it was added stops a create
        try FileManager.default.removeItem(atPath: home.home + "/src/docs")
        try FileManager.default.createSymbolicLink(atPath: home.home + "/src/docs", withDestinationPath: home.home)
        #expect(throws: ExtraFolderProblem.folder(.home)) { try ExtraFolders.checkAll(project, policy: home.policy) }
    }

    @Test func readOnlyIsTheDefaultAndSbxGetsColonRO() throws {
        #expect(Project.ExtraFolder(path: "/x").readOnly)
        let file = #"{"id":"\#(UUID().uuidString)","name":"app","folder":"/a","agent":"claude","provider":"agent-default","extraFolders":[{"path":"/x"},{"path":"/y","readOnly":false}]}"#
        let project = try JSONCoding.decode(Project.self, from: Data(file.utf8))
        #expect(project.extraFolders == [.init(path: "/x", readOnly: true), .init(path: "/y", readOnly: false)])
        #expect(project.extraFolders.map(ExtraFolders.argument) == ["/x:ro", "/y"])
        // files from before have none
        let old = #"{"id":"\#(UUID().uuidString)","name":"app","folder":"/a","agent":"claude","provider":"agent-default"}"#
        #expect(try JSONCoding.decode(Project.self, from: Data(old.utf8)).extraFolders.isEmpty)
        // and it round-trips through the project file
        let saved = try ProjectDirectory.decode(file: "app.json", data: try ProjectDirectory.encode(project))
        #expect(saved.extraFolders == project.extraFolders)
    }

    @Test func sbxListsThemAfterTheProjectFolder() throws {
        let sandboxes = try Fixture.decode([SbxSandbox].self, "sbx", "ls-v3.json")
        let v3 = try #require(sandboxes.first { $0.name == "m0-v3" })
        // the env file's own read-only mount is not an extra folder
        #expect(ExtraFolders.inSandbox(v3.workspaces) == [
            .init(path: "/Users/operator/Projects/private/paddock/scratch/m0/run/v3/extra-ro", readOnly: true),
            .init(path: "/Users/operator/Projects/private/paddock/scratch/m0/run/v3/extra-rw", readOnly: false),
        ])
        #expect(ExtraFolders.inSandbox(["/a"]).isEmpty)
    }

    @Test func theCreateMountsThemAfterTheProjectFolder() {
        let plan = SandboxPolicyPlan(denies: [], allows: [], httpAllows: [])
        let a = AgentLaunchPlanner(paths: PaddockPaths(configDirectory: "/c")).create(
            name: "app", agent: .claudeCode, folder: "/src/app", policy: plan, gateway: nil, extraFolders: ["/src/lib:ro", "/src/docs"]).arguments
        #expect(Array(a.suffix(4)) == ["claude", "/src/app", "/src/lib:ro", "/src/docs"])
    }

    @Test func aNewProjectTakesItsExtraFoldersChecked() throws {
        let home = try Home()
        defer { home.cleanup() }
        let app = try AppConfig.load(from: Fixture.data("config", "paddock-full.yaml")).config
        var draft = ProjectDraft(folder: home.project.folder, name: "app", agent: "claude", provider: "agent-default")
        draft.extraFolders = [.init(path: home.home + "/src/lib"), .init(path: home.home + "/src/docs", readOnly: false)]
        let project = try NewProject.make(draft, app: app, existing: ProjectList(), sandboxes: [], folderPolicy: home.policy)
        #expect(project.extraFolders == [.init(path: home.home + "/src/lib"), .init(path: home.home + "/src/docs", readOnly: false)])
        draft.extraFolders = [.init(path: home.home)]
        #expect(throws: NewProjectError.extraFolder(home.home, .folder(.home))) {
            try NewProject.make(draft, app: app, existing: ProjectList(), sandboxes: [], folderPolicy: home.policy)
        }
    }

    @Test func otherProjectsFoldersAreMarked() {
        let projects = [Project(name: "app", folder: "/src/app"), Project(name: "lib", folder: "/src/lib")]
        #expect(ExtraFolders.otherProject("/src/lib", in: projects, except: "app") == "lib")
        #expect(ExtraFolders.otherProject("/src/docs", in: projects, except: "app") == nil)
    }
}
