import Foundation

/// One `sbx create` call. It carries no secrets: gateway sandboxes use a fixed dummy key.
public struct SandboxLaunch: Sendable, Equatable {
    public var arguments: [String]
}

/// The model a gateway project uses and the gateway port its sandbox reaches.
public struct GatewayAccess: Sendable, Equatable {
    public let model: String
    public let port: Int

    public init(model: String, port: Int) {
        self.model = model
        self.port = port
    }
}

/// Builds the sbx commands that create a project's sandbox (backlog docs SbxService and ModelGateway, Wiring).
public struct AgentLaunchPlanner: Sendable {
    public let paths: PaddockPaths

    public init(paths: PaddockPaths) {
        self.paths = paths
    }

    /// How a sandbox reaches its gateway port on the host's loopback.
    public static func gatewayBaseURL(port: Int) -> String { "http://host.docker.internal:\(port)" }

    /// The Claude Code variables that name a model; all of them get the pinned model.
    static let claudeModelVariables = [
        "ANTHROPIC_MODEL", "ANTHROPIC_SMALL_FAST_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL", "CLAUDE_CODE_SUBAGENT_MODEL",
    ]

    /// - Parameter gateway: nil for the agent's default provider (no gateway, no extra variables).
    /// - Parameter kits: the `--kit` values in order (`KitSelection.resolve`), the gateway kit included.
    public func create(
        name: String,
        agent: AppConfig.Agent,
        folder: String,
        policy: SandboxPolicyPlan,
        gateway: GatewayAccess?,
        kits: [String] = [],
        publish: [Project.PortMapping] = [],
        template: String? = nil,
        clone: Bool = false,
        extraFolders: [String] = []
    ) -> SandboxLaunch {
        var arguments = ["create", "--name", name, "--no-progress"]
        if clone { arguments.append("--clone") }
        // `-p` applies only at create; later changes use `sbx ports N --publish/--unpublish`.
        for mapping in publish {
            arguments += ["-p", Ports.spec(mapping)]
        }
        // A project image is local (`sbx template load`); sbx would otherwise pull it from Docker Hub.
        if let template { arguments += ["--template", template, "--pull", "never"] }
        arguments += policy.createArguments
        for kit in kits {
            arguments += ["--kit", kit]
        }

        for (name, value) in environment(agent: agent, gateway: gateway) {
            arguments += ["-e", "\(name)=\(value)"]
        }

        // The project folder first (sbx and Paddock read it as the project's), then the extra
        // folders as `PATH` or `PATH:ro` (`ExtraFolders.argument`).
        arguments += [agent.sbxAgent, folder] + extraFolders
        return SandboxLaunch(arguments: arguments)
    }

    /// What Paddock sets in a sandbox's environment for its agent: the gateway's address, token,
    /// and pinned model for a local model, and OpenCode's own settings. The same for `sbx create -e`
    /// and Paddock's overlay of an `sbxenv.yaml` (`PaddockOverlay.env`).
    public func environment(agent: AppConfig.Agent, gateway: GatewayAccess?) -> [(name: String, value: String)] {
        var variables: [(name: String, value: String)] = []
        if let gateway {
            switch agent {
            case .claudeCode:
                variables.append(("ANTHROPIC_BASE_URL", Self.gatewayBaseURL(port: gateway.port)))
                variables += ClaudeGateway.environment
                variables += Self.claudeModelVariables.map { ($0, gateway.model) }
            case .openCode:
                variables += [("OPENCODE_CONFIG_CONTENT", openCodeConfig(gateway)),
                              ("SBX_CRED_ANTHROPIC_MODE", "none"), ("SBX_CRED_OPENAI_MODE", "none")]
            }
        }
        // Paddock pins nothing of OpenCode's, but OpenCode should not offer upgrades of its own
        // inside a sandbox (sbx's opencode kit leaves it unset; PAD-73.2).
        if agent == .openCode { variables.append(("OPENCODE_DISABLE_AUTOUPDATE", "1")) }
        return variables
    }

    /// `sbx policy deny network --sandbox N` for each of `resources`, in batches: `sbx env create`
    /// takes no `--deny-network`, so Paddock's denies (and hosts the operator declined) follow it.
    public func denyCommands(name: String, resources: [String]) -> [[String]] {
        stride(from: 0, to: resources.count, by: 40).map { start in
            ["policy", "deny", "network", "--sandbox", name, resources[start..<min(start + 40, resources.count)].joined(separator: ",")]
        }
    }

    /// The per-sandbox allows that follow `sbx create` (allowed hosts, then the gateway's HTTP rule).
    public func policyCommands(name: String, plan: SandboxPolicyPlan) -> [[String]] {
        let base = ["policy", "allow", "network", "--sandbox", name]
        return plan.allows.map { base + [$0] }
            + plan.httpAllows.map { base + [$0.resource, "--method", $0.methods.joined(separator: ","), "--path", $0.path] }
    }

    /// `sbx exec` that writes OpenCode's config file in the sandbox, so every OpenCode process reads
    /// it, whatever started it (`OPENCODE_CONFIG_CONTENT` alone did not always reach OpenCode). When
    /// the file changes, OpenCode 2's background server stops: it keeps the config it started with,
    /// and the next session starts it again. The config goes as base64 (it holds no secret, only
    /// the dummy key), so no shell on the way can change it.
    public func writeOpenCodeConfig(name: String, gateway: GatewayAccess) -> [String] {
        let config = Data(openCodeConfig(gateway).utf8).base64EncodedString()
        return ["exec", name, "sh", "-c", Self.openCodeConfigScript, "paddock-opencode-config", config]
    }

    /// `$1` is the base64 config. Checked with OpenCode 2.1.4: it reads `opencode.json` there,
    /// not `config.json`.
    static let openCodeConfigScript = #"""
        set -e
        dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
        mkdir -p "$dir"
        printf '%s' "$1" | base64 -d > "$dir/opencode.json.paddock"
        if cmp -s "$dir/opencode.json.paddock" "$dir/opencode.json"; then
          rm -f "$dir/opencode.json.paddock"
        else
          mv "$dir/opencode.json.paddock" "$dir/opencode.json"
          opencode service stop >/dev/null 2>&1 || true
        fi
        """#

    /// OpenCode's provider config, shaped like sbx's own `--model` kit. `enabled_providers` hides
    /// OpenCode's built-in catalog (its own free models, and every provider it has a key for), so
    /// the model list shows only the gateway's model (checked with OpenCode 2.1.4).
    func openCodeConfig(_ gateway: GatewayAccess) -> String {
        let config: [String: Any] = [
            "$schema": "https://opencode.ai/config.json",
            "model": "paddock/\(gateway.model)",
            "enabled_providers": ["paddock"],
            "provider": [
                "paddock": [
                    "name": "paddock",
                    "npm": "@ai-sdk/openai-compatible",
                    "options": ["baseURL": Self.gatewayBaseURL(port: gateway.port) + "/v1", "apiKey": ClaudeGateway.token],
                    "models": [gateway.model: ["name": gateway.model]],
                ] as [String: Any],
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
