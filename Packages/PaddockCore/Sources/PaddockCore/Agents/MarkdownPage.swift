import Foundation
import Markdown

/// Turns a Markdown file from the sandbox into one self-contained HTML page for a native show tab
/// (backlog doc Browser, Native show tabs). **Untrusted input:** every piece of text is escaped,
/// raw HTML in the file shows as literal text, and the page carries a CSP that allows no scripts,
/// no network, and images only from the tab's own `paddock-file://` origin or `data:`. Links keep
/// only relative targets (files beside it, `#anchors`) and http(s)/mailto, which the web view's
/// navigation policy refuses anyway; anything else (`javascript:`, `file:`) loses its link.
///
/// GitHub-flavored: tables, task lists, strikethrough, autolinks. Front matter (`---` YAML at the
/// top) shows as a small key/value block.
public enum MarkdownPage {
    public static func html(from data: Data, title: String) -> Data {
        Data(html(from: String(decoding: data, as: UTF8.self), title: title).utf8)
    }

    public static func html(from source: String, title: String) -> String {
        // "\r\n" is one Character in Swift: lines would not split.
        var text = source.replacingOccurrences(of: "\r\n", with: "\n")
        if text.unicodeScalars.first == "\u{FEFF}" {
            text.unicodeScalars.removeFirst()
        }
        let (frontMatter, body) = splitFrontMatter(text)
        // No smart quotes: agents write code-like text ("0"|"1", it's) that must stay as typed.
        let document = Document(parsing: repairTablePipes(body), options: [.disableSmartOpts])
        var renderer = MarkdownRenderer()
        let content = renderer.render(document)
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="viewport" content="width=device-width">
        <title>\(escape(title))</title>
        <style>\(stylesheet)</style>
        </head><body><main>
        \(frontMatter.map(renderFrontMatter) ?? "")\(content)</main></body></html>
        """
    }

    public static let contentSecurityPolicy =
        "default-src 'none'; img-src \(NativeShowPolicy.scheme): data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"

    // MARK: Front matter

    public enum FrontMatter: Equatable {
        /// Simple `key: value` lines, in order (quotes around a value removed).
        case fields([(key: String, value: String)])
        /// Anything else (nested YAML, lists): shown as it is.
        case raw(String)

        public static func == (lhs: FrontMatter, rhs: FrontMatter) -> Bool {
            switch (lhs, rhs) {
            case let (.raw(left), .raw(right)): left == right
            case let (.fields(left), .fields(right)):
                left.map(\.key) == right.map(\.key) && left.map(\.value) == right.map(\.value)
            default: false
            }
        }
    }

    /// A `---` line first, then lines up to the next `---` (or `...`): front matter. Without the
    /// closing line the file has none.
    public static func splitFrontMatter(_ text: String) -> (FrontMatter?, String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---",
              let end = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) else { return (nil, text) }
        let block = lines[1 ..< end].map(String.init)
        let body = lines[(end + 1)...].joined(separator: "\n")
        var fields: [(key: String, value: String)] = []
        for line in block where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let colon = line.firstIndex(of: ":"),
                  case let key = String(line[..<colon]), !key.isEmpty,
                  key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
            else {
                return (.raw(block.joined(separator: "\n")), body)
            }
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == "'" || first == "\"", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            fields.append((key, value))
        }
        return (.fields(fields), body)
    }

    private static func renderFrontMatter(_ frontMatter: FrontMatter) -> String {
        switch frontMatter {
        case let .fields(fields) where fields.isEmpty:
            return ""
        case let .fields(fields):
            let rows = fields.map { "<tr><th>\(escape($0.key))</th><td>\(escape($0.value))</td></tr>" }
            return "<table class=\"front-matter\">\(rows.joined())</table>\n"
        case let .raw(text):
            return "<pre class=\"front-matter\">\(escape(text))</pre>\n"
        }
    }

    // MARK: Table pipes

    /// GFM splits a table row at every `|`, even inside code spans, so a row like
    /// `| refresh "0"|"1" vs boolean |` gets one cell too many and loses its last one. Only in such
    /// a row, and only when it then has exactly as many cells as the header: a pipe with no space
    /// on either side is taken as text (escaped as `\|`). Code fences are left alone.
    public static func repairTablePipes(_ text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var fence: String?
        var columns: Int?
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open) {
                    fence = nil
                }
                index += 1
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                columns = nil
                index += 1
                continue
            }
            if let count = columns {
                guard trimmed.contains("|") else {
                    columns = nil
                    index += 1
                    continue
                }
                if cellCount(line) > count {
                    let repaired = escapeTightPipes(line)
                    if cellCount(repaired) == count {
                        lines[index] = repaired
                    }
                }
            } else if index + 1 < lines.count, trimmed.contains("|"), isDelimiterRow(lines[index + 1]),
                      cellCount(lines[index + 1]) == cellCount(line) {
                columns = cellCount(line)
                index += 2
                continue
            }
            index += 1
        }
        return lines.joined(separator: "\n")
    }

    /// Cells in a table row: unescaped pipes, without a leading and a trailing one.
    static func cellCount(_ line: String) -> Int {
        var row = Substring(line.trimmingCharacters(in: .whitespaces))
        if row.hasPrefix("|") {
            row = row.dropFirst()
        }
        if row.hasSuffix("|"), !row.hasSuffix("\\|") {
            row = row.dropLast()
        }
        var count = 1
        var escaped = false
        for char in row {
            if escaped {
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "|" {
                count += 1
            }
        }
        return count
    }

    static func isDelimiterRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.allSatisfy({ "|-: \t".contains($0) }) else { return false }
        var row = Substring(trimmed)
        if row.hasPrefix("|") {
            row = row.dropFirst()
        }
        if row.hasSuffix("|") {
            row = row.dropLast()
        }
        return row.split(separator: "|", omittingEmptySubsequences: false).allSatisfy {
            let cell = $0.trimmingCharacters(in: .whitespaces)
            return cell.contains("-") && cell.drop { $0 == ":" }.reversed().drop { $0 == ":" }.allSatisfy { $0 == "-" }
        }
    }

    /// Escapes every unescaped `|` with a non-space character on both sides.
    static func escapeTightPipes(_ line: String) -> String {
        let chars = Array(line)
        var result = ""
        var escaped = false
        for (position, char) in chars.enumerated() {
            defer { result.append(char) }
            if escaped {
                escaped = false; continue
            }
            if char == "\\" {
                escaped = true; continue
            }
            guard char == "|", position > 0, position + 1 < chars.count,
                  !chars[position - 1].isWhitespace, !chars[position + 1].isWhitespace else { continue }
            result.append("\\")
        }
        return result
    }

    // MARK: HTML

    public static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for char in text {
            switch char {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(char)
            }
        }
        return result
    }

    /// A link target the page may keep: relative (no scheme, not `//host`), or http, https, mailto.
    public static func safeLink(_ destination: String) -> String? {
        let target = destination.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        guard let scheme = scheme(of: target) else { return target.hasPrefix("//") ? nil : target }
        return ["http", "https", "mailto"].contains(scheme) ? target : nil
    }

    /// An image source the page may load: relative to the file (served through `paddock-file://`)
    /// or `data:`. Remote images would be blocked anyway; they show as their alt text instead.
    public static func safeImage(_ source: String) -> String? {
        let target = source.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        guard let scheme = scheme(of: target) else { return target.hasPrefix("//") ? nil : target }
        return scheme == "data" && target.lowercased().hasPrefix("data:image/") ? target : nil
    }

    private static func scheme(of target: String) -> String? {
        guard let colon = target.firstIndex(of: ":") else { return nil }
        let head = target[..<colon]
        guard let first = head.first, first.isLetter,
              head.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }) else { return nil }
        return head.lowercased()
    }

    /// GitHub's heading ids: lowercase, letters, digits, `-` and `_` kept, spaces to `-`.
    public static func slug(_ text: String) -> String {
        String(text.lowercased().compactMap { char -> Character? in
            if char == " " {
                return "-"
            }
            return char.isLetter || char.isNumber || char == "-" || char == "_" ? char : nil
        })
    }
}
