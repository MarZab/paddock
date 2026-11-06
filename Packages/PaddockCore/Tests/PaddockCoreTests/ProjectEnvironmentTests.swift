import Foundation
@testable import PaddockCore
import Testing

@Suite("YAMLCoding")
struct YAMLCodingTests {
    func read(_ text: String) throws -> JSONValue { try YAMLCoding.value(fromYAML: Data(text.utf8)) }

    @Test func scalarsKeepTheirYAMLTypes() throws {
        let value = try read("""
            quoted: "3"
            number: 3
            float: 1.5
            yes: yes
            on: off
            flag: true
            nothing: ~
            block: |
              text
            """)
        #expect(value["quoted"] == .string("3"))
        #expect(value["number"] == .number(3))
        #expect(value["float"] == .number(1.5))
        #expect(value["yes"] == .string("yes"))  // YAML 1.2: not a boolean
        #expect(value["on"] == .string("off"))
        #expect(value["flag"] == .bool(true))
        #expect(value["nothing"] == .null)
        #expect(value["block"] == .string("text"))
    }

    @Test(arguments: [
        ("a: &x 1\nb: *x\n", YAMLCoding.Problem.alias),
        ("base: &b {x: 1}\nc:\n  <<: *b\n", .alias),
        ("1: one\n", .nonStringKey),
        ("", .empty),
    ])
    func refusesWhatSbxMightReadDifferently(text: String, problem: YAMLCoding.Problem) {
        #expect(throws: problem) { try read(text) }
    }

    @Test func syntaxErrorsAndDuplicateKeysAreReported() {
        #expect(throws: YAMLCoding.Problem.self) { try read("a: [1, 2\n") }
        #expect(throws: YAMLCoding.Problem.self) { try read("a: 1\na: 2\n") }
        #expect(throws: YAMLCoding.Problem.alias) { try read("a: &x 1\n") }
    }
}

@Suite("SbxEnvFile")
struct SbxEnvFileTests {
    func load(_ text: String) throws(SbxEnvFileError) -> SbxEnvFile { try SbxEnvFile.load(from: Data(text.utf8)) }

    @Test func readsAnExampleFile() throws {
        let file = try SbxEnvFile.load(from: Fixture.data("config/sbxenv-example", "sbxenv.yaml"))
        #expect(file.name == "example" && file.agent == "sbx-kit-claude" && file.workspace == ".")
        #expect(file.kits.map(\.source) == ["docker.io/docker/sbx-kit-claude:2.1.316", "./tools/sandbox/example-dev"])
        #expect(file.ports == [.init(sandbox: 3001, host: 3001), .init(sandbox: 4000, host: 4000)])
        #expect(file.sandboxOptions["cpus"] == .number(4) && file.otherKeys.isEmpty)
    }

    @Test func readsEveryForm() throws {
        let file = try load("""
            schemaVersion: "1"
            agent: sbx-kit-claude
            kits:
              - docker.io/sbx/mise
              - { source: ./kit, args: { version: "1.2" } }
            additionalWorkspaces:
              - { path: ../lib, readOnly: true }
              - { path: ../docs, target: /docs }
            env: { NODE_ENV: test, WORKERS: 4 }
            ports: [{ sandbox: 3000, host: 3000, protocol: tcp, hostIP: 127.0.0.1 }]
            lifecycle: { initialize: [{ command: "true" }] }
            """)
        #expect(file.kits[1] == .init(source: "./kit", args: ["version": .string("1.2")]))
        #expect(file.additionalWorkspaces == [.init(path: "../lib", readOnly: true), .init(path: "../docs", target: "/docs")])
        #expect(file.env == ["NODE_ENV": "test", "WORKERS": "4"])
        #expect(file.ports == [.init(sandbox: 3000, host: 3000, transport: "tcp", hostIP: "127.0.0.1")])
        #expect(file.otherKeys == ["lifecycle"] && file.workspace == nil)
    }

    @Test(arguments: [
        ("agent: a\n", SbxEnvFileError.unsupportedVersion(nil)),
        ("schemaVersion: 1\nagent: a\n", .invalid(key: "schemaVersion", expected: "the quoted string \"1\"")),
        ("schemaVersion: \"2\"\nagent: a\n", .unsupportedVersion("2")),
        ("schemaVersion: \"1\"\n", .invalid(key: "agent", expected: "set")),
        ("schemaVersion: \"1\"\nagent: a\nnetwork: {}\n", .unknownKey("network")),
        ("schemaVersion: \"1\"\nagent: a\nports: [{ sandbox: 1, bind: x }]\n", .unknownKey("ports[0].bind")),
        ("schemaVersion: \"1\"\nagent: a\nadditionalWorkspaces: [{ path: x, mode: ro }]\n", .unknownKey("additionalWorkspaces[0].mode")),
        ("schemaVersion: \"1\"\nagent: a\nkits: [{ source: x, digest: y }]\n", .unknownKey("kits[0].digest")),
        ("schemaVersion: \"1\"\nagent: a\nports: [{ sandbox: \"80\" }]\n", .invalid(key: "ports[0].sandbox", expected: "a whole number")),
    ])
    func refusesWhatItDoesNotKnow(text: String, error: SbxEnvFileError) {
        #expect(throws: error) { try load(text) }
    }
}

@Suite("ProjectEnvironment")
struct ProjectEnvironmentTests {
    /// A home with a project folder and siblings, so FolderPolicy runs for real.
    struct Home {
        let home: String
        let project: String

        init() throws {
            home = FolderPolicy.canonical(NSTemporaryDirectory()) + "/paddock-env-" + UUID().uuidString
            project = home + "/src/app"
            for folder in [project, home + "/src/lib", home + "/src/other", home + "/.ssh"] {
                try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            }
        }

        var context: ProjectEnvironment.Context {
            ProjectEnvironment.Context(folderPolicy: FolderPolicy(home: home, paddockConfigDirectory: home + "/.config/paddock"),
                                       app: AppConfig(), otherProjects: ["other": home + "/src/other"])
        }

        func write(_ relative: String, _ text: String) throws {
            let path = project + "/" + relative
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: URL(fileURLWithPath: path))
        }

        func environment(_ yaml: String) throws -> ProjectEnvironment {
            try write("sbxenv.yaml", "schemaVersion: \"1\"\nagent: sbx-kit-claude\n" + yaml)
            return try #require(ProjectEnvironment.read(folder: project, context: context))
        }

        func kit(_ body: String, name: String = "kit") throws {
            try write("\(name)/\(name).yaml", "schemaVersion: \"3\"\nkind: mixin\n" + body)
        }

        func cleanup() { try? FileManager.default.removeItem(atPath: home) }
    }

    @Test func noFileIsNoEnvironment() throws {
        let home = try Home()
        defer { home.cleanup() }
        #expect(ProjectEnvironment.read(folder: home.project, context: home.context) == nil)
    }

    @Test func anExampleFileIsAccepted() throws {
        let home = try Home()
        defer { home.cleanup() }
        for file in ["sbxenv.yaml", "tools/sandbox/example-dev/example-dev.yaml", "tools/sandbox/example-dev/example-dev.dockerfile"] {
            let parent = (file as NSString).deletingLastPathComponent
            let directory = parent.isEmpty ? "config/sbxenv-example" : "config/sbxenv-example/" + parent
            try home.write(file, String(decoding: try Fixture.data(directory, (file as NSString).lastPathComponent), as: UTF8.self))
        }
        let env = try #require(ProjectEnvironment.read(folder: home.project, context: home.context))
        #expect(env.problems.isEmpty, "\(env.problems)")
        #expect(env.isAcceptable)
        #expect(env.kits.map(\.origin) == [.catalog, .local(home.project + "/tools/sandbox/example-dev")])
        #expect(env.installHosts.map(\.host) == ["ports.ubuntu.com", "archive.ubuntu.com", "security.ubuntu.com"])
        #expect(env.runtimeHosts.contains { $0.host == "registry.npmjs.org" && !$0.deny })
        #expect(env.fingerprint.count == 64)
    }

    /// Paddock's own repo: its sbxenv.yaml and kit, copied as they are.
    @Test func thisRepositorysOwnFilesAreAccepted() throws {
        let home = try Home()
        defer { home.cleanup() }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
        for file in ["sbxenv.yaml", "tools/sandbox/paddock/paddock.yaml", "tools/sandbox/paddock/paddock.dockerfile"] {
            try home.write(file, String(decoding: try Data(contentsOf: URL(fileURLWithPath: repo + "/" + file)), as: UTF8.self))
        }
        let env = try #require(ProjectEnvironment.read(folder: home.project, context: home.context))
        #expect(env.problems.isEmpty, "\(env.problems)")
        #expect(env.file?.agent == "claude" && env.kits.map(\.source) == ["./tools/sandbox/paddock"])
        #expect(env.installHosts.contains { $0.host == "download.swift.org" })
        #expect(env.runtimeHosts.contains { $0.host == "registry.npmjs.org" && !$0.deny })
    }

    @Test func refusesKeysThatReachTheMacOrItsSecrets() throws {
        let home = try Home()
        defer { home.cleanup() }
        let env = try home.environment("""
            lifecycle: { initialize: [{ command: touch x }] }
            secrets: { TOKEN: { command: cat ~/.token } }
            mounts: { cache: /Users }
            sandboxOptions: { cpus: 2, usb: true }
            env: { ANTHROPIC_BASE_URL: http://host.docker.internal:17481, NODE_ENV: test }
            """)
        #expect(env.problems.contains(.refusedKey("lifecycle", reason: "it runs commands on this Mac")))
        #expect(env.problems.contains { if case .refusedKey("secrets", _) = $0 { true } else { false } })
        #expect(env.problems.contains { if case .refusedKey("mounts", _) = $0 { true } else { false } })
        #expect(env.problems.contains(.refusedOption("usb")))
        #expect(env.problems.contains(.refusedEnv("ANTHROPIC_BASE_URL")))
        #expect(env.problems.count == 5)
        #expect(!env.isAcceptable)
    }

    @Test func theWorkspaceIsTheProjectFolderOrNothing() throws {
        let home = try Home()
        defer { home.cleanup() }
        #expect(try home.environment("workspace: .\n").problems.isEmpty)
        #expect(try home.environment("workspace: \(home.project)\n").problems.isEmpty)
        #expect(try home.environment("").problems.isEmpty)
        #expect(try home.environment("workspace: ..\n").problems == [.workspaceNotProject("..")])
        #expect(try home.environment("workspace: { path: . }\n").problems.contains {
            if case .refusedKey("workspace", _) = $0 { true } else { false }
        })
    }

    @Test func extraFoldersAreCheckedLikeProjects() throws {
        let home = try Home()
        defer { home.cleanup() }
        try FileManager.default.createSymbolicLink(atPath: home.home + "/src/home-link", withDestinationPath: home.home)
        let env = try home.environment("""
            additionalWorkspaces:
              - { path: ../lib, readOnly: true }
              - { path: ../other }
              - { path: ../home-link }
              - { path: ../.., readOnly: true }
              - { path: ../missing }
              - { path: . }
              - { path: ../lib, target: /etc }
            """)
        #expect(env.extraFolders.first == .init(path: home.home + "/src/lib", readOnly: true, target: nil, otherProject: nil))
        #expect(env.extraFolders.contains { $0.path == home.home + "/src/other" && $0.otherProject == "other" && !$0.readOnly })
        #expect(env.problems.contains(.extraFolder("../home-link", .home)))  // the link is followed
        #expect(env.problems.contains(.extraFolder("../..", .home)))
        #expect(env.problems.contains(.extraFolderMissing("../missing")))
        #expect(env.problems.contains(.extraFolderIsProject(".")))
        #expect(env.problems.contains(.extraFolderTarget("/etc")))
    }

    @Test(arguments: [
        ("/workspace/docs", true), ("/mnt/lib", true), ("/data/x/y", true), ("/Users/me/src/lib", true),
        ("/home/agent/.claude/skills", false), ("/usr/local/bin", false), ("/etc/profile.d", false),
        ("/workspace", false), ("/workspace/../etc", false), ("/workspacex/a", false), ("docs", false), ("/tmp/paddock-tabs", false),
    ])
    func extraFolderTargetsAreAnAllowlist(target: String, allowed: Bool) {
        let clean = (target as NSString).standardizingPath
        #expect(ProjectEnvironment.isAllowedTarget(clean, original: target, home: "/Users/me") == allowed)
    }

    @Test func portsStayClearOfPaddocksServices() throws {
        let home = try Home()
        defer { home.cleanup() }
        let env = try home.environment("""
            ports:
              - { sandbox: 3000, host: 3000 }
              - { sandbox: 8080, host: 17434 }
              - { sandbox: 80, host: 17480 }
              - { sandbox: 2375 }
              - { sandbox: 9000, host: 9000, hostIP: 0.0.0.0 }
            """)
        #expect(env.problems == [.port(17434), .port(17480), .port(2375), .portHostIP("0.0.0.0")])
    }

    @Test func kitsAreSbxsOrTheProjectsOwn() throws {
        let home = try Home()
        defer { home.cleanup() }
        try home.kit("")
        try FileManager.default.createSymbolicLink(atPath: home.project + "/linked", withDestinationPath: home.project + "/kit")
        let env = try home.environment("""
            kits:
              - docker.io/docker/sbx-kit-claude:2.1.316
              - sbx/playwright:1.61.1
              - docker.io/sbx/mise@sha256:abc
              - ./kit
              - docker.io/acme/tools-kit:1
              - git+https://github.com/acme/kits.git
              - ../outside
              - ./kit/../kit
              - ./linked
              - /abs/kit
              - docker.io/sbx/../evil
            """)
        #expect(env.kits.prefix(4).map(\.origin) == [.catalog, .catalog, .catalog, .local(home.project + "/kit")])
        #expect(env.problems == [
            .customKit("docker.io/acme/tools-kit:1"), .customKit("git+https://github.com/acme/kits.git"),
            .localKitPath("../outside"), .localKitPath("./kit/../kit"), .localKitPath("./linked"), .localKitPath("/abs/kit"),
            .customKit("docker.io/sbx/../evil"),
        ])
    }

    @Test func aProjectKitRefusesWhatSbxFailsLate() throws {
        let home = try Home()
        defer { home.cleanup() }
        try home.kit("""
            capabilities:
              - type: com.docker.sandbox/network-policy@2
                config:
                  install: [deb.debian.org]
              - type: com.docker.sandbox/agent-context@2
                config: { content: hello }
            """)
        let env = try home.environment("kits: [./kit]\n")
        let messages = env.problems.map(\.description)
        #expect(messages.contains { $0.contains("use agent-context@1") })
        #expect(messages.contains { $0.contains("network install must be a mapping") })
    }

    @Test func aProjectKitAsksOnlyForWhatPaddockAccepts() throws {
        let home = try Home()
        defer { home.cleanup() }
        try home.kit("""
            capabilities:
              - type: com.docker.sandbox/network-policy@2
                config:
                  install: { allow: [ports.ubuntu.com] }
                  runtime:
                    allow:
                      - example.com
                      - { hosts: [api.example.com], methods: [GET], paths: ["/v1/**"] }
                      - localhost:5432
                      - "**"
                      - "*"
                    deny: [ads.example.com]
              - { type: com.docker.sandbox/host-port@1, config: { host: 5432 } }
              - type: com.docker.sandbox/credential@1
                config: { service: github, phase: runtime }
              - type: com.docker.sandbox/ssh-agent@1
              - type: com.acme/anything@1
            """)
        let env = try home.environment("kits: [./kit]\n")
        #expect(env.installHosts.map(\.host) == ["ports.ubuntu.com"])
        #expect(env.runtimeHosts.map(\.host) == ["example.com", "api.example.com", "ads.example.com"])
        #expect(env.runtimeHosts[1].methods == ["GET"] && env.runtimeHosts[1].paths == ["/v1/**"])
        #expect(env.runtimeHosts[2].deny)
        let messages = env.problems.map(\.description)
        #expect(messages.contains("kit ./kit: credential@1 is not accepted in a project's kit"))
        #expect(messages.contains("kit ./kit: ssh-agent@1 is not accepted in a project's kit"))
        #expect(messages.contains("kit ./kit: com.acme/anything@1 is not accepted in a project's kit"))
        #expect(messages.contains("kit ./kit: localhost:5432 is this Mac; allow its ports under Ports"))
        #expect(messages.contains("kit ./kit: ** would match every host"))
        #expect(messages.contains("kit ./kit: * would match every host"))
        #expect(messages.contains("kit ./kit: host-port@1 is not accepted in a project's kit"))  // sbx 0.51 lacks it
        #expect(env.problems.count == 7)
    }

    @Test func aProjectKitIsAMixinWithItsOwnFiles() throws {
        let home = try Home()
        defer { home.cleanup() }
        try home.write("kit/kit.yaml", "schemaVersion: \"3\"\nkind: workload\n")
        try FileManager.default.createSymbolicLink(atPath: home.project + "/kit/secret", withDestinationPath: home.home + "/.ssh")
        var env = try home.environment("kits: [./kit]\n")
        #expect(env.problems.map(\.description) == ["kit ./kit: secret is a link; a kit's files must be its own"])
        try FileManager.default.removeItem(atPath: home.project + "/kit/secret")
        env = try home.environment("kits: [./kit]\n")
        #expect(env.problems.map(\.description) == ["kit ./kit: a project's own kit must be a mixin, not a workload"])
        try home.write("kit/kit.yaml", "schemaVersion: \"3\"\nkind: mixin\nprovides: [kit, other@1.0.0]\n")
        env = try home.environment("kits: [./kit]\n")
        #expect(env.problems.map(\.description) == ["kit ./kit: provides kit without a version (add @1.0.0, or a top-level version:)"])
        try home.write("kit/kit.yaml", "schemaVersion: \"3\"\nkind: mixin\nversion: \"1.0.0\"\nprovides: [kit]\n")
        #expect(try home.environment("kits: [./kit]\n").problems.isEmpty)
        try home.write("kit/kit.yaml", "schemaVersion: \"2\"\nkind: mixin\n")
        env = try home.environment("kits: [./kit]\n")
        #expect(env.problems.map(\.description) == [#"kit ./kit: schemaVersion "2" is not a v3 kit ("3")"#])
        try FileManager.default.removeItem(atPath: home.project + "/kit/kit.yaml")
        env = try home.environment("kits: [./kit]\n")
        #expect(env.problems.map(\.description) == ["kit ./kit: kit.yaml is missing"])
    }

    @Test func theFingerprintCoversTheFileAndTheKit() throws {
        let home = try Home()
        defer { home.cleanup() }
        try home.kit("")
        try home.write("kit/kit.dockerfile", "FROM scratch\n")
        let first = try home.environment("kits: [./kit]\n").fingerprint
        #expect(try home.environment("kits: [./kit]\n").fingerprint == first)
        try home.write("kit/kit.dockerfile", "FROM scratch\nCOPY x /x\n")
        let second = try home.environment("kits: [./kit]\n").fingerprint
        #expect(second != first)
        try home.write("kit/extra/file.txt", "new")
        #expect(try home.environment("kits: [./kit]\n").fingerprint != second)
        #expect(try home.environment("kits: [./kit]\nenv: { A: b }\n").fingerprint != second)
    }

    @Test func aBrokenFileIsOneProblem() throws {
        let home = try Home()
        defer { home.cleanup() }
        try home.write("sbxenv.yaml", "schemaVersion: \"1\"\nagent: [\n")
        let env = try #require(ProjectEnvironment.read(folder: home.project, context: home.context))
        #expect(env.file == nil && env.problems.count == 1 && !env.isAcceptable && env.fingerprint.count == 64)
    }
}

@Suite("EnvironmentReview")
struct EnvironmentReviewTests {
    @Test func theOperatorConfirmsTheFileAndMayDeclineEachRuntimeHost() throws {
        let home = try ProjectEnvironmentTests.Home()
        defer { home.cleanup() }
        try home.kit("""
            capabilities:
              - type: com.docker.sandbox/network-policy@2
                config:
                  install: { allow: [ports.ubuntu.com] }
                  runtime:
                    allow:
                      - api.github.com:443
                      - { hosts: [api.example.com], methods: [GET], paths: ["/v1/**"] }
                      - api.example.com
                    deny: [ads.example.com]
            """)
        let env = try home.environment("kits: [./kit]\n")
        let globals = try Fixture.decode(SbxPolicyList.self, "sbx", "policy-ls.json").rules
        var project = Project(name: "app", folder: home.project)
        let review = EnvironmentReview.make(env, project: project, globalRules: globals)
        #expect(review.needsApproval && review.canApprove)
        // one row per host and kit; a global allow is named, since declining still denies it here
        #expect(review.runtimeHosts.map(\.host) == ["api.github.com:443", "api.example.com"])
        #expect(review.runtimeHosts[0].allowedGlobally == "**.github.com:443")
        #expect(review.runtimeHosts[1].allowedGlobally == nil && review.runtimeHosts[1].methods == ["GET"])
        #expect(review.deniedHosts == ["ads.example.com"] && review.installHosts == ["ports.ubuntu.com"])

        project = review.approve(project, declined: ["api.example.com", "ads.example.com", "elsewhere.example"])
        #expect(project.approvedEnvironment == env.fingerprint)
        #expect(project.declinedHosts == ["api.example.com"])  // only hosts the review offered
        #expect(!EnvironmentReview.make(env, project: project, globalRules: globals).needsApproval)
    }

    @Test func refusedEntriesCannotBeConfirmed() throws {
        let home = try ProjectEnvironmentTests.Home()
        defer { home.cleanup() }
        let env = try home.environment("lifecycle: { initialize: [{ command: touch x }] }\n")
        #expect(!EnvironmentReview.make(env, project: Project(name: "app", folder: home.project), globalRules: []).canApprove)
    }
}

@Suite("PaddockOverlay")
struct PaddockOverlayTests {
    @Test func readsBackAsWritten() throws {
        let overlay = PaddockOverlay(
            agent: "sbx-kit-claude", workspace: "/Users/op/src/My App",
            kits: ["docker.io/sbx/mise@sha256:abc", "/Users/op/.config/paddock/kits/status"],
            env: ["ANTHROPIC_BASE_URL": "http://host.docker.internal:17480", "PADDOCK_NOTE": "a: b\n- c \"d\" # e"])
        let file = try SbxEnvFile.load(from: Data(overlay.yaml.utf8))
        #expect(file.agent == overlay.agent && file.workspace == overlay.workspace)
        #expect(file.kits.map(\.source) == overlay.kits)
        #expect(file.env == overlay.env)
        #expect(file.otherKeys.isEmpty && file.name == nil)
        #expect(overlay.yaml.contains("workspace: \"/Users/op/src/My App\"\n"))
    }

    @Test func extraFoldersBecomeAdditionalWorkspaces() throws {
        let overlay = PaddockOverlay(agent: "claude", workspace: "/Users/op/src/app",
                                     extraFolders: [.init(path: "/Users/op/src/lib"), .init(path: "/Users/op/notes, \"x\"", readOnly: false)])
        let file = try SbxEnvFile.load(from: Data(overlay.yaml.utf8))
        #expect(file.additionalWorkspaces.map(\.path) == ["/Users/op/src/lib", "/Users/op/notes, \"x\""])
        #expect(file.additionalWorkspaces.map(\.readOnly) == [true, false])
    }

    @Test func theCreateNamesBothFilesAndNothingRunsOnTheMac() {
        #expect(PaddockOverlay.createArguments(environmentFile: "/p/sbxenv.yaml", overlay: "/c/app.sbxenv.yaml", name: "app", clone: true)
            == ["env", "create", "/p/sbxenv.yaml", "/c/app.sbxenv.yaml", "--name", "app", "--skip-host-commands", "--force", "--clone"])
    }

    @Test func livesInPaddocksProjectsFolder() {
        let paths = PaddockPaths(configDirectory: "/Users/op/.config/paddock")
        #expect(PaddockOverlay.path(project: "app", paths: paths) == "/Users/op/.config/paddock/projects/app.sbxenv.yaml")
    }
}

@Suite("SandboxFiles")
struct SandboxFilesTests {
    @Test(arguments: [("my-app", "my-app"), ("v1.2", "v1-2"), ("App", "app"), ("--", "project"), (".x.", "x")])
    func kitNames(name: String, kit: String) {
        #expect(SandboxFiles.kitName(for: name) == kit)
        #expect(Kit.isValidName(SandboxFiles.kitName(for: name)))
    }

    @Test func generatedFilesPassPaddocksOwnChecks() throws {
        let home = try ProjectEnvironmentTests.Home()
        defer { home.cleanup() }
        let input = SandboxFiles.Input(name: "app", agent: "sbx-kit-claude", workload: "docker.io/docker/sbx-kit-claude:2.1.316",
                                       publish: [3000], allow: ["api.example.com", "*.npmjs.org"],
                                       deny: ["ads.example.com"])
        try SandboxFiles.write(SandboxFiles.files(input), into: home.project)
        let env = try #require(ProjectEnvironment.read(folder: home.project, context: home.context))
        #expect(env.problems.isEmpty, "\(env.problems)")
        #expect(env.file?.name == "app" && env.file?.ports == [.init(sandbox: 3000, host: 3000)])
        #expect(env.kits.map(\.origin) == [.catalog, .local(home.project + "/tools/sandbox/app")])
        #expect(env.runtimeHosts.map(\.host) == ["api.example.com", "*.npmjs.org", "ads.example.com"])
        let descriptor = try #require(env.kits[1].descriptor)
        #expect(descriptor.capabilities.map(\.type) == ["com.docker.sandbox/network-policy@2"])
        // never over a project's own files
        #expect(throws: SandboxFiles.WriteError.exists("sbxenv.yaml")) { try SandboxFiles.write(SandboxFiles.files(input), into: home.project) }
    }

    @Test func generatedFilesNameNothingOfPaddocks() throws {
        for file in SandboxFiles.files(.init(name: "app", agent: "claude", publish: [3000], allow: ["a.example.com"], deny: ["b.example.com"])) {
            // the run script alone names the overlay's folder (it is a default, RUN_SANDBOX_OVERLAY sets another)
            #expect(file.path == SandboxFiles.runScriptPath || !file.contents.localizedCaseInsensitiveContains("paddock"), "\(file.path)")
            #expect(!file.contents.contains("agent-context"), "\(file.path)")
        }
    }

    @Test func theRunScriptIsWrittenExecutableAndNeverOverAnother() throws {
        let home = try ProjectEnvironmentTests.Home()
        defer { home.cleanup() }
        try SandboxFiles.write(SandboxFiles.files(.init(name: "app", agent: "claude")), into: home.project)
        let path = home.project + "/" + SandboxFiles.runScriptPath
        #expect(FileManager.default.isExecutableFile(atPath: path))
        let script = try String(contentsOfFile: path, encoding: .utf8)
        #expect(script.hasPrefix("#!/bin/sh\n#MISE description=") && script.contains("--skip-host-commands") && script.contains("sbx env plan") && script.contains("RUN_SANDBOX_OVERLAY"))
    }

    @Test func aMinimalProjectGetsOnlyTheAgentAndItsKit() throws {
        let home = try ProjectEnvironmentTests.Home()
        defer { home.cleanup() }
        try SandboxFiles.write(SandboxFiles.files(.init(name: "app", agent: "sbx-kit-claude", workload: "docker.io/docker/sbx-kit-claude:2.1.316")),
                               into: home.project)
        let env = try #require(ProjectEnvironment.read(folder: home.project, context: home.context))
        #expect(env.isAcceptable && env.runtimeHosts.isEmpty && env.file?.ports == [])
    }

    @Test func sbxsOwnAgentNeedsNoWorkloadKit() throws {
        let home = try ProjectEnvironmentTests.Home()
        defer { home.cleanup() }
        try SandboxFiles.write(SandboxFiles.files(.init(name: "app", agent: "claude")), into: home.project)
        let env = try #require(ProjectEnvironment.read(folder: home.project, context: home.context))
        #expect(env.isAcceptable && env.file?.agent == "claude")
        #expect(env.kits.map(\.source) == ["./tools/sandbox/app"])
    }

}

/// sbx 0.51 output for sandboxes made by `sbx env create` with v3 kits (PAD-73.1, fourth run).
@Suite("sbx v3 shapes")
struct SbxV3ShapeTests {
    @Test func sbxLsListsExtraFoldersAndTheEnvFileAsWorkspaces() throws {
        let sandboxes = try Fixture.decode([SbxSandbox].self, "sbx", "ls-v3.json")
        let v3 = try #require(sandboxes.first { $0.name == "m0-v3" })
        #expect(v3.agent == "sbx-kit-claude" && v3.isRunning)
        // the project first, extra folders with :ro when read-only, and sbx's own read-only
        // mount of the env file inside the project (the agent cannot change it in the sandbox)
        #expect(v3.workspaces.count == 4)
        #expect(v3.workspaces[1].hasSuffix("/extra-ro:ro") && !v3.workspaces[2].hasSuffix(":ro"))
        #expect(v3.workspaces[3].hasSuffix("/project/sbxenv.yaml:ro"))
        // the built-in claude is a v3 kit in 0.51 and its agent name stays claude
        #expect(sandboxes.contains { $0.name == "m0-v2mix" && $0.agent == "claude" })
    }

    @Test func kitRulesAreOneAllowForEveryKitAndOneHTTPRulePerBoundedEntry() throws {
        let rules = try Fixture.decode(SbxPolicyList.self, "sbx", "policy-ls-v3-sandbox.json").rules
        let kit = try #require(rules.first { $0.name == "kit:m0-v3" })
        #expect(kit.decision == "allow" && kit.resources.contains("example.com") && kit.resources.contains("api.anthropic.com:443"))
        let http = try #require(rules.first { $0.name == "kit:m0-v3:http:0" })
        #expect(http.methods == ["GET"] && http.httpTargets?.first?.path == "/get")
        // the sandbox deny the operator adds over a kit allow (it wins: curl got 403)
        #expect(rules.contains { $0.decision == "deny" && $0.resources == ["example.com"] })
        // sbx 0.51 lists its implicit fallback with neither policy_id nor provenance
        let fallback = try #require(rules.first { $0.id == "default-deny-all" })
        #expect(fallback.policyId == nil && fallback.createdVia == "implicit" && fallback.resources == ["**"])
    }
}

@Suite("ProjectKitFile")
struct ProjectKitFileTests {
    @Test(arguments: [
        ("mise", "docker.io/sbx/mise"),
        ("docker.io/sbx/mise:2026.5.2", "docker.io/sbx/mise:2026.5.2"),
        ("docker.io/acme/tools-kit:1", nil),
        ("git+https://github.com/acme/kit.git", nil),
    ] as [(String, String?)])
    func onlyCatalogKitsGoToTheProject(text: String, reference: String?) {
        #expect(ProjectKitFile.catalogReference(text) == reference)
    }

    @Test func addsToTheBlockKeepingEverythingElse() throws {
        let text = "# mine\nagent: claude\nkits:\n  # the tools\n  - ./tools/sandbox/app\n  - source: docker.io/sbx/node\n    args: { v: \"1\" }\n\nenv:\n  A: b\n"
        let added = try ProjectKitFile.inserting("docker.io/sbx/mise", into: text)
        #expect(added == "# mine\nagent: claude\nkits:\n  # the tools\n  - ./tools/sandbox/app\n  - source: docker.io/sbx/node\n    args: { v: \"1\" }\n  - \"docker.io/sbx/mise\"\n\nenv:\n  A: b\n")
        // a list at column 0, and no list at all
        #expect(try ProjectKitFile.inserting("x", into: "kits:\n- a\nenv: {}\n") == "kits:\n- a\n- \"x\"\nenv: {}\n")
        #expect(try ProjectKitFile.inserting("x", into: "agent: claude\n") == "agent: claude\n\nkits:\n  - \"x\"\n")
        #expect(throws: ProjectKitFile.Problem.kitsNotABlock) { try ProjectKitFile.inserting("x", into: "kits: [a]\n") }
    }

    @Test func addsOnceToTheFileOnDisk() throws {
        let folder = NSTemporaryDirectory() + "paddock-kitfile-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try Data("schemaVersion: \"1\"\nagent: claude\n".utf8).write(to: URL(fileURLWithPath: folder + "/sbxenv.yaml"))
        #expect(try ProjectKitFile.add("docker.io/sbx/mise", folder: folder))
        #expect(try !ProjectKitFile.add("docker.io/sbx/mise", folder: folder))
        let file = try SbxEnvFile.load(from: Data(contentsOf: URL(fileURLWithPath: folder + "/sbxenv.yaml")))
        #expect(file.kits.map(\.source) == ["docker.io/sbx/mise"])
    }
}
