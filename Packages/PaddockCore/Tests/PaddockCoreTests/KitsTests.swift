import Foundation
import Testing
@testable import PaddockCore

/// sbx kits per project: backlog doc Kits.
@Suite("Kits")
struct KitsTests {
    let paths = PaddockPaths(configDirectory: "/Users/op/.config/paddock")

    func load(_ yaml: String) throws -> (config: AppConfig, unknownKeys: [String]) {
        try AppConfig.load(from: Data(("version: 1\n" + yaml).utf8))
    }

    // MARK: - paddock.yaml

    @Test func everyConfigHasTheDefaultKits() throws {
        let (config, unknown) = try load("")
        #expect(unknown.isEmpty)
        #expect(config.kits == AppConfig.defaultKits)
        #expect(config.kits["opencode"] == nil && config.kits["status"]?.source == .builtin(.status))
        #expect(config.kits["browser"]?.needs == ["base", "playwright", "node"])
        // PAD-147: the base kit is in every sandbox; Playwright MCP is its own kit, for Claude Code
        #expect(config.kits["base"] == Kit(source: .builtin(.base), summary: config.kits["base"]?.summary ?? "", recommended: true, needs: ["node"]))
        #expect(config.kits["browser-mcp"]?.needs == ["browser"] && config.kits["browser-mcp"]?.agents == [.claudeCode])
        #expect(config.kits["browser-mcp"]?.recommended == false && config.kits["base"]?.recommended == true)
        // sbx's v3 kits, pinned by tag and digest (their tags move)
        for (name, kit) in config.kits {
            guard case .reference(let reference) = kit.source else { continue }
            #expect(reference.hasPrefix("docker.io/sbx/\(name):") && reference.contains("@sha256:"), "\(name)")
            #expect(AppConfig.referenceProblem(reference) == nil)
        }
    }

    @Test func aSectionAddsChangesOrRemovesKits() throws {
        let (config, unknown) = try load("""
            kits:
              mine:
                source: /Users/op/kits/mine
                summary: My tools
                agents: [claudeCode]
              playwright:
                recommended: true
              gh:
              opencode:
                enabled: false
            """)
        #expect(unknown.isEmpty)
        #expect(config.kits["mine"] == Kit(source: .reference("/Users/op/kits/mine"), summary: "My tools", agents: [.claudeCode]))
        #expect(config.kits["playwright"]?.recommended == true)
        #expect(config.kits["playwright"]?.source == AppConfig.defaultKits["playwright"]?.source)
        // a name alone is sbx's contrib kit (the v2 build)
        #expect(config.kits["gh"]?.source == .reference("docker.io/sbx/gh"))
        #expect(config.kits["opencode"] == nil)
        // mise is a default, off unless chosen
        #expect(config.kits["mise"]?.recommended == false)
    }

    @Test func onlyPaddocksKitsPlaywrightAndMiseAreDefaults() {
        #expect(Set(AppConfig.defaultKits.keys) == ["base", "browser", "browser-mcp", "playwright", "status", "voice", "mise", "node"])
    }

    @Test func unknownKitKeysAreReported() throws {
        let (_, unknown) = try load("kits:\n  playwright:\n    recomended: true\n")
        #expect(unknown == ["kits.playwright.recomended"])
    }

    @Test(arguments: [
        ("kits:\n  x:\n    source: a\n    builtin: browser", "set either source or builtin, not both"),
        ("kits:\n  x:\n    source: \"--privileged\"", "source may not start with -"),
        ("kits:\n  x:\n    source: ./kits/x", "a local kit needs an absolute path"),
        ("kits:\n  x:\n    source: \"docker.io/x kit\"", "source may not contain spaces or control characters"),
        ("kits:\n  x:\n    source: \"\"", "source is empty"),
        ("kits:\n  x:\n    source: docker.io/x\n    needs: [nope]", "needs nope, which is not defined"),
        ("kits:\n  x:\n    source: docker.io/x\n    agents: [claude]", "agents names claude, which is not an agent kind (claudeCode, openCode)"),
    ])
    func badKitsAreRefused(yaml: String, problem: String) {
        #expect(throws: AppConfigError.invalidKit(name: "x", problem: problem)) { try load(yaml) }
    }

    @Test func withoutASourceTheNameMustBeAnSbxKitName() {
        #expect(throws: AppConfigError.invalidKit(name: "My_Kit", problem: "set source (or builtin); without one the name must be an sbx kit name")) {
            try load("kits:\n  My_Kit:\n    summary: no source")
        }
    }

    @Test func unknownBuiltinsAndCyclesAreRefused() {
        #expect(throws: AppConfigError.self) { try load("kits:\n  x:\n    builtin: claude-gateway") }
        let cycle = "kits:\n  a:\n    source: docker.io/a\n    needs: [b]\n  b:\n    source: docker.io/b\n    needs: [a]"
        #expect(throws: AppConfigError.invalidKit(name: "a", problem: "its needs go round in a circle")) { try load(cycle) }
    }

    // MARK: - Selection

    @Test func paddocksOwnKitsArePreselected() {
        let app = AppConfig()
        #expect(KitSelection.preselected(agent: .openCode, app: app) == ["base", "node", "status"])
        #expect(KitSelection.preselected(agent: .claudeCode, app: app) == ["base", "node", "status"])
    }

    @Test func theDraftFollowsTheAgentAndTheNeeds() throws {
        let app = try load("kits:\n  task:\n").config
        var draft = ProjectDraft(folder: "/src/app", name: "paddock-app", agent: "opencode", provider: "agent-default",
                                 kits: ["task"])
        draft.agentChanged(app: app)
        #expect(draft.kits == ["base", "node", "status", "task"])
        // the base kit is optional: unselecting it unselects the browser kit, which needs it
        draft.setKit("base", selected: false, app: app)
        #expect(draft.kits == ["node", "status", "task"])
        draft.setKit("browser", selected: true, app: app)
        #expect(draft.kits == ["base", "browser", "node", "playwright", "status", "task"])
        // unselecting a kit unselects what builds on it (the base kit stays: every sandbox has it)
        draft.setKit("playwright", selected: false, app: app)
        #expect(draft.kits == ["base", "node", "status", "task"])
        draft.agent = "claude"
        draft.agentChanged(app: app)
        #expect(draft.kits == ["base", "node", "status", "task"])
    }

    @Test func kitsComeAfterWhatTheyNeedAndTheGatewayNeedsNone() throws {
        let app = try load("kits:\n  vale:\n").config
        let kits = try KitSelection.resolve(["vale", "browser", "playwright", "node", "base"], agent: .claudeCode, usesGateway: true, app: app,
                                            paths: paths, projectFolders: [])
        #expect(kits.map(\.name) == ["node", "base", "playwright", "browser", "vale"])
        #expect(kits[3].argument == "/Users/op/.config/paddock/kits/paddock-browser" && kits[3].builtin == .browser)
        #expect(kits[1].argument == "/Users/op/.config/paddock/kits/paddock-base" && kits[1].builtin == .base)
        #expect(kits[0].argument == "/Users/op/.config/paddock/kits/paddock-node")
        // no gateway kit for OpenCode, or without a local model
        #expect(try KitSelection.resolve(["status", "node"], agent: .openCode, usesGateway: true, app: app, paths: paths, projectFolders: [])
            .map(\.name) == ["node", "status"])
        #expect(try KitSelection.resolve([], agent: .claudeCode, usesGateway: false, app: app, paths: paths, projectFolders: []).isEmpty)
    }

    @Test func resolvingChecksEveryKit() throws {
        let app = AppConfig()
        #expect(throws: KitError.unknownKit("nope")) {
            try KitSelection.ordered(["nope"], agent: .claudeCode, app: app, projectFolders: [])
        }
        let openCodeOnly = try load("kits:\n  oc:\n    source: docker.io/acme/oc\n    agents: [openCode]\n").config
        #expect(throws: KitError.notForAgent(kit: "oc", agent: "claude")) {
            try KitSelection.ordered(["oc"], agent: .claudeCode, app: openCodeOnly, projectFolders: [])
        }
        #expect(throws: KitError.missingNeed(kit: "browser", needs: "base")) {
            try KitSelection.ordered(["browser"], agent: .claudeCode, app: app, projectFolders: [])
        }
    }

    /// An agent can write its project folder: a kit from there could rewrite its own install steps
    /// and network rules.
    @Test func aLocalKitInsideAProjectFolderIsRefused() throws {
        var app = AppConfig()
        app.kits["mine"] = Kit(source: .reference("/Users/op/src/other/kit"))
        #expect(throws: KitError.kitInsideProject(kit: "mine", path: "/Users/op/src/other/kit")) {
            try KitSelection.ordered(["mine"], agent: .claudeCode, app: app, projectFolders: ["/Users/op/src/app", "/Users/op/src/other"])
        }
        #expect(try KitSelection.ordered(["mine"], agent: .claudeCode, app: app, projectFolders: ["/Users/op/src/app"]) == ["mine"])
    }

    // MARK: - The kit field

    @Test(arguments: [
        ("mise", "mise", nil),
        ("  task ", "task", nil),
        ("docker.io/sbx/mise-kit@sha256:6296fd5b", "mise", "docker.io/sbx/mise-kit@sha256:6296fd5b"),
        ("docker.io/acme/lint-kit:1.2", "lint", "docker.io/acme/lint-kit:1.2"),
        ("git+https://github.com/acme/kits.git#dir=tools", "kits", "git+https://github.com/acme/kits.git#dir=tools"),
        ("/Users/op/kits/My-Tools", "my-tools", "/Users/op/kits/My-Tools"),
    ] as [(String, String, String?)])
    func theFieldTakesANameOrAReference(input: String, name: String, source: String?) throws {
        let parsed = try Kit.parseInput(input)
        #expect(parsed.name == name && parsed.source == source)
    }

    @Test func theFieldRefusesWhatSbxWouldNotTake() {
        #expect(throws: KitInputError.invalidReference("source may not start with -")) { try Kit.parseInput("--privileged") }
        #expect(throws: KitInputError.invalidReference("a local kit needs an absolute path")) { try Kit.parseInput("./kit") }
        #expect(throws: KitInputError.self) { try Kit.parseInput("docker.io/a b") }
    }

    @Test func addingAKitAppendsASectionAndKeepsTheRest() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-cfg-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/paddock.yaml"
        // no file yet: a minimal one with the kit
        #expect(try AppConfigFile.addKit("gh", app: AppConfig(), path: path) == "gh")
        var app = try AppConfig.load(atPath: path).config
        #expect(app.kits["gh"]?.source == .reference("docker.io/sbx/gh"))
        // a hand edit (and its comment) stays; a reference gets its source
        let edited = String(decoding: FileManager.default.contents(atPath: path) ?? Data(), as: UTF8.self) + "# mine\n"
        try Data(edited.utf8).write(to: URL(fileURLWithPath: path))
        #expect(try AppConfigFile.addKit("docker.io/acme/lint-kit:1.2", app: app, path: path) == "lint")
        let text = String(decoding: FileManager.default.contents(atPath: path) ?? Data(), as: UTF8.self)
        #expect(text.hasSuffix("  gh: {}\n  # Added from Paddock's kit field.\n  lint:\n    source: \"docker.io/acme/lint-kit:1.2\"\n# mine\n"))
        app = try AppConfig.load(atPath: path).config
        #expect(app.kits["lint"]?.source == .reference("docker.io/acme/lint-kit:1.2"))
        // the same kit again changes nothing; the same name from elsewhere is refused
        #expect(try AppConfigFile.addKit("lint", app: try load("kits:\n  lint:\n").config, path: path) == "lint")
        #expect(throws: KitInputError.nameTaken("lint")) { try AppConfigFile.addKit("docker.io/other/lint-kit", app: app, path: path) }
        #expect(throws: KitInputError.nameTaken("playwright")) { try AppConfigFile.addKit("/Users/op/playwright", app: app, path: path) }
        // a defined kit's name only selects it
        #expect(try AppConfigFile.addKit("playwright", app: app, path: path) == "playwright")
        #expect(!String(decoding: FileManager.default.contents(atPath: path) ?? Data(), as: UTF8.self).contains("\n  playwright:"))
    }

    /// A new paddock.yaml documents every section, and means exactly the defaults.
    @Test func theTemplateIsTheDefaultsWithEverySectionDocumented() throws {
        let (config, unknown) = try AppConfig.load(from: Data(AppConfigFile.template.utf8))
        #expect(config == AppConfig() && unknown.isEmpty)
        for section in ["models:", "defaults:", "providers:", "agents:", "ports:", "kits:"] {
            #expect(AppConfigFile.template.contains("\n# " + section), "\(section)")
        }
        // every key the file knows is shown
        for key in ["gatewayPorts:", "maxBodyMB:", "maxConcurrentPerProject:", "agent:", "provider:", "kind:", "model:",
                    "publishRange:", "source:", "summary:", "recommended:", "agents:", "needs:", "enabled:", "builtin:"] {
            #expect(AppConfigFile.template.contains(key), "\(key)")
        }
        #expect(!AppConfigFile.template.contains("\u{2014}"))
    }

    // MARK: - Projects

    @Test func projectFilesFromBeforeKitsGetWhatPaddockAlwaysAdded() throws {
        let app = AppConfig()
        // they got Paddock's opencode kit, which is gone (PAD-73.2), as are setup's choosers; every
        // project gets the base kit and what it needs (PAD-147)
        let old = Project(name: "paddock-app", folder: "/src/app", agent: "opencode")
        #expect(old.chosenKits(app) == ["base", "node"])
        #expect(Project(name: "paddock-app", folder: "/src/app", agent: "claude", kits: ["setup", "status"]).chosenKits(app) == ["status", "base", "node"])
        #expect(Project(name: "paddock-app", folder: "/src/app", agent: "claude").chosenKits(app) == ["base", "node"])
        let chosen = Project(name: "paddock-app", folder: "/src/app", agent: "opencode", kits: [])
        #expect(chosen.chosenKits(app) == ["base", "node"])
        // a project that chose the browser kit before the split gets the base kit too
        #expect(Project(name: "paddock-app", folder: "/src/app", agent: "claude", kits: ["browser", "playwright", "node"]).chosenKits(app)
            == ["browser", "playwright", "node", "base"])
        // a choice made since (kitChoice recorded) is taken as it is: the base kit is optional
        var since = Project(name: "paddock-app", folder: "/src/app", agent: "claude", kits: ["status"])
        since.kitChoice = KitSelection.choiceRevision
        #expect(since.chosenKits(app) == ["status", "node"])
        since.kits = ["base", "status"]
        #expect(since.chosenKits(app) == ["base", "status", "node"])
        // ...and the browser kit still brings it
        since.kits = ["browser"]
        #expect(Set(since.chosenKits(app)) == ["browser", "base", "playwright", "node"])
        // kitChoice is kept in the project file; files from before it have none
        let decoded = try ProjectDirectory.decode(file: "paddock-app.json", data: try ProjectDirectory.encode(since))
        #expect(decoded.kitChoice == KitSelection.choiceRevision)
        // paddock.yaml can still turn it off, and then nothing adds it
        var off = app
        off.kits["base"] = nil
        off.kits["browser"]?.needs = ["playwright", "node"]
        #expect(Project(name: "paddock-app", folder: "/src/app", agent: "claude").chosenKits(off).isEmpty)

        var saved = Project(name: "paddock-app", folder: "/src/app", kits: ["playwright"], sandboxKits: ["docker.io/sbx/playwright-kit@sha256:abc"])
        saved = try ProjectDirectory.decode(file: "paddock-app.json", data: try ProjectDirectory.encode(saved))
        #expect(saved.kits == ["playwright"] && saved.sandboxKits == ["docker.io/sbx/playwright-kit@sha256:abc"])
    }

    @Test func otherKitsThanTheSandboxWasCreatedWithMeanRecreate() {
        let app = AppConfig()
        let sandbox = SbxSandbox(name: "paddock-app", id: "1", agent: "claude", status: "running", lastUsedAt: nil,
                                 workspaces: ["/src/app"], createdAt: Date())
        let snapshot = SandboxSnapshot(sandbox: sandbox, ports: [], rules: [])
        var project = Project(name: "paddock-app", folder: "/src/app", kits: ["playwright"], sandboxKits: ["a"])
        func kitsItem() -> SyncItem? {
            SandboxSync.diff(project: project, snapshot: snapshot, globalRules: [], app: app,
                             expectedKits: .success(["a", "b"])).first { $0.id == "kits" }
        }
        #expect(kitsItem()?.apply == .recreate)
        project.sandboxKits = ["a", "b"]
        #expect(kitsItem() == nil)
        // a sandbox whose kits Paddock never recorded
        project.sandboxKits = nil
        #expect(kitsItem() == nil)
        let broken = SandboxSync.diff(project: project, snapshot: snapshot, globalRules: [], app: app,
                                      expectedKits: .failure(.unknownKit("gone"))).first { $0.id == "kits" }
        #expect(broken?.apply == nil && broken?.summary.contains("gone") == true)
    }

    // MARK: - The browser kit

    @Test func theBrowserKitBuildsOnThePlaywrightKit() {
        let spec = BrowserKit.spec
        #expect(spec.contains("schemaVersion: \"3\"") && spec.contains("kind: mixin"))
        #expect(spec.contains("\"\(BrowserKit.package)@\(BrowserKit.version)\""))
        // Playwright's own Chromium; Google Chrome has no Linux arm64 build
        #expect(spec.contains("default: chromium\n    env: PLAYWRIGHT_MCP_BROWSER"))
        // the dashboard, published by sbx on the Mac's loopback
        #expect(spec.contains("container: \(BrowserKit.dashboardPort)"))
        #expect(spec.contains("show --port \(BrowserKit.dashboardPort) --host 0.0.0.0"))
        // its network allows never name this Mac (llmman, gateways)
        let allows = spec.components(separatedBy: "network-policy@2").dropFirst().first?.components(separatedBy: "port@1").first ?? ""
        #expect(allows.contains("registry.npmjs.org:443"))
        #expect(!allows.contains("localhost") && !allows.contains("host.docker.internal"))
        #expect(!spec.contains("\t"))
    }

    /// Playwright MCP in the sandbox (PAD-141, PAD-142), its own kit on the browser kit since PAD-147:
    /// installed there, one server per sandbox started on every start, and Claude Code registered with
    /// it over HTTP. The browser kit no longer installs or starts it.
    @Test func theBrowserMCPKitRunsOneSharedPlaywrightMCP() throws {
        let spec = BrowserMCPKit.spec
        #expect(spec.contains("\"\(BrowserKit.mcpPackage)@\(BrowserKit.mcpVersion)\""))
        #expect(BrowserKit.spec.contains("\"\(BrowserKit.package)@\(BrowserKit.version)\"\n"))
        #expect(!BrowserKit.spec.contains(BrowserKit.mcpPackage) && !BrowserKit.spec.contains(BrowserKit.mcpLauncherPath))
        #expect(!BrowserKit.spec.contains("mcp__"))
        // the pair built on the same Playwright, so one Chromium build serves both
        #expect(BrowserKit.version == "0.1.22" && BrowserKit.mcpVersion == "0.0.83")
        let script = BrowserKit.registerMCPScript
        #expect(script.contains("command -v claude >/dev/null || exit 0"))
        #expect(script.hasSuffix("claude mcp add --scope user --transport http playwright http://localhost:38324/mcp"))
        // localhost in the sandbox only: sbx publishes only the browser kit's dashboard port
        #expect(BrowserKit.spec.components(separatedBy: "com.docker.sandbox/port@1").count == 2)
        #expect(!spec.contains("com.docker.sandbox/port@1"))
        // the YAML holds both steps as written, run as the agent's user, the server first
        guard case .object(let root) = try YAMLCoding.value(fromYAML: Data(spec.utf8)),
              case .array(let capabilities)? = root["capabilities"] else {
            Issue.record("the kit is not a YAML object with capabilities")
            return
        }
        let startup: [JSONValue] = capabilities.flatMap { capability -> [JSONValue] in
            guard case .object(let object) = capability, object["type"] == .string("com.docker.sandbox/lifecycle@1"),
                  case .object(let config)? = object["config"], case .array(let steps)? = config["startup"] else { return [] }
            return steps
        }
        func index(of command: JSONValue) -> Int? {
            startup.firstIndex {
                guard case .object(let step) = $0 else { return false }
                return step["command"] == command && step["user"] == .string("1000")
            }
        }
        let start = index(of: .array([.string(BrowserKit.mcpLauncherPath), .string("start")]))
        let register = index(of: .array([.string("sh"), .string("-c"), .string(script)]))
        #expect(start != nil && register != nil && (start ?? 0) < (register ?? 0))
        #expect(spec.contains("mcp__\(BrowserKit.mcpServerName)__*") && spec.contains("paddock-browser-mcp restart"))
        #expect(spec.contains(Data(BrowserKit.mcpLauncher.utf8).base64EncodedString()))
        #expect(spec.contains("provides: [paddock-browser-mcp]") && spec.contains("allow: [registry.npmjs.org:443]"))
    }

    /// The launcher's server: a kept profile, the extensions folder, localhost, full Chromium, and none
    /// of its caller's PLAYWRIGHT_MCP_ settings (no unrestricted file access); stopped with its browser.
    @Test func theMCPLauncherKeepsTheProfileAndLoadsExtensions() {
        let launcher = BrowserKit.mcpLauncher
        #expect(launcher.hasPrefix(NodeScript.header))
        #expect(launcher.contains("const PROFILE = '/home/agent/.cache/paddock-browser/profile';"))
        #expect(launcher.contains("const EXTENSIONS = '/home/agent/.config/paddock-browser/extensions';"))
        #expect(launcher.contains("fs.existsSync(path.join(EXTENSIONS, n, 'manifest.json'))"))
        #expect(launcher.contains("`--disable-extensions-except=${found.join(',')}`, `--load-extension=${found.join(',')}`"))
        #expect(launcher.contains("server: { host: 'localhost', port: PORT }") && launcher.contains("const PORT = 38324;"))
        #expect(launcher.contains("sharedBrowserContext: true"))
        #expect(launcher.contains("if (!key.startsWith('PLAYWRIGHT_MCP_')) env[key] = value;"))
        #expect(launcher.contains("PLAYWRIGHT_MCP_BROWSER: 'chromium'"))
        #expect(!launcher.contains("unrestricted") && !launcher.contains("ignoreHTTPSErrors") && !launcher.contains("0.0.0.0"))
        #expect(launcher.contains("detached: true") && launcher.contains("process.kill(-pid, 'SIGTERM')"))
    }

    @Test func theDashboardIsTheLoopbackPortSbxPublishes() throws {
        let ports = [SbxPort(hostIP: "127.0.0.1", hostPort: 18001, sandboxPort: 3000),
                     SbxPort(hostIP: "0.0.0.0", hostPort: 50001, sandboxPort: BrowserKit.dashboardPort),
                     SbxPort(hostIP: "127.0.0.1", hostPort: 50002, sandboxPort: BrowserKit.dashboardPort)]
        #expect(BrowserKit.dashboardURL(ports: ports)?.absoluteString == "http://127.0.0.1:50002/")
        #expect(BrowserKit.dashboardURL(ports: Array(ports.prefix(2))) == nil)
        // sbx 0.51 publishes a kit's port@1 on both loopbacks, as "tcp" (PAD-73.2 capture)
        let v3 = try Fixture.decode([SbxPort].self, "sbx", "ports-v3-dashboard.json")
        #expect(v3.map(\.hostIP) == ["127.0.0.1", "::1"])
        #expect(BrowserKit.dashboardURL(ports: v3)?.absoluteString == "http://127.0.0.1:49154/")
        let app = AppConfig()
        #expect(BrowserKit.isChosen(by: Project(name: "p1", folder: "/a", kits: ["browser", "playwright"]), app: app))
        #expect(!BrowserKit.isChosen(by: Project(name: "p1", folder: "/a", kits: ["playwright"]), app: app))
    }

    /// `sandboxKits` records Paddock's kits with a hash of their spec; any version counts.
    @Test func theBrowserKitIsFoundInTheSandboxInAnyVersion() {
        let dir = BrowserKit.directory(in: paths)
        func project(_ kits: [String]?) -> Project { Project(name: "p1", folder: "/a", sandboxKits: kits) }
        #expect(BrowserKit.isInSandbox(of: project([dir + "#0123456789ab"]), paths: paths) == true)
        #expect(BrowserKit.isInSandbox(of: project([dir]), paths: paths) == true)
        #expect(BrowserKit.isInSandbox(of: project([dir + "-other"]), paths: paths) == false)
        #expect(BrowserKit.isInSandbox(of: project(nil), paths: paths) == nil)
    }

    /// A report server (`npx playwright show-report`, default port 9323) once held the dashboard's port.
    @Test func theDashboardPortIsNotPlaywrightsReportPortAndIsRecognized() throws {
        #expect(BrowserKit.dashboardPort != 9323)
        #expect(BrowserKit.spec.contains("container: \(BrowserKit.dashboardPort)"))
        #expect(BrowserKit.isDashboard(finalURL: URL(string: "http://127.0.0.1:49154/index.html?ws=976bb9bc")))
        #expect(!BrowserKit.isDashboard(finalURL: URL(string: "http://127.0.0.1:49154/")))  // a report's index
        #expect(!BrowserKit.isDashboard(finalURL: URL(string: "http://127.0.0.1:49154/index.html")))
        #expect(!BrowserKit.isDashboard(finalURL: nil))
        // nothing answering is not another server
        #expect(BrowserKit.dashboardAnswer(answered: false, finalURL: nil) == .none)
        #expect(BrowserKit.dashboardAnswer(answered: true, finalURL: URL(string: "http://127.0.0.1:1/")) == .otherServer)
        #expect(BrowserKit.dashboardAnswer(answered: true, finalURL: URL(string: "http://127.0.0.1:1/index.html?ws=a")) == .dashboard)
    }

    /// Writes every built-in kit to PADDOCK_DUMP_KITS when it is set, for a schema check outside
    /// the tests (`kit.schema.json`; PAD-73.2).
    @Test func dumpTheKitsWhenAsked() throws {
        guard let root = ProcessInfo.processInfo.environment["PADDOCK_DUMP_KITS"] else { return }
        let paths = PaddockPaths(configDirectory: root)
        for kit in BuiltinKit.allCases { try BuiltinKits.install(kit, in: paths) }
    }

    @Test func installWritesTheBuiltinKits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-kit-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let paths = PaddockPaths(configDirectory: root)
        for kit in BuiltinKit.allCases {
            let dir = try BuiltinKits.install(kit, in: paths)
            #expect(dir == BuiltinKits.directory(kit, in: paths))
            #expect(FileManager.default.fileExists(atPath: KitFile.file(in: dir)))
        }
    }
}
