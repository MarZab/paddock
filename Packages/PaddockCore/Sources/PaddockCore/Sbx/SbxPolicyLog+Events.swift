import Foundation

extension SbxPolicyLog {
    /// What one `policy.network` event did to the log.
    public enum Change: Sendable, Equatable {
        /// Not a `policy.network` event, or one Paddock cannot read.
        case none
        /// New counts for an entry the log had.
        case updated
        /// An entry the log did not have: a host this sandbox had not reached (or tried) this way.
        case added(Entry)
    }

    /// The log from sbx's events, instead of reading `sbx policy log` again. Each entry is one
    /// sandbox, host, decision, proxy type, and rule; a `policy.network` event carries one entry with
    /// its counts so far, which replaces the entry or adds it. The replay on connect is the whole log.
    /// Verified on sbx 0.49.2: the replay and its live events give what `sbx policy log` printed.
    @discardableResult
    public mutating func apply(_ event: SbxEvent) -> Change {
        guard event.kind == .policyNetwork, let sandbox = event.sandboxName, let data = event.data,
              let payload = try? JSONCoding.decode(NetworkEventData.self, from: JSONEncoder().encode(data)) else {
            return .none
        }
        let entry = Entry(sandboxId: sandbox, host: payload.host, proxyType: payload.proxyType,
                          rule: payload.rule?.isEmpty == false ? payload.rule : nil, reason: payload.reason,
                          count: payload.count, firstSeen: payload.since, lastSeen: payload.lastSeen)
        switch event.action {
        case "allowed": return Self.upsert(entry, into: &allowed)
        case "blocked": return Self.upsert(entry, into: &blocked)
        default: return .none
        }
    }

    private static func upsert(_ entry: Entry, into entries: inout [Entry]) -> Change {
        if let index = entries.firstIndex(where: { $0.isSameEntry(as: entry) }) {
            entries[index] = entry
            return .updated
        }
        entries.append(entry)
        return .added(entry)
    }
}

extension SbxPolicyLog.Entry {
    func isSameEntry(as other: Self) -> Bool {
        sandboxId == other.sandboxId && host == other.host && proxyType == other.proxyType && rule == other.rule
    }
}

/// `data` of a `policy.network` event: a log entry, with sbx's event names (`count`, `since`).
private struct NetworkEventData: Decodable {
    let host: String
    let count: Int
    let since: Date
    let lastSeen: Date
    let proxyType: String?
    /// Empty when no rule matched an allowed host.
    let rule: String?
    /// Only on `blocked`.
    let reason: String?
}
