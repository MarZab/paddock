import Foundation

/// The back and forth in a project's voice popup (backlog doc Voice, One popup): what its agents
/// said and asked, and what the operator sent them. Display only and in memory, oldest first, at
/// most `limit`. Agent text is untrusted and shown as plain text without invisible characters.
public struct VoiceConversation: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Identifiable {
        public enum Speaker: Sendable, Equatable {
            case agent
            case `operator`
        }

        public let id: UUID
        public let speaker: Speaker
        public let text: String
        /// An agent's question (`paddock-voice ask`), not a statement.
        public let isQuestion: Bool
        /// The agent tab it belongs to; nil when the agent ran outside a tab Paddock opened.
        public let tab: UUID?
        public let time: Date

        public init(id: UUID = UUID(), speaker: Speaker, text: String, isQuestion: Bool = false, tab: UUID?,
                    time: Date = Date()) {
            self.id = id
            self.speaker = speaker
            self.text = speaker == .agent ? SpokenText.dropInvisible(text) : text
            self.isQuestion = isQuestion
            self.tab = tab
            self.time = time
        }
    }

    public static let limit = 50

    public private(set) var entries: [Entry] = []

    public init() {}

    public mutating func append(_ entry: Entry) {
        guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        entries.append(entry)
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }

    /// What a popup shows: its tab's entries, and with `untabbed` also those of no tab (the left
    /// half's popup takes them, like an untabbed question).
    public func entries(for tab: UUID?, untabbed: Bool) -> [Entry] {
        entries.filter { entry in
            if let entryTab = entry.tab { return entryTab == tab }
            return untabbed
        }
    }

    /// How an answer to a question reads in the conversation.
    public static func text(of answer: VoiceAnswer) -> String {
        switch answer {
        case .dismissed: "Dismissed"
        case .timeout: "No answer"
        case .choice(let choice): choice
        case .text(let text): text
        }
    }
}
