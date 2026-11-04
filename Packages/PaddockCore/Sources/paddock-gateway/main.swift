import Foundation
import PaddockCore

// Developer tool for M2.5: runs the ModelGateway against the real llmman and creates (or
// reuses) one sandbox wired to it, the way the app's Reconciler will. Everything it does goes through
// PaddockCore, so a trial exercises the same rules (FolderPolicy, PolicyPlanner, gateway).

let usage = """
    usage: paddock-gateway trial --model MODEL [--agent claude|opencode] [--name paddock-NAME] [--allow HOST]... FOLDER

    Creates a sandbox for FOLDER whose only model access is this gateway (or reuses it if it
    exists), then serves until Ctrl-C. Attach from another terminal with: sbx run --name NAME

      --model   a model name as llmman lists it (GET /api/tags), every request is pinned to it
      --agent   claude (default) or opencode
      --name    sandbox name, must start with paddock- (default: paddock-trial)
      --allow   extra host the sandbox may reach, repeatable; everything else is denied
    """

struct Options {
    var agent = AppConfig.Agent.claudeCode
    var model: String?
    var name = "paddock-trial"
    var allow: [String] = []
    var folder: String?
}

struct TrialError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("paddock-gateway: \(message)\n".utf8))
    exit(1)
}

func parse(_ arguments: [String]) -> Options {
    if arguments.isEmpty || arguments.contains("-h") || arguments.contains("--help") {
        print(usage)
        exit(0)
    }
    guard arguments.first == "trial" else { fail("unknown command\n\n" + usage) }
    var options = Options()
    var rest = arguments.dropFirst()
    func value(_ flag: String) -> String {
        guard let next = rest.popFirst() else { fail("\(flag) needs a value") }
        return next
    }
    while let argument = rest.popFirst() {
        switch argument {
        case "--model": options.model = value(argument)
        case "--name": options.name = value(argument)
        case "--allow": options.allow.append(value(argument))
        case "--agent":
            switch value(argument) {
            case "claude": options.agent = .claudeCode
            case "opencode": options.agent = .openCode
            case let other: fail("unknown agent \(other); use claude or opencode")
            }
        default:
            guard !argument.hasPrefix("-"), options.folder == nil else { fail("unexpected \(argument)\n\n" + usage) }
            options.folder = argument
        }
    }
    return options
}

/// Runs llmman's hardening checks and refuses to continue on any red one, as the app will
/// (CLAUDE.md: local models only while every check is green). A model llmman does not list is
/// only a warning: whether llmman pulls it on request is an open risk a trial answers (risk 6).
func checkLlmman(model: String, home: String) async {
    let transport = HTTPLlmmanTransport()
    let api = LlmmanAPI(transport: transport)
    let health = await LlmmanHealthChecker(api: api, runner: FoundationProcessRunner(), home: home).check()
    let tags = try? await api.tags()
    try? await transport.shutdown()

    for check in health.checks {
        let mark = switch check.status {
        case .green: "ok  "
        case .yellow: "warn"
        case .red: "FAIL"
        }
        print("llmman \(mark) \(check.kind.rawValue): \(check.detail)")
    }
    guard health.allowsLocalModels else { fail("llmman hardening checks failed; not starting the gateway") }
    if let tags, !tags.models.contains(where: { $0.name == model }) {
        print("warning: llmman does not list \(model). Models: \(tags.models.map(\.name).joined(separator: ", "))")
    }
}

func describe(_ entry: GatewayLogEntry) -> String {
    let time = entry.date.formatted(date: .omitted, time: .standard)
    let seconds = Double(entry.duration.components.seconds) + Double(entry.duration.components.attoseconds) / 1e18
    var line = "\(time)  \(entry.route)  \(entry.status)  \(String(format: "%.1fs", seconds))"
    if entry.inputTokens != nil || entry.outputTokens != nil {
        line += "  tokens in \(entry.inputTokens.map(String.init) ?? "?") out \(entry.outputTokens.map(String.init) ?? "?")"
    }
    return line
}

/// Ctrl-C and SIGTERM always stop the gateway, even when a parent (such as a task runner)
/// started it with SIGINT ignored. Nothing needs saving.
/// A plain function, not top-level code: a closure written at top level would be main-actor
/// isolated, and Swift 6 traps when Dispatch runs it on another queue.
func installSignalHandlers() -> [any DispatchSourceSignal] {
    [SIGINT, SIGTERM].map { number in
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler { @Sendable in
            FileHandle.standardError.write(Data("\ngateway stopped\n".utf8))
            exit(0)
        }
        source.resume()
        return source
    }
}

let signalSources = installSignalHandlers()

let options = parse(Array(CommandLine.arguments.dropFirst()))
guard let model = options.model else { fail("--model is required\n\n" + usage) }
guard let folderArgument = options.folder else { fail("FOLDER is required\n\n" + usage) }
guard ProjectList.isValidSandboxName(options.name) else { fail("\(options.name) is not a valid sbx sandbox name") }

let environment = ProcessInfo.processInfo.environment
let home = FileManager.default.homeDirectoryForCurrentUser.path
let paths = PaddockPaths(environment: environment, home: home)
let folder = URL(fileURLWithPath: folderArgument).standardizedFileURL.resolvingSymlinksInPath().path

do {
    var app = AppConfig()
    app = try AppConfig.load(atPath: paths.appConfig).config
    try FolderPolicy(home: home, paddockConfigDirectory: paths.configDirectory).check(folder)

    guard let sbxURL = BinaryLocator(loginPath: environment["PATH"]).locate("sbx") else {
        fail("sbx not found. Install it, for example: brew install docker/tap/sbx")
    }
    let sbx = SbxService(runner: FoundationProcessRunner(), sbx: sbxURL)
    _ = try await sbx.checkedVersion()
    await checkLlmman(model: model, home: home)

    let range = app.models.gatewayPorts
    let exists = try await sbx.sandboxes().contains { $0.name == options.name }

    // An existing sandbox keeps the gateway port it was created with; read it back from its rule.
    // The trial always creates sandboxes on the range's first port, so that is the fallback.
    func gatewayRulePort() async throws -> Int? {
        PolicyPlanner.gatewayPort(ofSandbox: options.name, rules: try await sbx.policies(sandbox: options.name).rules, in: range)
    }
    let existingPort = exists ? try await gatewayRulePort() : nil
    let port = existingPort ?? range.lowerBound

    // From here on the gateway owns an HTTP client, which must be shut down on every exit path.
    let gateway = ModelGateway(configuration: .init(models: app.models)) { print(describe($0)) }
    var bound: BoundGateway?
    do {
        let listener = try await gateway.bind(port: port, binding: GatewayBinding(projectID: UUID(), projectName: options.name, model: model))
        bound = listener
        if exists {
            print("reusing \(options.name); --agent and --allow apply only when a sandbox is created")
            if existingPort == nil {
                // seen once on sbx 0.49.2: a rule added after create was gone later (cause not known yet)
                print("warning: \(options.name) had no gateway rule; adding it again for port \(port)")
                try await sbx.perform(["policy", "allow", "network", "--sandbox", options.name, "localhost:\(port)",
                                       "--method", "GET,POST", "--path", "/v1/**"])
            }
        } else {
            let plan = try PolicyPlanner(gatewayPort: port, gatewayPorts: range)
                .plan(globalRules: try await sbx.policies().rules, allowed: options.allow, usesGateway: true)
            // Neither agent needs a kit for the gateway, only environment (PAD-73.2).
            let kits: [String] = []
            let planner = AgentLaunchPlanner(paths: paths)
            let launch = planner.create(name: options.name, agent: options.agent, folder: folder, policy: plan,
                                        gateway: GatewayAccess(model: model, port: port), kits: kits)
            print("creating \(options.name) (\(plan.denies.count) per-sandbox denies, \(plan.allows.count) allows)...")
            try await sbx.create(launch)
            for command in planner.policyCommands(name: options.name, plan: plan) {
                try await sbx.perform(command)
            }
        }
        guard try await gatewayRulePort() == port else {
            throw TrialError("sbx does not list the gateway rule for \(options.name); check: sbx policy ls \(options.name)")
        }
        if options.agent == .openCode {
            try await sbx.perform(AgentLaunchPlanner(paths: paths)
                .writeOpenCodeConfig(name: options.name, gateway: GatewayAccess(model: model, port: port)))
        }

        print("""

            gateway on 127.0.0.1:\(port), model \(model)
            attach:  sbx run --name \(options.name)
            shell:   sbx exec -it \(options.name) bash
            remove:  sbx rm --force \(options.name)   (it reaches models only while this gateway runs)
            Ctrl-C stops the gateway; run this again to reuse the sandbox. One line per request follows (no bodies).

            """)
        try await listener.serve()
    } catch {
        await bound?.stop()
        try? await gateway.shutdown()
        throw error
    }
} catch {
    fail(String(describing: error))
}
