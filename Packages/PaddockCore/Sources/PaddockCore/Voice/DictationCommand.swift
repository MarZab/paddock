import Foundation

/// A word said on its own while dictating (backlog doc Voice, Dictation): a command, not text.
/// "stop" (or "cancel") holds hands-free's send and pauses the microphone; "send" sends at once. Only a sentence
/// that is nothing but the word counts, so "stop the server" or "send it to staging" stay text.
public enum DictationCommand: String, Sendable, CaseIterable {
    case stop
    case send

    /// The text without its command sentences, and the commands in the order they were said.
    public static func strip(_ text: String) -> (text: String, commands: [DictationCommand]) {
        var kept = ""
        var commands: [DictationCommand] = []
        for sentence in sentences(text) {
            if let command = command(in: sentence) {
                commands.append(command)
            } else {
                kept += sentence
            }
        }
        guard !commands.isEmpty else { return (text, []) }
        return (kept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : kept, commands)
    }

    /// While an agent is read aloud, the microphone hears it too, so the operator's "stop" or
    /// "cancel" comes mixed into its words, without a sentence of its own, and only in tentative
    /// results until the speech ends. Then either word anywhere in what is heard counts, unless
    /// the agent's own text has it (the microphone hearing the speaker).
    public static func stopsSpeech(heard: String, spoken: String) -> Bool {
        let said = Set(words(spoken))
        return words(heard).contains { ($0 == "stop" || $0 == "cancel") && !said.contains($0) }
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
    }

    /// Pieces ending at `.`, `!`, or `?` (with the space before them), which join back into `text`.
    static func sentences(_ text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var ended = false
        for character in text {
            if ended && !".!?".contains(character) {
                pieces.append(current)
                current = ""
                ended = false
            }
            current.append(character)
            if ".!?".contains(character) { ended = true }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    private static func command(in sentence: String) -> DictationCommand? {
        let word = sentence.filter { $0.isLetter || $0.isNumber }.lowercased()
        let rest = sentence.filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace && !".!?,".contains($0) }
        guard rest.isEmpty else { return nil }
        return word == "cancel" ? .stop : DictationCommand(rawValue: word)
    }
}
