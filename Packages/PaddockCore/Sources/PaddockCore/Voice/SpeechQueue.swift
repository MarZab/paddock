import Foundation

/// Something that reads text aloud: AVSpeechSynthesizer in the app, a fake in tests.
public protocol SpeechSynthesizing: Sendable {
    /// Speaks `text` and returns when it is done: true when it finished, false when `stop()` cut it off.
    func speak(_ text: String) async -> Bool
    /// Stops what is being spoken now.
    func stop() async
}

/// One app-wide queue for everything Paddock says (backlog doc Voice): utterances never overlap,
/// each starts with who says it (`SpokenText.utterance`), and the operator starting to talk or
/// type in a tab stops what that tab's agent says.
public actor SpeechQueue {
    public struct Utterance: Sendable, Equatable {
        public let id: String
        public let project: String
        public let tab: UUID?
        public let text: String

        public init(id: String = UUID().uuidString, project: String, tab: UUID? = nil, text: String) {
            self.id = id
            self.project = project
            self.tab = tab
            self.text = text
        }

        /// What the synthesizer gets: the text alone, cleaned (who said it shows in the popup).
        public var spoken: String { SpokenText.clean(text) }
    }

    public enum Outcome: Sendable, Equatable {
        case done
        /// Cut off or taken out of the queue before its turn.
        case interrupted
        /// Not queued: the project already has `maxPendingPerProject` waiting.
        case dropped
    }

    /// An agent that talks too much is not queued further.
    public static let maxPendingPerProject = 3

    private let synthesizer: SpeechSynthesizing
    private var pending: [(utterance: Utterance, done: CheckedContinuation<Outcome, Never>)] = []
    private var current: Utterance?
    private var currentInterrupted = false
    private var draining = false

    public init(synthesizer: SpeechSynthesizing) {
        self.synthesizer = synthesizer
    }

    /// Speaks after everything queued before it, and returns how it ended.
    public func speak(_ utterance: Utterance) async -> Outcome {
        let queued = pending.filter { $0.utterance.project == utterance.project }.count
        guard queued < Self.maxPendingPerProject else { return .dropped }
        return await withCheckedContinuation { continuation in
            pending.append((utterance, continuation))
            if !draining {
                draining = true
                Task { await self.drain() }
            }
        }
    }

    /// Stops and drops what the tab's agent says (the operator started talking or typing there).
    public func interrupt(tab: UUID) async {
        await interrupt { $0.tab == tab }
    }

    /// Stops and drops everything (the operator's Stop Speaking).
    public func interruptAll() async {
        await interrupt { _ in true }
    }

    /// Whether something is being said now.
    public var isSpeaking: Bool { current != nil }

    private func interrupt(where matches: (Utterance) -> Bool) async {
        let dropped = pending.filter { matches($0.utterance) }
        pending.removeAll { matches($0.utterance) }
        for entry in dropped {
            entry.done.resume(returning: .interrupted)
        }
        if let current, matches(current) {
            currentInterrupted = true
            await synthesizer.stop()
        }
    }

    private func drain() async {
        while !pending.isEmpty {
            let (utterance, done) = pending.removeFirst()
            current = utterance
            currentInterrupted = false
            let finished = await synthesizer.speak(utterance.spoken)
            let outcome: Outcome = finished && !currentInterrupted ? .done : .interrupted
            current = nil
            done.resume(returning: outcome)
        }
        draining = false
    }
}

/// When Paddock itself says how an agent is doing (backlog doc Voice, State announcements): in its
/// own words, never the agent's, so this needs no voice kit.
public enum VoiceAnnouncements {
    public enum Setting: String, Sendable, Equatable, CaseIterable, Codable {
        case off
        /// Only when an agent starts waiting for the operator.
        case needsYou
        /// Waiting, and finished (working to idle).
        case everyChange
    }

    /// A state must hold this long before it is announced, so a quick flip (a permission answered
    /// at once) says nothing.
    public static let settleTime: TimeInterval = 2

    /// What to say when a session's state changed from `previous` to `current`, or nil. `looking`:
    /// the operator has that session's tab in front of them, so nothing is said.
    public static func announcement(project: String, session: String?, previous: AgentState.Kind?, current: AgentState.Kind,
                                    setting: Setting, looking: Bool) -> String? {
        guard setting != .off, !looking, previous != current else { return nil }
        let who = session.map { "\(project), \($0)," } ?? project
        switch current {
        case .waiting:
            return "\(who) is waiting for you"
        case .idle where previous == .working && setting == .everyChange:
            return "\(who) finished"
        default:
            return nil
        }
    }
}
