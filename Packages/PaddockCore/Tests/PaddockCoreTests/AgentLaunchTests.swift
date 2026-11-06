import Foundation
import Testing
@testable import PaddockCore

/// Agent wiring: backlog doc ModelGateway, Wiring an agent to the gateway. No secrets are involved: the gateway
/// identifies a project by its port, and agents present a fixed dummy key.
@Suite("AgentLaunch")
struct AgentLaunchTests {
    let paths = PaddockPaths(configDirectory: "/Users/op/.config/paddock")
    var planner: AgentLaunchPlanner { AgentLaunchPlanner(paths: paths) }
    let model = "hf.co/unsloth/Qwen3.5-0.8B-GGUF:latest"
    var gateway: GatewayAccess { GatewayAccess(model: model, port: 17482) }
    let plan = SandboxPolicyPlan(
        denies: ["localhost:5432", "localhost:17434"],
        allows: ["registry.npmjs.org"],
        httpAllows: [.init(resource: "localhost:17482", methods: ["GET", "POST"], path: "/v1/**")]
    )

    @Test func claudeGetsTheGatewayAsEnvironmentAndPinsEveryModelVariable() {
        let a = planner.create(name: "paddock-app", agent: .claudeCode, folder: "/Users/op/src/app", policy: plan, gateway: gateway,
                               kits: []).arguments
        #expect(Array(a.prefix(4)) == ["create", "--name", "paddock-app", "--no-progress"])
        #expect(Array(a.suffix(2)) == ["claude", "/Users/op/src/app"])
        #expect(!a.contains("--kit"))
        // no gateway kit (PAD-73.2): the dummy token and the quiet settings are environment
        #expect(a.contains("ANTHROPIC_AUTH_TOKEN=paddock") && a.contains("SBX_CRED_ANTHROPIC_MODE=none"))
        #expect(a.contains("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1") && a.contains("CLAUDE_CODE_AUTO_MODE_SERVER=0"))
        #expect(a.contains("CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1"))
        #expect(a.contains("ANTHROPIC_BASE_URL=http://host.docker.internal:17482"))
        for variable in AgentLaunchPlanner.claudeModelVariables {
            #expect(a.contains("\(variable)=\(model)"))
        }
        #expect(a.contains("--deny-network") && a.contains("localhost:17434"))
        // a token, not an API key: Claude Code asks to approve a custom API key
        #expect(!a.contains { $0.hasPrefix("ANTHROPIC_API_KEY") })
        #expect(ClaudeGateway.token == "paddock" && !GatewayPolicy.forwardedHeaders.contains("authorization"))
    }

    @Test func openCodeGetsItsProviderConfig() throws {
        let a = planner.create(name: "paddock-app", agent: .openCode, folder: "/src/app", policy: plan, gateway: gateway,
                               kits: [AgentStatusKit.directory(in: paths)]).arguments
        // the kits it was given, and no other (no gateway kit for OpenCode)
        #expect(a.filter { $0 == "--kit" }.count == 1)
        #expect(a.contains("/Users/op/.config/paddock/kits/paddock-status"))
        // no upgrades of OpenCode's own inside the sandbox (sbx's opencode kit leaves it unset)
        #expect(a.contains("OPENCODE_DISABLE_AUTOUPDATE=1"))
        let entry = try #require(a.first { $0.hasPrefix("OPENCODE_CONFIG_CONTENT=") })
        let config = String(entry.dropFirst("OPENCODE_CONFIG_CONTENT=".count))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any])
        #expect(object["model"] as? String == "paddock/\(model)")
        // only the gateway's provider shows up in OpenCode's model list
        #expect(object["enabled_providers"] as? [String] == ["paddock"])
        let provider = try #require((object["provider"] as? [String: Any])?["paddock"] as? [String: Any])
        let options = try #require(provider["options"] as? [String: String])
        #expect(options["baseURL"] == "http://host.docker.internal:17482/v1")
        #expect(options["apiKey"] == ClaudeGateway.token)
        #expect((provider["models"] as? [String: Any])?[model] != nil)
        #expect(a.contains("SBX_CRED_OPENAI_MODE=none"))
    }

    @Test func theOpenCodeConfigFileIsWrittenAndAStaleServerStopped() throws {
        let command = planner.writeOpenCodeConfig(name: "paddock-app", gateway: gateway)
        #expect(Array(command.prefix(4)) == ["exec", "paddock-app", "sh", "-c"])
        let encoded = try #require(command.last)
        let config = try #require(Data(base64Encoded: encoded))
        #expect(String(decoding: config, as: UTF8.self) == planner.openCodeConfig(gateway))

        // The script itself, under sh, in a home of its own; `opencode` records what it was asked.
        let home = NSTemporaryDirectory() + "paddock-opencode-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: home) }
        let bin = home + "/bin"
        try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho \"$@\" >> \"$HOME/opencode-calls\"\n".utf8).write(to: URL(fileURLWithPath: bin + "/opencode"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin + "/opencode")
        func run() throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = Array(command.dropFirst(3))
            process.environment = ["HOME": home, "PATH": bin + ":/usr/bin:/bin"]
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        let file = home + "/.config/opencode/opencode.json"
        let calls = home + "/opencode-calls"
        try run()
        #expect(FileManager.default.contents(atPath: file) == config)
        #expect(String(decoding: FileManager.default.contents(atPath: calls) ?? Data(), as: UTF8.self) == "service stop\n")
        // unchanged: the server keeps running
        try run()
        #expect(String(decoding: FileManager.default.contents(atPath: calls) ?? Data(), as: UTF8.self) == "service stop\n")
        #expect(!FileManager.default.fileExists(atPath: file + ".paddock"))
    }

    @Test func agentDefaultHasNoGatewayWiring() {
        let a = planner.create(name: "paddock-app", agent: .claudeCode, folder: "/src/app",
                               policy: plan, gateway: nil, template: "docker.io/paddock/app:1", clone: true).arguments
        #expect(!a.contains("-e") && !a.contains("--kit"))
        #expect(a.contains("--clone"))
        #expect(a.contains("docker.io/paddock/app:1"))
    }

    @Test func kitsGoInTheirOrderBeforeTheAgent() {
        let kits = ["docker.io/sbx/playwright@sha256:abc", BrowserKit.directory(in: paths), AgentStatusKit.directory(in: paths)]
        let a = planner.create(name: "paddock-app", agent: .openCode, folder: "/src/app", policy: plan, gateway: nil, kits: kits).arguments
        let given = a.indices.filter { a[$0] == "--kit" }.map { a[$0 + 1] }
        #expect(given == kits)
        // without the gateway, only the one setting every OpenCode sandbox gets
        #expect(a.indices.filter { a[$0] == "-e" }.map { a[$0 + 1] } == ["OPENCODE_DISABLE_AUTOUPDATE=1"])
        #expect(Array(a.suffix(2)) == ["opencode", "/src/app"])
    }

    @Test func policyCommandsFollowThePlan() {
        #expect(planner.policyCommands(name: "paddock-app", plan: plan) == [
            ["policy", "allow", "network", "--sandbox", "paddock-app", "registry.npmjs.org"],
            ["policy", "allow", "network", "--sandbox", "paddock-app", "localhost:17482", "--method", "GET,POST", "--path", "/v1/**"],
        ])
    }

    @Test func createRunsSbx() async throws {
        let runner = FakeRunner()
        let launch = planner.create(name: "paddock-app", agent: .claudeCode, folder: "/src/app", policy: plan, gateway: gateway)
        runner.respond(to: launch.arguments, with: Data())
        let sbx = SbxService(runner: runner, sbx: URL(fileURLWithPath: "/opt/homebrew/bin/sbx"))
        try await sbx.create(launch)
        #expect(runner.calls == [launch.arguments])
    }

    @Test func failedCommandsThrow() async {
        let runner = FakeRunner()
        let sbx = SbxService(runner: runner, sbx: URL(fileURLWithPath: "/opt/homebrew/bin/sbx"))
        await #expect(throws: SbxError.self) { try await sbx.perform(["policy", "allow", "network", "x"]) }
    }
}
