import Foundation

/// One line of `sbx events --json`. On connect sbx replays the current state,
/// then sends `{"type":"sync","action":"complete"}`.
public struct SbxEvent: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let type: String
    public let action: String
    public let timestamp: Date
    public let sandboxName: String?
    public let sandboxId: String?
    public let createdAt: Date?
    /// Type-specific payload (`sandbox.ports`, `policy.network`), kept untyped until each is needed.
    public let data: JSONValue?

    public enum Kind: Sendable, Equatable {
        case sandboxLifecycle
        case sandboxPorts
        case policyNetwork
        case sync
        case other(String)
    }

    public var kind: Kind {
        switch type {
        case "sandbox.lifecycle": .sandboxLifecycle
        case "sandbox.ports": .sandboxPorts
        case "policy.network": .policyNetwork
        case "sync": .sync
        default: .other(type)
        }
    }

    public var isSyncComplete: Bool { kind == .sync && action == "complete" }
}

public enum SbxEventDecoder {
    /// Decodes one NDJSON line. Blank lines and the human-readable banner sbx prints on stderr
    /// never reach this; any other non-JSON line is an error for the caller to log.
    public static func decode(line: String) throws -> SbxEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try JSONCoding.decode(SbxEvent.self, from: Data(trimmed.utf8))
    }
}
