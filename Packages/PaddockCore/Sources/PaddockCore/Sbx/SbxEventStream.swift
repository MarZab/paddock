import Foundation

/// `sbx events --json` as a stream of events (backlog doc SbxService: live updates).
public struct SbxEventStream: Sendable {
    private let streamer: any LineStreaming
    private let sbx: URL

    public init(streamer: any LineStreaming = FoundationLineStreamer(), sbx: URL) {
        self.streamer = streamer
        self.sbx = sbx
    }

    /// Lines that are not events (sbx may add banners or new shapes) are skipped.
    public func events() -> AsyncThrowingStream<SbxEvent, any Error> {
        let lines = streamer.lines(sbx, arguments: ["events", "--json"])
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in lines {
                        if let event = try? SbxEventDecoder.decode(line: line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Each sandbox's state, built from events. sbx replays the current state on connect, so a fresh
/// value per connection is correct; `isSynced` turns true at the replay's end.
public struct SandboxStates: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case running
        case stopped
        /// A state sbx reported that Paddock has no name for.
        case other(String)

        public init(sbxStatus: String) {
            switch sbxStatus {
            case "running": self = .running
            case "stopped": self = .stopped
            default: self = .other(sbxStatus)
            }
        }
    }

    public private(set) var states: [String: State] = [:]
    public private(set) var isSynced = false
    /// When each sandbox's last lifecycle event arrived, so a list older than it never drops it.
    private var seenAt: [String: Date] = [:]

    public init() {}

    /// From `sbx ls --json`, when events are not available.
    public init(sandboxes: [SbxSandbox]) {
        for sandbox in sandboxes {
            states[sandbox.name] = State(sbxStatus: sandbox.status)
        }
        isSynced = true
    }

    public subscript(name: String) -> State? { states[name] }

    /// Takes a `sbx ls` asked at `listedAt` as the truth for every sandbox without a lifecycle
    /// event since: one it does not list is dropped (a `deleted` event the stream missed, for
    /// example while it reconnected), and a listed one gets its status (a missed `stopped`). A
    /// sandbox with an event after the list (one just created or started) keeps that event's state.
    public mutating func reconcile(with sandboxes: [SbxSandbox], listedAt: Date) {
        let listed = Dictionary(sandboxes.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for name in Set(states.keys).union(listed.keys) where (seenAt[name] ?? .distantPast) < listedAt {
            if let sandbox = listed[name] {
                states[name] = State(sbxStatus: sandbox.status)
            } else {
                states[name] = nil
                seenAt[name] = nil
            }
        }
    }

    /// Lifecycle actions seen on sbx 0.49.2: `created`, `started`, `stopped`, `deleted`.
    public mutating func apply(_ event: SbxEvent, at now: Date = Date()) {
        if event.isSyncComplete {
            isSynced = true
            return
        }
        guard event.kind == .sandboxLifecycle, let name = event.sandboxName else { return }
        seenAt[name] = now
        switch event.action {
        case "created", "stopped": states[name] = .stopped
        case "started": states[name] = .running
        case "deleted":
            states[name] = nil
            seenAt[name] = nil
        default: states[name] = .other(event.action)
        }
    }
}
