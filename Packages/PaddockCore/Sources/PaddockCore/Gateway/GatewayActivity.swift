import Foundation

/// What a project's model use adds up to, from the gateway's metadata log
/// (backlog doc ModelGateway, Logging; UI). Counts only; the log holds no bodies or headers.
public struct GatewayActivity: Sendable, Equatable {
    public var requests = 0
    public var errors = 0
    public var inputTokens = 0
    public var outputTokens = 0

    public init() {}

    /// The summary for one project, or for every project when `project` is nil.
    public static func summarize(_ entries: [GatewayLogEntry], project: String? = nil) -> GatewayActivity {
        var activity = GatewayActivity()
        for entry in entries where project == nil || entry.project == project {
            activity.requests += 1
            if entry.status >= 400 { activity.errors += 1 }
            activity.inputTokens += entry.inputTokens ?? 0
            activity.outputTokens += entry.outputTokens ?? 0
        }
        return activity
    }
}

extension [GatewayLogEntry] {
    /// Newest first, for the log drawer; one project's entries when `project` is set.
    public func newestFirst(project: String? = nil) -> [GatewayLogEntry] {
        filter { project == nil || $0.project == project }.sorted { $0.date > $1.date }
    }
}
