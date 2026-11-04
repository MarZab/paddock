import Foundation

/// What of a dictation is worth sending (backlog doc Voice, Dictation). The recognizer turns noise
/// into "." or "Hmm.", and taking out a start word or a command can leave a lone comma; none of that
/// reaches the agent. Leading punctuation goes ("Paddock, run the tests" leaves ", run the tests"
/// in some results).
public enum DictationText {
    /// Sounds, not words: a dictation of nothing else is not sent.
    static let fillers: Set<String> = ["uh", "uhm", "um", "umm", "hm", "hmm", "mm", "mhm", "ah", "er", "erm", "oh"]

    /// The text to send, or nil when there is nothing in it: no letter or digit, or only fillers.
    public static func prompt(_ text: String) -> String? {
        let trimmed = text.drop { $0.isWhitespace || $0.isPunctuation || $0.isSymbol }
        let result = String(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = result.lowercased().split { !($0.isLetter || $0.isNumber) }
        guard !words.isEmpty, !words.allSatisfy({ fillers.contains(String($0)) }) else { return nil }
        return result
    }
}
