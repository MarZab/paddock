import Foundation

/// What an agent tab shows (backlog doc Kits, Agent status): the agent's activity, and a "finished"
/// mark for a tab whose agent stopped working or waiting while the operator was elsewhere, until they
/// look at it.
public enum AgentTabMark: Sendable, Equatable {
    case none
    case working
    case waiting
    case finished
}

public struct AgentTabMarks: Sendable, Equatable {
    private var last: [UUID: AgentActivity] = [:]
    private var unseen: Set<UUID> = []

    public init() {}

    /// The tab's mark now. `isShown`: the operator is looking at the tab.
    public mutating func update(tab: UUID, activity: AgentActivity, isShown: Bool) -> AgentTabMark {
        let before = last[tab] ?? .none
        last[tab] = activity
        switch activity {
        case .working, .waiting:
            unseen.remove(tab)
            return activity == .working ? .working : .waiting
        case .none:
            if before != .none, !isShown { unseen.insert(tab) }
            if isShown { unseen.remove(tab) }
            return unseen.contains(tab) ? .finished : .none
        }
    }

    /// The tab's mark as the last `update` left it.
    public func mark(of tab: UUID) -> AgentTabMark {
        switch last[tab] ?? .none {
        case .working: .working
        case .waiting: .waiting
        case .none: unseen.contains(tab) ? .finished : .none
        }
    }

    /// Some tab finished while not in view and was not looked at since (the project's mark).
    public var hasUnseen: Bool { !unseen.isEmpty }

    /// The operator looked at the tab: its "finished" mark goes.
    public mutating func seen(_ tab: UUID) {
        unseen.remove(tab)
    }

    /// The tab is gone.
    public mutating func forget(_ tab: UUID) {
        last[tab] = nil
        unseen.remove(tab)
    }
}
