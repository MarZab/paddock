import Foundation

/// What happened in each sandbox while Paddock was watching, from sbx's events: lifecycle changes,
/// published ports, and the first connection to each host. Memory only, newest first, at most
/// `limit` per sandbox. The replay on connect is the current state, not news, so the caller records
/// only what comes after it.
public struct ActivityTimeline: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Identifiable {
        public enum Kind: Sendable, Equatable {
            /// sbx's lifecycle action: `created`, `started`, `stopped`.
            case lifecycle(String)
            /// The sandbox publishes this many ports now.
            case ports(Int)
            /// A host the sandbox had not reached this way before.
            case connected(host: String)
            /// A host the sandbox had not been blocked from before, and why.
            case blocked(host: String, reason: String?)
        }

        /// The event's id.
        public let id: String
        public let date: Date
        public let sandbox: String
        public let kind: Kind

        /// What happened, in a few words (Recent Activity's row).
        public var text: String {
            switch kind {
            case .lifecycle(let action): action.prefix(1).uppercased() + action.dropFirst()
            case .ports(0): "No published ports"
            case .ports(let count): "Publishes \(count) port\(count == 1 ? "" : "s")"
            case .connected(let host): "Reached \(host)"
            case .blocked(let host, _): "Blocked from \(host)"
            }
        }

        /// The Log's line (its source is `sandbox`): what happened, and why a host was blocked.
        public var logLine: String {
            if case .blocked(_, let reason?) = kind { return "\(text): \(reason)" }
            return text
        }
    }

    public static let limit = 50

    public private(set) var entries: [String: [Entry]] = [:]

    public init() {}

    public subscript(sandbox: String) -> [Entry] { entries[sandbox] ?? [] }

    /// Records one live event. `change` is what it did to the network log: only a new entry is news,
    /// not one more connection to a known host. Returns the entry it added, if any.
    @discardableResult
    public mutating func record(_ event: SbxEvent, change: SbxPolicyLog.Change = .none) -> Entry? {
        guard let sandbox = event.sandboxName else { return nil }
        let kind: Entry.Kind
        switch event.kind {
        case .sandboxLifecycle:
            // A removed sandbox's history goes with it.
            if event.action == "deleted" {
                entries[sandbox] = nil
                return nil
            }
            kind = .lifecycle(event.action)
        case .sandboxPorts:
            guard case .array(let ports)? = event.data?["ports"] else { return nil }
            kind = .ports(ports.count)
        case .policyNetwork:
            guard case .added(let entry) = change else { return nil }
            kind = event.action == "blocked" ? .blocked(host: entry.host, reason: entry.reason) : .connected(host: entry.host)
        case .sync, .other:
            return nil
        }
        let entry = Entry(id: event.id, date: event.timestamp, sandbox: sandbox, kind: kind)
        var list = entries[sandbox] ?? []
        list.insert(entry, at: 0)
        if list.count > Self.limit { list.removeLast(list.count - Self.limit) }
        entries[sandbox] = list
        return entry
    }
}
