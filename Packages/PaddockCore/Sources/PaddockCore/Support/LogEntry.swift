import Foundation

/// Where a line of the Log came from (backlog doc UI, Log): the page filters by it, and the log
/// file names it on each line.
public enum LogCategory: String, Sendable, CaseIterable, Identifiable {
    /// Errors the status popover showed and the app's own messages.
    case paddock
    /// What a create did, step by step (`LogSink`). Named `build` from Paddock's image builds
    /// before PAD-73.4; the name stays, since the Log's chosen categories are stored by it.
    case build
    /// What sbx reported a sandbox did (`ActivityTimeline`), the projects' Recent Activity.
    case sandbox
    case voice
    /// sbx's processes on the Mac stopped or found running.
    case processes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .paddock: "Paddock"
        case .build: "Setup"
        case .sandbox: "Sandbox activity"
        case .voice: "Voice"
        case .processes: "Processes"
        }
    }
}

/// One line of the Log.
public struct LogEntry: Sendable, Identifiable, Equatable {
    public let id = UUID()
    public let date: Date
    public let category: LogCategory
    /// What it came from, when one thing: a project's sandbox, with its agent tab ("app · agent 2").
    public let source: String?
    public let message: String
    public let isError: Bool

    public init(date: Date = Date(), category: LogCategory, source: String? = nil, message: String,
                isError: Bool = false) {
        self.date = date
        self.category = category
        self.source = source
        self.message = message
        self.isError = isError
    }

    /// One entry per line of `text`. Empty lines inside stay (a message's own layout); the trailing
    /// newline of a command's output adds none (PAD-97).
    public static func lines(of text: String, category: LogCategory, source: String? = nil, isError: Bool = false) -> [LogEntry] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        while lines.count > 1, lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        return lines.map { LogEntry(category: category, source: source, message: String($0), isError: isError) }
    }

    /// The line in the log file: the time, ERROR for an error, the category, then the source and a
    /// colon, or `-` without one, then the message. A source never holds ": " (it is written as
    /// ":"), so `init(fileLine:)` reads the line back unambiguously.
    public var fileLine: String {
        let source = source.map { $0.replacingOccurrences(of: ": ", with: ":") + ":" } ?? "-"
        return "\(date.formatted(.iso8601))\(isError ? " ERROR" : "") [\(category.rawValue)] \(source) \(message)"
    }

    /// Reads a line of a log file back (`fileLine`). Nil for a line in no form Paddock writes; the
    /// caller shows it as text (`LogFiles.entries(in:)`). A line from before PAD-78 has no `-`, so a
    /// colon in its message may read as a source.
    public init?(fileLine line: String) {
        guard let space = line.firstIndex(of: " "),
              let date = try? Date(String(line[..<space]), strategy: .iso8601) else { return nil }
        var rest = line[line.index(after: space)...]
        let isError = rest.hasPrefix("ERROR [")
        if isError { rest = rest.dropFirst("ERROR ".count) }
        guard rest.hasPrefix("["), let close = rest.firstIndex(of: "]"),
              let category = LogCategory(rawValue: String(rest[rest.index(after: rest.startIndex)..<close])) else { return nil }
        rest = rest[rest.index(after: close)...]
        if rest.hasPrefix(" ") { rest = rest.dropFirst() }
        var source: String?
        if rest.hasPrefix("- ") || rest == "-" {
            rest = rest.dropFirst(min(2, rest.count))
        } else if let colon = rest.range(of: ": ") {
            source = String(rest[..<colon.lowerBound])
            rest = rest[colon.upperBound...]
        } else if rest.hasSuffix(":") {
            source = String(rest.dropLast())
            rest = ""
        }
        self.init(date: date, category: category, source: source, message: String(rest), isError: isError)
    }
}

/// What the Log page shows: the chosen categories (none chosen shows every one), errors only or
/// everything, and lines whose message or source contains the search text (any case).
public struct LogFilter: Sendable, Equatable {
    public var categories: Set<LogCategory>
    public var errorsOnly: Bool
    public var text: String

    public init(categories: Set<LogCategory> = [], errorsOnly: Bool = false, text: String = "") {
        self.categories = categories
        self.errorsOnly = errorsOnly
        self.text = text
    }

    public func matches(_ entry: LogEntry) -> Bool {
        guard categories.isEmpty || categories.contains(entry.category), !errorsOnly || entry.isError else {
            return false
        }
        let query = text.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || entry.message.localizedCaseInsensitiveContains(query)
            || entry.source?.localizedCaseInsensitiveContains(query) == true
    }

    public func apply(_ entries: [LogEntry]) -> [LogEntry] { entries.filter(matches) }

    /// Adds a category to the choice, or takes it out; taking out the last one shows every one again.
    public mutating func toggle(_ category: LogCategory) {
        if categories.remove(category) == nil { categories.insert(category) }
    }

    /// The chosen categories as stored in the app's defaults: their raw values, comma-separated;
    /// an unknown one (from a later version) is ignored.
    public var categoriesStored: String { categories.map(\.rawValue).sorted().joined(separator: ",") }

    public static func categories(stored: String) -> Set<LogCategory> {
        Set(stored.split(separator: ",").compactMap { LogCategory(rawValue: String($0)) })
    }
}

/// The log files in `~/Library/Logs/Paddock`: one per launch of the app, named by when it started
/// and its process id (`paddock-2026-10-30_08-25-50-4711.log`), so Paddock and Paddock Dev never
/// share one and `mise run hang` finds the stuck app's own. At launch, a file last written over
/// `maxAge` ago goes.
public enum LogFiles {
    public static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    public static func name(started: Date, pid: Int32, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: started)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        let day = "\(parts.year ?? 0)-\(two(parts.month))-\(two(parts.day))"
        let time = "\(two(parts.hour))-\(two(parts.minute))-\(two(parts.second))"
        return "paddock-\(day)_\(time)-\(pid).log"
    }

    /// Whether `name` is one of Paddock's logs: a session's, or the single `paddock.log` of earlier
    /// versions. Nothing else in the folder is touched.
    public static func isPaddockLog(_ name: String) -> Bool {
        name == "paddock.log" || name.wholeMatch(of: /paddock-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-\d+\.log/) != nil
    }

    /// One session's file, from its name.
    public struct Session: Sendable, Equatable, Identifiable, Hashable {
        public let name: String
        public let started: Date
        public let pid: Int32
        public var id: String { name }
    }

    /// The session a file name stands for; nil for `paddock.log` and anything else.
    public static func session(named name: String, timeZone: TimeZone = .current) -> Session? {
        guard let match = name.wholeMatch(of: /paddock-(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})-(\d+)\.log/),
              let pid = Int32(match.7) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = DateComponents(year: Int(match.1), month: Int(match.2), day: Int(match.3),
                                   hour: Int(match.4), minute: Int(match.5), second: Int(match.6))
        guard let started = calendar.date(from: parts) else { return nil }
        return Session(name: name, started: started, pid: pid)
    }

    /// The sessions among `names`, newest first, without `current`.
    public static func sessions(_ names: [String], current: String, timeZone: TimeZone = .current) -> [Session] {
        names.filter { $0 != current }.compactMap { session(named: $0, timeZone: timeZone) }
            .sorted { ($0.started, $0.pid) > ($1.started, $1.pid) }
    }

    /// A log file's lines as entries. A line Paddock cannot read shows as a message of its own,
    /// at the time of the line before it.
    public static func entries(in text: String) -> [LogEntry] {
        var entries: [LogEntry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let entry = LogEntry(fileLine: String(line)) {
                entries.append(entry)
            } else {
                entries.append(LogEntry(date: entries.last?.date ?? .distantPast, category: .paddock, message: String(line)))
            }
        }
        return entries
    }

    /// The logs last written more than `maxAge` before `now`, by name; `current` always stays.
    public static func toRemove(_ files: [(name: String, modified: Date)], current: String, now: Date = Date(),
                                maxAge: TimeInterval = maxAge) -> [String] {
        files.filter { isPaddockLog($0.name) && $0.name != current && now.timeIntervalSince($0.modified) > maxAge }
            .map(\.name).sorted()
    }
}
