import Foundation

/// One line of `paddock-voice-watch` (backlog doc Voice): something the agent wants said, asked, or
/// recognized. It comes from the sandbox, so anything that is not exactly this shape and within the
/// limits is dropped, and the text is cleaned again before it is shown or spoken (`SpokenText`).
public struct VoiceMessage: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Speak `text`.
        case say(text: String)
        /// Ask `question` and wait for the operator's answer until `deadline`.
        case ask(question: String, choices: [String], deadline: Date)
        /// The agent took back its question (it gave up, or was stopped).
        case cancel
        /// The project's words for recognition, all of them (each message replaces the last).
        case words([String])
    }

    /// `v-` and eight hex digits, the handle for answers.
    public let id: String
    public let kind: Kind
    /// The tab the agent runs in (`PADDOCK_TAB`), when Paddock opened it.
    public let tab: UUID?
    public let time: Date

    static let maxLine = 32 * 1024
    // The limits `paddock-voice` enforces too (`VoiceKit.script`).
    static let maxText = 600
    static let maxQuestion = 300
    static let maxChoices = 8
    static let maxChoice = 80
    static let maxWords = 200
    static let maxWord = 48
    /// A say this old when it arrives is not spoken (Paddock was not following, or was busy).
    public static let staleAfter: TimeInterval = 60

    public init(id: String, kind: Kind, tab: UUID?, time: Date) {
        self.id = id
        self.kind = kind
        self.tab = tab
        self.time = time
    }

    public init?(line: String) {
        guard line.utf8.count <= Self.maxLine,
              let raw = try? JSONDecoder().decode(Raw.self, from: Data(line.utf8)),
              Self.isMessageID(raw.id), raw.time >= 0 else { return nil }
        let kind: Kind
        switch raw.kind {
        case "say":
            guard let text = raw.text, Self.isText(text, max: Self.maxText) else { return nil }
            kind = .say(text: text)
        case "ask":
            let choices = raw.choices ?? []
            guard let text = raw.text, Self.isText(text, max: Self.maxQuestion), let deadline = raw.deadline, deadline >= raw.time,
                  choices.count <= Self.maxChoices, choices.allSatisfy({ Self.isText($0, max: Self.maxChoice) }),
                  Set(choices.map { $0.lowercased() }).count == choices.count else { return nil }
            kind = .ask(question: text, choices: choices, deadline: Date(timeIntervalSince1970: TimeInterval(deadline)))
        case "cancel":
            kind = .cancel
        case "words":
            guard let words = raw.words, words.count <= Self.maxWords, words.allSatisfy(VoiceKeywords.isWord) else { return nil }
            kind = .words(words)
        default:
            return nil
        }
        self.init(id: raw.id, kind: kind, tab: raw.tab.flatMap(UUID.init(uuidString:)),
                  time: Date(timeIntervalSince1970: TimeInterval(raw.time)))
    }

    /// Whether a say came too late to be spoken. Questions stay until their deadline instead.
    public func isStale(now: Date) -> Bool {
        switch kind {
        case .say: now.timeIntervalSince(time) > Self.staleAfter
        case .ask(_, _, let deadline): now > deadline
        case .cancel, .words: false
        }
    }

    public static func isMessageID(_ id: String) -> Bool {
        id.utf8.count == 10 && id.hasPrefix("v-") && id.dropFirst(2).allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// Not empty, within `max` characters, one line without control characters.
    private static func isText(_ text: String, max: Int) -> Bool {
        !text.isEmpty && text.count <= max && !text.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    private struct Raw: Decodable {
        let id: String
        let kind: String
        let text: String?
        let choices: [String]?
        let deadline: Int?
        let words: [String]?
        let tab: String?
        let time: Int
    }
}

/// What Paddock answers an `ask` with: the line `paddock-voice` prints.
public enum VoiceAnswer: Sendable, Equatable {
    case dismissed
    case timeout
    /// One of the question's choices, exactly as the agent gave it.
    case choice(String)
    /// Free text the operator said or typed.
    case text(String)

    static let maxLength = 2000

    /// The line for `paddock-voice --answer` on standard input: one line, no control characters.
    public var line: String {
        switch self {
        case .dismissed: "dismissed"
        case .timeout: "timeout"
        case .choice(let choice): "choice: " + Self.oneLine(choice)
        case .text(let text): "answer: " + Self.oneLine(text)
        }
    }

    /// The operator's answer to a question: a choice when it names one (`VoiceChoice.match`),
    /// otherwise the text. Nil for an empty answer.
    public static func to(choices: [String], answer: String) -> VoiceAnswer? {
        let text = oneLine(answer)
        guard !text.isEmpty else { return nil }
        if let index = VoiceChoice.match(text, choices: choices) { return .choice(choices[index]) }
        return .text(text)
    }

    private static func oneLine(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { scalar -> Character in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: " "
            default: Character(scalar)
            }
        }
        let joined = String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(joined.prefix(maxLength - 10))
    }
}
