import Foundation

/// What Paddock captures of itself when it hangs or the operator asks (System > Capture
/// Diagnostics): what `mise run hang` captures from outside, without spindump, which needs sudo
/// (backlog doc UI, Hang capture; PAD-121). Each step's output goes to a file of its own; a step
/// that fails is noted in `summary.txt` and the rest go on.
public struct HangCapture: Sendable {
    public struct Step: Sendable, Equatable {
        public let name: String
        /// Where its output goes, in the capture's folder.
        public let file: String
        public let executable: String
        public let arguments: [String]
    }

    public let pid: Int32
    /// The process name, as `log show` matches it ("Paddock" or "Paddock Dev").
    public let processName: String

    public init(pid: Int32, processName: String) {
        self.pid = pid
        self.processName = processName
    }

    public var steps: [Step] {
        let pid = String(pid)
        return [
            // Where every thread is, the main one first: the step that says why it hangs.
            Step(name: "sample (5 s)", file: "sample.txt", executable: "/usr/bin/sample", arguments: [pid, "5"]),
            Step(name: "footprint", file: "footprint.txt", executable: "/usr/bin/footprint", arguments: [pid]),
            Step(name: "vmmap summary", file: "vmmap.txt", executable: "/usr/bin/vmmap", arguments: ["--summary", pid]),
            Step(name: "heap", file: "heap.txt", executable: "/usr/bin/heap", arguments: ["-s", pid]),
            Step(name: "open files", file: "lsof.txt", executable: "/usr/sbin/lsof", arguments: ["-p", pid]),
            Step(name: "system log (10 min)", file: "log-paddock.txt", executable: "/usr/bin/log",
                 arguments: ["show", "--last", "10m", "--style", "compact",
                             "--predicate", "process == \"\(processName.replacingOccurrences(of: "\"", with: ""))\""]),
        ]
    }

    /// A folder per capture, named by when it started.
    public static func folderName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    /// Runs every step into `folder` (created), copies `logFile` (Paddock's own log) there, and
    /// writes `summary.txt`: why, and how each step went. Returns the summary's lines.
    @discardableResult
    public func capture(into folder: URL, reason: String, logFile: URL?, runner: ProcessRunner) async -> [String] {
        let files = FileManager.default
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        var summary = ["Paddock (\(processName), pid \(pid)): \(reason)", "Captured \(Date())"]
        for step in steps {
            do {
                let result = try await runner.run(URL(fileURLWithPath: step.executable), arguments: step.arguments)
                var data = result.stdout
                if !result.stderr.isEmpty { data.append(Data("\n--- stderr ---\n".utf8) + result.stderr) }
                try data.write(to: folder.appendingPathComponent(step.file))
                summary.append("\(step.name): " + (result.exitCode == 0 ? "ok" : "exit \(result.exitCode)"))
            } catch {
                summary.append("\(step.name): failed (\(error))")
            }
        }
        if let logFile {
            do {
                try files.copyItem(at: logFile, to: folder.appendingPathComponent("paddock.log"))
                summary.append("paddock log: ok")
            } catch {
                summary.append("paddock log: failed (\(error))")
            }
        }
        try? Data((summary.joined(separator: "\n") + "\n").utf8).write(to: folder.appendingPathComponent("summary.txt"))
        return summary
    }
}

/// When the watchdog captures (PAD-121): the main thread has not answered for `stuckAfter`, once
/// per hang, and not again within `minimumGap` of the last capture. Pure, so the rule is tested;
/// the thread that asks it lives in the app.
public struct HangWatchdogClock: Sendable {
    /// How often the watchdog asks the main thread: a wake-up every 2 s costs next to nothing.
    public static let interval: TimeInterval = 2
    public static let stuckAfter: TimeInterval = 6
    public static let minimumGap: TimeInterval = 10 * 60

    /// When the main thread last answered.
    public private(set) var lastAnswer: Date
    private var capturedThisHang = false
    private var lastCapture: Date?
    /// When the watchdog last asked: a watchdog that was itself held up (the Mac slept, App Nap)
    /// says nothing about the main thread, so the wait starts over.
    private var lastCheck: Date

    public init(now: Date) {
        lastAnswer = now
        lastCheck = now
    }

    /// The main thread answered. Returns how long it had been stuck when that hang was captured,
    /// so the app can say so; nil otherwise.
    public mutating func answered(at now: Date) -> TimeInterval? {
        defer {
            lastAnswer = now
            capturedThisHang = false
        }
        return capturedThisHang ? now.timeIntervalSince(lastAnswer) : nil
    }

    /// Whether to capture now; true at most once per hang.
    public mutating func shouldCapture(at now: Date) -> Bool {
        defer { lastCheck = now }
        if now.timeIntervalSince(lastCheck) > Self.interval * 3 {
            lastAnswer = now
            return false
        }
        guard !capturedThisHang, now.timeIntervalSince(lastAnswer) >= Self.stuckAfter else { return false }
        if let lastCapture, now.timeIntervalSince(lastCapture) < Self.minimumGap { return false }
        capturedThisHang = true
        lastCapture = now
        return true
    }
}
