import Foundation

/// The one mark a project shows in the sidebar, its card, its toolbar, and Info (backlog doc UI,
/// Status marks): its sandbox's state, or an approval request waiting for the operator. The agents'
/// states are on their own rows under the project (`SidebarAgents`, PAD-63), not in this mark.
/// Each case has its own static shape, color only adds to it, so it reads at a glance without watching it (PAD-33).
/// Display only: it decides nothing.
public enum ProjectBadge: Sendable, Equatable {
    /// An approval request waits for the operator.
    case needsYou
    case running
    /// A state sbx reported that is neither running nor stopped (starting, stopping), in sbx's words.
    case changing(String)
    /// A state sbx reported that says something went wrong, in sbx's words.
    case problem(String)
    case stopped
    /// No sandbox yet.
    case none

    /// - Parameter requests: approval requests waiting for the operator.
    public init(state: SandboxStates.State?, requests: Int = 0) {
        if requests > 0 {
            self = .needsYou
            return
        }
        switch state {
        case .running?: self = .running
        case .stopped?: self = .stopped
        case .other(let text)?: self = Self.soundsWrong(text) ? .problem(text) : .changing(text)
        case nil: self = .none
        }
    }

    /// sbx names no failed state in the captures so far; a status with one of these words in it is
    /// shown as a problem, anything else as a change under way.
    static func soundsWrong(_ status: String) -> Bool {
        let lowered = status.lowercased()
        return ["error", "fail", "dead", "unhealthy", "crash"].contains { lowered.contains($0) }
    }

    /// The tooltip and accessibility label: the sandbox's state, then the approval requests.
    public static func help(state: SandboxStates.State?, requests: Int = 0) -> String {
        var parts = [describe(state)]
        if requests > 0 {
            parts.append("\(requests) approval request\(requests == 1 ? "" : "s") waiting for you")
        }
        return parts.joined(separator: ", ")
    }

    /// The sandbox's state in words.
    public static func describe(_ state: SandboxStates.State?) -> String {
        switch state {
        case .running?: "running"
        case .stopped?: "stopped"
        case .other(let text)?: text
        case nil: "no sandbox yet"
        }
    }
}
