import Foundation

/// sbx's approval requests (`sbx policy approval ls --json`) a project's Info offers next to its
/// suggestions: what its agent tried that no rule decided, each with the answers sbx offers.
public enum ApprovalRequests {
    /// The project's sandbox's requests, newest first, without the ones for Paddock's own services
    /// (llmman, the gateway ports): those stay denied whatever is asked. Nor the ones the operator
    /// dismissed before (`ignored`, by `ignoreID`): sbx asks again when the agent tries again.
    public static func pending(_ approvals: [SbxApproval], sandbox: String, ignored: [String] = [], app: AppConfig) -> [SbxApproval] {
        approvals
            .filter { $0.sandboxName == sandbox && !isPaddockService($0.host, app: app) && !ignored.contains(ignoreID($0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// What `Project.ignoredSuggestions` keeps for a dismissed request: its title, so the same
    /// request asked again stays dismissed.
    public static func ignoreID(_ approval: SbxApproval) -> String {
        "approval:\(approval.title)"
    }

    static func isPaddockService(_ host: String, app: AppConfig) -> Bool {
        let pattern = HostPattern(parsing: host)
        guard PolicyPlanner.hostLoopbackNames.contains(pattern.host), let port = pattern.port else { return false }
        return Ports.isReserved(port, app: app)
    }
}
