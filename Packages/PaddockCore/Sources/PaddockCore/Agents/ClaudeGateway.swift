import Foundation

/// What points Claude Code at Paddock's model gateway (backlog doc ModelGateway, Wiring an agent to
/// the gateway): environment variables only, passed at create. sbx 0.51's own claude kit already
/// marks onboarding complete, and a token in `ANTHROPIC_AUTH_TOKEN` is sent as `Authorization`
/// without the approval Claude Code asks for an `ANTHROPIC_API_KEY`, so Paddock's gateway kit is
/// gone (checked with `mise run m0 kits`, 2026-11-04; PAD-73.2). It holds no model and no secret:
/// the model comes per sandbox, and the token is a fixed dummy the gateway drops, since it
/// identifies a project by its port.
public enum ClaudeGateway {
    /// The token every gateway sandbox presents. Not a secret: the gateway ignores it and never
    /// forwards it (`GatewayPolicy.forwardedHeaders`).
    public static let token = "paddock"

    /// Set on every Claude Code sandbox that uses the gateway, besides its address and model.
    public static let environment: [(name: String, value: String)] = [
        ("ANTHROPIC_AUTH_TOKEN", token),
        // Without this sbx also writes an apiKeyHelper, and Claude warns about two auth methods.
        ("SBX_CRED_ANTHROPIC_MODE", "none"),
        // No telemetry, error reports, or update checks: the sandbox only reaches the gateway.
        ("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1"),
        // llmman cannot run auto mode's server-side classifier checks, so Claude Code should not
        // ask for them (code.claude.com/docs/en/auto-mode-classifier-billing).
        ("CLAUDE_CODE_AUTO_MODE_SERVER", "0"),
        // Anthropic beta features mean nothing to a local model.
        ("CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS", "1"),
    ]
}
