import Foundation
import Synchronization

/// An sbx network resource: a host or host glob with an optional port, as in
/// `registry.npmjs.org:443`, `*.npmjs.org`, `**.github.com:443`, `localhost:5432`, or `**`.
///
/// Glob rules follow `sbx policy allow network --help`: `*` matches within one label,
/// `**.` matches one or more labels, `?` one character, `[...]` and `[!...]` classes.
public struct HostPattern: Sendable, Hashable, CustomStringConvertible {
    public let host: String
    public let port: Int?

    public init(host: String, port: Int?) {
        self.host = host.lowercased()
        self.port = port
    }

    public init(parsing resource: String) {
        let text = resource.trimmingCharacters(in: .whitespaces)
        if let colon = text.lastIndex(of: ":"), let port = Int(text[text.index(after: colon)...]) {
            self.init(host: String(text[..<colon]), port: port)
        } else {
            self.init(host: text, port: nil)
        }
    }

    public var description: String { port.map { "\(host):\($0)" } ?? host }

    /// `**` on its own: every host.
    public var isAllHosts: Bool { host == "**" }

    /// True when this pattern allows everything `other` names. `other` is read literally,
    /// so wildcards in it are ordinary characters here.
    public func covers(_ other: HostPattern) -> Bool {
        if let port, port != other.port { return false }
        return Self.hostMatches(pattern: host, literal: other.host)
    }

    static func hostMatches(pattern: String, literal: String, cache: HostGlobCache = .shared) -> Bool {
        if pattern == "**" { return true }
        guard let regex = cache.regex(for: pattern) else {
            return pattern == literal
        }
        let range = NSRange(literal.startIndex..., in: literal)
        return regex.firstMatch(in: literal, range: range) != nil
    }

    /// The glob as a whole-host regular expression; nil when it does not compile.
    static func compile(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: "^" + regexBody(for: pattern) + "$")
    }

    private static func regexBody(for pattern: String) -> String {
        var out = ""
        var chars = Array(pattern)[...]
        while let c = chars.first {
            if chars.starts(with: Array("**.")) {
                out += "(?:[^.]+\\.)+"
                chars = chars.dropFirst(3)
                continue
            }
            chars = chars.dropFirst()
            switch c {
            case "*": out += "[^.]*"
            case "?": out += "[^.]"
            case "[":
                var cls = "["
                if chars.first == "!" {
                    cls += "^"
                    chars = chars.dropFirst()
                }
                while let d = chars.first, d != "]" {
                    cls += d == "\\" ? "\\\\" : String(d)
                    chars = chars.dropFirst()
                }
                chars = chars.dropFirst()
                out += cls + "]"
            default:
                out += NSRegularExpression.escapedPattern(for: String(c))
            }
        }
        return out
    }
}

/// Compiled host globs by pattern. The views build their rule and host rows on every render, each
/// with many pattern checks, and compiling a regular expression for each one held up project
/// switches (PAD-29). A failed compile is kept too, so it is not retried.
final class HostGlobCache: Sendable {
    static let shared = HostGlobCache()

    private struct Entry: @unchecked Sendable {
        /// NSRegularExpression is immutable and safe to share between threads.
        let regex: NSRegularExpression?
    }

    private let limit: Int
    private let entries = Mutex<[String: Entry]>([:])
    private let compiles = Mutex(0)

    /// - Parameter limit: entries kept before the cache starts over; rules name few patterns.
    init(limit: Int = 1024) {
        self.limit = limit
    }

    func regex(for pattern: String) -> NSRegularExpression? {
        if let entry = entries.withLock({ $0[pattern] }) { return entry.regex }
        let entry = Entry(regex: HostPattern.compile(pattern))
        compiles.withLock { $0 += 1 }
        entries.withLock {
            if $0.count >= limit { $0.removeAll() }
            $0[pattern] = entry
        }
        return entry.regex
    }

    /// How many patterns this cache compiled, for tests.
    var compileCount: Int { compiles.withLock { $0 } }
    var count: Int { entries.withLock { $0.count } }
}
