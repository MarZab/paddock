import Foundation

/// One process on the Mac, as `ps` reports it.
public struct HostProcess: Sendable, Equatable {
    public let pid: Int32
    /// 1 once its parent is gone: launchd adopted it.
    public let ppid: Int32
    public let user: String
    /// Resident memory in KiB.
    public let rssKiB: Int
    /// `ps`'s %CPU: a decaying average, not the last second.
    public let cpuPercent: Double
    /// Seconds since it started.
    public let elapsed: Int
    /// The command line as `ps` joins it: arguments with spaces in them cannot be told apart.
    public let command: String

    public init(pid: Int32, ppid: Int32, user: String, rssKiB: Int, cpuPercent: Double, elapsed: Int, command: String) {
        self.pid = pid
        self.ppid = ppid
        self.user = user
        self.rssKiB = rssKiB
        self.cpuPercent = cpuPercent
        self.elapsed = elapsed
        self.command = command
    }

    /// Its parent is gone (a closed terminal, a crashed app).
    public var isOrphan: Bool { ppid == 1 }
}

/// The Mac's process list, read with `ps` (there is no JSON form; the columns are fixed by `-o`).
public enum HostProcesses {
    public static let ps = URL(fileURLWithPath: "/bin/ps")
    /// Every user's processes (`-ax`), command lines not cut to a width (`-ww`).
    public static let arguments = ["-axww", "-o", "pid,ppid,user,rss,%cpu,etime,command"]

    public static func read(runner: ProcessRunner) async throws -> [HostProcess] {
        let result = try await runner.run(ps, arguments: arguments)
        guard result.exitCode == 0 else { throw HostProcessesError.failed(result.exitCode, result.stderrText) }
        return parse(String(decoding: result.stdout, as: UTF8.self))
    }

    /// Lines that do not have every column (the header, a blank line) are skipped.
    public static func parse(_ text: String) -> [HostProcess] {
        text.split(whereSeparator: \.isNewline).compactMap { parseLine(Substring($0)) }
    }

    private static func parseLine(_ line: Substring) -> HostProcess? {
        var rest = line[...]
        var fields: [Substring] = []
        // Six columns without spaces, then the command with its own.
        while fields.count < 6 {
            rest = rest.drop(while: \.isWhitespace)
            guard let end = rest.firstIndex(where: \.isWhitespace) else { return nil }
            fields.append(rest[..<end])
            rest = rest[end...]
        }
        let command = rest.drop(while: \.isWhitespace)
        guard let pid = Int32(fields[0]), let ppid = Int32(fields[1]), let rss = Int(fields[3]),
              let cpu = Double(fields[4]), let elapsed = elapsedSeconds(fields[5]), !command.isEmpty else { return nil }
        return HostProcess(pid: pid, ppid: ppid, user: String(fields[2]), rssKiB: rss, cpuPercent: cpu,
                           elapsed: elapsed, command: String(command))
    }

    /// `ps`'s etime: `[[dd-]hh:]mm:ss`.
    static func elapsedSeconds(_ text: Substring) -> Int? {
        var days = 0
        var clock = text
        if let dash = text.firstIndex(of: "-") {
            guard let parsed = Int(text[..<dash]) else { return nil }
            days = parsed
            clock = text[text.index(after: dash)...]
        }
        let parts = clock.split(separator: ":").map { Int($0) }
        guard (2...3).contains(parts.count), !parts.contains(nil) else { return nil }
        let numbers = parts.compactMap { $0 }
        let seconds = numbers.reduce(0) { $0 * 60 + $1 }
        return days * 86_400 + seconds
    }
}

public enum HostProcessesError: Error, Equatable, CustomStringConvertible {
    case failed(Int32, String)

    public var description: String {
        switch self {
        case .failed(let code, let stderr): "ps exited with \(code): \(stderr)"
        }
    }
}
