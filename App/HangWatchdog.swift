import Foundation
import PaddockCore

/// Captures Paddock when its main thread hangs (backlog doc UI, Hang capture; PAD-121). A thread of
/// its own asks the main thread every 2 s; when it has not answered for 6 s, the thread captures
/// `HangCapture` into `~/Library/Logs/Paddock/hangs/<time>/` itself, once per hang. No Swift tasks
/// decide anything here: a stuck main thread or a starved pool must not stop the watchdog.
final class HangWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var clock = HangWatchdogClock(now: Date())
    /// A question is on its way to the main thread and has not been answered.
    private var asking = false
    private var lastFolder: URL?
    private var thread: Thread?
    /// On the main thread, when it answers again after a captured hang: how long, and where the
    /// capture is. Set by `start`, behind the lock like the rest; called only on the main thread.
    private var recovered: (@MainActor (TimeInterval, URL) -> Void)?

    func start(recovered: @escaping @MainActor (TimeInterval, URL) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.recovered = recovered
        guard thread == nil else { return }
        let thread = Thread { [weak self] in
            while let self {
                Thread.sleep(forTimeInterval: HangWatchdogClock.interval)
                self.check()
            }
        }
        thread.name = "paddock-hang-watchdog"
        thread.qualityOfService = .utility
        self.thread = thread
        thread.start()
    }

    private func check() {
        let now = Date()
        let (ask, capture) = lock.withLock { () -> (Bool, Bool) in
            let capture = clock.shouldCapture(at: now)
            let ask = !asking
            asking = true
            return (ask, capture)
        }
        if ask {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.answered() }
            }
        }
        if capture {
            let folder = Self.capture(reason: "the main thread did not answer for \(Int(HangWatchdogClock.stuckAfter)) s")
            lock.withLock { lastFolder = folder }
        }
    }

    @MainActor
    private func answered() {
        let (stuck, folder, recovered) = lock.withLock { () -> (TimeInterval?, URL?, (@MainActor (TimeInterval, URL) -> Void)?) in
            asking = false
            return (clock.answered(at: Date()), lastFolder, self.recovered)
        }
        if let stuck, let folder { recovered?(stuck, folder) }
    }

    /// Captures now and waits for it (on the watchdog's thread, or any thread but the main one).
    /// Paddock's log file says so at once, since the Log page cannot while the main thread hangs.
    static func capture(reason: String) -> URL {
        let folder = folder()
        for entry in AppModel.logEntries("Paddock is not responding (\(reason)); capturing diagnostics into \(folder.path)",
                                         category: .paddock, source: nil, isError: true) {
            LogFile.shared.append(entry)
        }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await run(into: folder, reason: reason)
            done.signal()
        }
        done.wait()
        return folder
    }

    /// Where a capture goes: `~/Library/Logs/Paddock/hangs/<time>/`.
    static func folder() -> URL {
        LogFile.shared.folder.appendingPathComponent("hangs", isDirectory: true)
            .appendingPathComponent(HangCapture.folderName(at: Date()), isDirectory: true)
    }

    /// The capture itself: each command is limited, so one that hangs too cannot hold the rest.
    static func run(into folder: URL, reason: String) async {
        let info = ProcessInfo.processInfo
        await HangCapture(pid: info.processIdentifier, processName: info.processName)
            .capture(into: folder, reason: reason, logFile: LogFile.shared.url,
                     runner: FoundationProcessRunner(timeout: .seconds(60)))
    }
}
