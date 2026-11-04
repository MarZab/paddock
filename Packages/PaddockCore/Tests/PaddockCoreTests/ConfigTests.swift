import Foundation
import Testing
@testable import PaddockCore

@Suite("AppConfig")
struct AppConfigTests {
    func load(_ name: String) throws -> (config: AppConfig, unknownKeys: [String]) {
        try AppConfig.load(from: Fixture.data("config", name))
    }

    @Test func fullConfig() throws {
        let (config, unknown) = try load("paddock-full.yaml")
        #expect(unknown.isEmpty)
        #expect(config.models.gatewayPorts == 17480...17579)
        // underscores in section names survive (no snake_case conversion)
        #expect(config.providers["local_qwen"] == .local(model: "hf.co/unsloth/Qwen3.5-35B-A3B-GGUF:latest"))
        #expect(config.agents["opencode"] == .openCode)
        #expect(config.agents["opencode"]?.sbxAgent == "opencode")
        #expect(config.ports.publishRange == 18000...18999)
    }

    @Test func minimalConfigGetsDefaults() throws {
        let (config, unknown) = try load("paddock-minimal.yaml")
        #expect(unknown.isEmpty)
        #expect(config == AppConfig())
        #expect(config.providers[config.defaults.provider] == .agentDefault)
    }

    @Test func unknownKeysAreReportedNotFatal() throws {
        let (config, unknown) = try load("paddock-unknown-keys.yaml")
        #expect(unknown == ["models.gatewayPrt", "modles", "ports.hostServices", "ports.publish"])
        #expect(config.models.gatewayPorts == 17480...17579)
    }

    @Test func missingFileMeansDefaults() throws {
        let (config, unknown) = try AppConfig.load(atPath: "/nonexistent/paddock.toml")
        #expect(config == AppConfig() && unknown.isEmpty)
    }

    @Test func badVersionIsRejected() throws {
        #expect(throws: AppConfigError.unsupportedVersion(2)) { try load("paddock-bad-version.yaml") }
        // a file without `version`
        #expect(throws: AppConfigError.unsupportedVersion(nil)) { try AppConfig.load(from: Data("models: {}\n".utf8)) }
    }

    @Test func malformedJSONIsRejected() {
        #expect(throws: AppConfigError.self) { try AppConfig.load(from: Data("{ version: 1".utf8)) }
    }

    /// Ranges holding llmman's or Docker's port, privileged ports, or the publish range.
    @Test(arguments: ["[17400,17500]", "[2370,2380]", "[80,90]", "[65000,70000]", "[18500,18600]"])
    func gatewayPortsMustBeSafe(range: String) {
        let json = #"version: 1\#nmodels: { gatewayPorts: \#(range) }"#
        #expect(throws: AppConfigError.invalidGatewayPorts) { try AppConfig.load(from: Data(json.utf8)) }
    }

    @Test(arguments: ["[17500]", "[17600,17500]"])
    func gatewayPortsMustBeARange(range: String) {
        let json = #"version: 1\#nmodels: { gatewayPorts: \#(range) }"#
        #expect(throws: AppConfigError.self) { try AppConfig.load(from: Data(json.utf8)) }
    }

    @Test func providerKindsAreChecked() {
        let unknown = #"version: 1\#nproviders: { agent-default: { kind: "agentDefault" }, x: { kind: "hosted" } }"#
        #expect(throws: AppConfigError.unknownProviderKind(name: "x", kind: "hosted")) { try AppConfig.load(from: Data(unknown.utf8)) }
        let noModel = #"version: 1\#nproviders: { agent-default: { kind: "agentDefault" }, x: { kind: "local" } }"#
        #expect(throws: AppConfigError.localProviderWithoutModel("x")) { try AppConfig.load(from: Data(noModel.utf8)) }
    }

    @Test func defaultsMustNameExistingSections() {
        let json = #"version: 1\#ndefaults: { provider: "hosted" }"#
        #expect(throws: AppConfigError.missingDefaultSection(kind: "provider", name: "hosted")) { try AppConfig.load(from: Data(json.utf8)) }
    }

    @Test func policySectionsAreGone() throws {
        // A sandbox's network is sbx's global rules plus its project's confirmed sbxenv.yaml.
        let json = #"version: 1\#ndefaults: { policy: "default" }\#npolicies: { default: { allow: [] } }"#
        let (_, unknown) = try AppConfig.load(from: Data(json.utf8))
        #expect(unknown == ["defaults.policy", "policies"])
    }

    @Test func hostServicesAreNoLongerAPaddockJSONSetting() throws {
        let (_, unknown) = try AppConfig.load(from: Data(#"version: 1\#nports: { publishRange: [18000, 18999], hostServices: [] }"#.utf8))
        #expect(unknown == ["ports.hostServices"])
    }

    @Test func publishRangeMustBeOrdered() {
        let json = #"version: 1\#nports: { publishRange: [19000, 18000] }"#
        #expect(throws: AppConfigError.invalidPublishRange) { try AppConfig.load(from: Data(json.utf8)) }
    }

    @Test func pathsFollowXDG() {
        #expect(PaddockPaths(environment: [:], home: "/Users/op").appConfig == "/Users/op/.config/paddock/paddock.yaml")
        #expect(PaddockPaths(environment: ["XDG_CONFIG_HOME": "/x/cfg"], home: "/Users/op").projects == "/x/cfg/paddock/projects")
        // a relative XDG_CONFIG_HOME is invalid per the spec and ignored
        #expect(PaddockPaths(environment: ["XDG_CONFIG_HOME": "cfg"], home: "/Users/op").configDirectory == "/Users/op/.config/paddock")
    }
}

/// Paddock's project files in its config dir (backlog doc ProjectStore).
@Suite("ProjectDirectory")
struct ProjectDirectoryTests {
    func temporaryDirectory() -> ProjectDirectory {
        ProjectDirectory(path: NSTemporaryDirectory() + "paddock-projects-" + UUID().uuidString)
    }

    @Test func loadsTheFixture() throws {
        let project = try ProjectDirectory.decode(file: "paddock-app.json", data: Fixture.data("config", "project-file.json"))
        #expect(project.name == "paddock-app")
        #expect(project.provider == "local_qwen")
        #expect(project.gatewayPort == 17480)
        // Its `ports` key is from before sbx was the only store for ports; it is ignored.
        #expect(project.folder.hasSuffix("app"))
    }

    @Test func savesOwnerOnlyAndLoadsBack() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory.path) }
        let project = Project(name: "paddock-app", folder: "/Users/op/src/app", provider: "local_qwen", gatewayPort: 17480)
        try directory.save(project)
        let loaded = directory.load()
        #expect(loaded.problems.isEmpty)
        #expect(loaded.projects.projects == [project])
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path + "/paddock-app.json")
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try directory.delete(named: "paddock-app")
        #expect(directory.load().projects.projects.isEmpty)
    }

    @Test func badFilesAreReportedAndSkipped() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory.path) }
        try directory.save(Project(name: "paddock-good", folder: "/a"))
        let write = { (name: String, text: String) in
            try Data(text.utf8).write(to: URL(fileURLWithPath: directory.path + "/" + name))
        }
        try write("paddock-typo.json", "{ not json")
        try write("paddock-old.json", #"{"version":2}"#)
        try write("paddock-renamed.json", String(decoding: try ProjectDirectory.encode(Project(name: "paddock-other", folder: "/b")), as: UTF8.self))
        try write("notes.txt", "ignored")
        let loaded = directory.load()
        #expect(loaded.projects.projects.map(\.name) == ["paddock-good"])
        #expect(loaded.problems.count == 3)
        #expect(loaded.problems.contains(.unsupportedVersion(file: "paddock-old.json", version: 2)))
        #expect(loaded.problems.contains(.nameMismatch(file: "paddock-renamed.json", name: "paddock-other")))
    }

    @Test func optionalPartsMayBeLeftOut() throws {
        let json = #"{"version":1,"id":"6F1C2D3E-4A5B-4C6D-8E7F-0123456789AB","name":"paddock-x","folder":"/x","agent":"claude","provider":"agent-default"}"#
        let project = try ProjectDirectory.decode(file: "paddock-x.json", data: Data(json.utf8))
        #expect(!project.cloneMode && project.gatewayPort == nil && project.approvedEnvironment == nil)
        #expect(project.declinedHosts.isEmpty && project.sandboxEnvironment == nil && project.extraFolders.isEmpty)
        #expect(project.ignoredSuggestions.isEmpty && project.terminalTheme == nil)
    }

    @Test func theTerminalThemeIsKept() throws {
        let project = Project(name: "paddock-x", folder: "/x", terminalTheme: "nord")
        let data = try ProjectDirectory.encode(project)
        #expect(try ProjectDirectory.decode(file: "paddock-x.json", data: data).terminalTheme == "nord")
    }
}

@Suite("ProjectList")
struct ProjectListTests {
    @Test(arguments: [
        ("paddock-app", true), ("paddock-my.app-2", true),
        ("claude-plane", true), ("example", true), ("paddock-", true), ("paddock-x y", false), ("default", false),
        ("paddock-ü", false), ("-x", false), ("x", false),
    ])
    func sandboxNames(name: String, valid: Bool) {
        #expect(ProjectList.isValidSandboxName(name) == valid)
    }

    @Test func gatewayPortsAreUniqueAndAssignedLowestFirst() throws {
        let a = Project(name: "paddock-a", folder: "/a", gatewayPort: 17480)
        let b = Project(name: "paddock-b", folder: "/b", gatewayPort: 17480)
        #expect(throws: ProjectStoreError.duplicateGatewayPort(17480)) { try ProjectList(validating: [a, b]) }
        let list = try ProjectList(validating: [a, Project(name: "paddock-c", folder: "/c")])
        #expect(list.nextGatewayPort(in: 17480...17482) == 17481)
        #expect(list.nextGatewayPort(in: 17480...17480) == nil)
    }

    @Test func namesAndFoldersAreUnique() {
        let a = Project(name: "paddock-app", folder: "/a")
        #expect(throws: ProjectStoreError.duplicateName("paddock-app")) { try ProjectList(validating: [a, Project(name: "paddock-app", folder: "/b")]) }
        #expect(throws: ProjectStoreError.duplicateFolder("/a")) { try ProjectList(validating: [a, Project(name: "paddock-b", folder: "/a")]) }
        #expect(throws: ProjectStoreError.invalidName("my sandbox")) { try ProjectList(validating: [Project(name: "my sandbox", folder: "/m")]) }
    }
}

@Suite("paddock.yaml")
struct AppConfigYAMLTests {
    @Test func emptySectionsReadLikeTOMLsEmptyTables() throws {
        // all of a section commented out: absent; a kit without keys: sbx's contrib kit
        let (config, unknown) = try AppConfig.load(from: Data("version: 1\nmodels:\nkits:\n  gh:\nmodles:\n".utf8))
        #expect(config.models == AppConfig().models)
        #expect(config.kits["gh"]?.source == .reference("docker.io/sbx/gh"))
        #expect(unknown == ["modles"])
        // like TOML, a file needs its version, even one with only comments
        #expect(throws: AppConfigError.unsupportedVersion(nil)) { try AppConfig.load(from: Data("# only comments\n".utf8)) }
    }

    @Test func aKitGoesAtTheEndOfTheKitsBlock() throws {
        let file = """
            version: 1
            # my kits
            kits:
              mine:
                source: /Users/op/kits/mine  # pinned later

              # a comment inside
            # a comment after
            ports:
              publishRange: [18000, 18999]
            """
        let result = try AppConfigFile.insertingKit("lint", source: "docker.io/acme/lint-kit:1.2", into: file)
        #expect(result == """
            version: 1
            # my kits
            kits:
              mine:
                source: /Users/op/kits/mine  # pinned later

              # a comment inside
              # Added from Paddock's kit field.
              lint:
                source: "docker.io/acme/lint-kit:1.2"
            # a comment after
            ports:
              publishRange: [18000, 18999]

            """)
        let loaded = try AppConfig.load(from: Data(result.utf8))
        #expect(loaded.config.kits["lint"]?.source == .reference("docker.io/acme/lint-kit:1.2") && loaded.config.kits["mine"] != nil)
        // without a kits block, one is added at the end
        let added = try AppConfigFile.insertingKit("gh", source: nil, into: "version: 1\n")
        #expect(added == "version: 1\n\nkits:\n  # Added from Paddock's kit field.\n  gh: {}\n")
        // a kits mapping on one line is left to the operator
        #expect(throws: AppConfigFile.Problem.kitsNotABlock) { try AppConfigFile.insertingKit("gh", source: nil, into: "kits: { a: {} }\n") }
    }
}

@Suite("PaddockPaths.secure")
struct PaddockPathsSecureTests {
    @Test func makesFoldersAndFilesOwnerOnly() throws {
        let root = FolderPolicy.canonical(NSTemporaryDirectory()) + "/paddock-secure-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        let paths = PaddockPaths(configDirectory: root + "/paddock")
        for directory in [paths.projects, paths.kits + "/mykit"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o755])
        }
        for file in [paths.appConfig, paths.projects + "/a.json", paths.kits + "/mykit/mykit.yaml"] {
            FileManager.default.createFile(atPath: file, contents: Data("x".utf8), attributes: [.posixPermissions: 0o644])
        }
        paths.secure()
        func mode(_ path: String) throws -> Int {
            try #require(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
        }
        #expect(try mode(paths.configDirectory) == 0o700)
        #expect(try mode(paths.projects) == 0o700)
        #expect(try mode(paths.kits + "/mykit") == 0o700)
        #expect(try mode(paths.appConfig) == 0o600)
        #expect(try mode(paths.projects + "/a.json") == 0o600)
        #expect(try mode(paths.kits + "/mykit/mykit.yaml") == 0o600)
    }

    @Test func doesNotFollowLinks() throws {
        let root = FolderPolicy.canonical(NSTemporaryDirectory()) + "/paddock-secure-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        let paths = PaddockPaths(configDirectory: root + "/paddock")
        try FileManager.default.createDirectory(atPath: paths.projects, withIntermediateDirectories: true)
        let outside = root + "/outside.txt"
        FileManager.default.createFile(atPath: outside, contents: Data(), attributes: [.posixPermissions: 0o644])
        try FileManager.default.createSymbolicLink(atPath: paths.projects + "/link.json", withDestinationPath: outside)
        paths.secure()
        #expect(try FileManager.default.attributesOfItem(atPath: outside)[.posixPermissions] as? Int == 0o644)
    }
}
