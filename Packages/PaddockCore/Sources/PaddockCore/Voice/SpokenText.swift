import Foundation

/// Text made fit to be read aloud (backlog doc Voice, Rules). What an agent asks Paddock to say is
/// untrusted sandbox output, like a tab title: control, bidi, and zero-width characters are
/// dropped, markdown and code are taken out (the details stay in the terminal), and it is cut to a
/// fixed length. It is plain text for the synthesizer, never markup.
public enum SpokenText {
    public static let maxLength = 400

    public static func clean(_ text: String, maxLength: Int = maxLength) -> String {
        var text = dropInvisible(text)
        // Code blocks are dropped whole; inline code keeps its words.
        text = replacing(#"```[\s\S]*?(```|$)"#, in: text, with: " ")
        text = replacing(#"`([^`]*)`"#, in: text, with: "$1")
        // Links keep their words; a bare address is just "a link".
        text = replacing(#"!?\[([^\]]*)\]\([^)]*\)"#, in: text, with: "$1")
        text = replacing(#"\b(https?|ftp|file)://\S+"#, in: text, with: "a link")
        // A path says only its last part ("/a/b/Ports.swift" is "Ports.swift").
        text = replacing(#"(?:~|\.{1,2}|[\w.@+-]+)?(?:/[\w.@+-]+){2,}/?"#, in: text) { match in
            match.split(separator: "/").last.map(String.init) ?? match
        }
        // Headings, list markers, quotes, emphasis, and table bars.
        text = replacing(#"(?m)^\s{0,3}(#{1,6}|>|[-*+]|\d+[.)])\s+"#, in: text, with: "")
        text = replacing(#"(\*\*|__|\*|~~)"#, in: text, with: "")
        text = replacing(#"\s*\|\s*"#, in: text, with: ", ")
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return cut(words, to: maxLength)
    }

    /// Control characters become spaces; format characters (bidi controls, zero-width) go.
    public static func dropInvisible(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator:
                // Newlines matter for markdown above; the rest is a space.
                out.append(scalar == "\n" ? "\n" : " ")
            case .format, .privateUse, .unassigned, .surrogate:
                continue
            default:
                out.append(scalar)
            }
        }
        return String(out)
    }

    /// At a word boundary when there is one in the last fifth.
    static func cut(_ text: String, to length: Int) -> String {
        guard text.count > length else { return text }
        let head = String(text.prefix(length))
        if let space = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: space) > length * 4 / 5 {
            return String(head[..<space])
        }
        return head
    }

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func replacing(_ pattern: String, in text: String, with transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(String(result[range])))
        }
        return result
    }
}
