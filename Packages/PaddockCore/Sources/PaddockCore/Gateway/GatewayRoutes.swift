import Foundation

/// An incoming request, reduced to what the gateway decides on.
public struct GatewayRequest: Sendable {
    public let method: String
    /// The request target as received, possibly with a query string.
    public let target: String
    /// Header names in any case.
    public let headers: [(name: String, value: String)]
    public let body: Data

    public init(method: String, target: String, headers: [(name: String, value: String)], body: Data) {
        self.method = method
        self.target = target
        self.headers = headers
        self.body = body
    }

    func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// What one gateway listener serves: one project, one model. Each project has its own port,
/// and sbx's per-sandbox HTTP rule lets a sandbox reach only its project's port, so the port
/// identifies the project (backlog doc ModelGateway). There are no gateway tokens.
public struct GatewayBinding: Sendable, Equatable {
    public let projectID: UUID
    public let projectName: String
    /// The name as llmman's `/api/tags` reports it; every request is pinned to it.
    public let model: String

    public init(projectID: UUID, projectName: String, model: String) {
        self.projectID = projectID
        self.projectName = projectName
        self.model = model
    }
}

/// What to do with a request.
public enum GatewayDecision: Sendable, Equatable {
    /// Send to llmman: same method and path, these headers, this body.
    case forward(path: String, headers: [GatewayHeader], body: Data)
    /// Answer locally.
    case respond(status: Int, body: Data)
}

public struct GatewayHeader: Sendable, Equatable {
    public let name: String
    public let value: String
}

/// The gateway's rules (backlog doc ModelGateway). Pure, so every rule is unit-tested.
public struct GatewayPolicy: Sendable {
    /// The only routes that reach llmman. Exact paths: no prefixes, no `..`, no other APIs.
    public static let forwardedRoutes: Set<String> = [
        "POST /v1/messages",
        "POST /v1/messages/count_tokens",
        "POST /v1/chat/completions",
        "POST /v1/responses",
    ]
    /// Answered by the gateway itself with the project's one model.
    public static let modelsRoute = "GET /v1/models"

    /// Request headers passed on to llmman. Everything else (the agent's dummy API key,
    /// cookies, hop-by-hop, forwarding headers) is dropped.
    public static let forwardedHeaders: Set<String> = [
        "content-type", "accept", "anthropic-version", "anthropic-beta", "openai-beta",
    ]

    public let maxBodyBytes: Int

    public init(maxBodyBytes: Int) {
        self.maxBodyBytes = maxBodyBytes
    }

    /// Host names a sandbox or this Mac's own tools use to reach a listener. Anything else is a
    /// web page that was pointed at loopback (DNS rebinding) and is refused (PAD-82).
    public static let allowedHostNames: Set<String> = ["127.0.0.1", "localhost", "[::1]", "::1", "host.docker.internal"]

    /// The host name of a `Host` header value, without its port, lowercased.
    static func hostName(of value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") {
            return String(trimmed[...close])
        }
        return String(trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    public func decide(_ request: GatewayRequest, binding: GatewayBinding) -> GatewayDecision {
        // Browsers always send Host and, across origins, Origin; agents and sbx's proxy send no Origin.
        if let host = request.header("host"), !Self.allowedHostNames.contains(Self.hostName(of: host)) {
            return Self.error(403, "forbidden", "the Paddock gateway does not answer to this host name")
        }
        if request.header("origin") != nil {
            return Self.error(403, "forbidden", "the Paddock gateway does not answer web pages")
        }
        let path = String(request.target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let route = request.method.uppercased() + " " + path
        if route == Self.modelsRoute {
            return .respond(status: 200, body: Self.modelList(binding.model))
        }
        guard Self.forwardedRoutes.contains(route) else {
            return Self.error(403, "forbidden", "\(request.method) \(path) is not available through the Paddock gateway")
        }
        guard request.body.count <= maxBodyBytes else {
            return Self.error(413, "request_too_large", "request body is larger than \(maxBodyBytes) bytes")
        }
        guard let pinned = Self.pinModel(request.body, to: binding.model) else {
            return Self.error(400, "invalid_request_error", "request body must be a JSON object")
        }

        var headers = request.headers
            .filter { Self.forwardedHeaders.contains($0.name.lowercased()) }
            .map { GatewayHeader(name: $0.name.lowercased(), value: $0.value) }
        if !headers.contains(where: { $0.name == "content-type" }) {
            headers.append(GatewayHeader(name: "content-type", value: "application/json"))
        }
        return .forward(path: path, headers: headers, body: pinned)
    }

    /// Replaces `model` with the project's model, so an agent can neither pick another
    /// model nor make llmman pull one by name.
    static func pinModel(_ body: Data, to model: String) -> Data? {
        guard var object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        object["model"] = model
        return try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    static func modelList(_ model: String) -> Data {
        let list: [String: Any] = [
            "object": "list",
            "data": [["id": model, "object": "model", "owned_by": "paddock"]],
        ]
        return (try? JSONSerialization.data(withJSONObject: list, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    static func error(_ status: Int, _ type: String, _ message: String) -> GatewayDecision {
        let body: [String: Any] = ["type": "error", "error": ["type": type, "message": message]]
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        return .respond(status: status, body: data)
    }
}

/// Caps concurrent upstream requests per project; extra requests get `429`.
public actor GatewayConcurrencyLimiter {
    private let limit: Int
    private var active: [UUID: Int] = [:]

    public init(limitPerProject: Int) {
        self.limit = limitPerProject
    }

    /// Returns false when the project is at its limit.
    public func acquire(_ projectID: UUID) -> Bool {
        let current = active[projectID, default: 0]
        guard current < limit else { return false }
        active[projectID] = current + 1
        return true
    }

    public func release(_ projectID: UUID) {
        let current = active[projectID, default: 0]
        active[projectID] = current > 1 ? current - 1 : nil
    }
}

/// One line of the gateway's metadata log. Never bodies or headers.
public struct GatewayLogEntry: Sendable, Equatable {
    public let date: Date
    public let project: String
    public let route: String
    public let status: Int
    public let requestBytes: Int
    public let responseBytes: Int
    public let duration: Duration
    public let inputTokens: Int?
    public let outputTokens: Int?
}
