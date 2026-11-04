import Foundation

/// The words speech recognition is told to expect for a project (contextual strings; backlog doc
/// Voice): the agent's own (`paddock-voice words`) and the names of the project's files and
/// folders. Only a hint for the recognizer: a word can make a name come out right, never run anything.
public enum VoiceKeywords {
    /// Most words recognition is given; the agent's come first.
    public static let maxTotal = 300
    /// Folders not worth naming.
    static let skipped: Set<String> = [".git", "node_modules", ".build", "build", "dist", "DerivedData", ".swiftpm", "vendor",
                                       "target", ".venv", "__pycache__"]

    /// Letters or digits first, then letters, digits, spaces, and `. _ + # / ' -`; within the
    /// kit's limit.
    public static func isWord(_ word: String) -> Bool {
        guard let first = word.first, word.count <= VoiceMessage.maxWord, first.isLetter || first.isNumber else { return false }
        return word.allSatisfy { $0.isLetter || $0.isNumber || " ._+#/'-".contains($0) }
    }

    /// The agent's words, then the project's names, without repeats (ignoring case), at most `maxTotal`.
    public static func combined(agent: [String], project: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for word in agent + project where isWord(word) && seen.insert(word.lowercased()).inserted {
            out.append(word)
            if out.count == maxTotal { break }
        }
        return out
    }

    /// Names in the project folder two levels deep, skipping hidden files and build folders: each
    /// file's name without its extension when it looks like a code name (`PolicyPlanner`), and each
    /// folder's. Sorted, at most `limit`.
    public static func projectNames(in folder: URL, limit: Int = 200, fileManager: FileManager = .default) -> [String] {
        var names = Set<String>()
        func visit(_ url: URL, depth: Int) {
            guard depth <= 2, names.count < limit * 2,
                  let entries = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                                     options: [.skipsHiddenFiles]) else { return }
            for entry in entries {
                let name = entry.lastPathComponent
                let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if isDirectory {
                    guard !skipped.contains(name) else { continue }
                    if isWord(name) { names.insert(name) }
                    visit(entry, depth: depth + 1)
                } else {
                    let stem = entry.deletingPathExtension().lastPathComponent
                    if stem.count >= 3, isWord(stem) { names.insert(stem) }
                }
            }
        }
        visit(folder, depth: 1)
        return Array(names.sorted().prefix(limit))
    }
}

/// Matches a spoken answer to a question's choices (backlog doc Voice): by its name, or by its
/// place ("the second one", "option 3", "last").
public enum VoiceChoice {
    static let ordinals: [String: Int] = [
        "first": 1, "one": 1, "1": 1, "1st": 1,
        "second": 2, "two": 2, "2": 2, "2nd": 2,
        "third": 3, "three": 3, "3": 3, "3rd": 3,
        "fourth": 4, "four": 4, "4": 4, "4th": 4,
        "fifth": 5, "five": 5, "5": 5, "5th": 5,
        "sixth": 6, "six": 6, "6": 6, "6th": 6,
        "seventh": 7, "seven": 7, "7": 7, "7th": 7,
        "eighth": 8, "eight": 8, "8": 8, "8th": 8
    ]
    /// Words around a choice that do not change it ("the second one, please").
    static let filler: Set<String> = ["the", "one", "option", "choice", "number", "please", "i", "pick", "take", "go", "with",
                                      "choose", "let's", "lets", "say", "um", "uh", "okay", "ok", "it's", "its", "that"]

    /// The index of the choice `answer` names, or nil when it names none or more than one.
    public static func match(_ answer: String, choices: [String]) -> Int? {
        guard !choices.isEmpty else { return nil }
        let said = words(answer)
        guard !said.isEmpty else { return nil }
        let names = choices.map(words)
        // The whole answer is a choice ("Staging", "yes.").
        if let exact = names.firstIndex(of: said), names.lastIndex(of: said) == exact { return exact }
        let meaningful = said.filter { !filler.contains($0) }
        if let exact = names.firstIndex(of: meaningful), !meaningful.isEmpty, names.lastIndex(of: meaningful) == exact { return exact }
        // By place: only when the answer is nothing but a place and filler.
        if meaningful.count == 1, let word = meaningful.first {
            if word == "last" { return choices.count - 1 }
            if let place = ordinals[word], place <= choices.count, !names.contains([word]) { return place - 1 }
        }
        if meaningful.isEmpty, said.contains("one"), choices.count >= 1, !names.contains(["one"]) { return 0 }
        // A choice named inside the answer, when exactly one is.
        let found = names.indices.filter { !names[$0].isEmpty && contains(said, names[$0]) }
        return found.count == 1 ? found[0] : nil
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "'") }.map(String.init)
    }

    private static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        return (0...(haystack.count - needle.count)).contains { Array(haystack[$0..<($0 + needle.count)]) == needle }
    }
}

/// Dictated text as terminal input (backlog doc Voice, Rules): a bracketed paste, so the agent
/// takes it as typed text and a newline does not submit it; control characters (escape sequences,
/// the paste's end marker) are dropped. Return follows only when the operator asked for it.
public enum BracketedPaste {
    static let start = "\u{1B}[200~"
    static let end = "\u{1B}[201~"

    public static func encode(_ text: String, submit: Bool) -> Data {
        var cleaned = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control:
                if scalar == "\n" || scalar == "\t" { cleaned.append(scalar) } else if scalar == "\r" { cleaned.append("\n") }
            case .format, .lineSeparator, .paragraphSeparator:
                cleaned.append(" ")
            default:
                cleaned.append(scalar)
            }
        }
        let body = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return Data((start + body + end + (submit ? "\r" : "")).utf8)
    }
}
