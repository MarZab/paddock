import Foundation

/// Hands-free's start word (backlog doc Voice, Hands-free): when hands-free opens the microphone on
/// its own, nothing heard counts until the operator says it, so talk in the room is not dictated
/// and sent. What follows it is the dictation: "Paddock, run the tests" sends "run the tests".
/// Words match without case or punctuation, so "paddock." and "Paddock," count too.
public struct WakeWord: Sendable, Equatable {
    /// As the operator set it, for the popup's hint and as a recognition hint.
    public let phrase: String
    private let words: [String]

    /// Nil for an empty phrase, which turns the start word off, or one of more than four words.
    public init?(_ phrase: String) {
        let words = Self.words(in: phrase).map { String(phrase[$0]).lowercased() }
        guard !words.isEmpty, words.count <= 4 else { return nil }
        self.phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        self.words = words
    }

    /// What was said after the phrase's first occurrence, without the punctuation and spaces right
    /// after it; nil while the phrase was not said.
    public func after(_ text: String) -> String? {
        let ranges = Self.words(in: text)
        guard ranges.count >= words.count else { return nil }
        for start in 0...(ranges.count - words.count) {
            let candidate = ranges[start..<start + words.count]
            guard zip(candidate, words).allSatisfy({ text[$0.0].lowercased() == $0.1 }),
                  let end = candidate.last?.upperBound else { continue }
            let rest = text[end...].drop { $0.isWhitespace || $0.isPunctuation }
            return String(rest)
        }
        return nil
    }

    /// The runs of letters and digits.
    private static func words(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let isWord = text[index].isLetter || text[index].isNumber
            if isWord, start == nil { start = index }
            if !isWord, let begun = start {
                ranges.append(begun..<index)
                start = nil
            }
            index = text.index(after: index)
        }
        if let begun = start { ranges.append(begun..<text.endIndex) }
        return ranges
    }
}

/// Hands-free's start words: any of them starts the dictation (backlog doc Voice, Hands-free). The
/// setting is a comma-separated list; "Paddock, computer" by default.
public struct WakeWords: Sendable, Equatable {
    public static let defaultSetting = "Paddock, computer"

    public let words: [WakeWord]

    /// Nil when the setting names no usable phrase, which turns the start word off.
    public init?(setting: String) {
        let words = setting.split(separator: ",").compactMap { WakeWord(String($0)) }
        guard !words.isEmpty else { return nil }
        self.words = words
    }

    /// What was said after the first of the phrases to be said; nil while none was.
    public func after(_ text: String) -> String? {
        // The longest rest follows the phrase said first.
        words.compactMap { $0.after(text) }.max { $0.count < $1.count }
    }

    /// For the popup: `"Paddock" or "computer"`.
    public var hint: String {
        let quoted = words.map { "\"\($0.phrase)\"" }
        guard let last = quoted.last, quoted.count > 1 else { return quoted.first ?? "" }
        return quoted.dropLast().joined(separator: ", ") + " or " + last
    }

    public var phrases: [String] { words.map(\.phrase) }
}
