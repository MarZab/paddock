import Foundation

// Shapes verified against sbx's bundled llmman 0.1.571 (M0 rounds 2 and 3).
// Fixtures: Tests/PaddockCoreTests/Fixtures/llmman.

/// `GET /api/version`
public struct LlmmanVersion: Sendable, Equatable, Codable {
    public let exe: String
    public let pid: Int
    /// e.g. `0.1.571 (d76ad9e)`
    public let version: String

    public var semanticVersion: SemanticVersion? { SemanticVersion(parsing: version) }
}

/// `GET /api/tags`: models in llmman's store.
public struct LlmmanTags: Sendable, Equatable, Codable {
    public let models: [LlmmanStoredModel]
}

public struct LlmmanStoredModel: Sendable, Equatable, Codable, Identifiable {
    public struct Details: Sendable, Equatable, Codable {
        public let parentModel: String
        public let format: String
        public let family: String
        public let families: [String]
        public let parameterSize: String
        public let quantizationLevel: String
    }

    /// e.g. `hf.co/unsloth/Qwen3.5-0.8B-GGUF:latest`; this is the name the gateway pins to.
    public let name: String
    public let model: String
    public let size: Int64
    public let digest: String
    public let modifiedAt: Date
    public let details: Details

    public var id: String { name }
}

/// `GET /api/ps`: loaded models. Only the empty list has been captured so far,
/// so entries stay untyped until a fixture with a loaded model exists.
public struct LlmmanLoaded: Sendable, Equatable, Codable {
    public let models: [JSONValue]
}

/// `GET /llmman/node`: memory and model totals.
public struct LlmmanNode: Sendable, Equatable, Codable {
    public let memory: Int64
    public let loaded: [String: JSONValue]
    public let stored: [String: Int64]
}

/// `GET /llmman/shell` without a WebSocket upgrade: the web shell's status only.
public struct LlmmanShellStatus: Sendable, Equatable, Codable {
    public let enabled: Bool
    public let reason: String?
}
