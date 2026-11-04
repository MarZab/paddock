import Foundation

/// Output of a finished process.
public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public init(exitCode: Int32, stdout: Data, stderr: Data) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }

    /// What a failed command says: its stderr, then the tail of its stdout when it printed any
    /// (sbx reports a kit hook's output there, not on stderr). Tails are the last `lines` lines.
    public func failureText(lines: Int = 40) -> String {
        let out = String(decoding: stdout, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        guard !out.isEmpty else { return stderrText }
        let tail = out.suffix(lines).joined(separator: "\n")
        return stderrText + (stderrText.hasSuffix("\n") || stderrText.isEmpty ? "" : "\n") + "output:\n" + tail
    }
}

/// The only way PaddockCore starts processes. Tests inject a fake that returns fixtures.
public protocol ProcessRunner: Sendable {
    /// Runs `executable` to completion. `environment` replaces the inherited environment when set.
    /// `stdin` is written and closed before waiting, so secrets never need to go in `arguments`.
    func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]?,
        stdin: Data?
    ) async throws -> ProcessResult
}

extension ProcessRunner {
    public func run(_ executable: URL, arguments: [String]) async throws -> ProcessResult {
        try await run(executable, arguments: arguments, environment: nil, stdin: nil)
    }
}

/// Runs real processes with Foundation's `Process`.
///
/// Nothing here blocks a Swift concurrency thread or a GCD worker: each pipe is read and stdin is
/// written on a thread of its own, and the exit arrives through `terminationHandler`.
/// `Task.detached` would not do, since it runs on the same small cooperative pool; a few stuck
/// commands used to exhaust it and stall every actor in the app (PAD-28). GCD's workers are capped
/// too, and `readabilityHandler` misses EOFs on Linux.
public struct FoundationProcessRunner: ProcessRunner {
    /// Most output (each of stdout and stderr) a command may print, and how long it may run. A
    /// sandbox can make a command print without end or never return, so neither is unbounded (PAD-87).
    /// The default fits the largest file a show tab reads (base64 of `NativeShowPolicy.maxFileBytes`).
    public static let defaultMaxOutputBytes = 64 * 1024 * 1024
    public static let defaultTimeout: Duration = .seconds(15 * 60)

    public let maxOutputBytes: Int
    public let timeout: Duration

    public init(maxOutputBytes: Int = defaultMaxOutputBytes, timeout: Duration = defaultTimeout) {
        self.maxOutputBytes = maxOutputBytes
        self.timeout = timeout
    }

    public func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]?,
        stdin: Data?
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stdinPipe = stdin.map { _ in Pipe() }
        process.standardInput = stdinPipe ?? FileHandle.nullDevice

        let completion = RunCompletion()
        // Set before run(), so an exit that comes first is never missed.
        process.terminationHandler = { completion.exited($0.terminationStatus) }
        let box = UncheckedProcess(process)
        let stdoutReader = stdoutPipe.fileHandleForReading
        let stderrReader = stderrPipe.fileHandleForReading
        let stdinWriter = stdinPipe?.fileHandleForWriting

        // Cancelling the caller returns at once and ends the process, so a command that never
        // returns (or whose exit is never noticed) can be given up.
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard completion.start(continuation) else { return }
                do {
                    try box.process.runUnmasked()
                } catch {
                    completion.fail(error)
                    return
                }
                // Cancelled while starting: the handler found nothing running to end.
                if completion.isCancelled { box.process.terminate() }

                // Ends a command that runs too long; the timer goes when the run finishes.
                let limit = timeout
                let timer = Task {
                    try? await Task.sleep(for: limit)
                    guard !Task.isCancelled else { return }
                    completion.fail(ProcessLimitError.timedOut(limit))
                    if box.process.isRunning { box.process.terminate() }
                }
                completion.setCleanup { timer.cancel() }

                // Drain both pipes concurrently so a full pipe never blocks the child. Past the
                // cap the output is dropped (still drained), and the command is ended.
                let cap = maxOutputBytes
                let exceeded: @Sendable () -> Void = {
                    completion.fail(ProcessLimitError.outputTooLarge(cap))
                    if box.process.isRunning { box.process.terminate() }
                }
                Self.onThread("paddock-stdout") { completion.stdout(Self.readBounded(stdoutReader, limit: cap, exceeded)) }
                Self.onThread("paddock-stderr") { completion.stderr(Self.readBounded(stderrReader, limit: cap, exceeded)) }
                if let stdin, let stdinWriter {
                    Self.onThread("paddock-stdin") {
                        try? stdinWriter.write(contentsOf: stdin)
                        try? stdinWriter.close()
                    }
                }
            }
        } onCancel: {
            completion.cancel()
            if box.process.isRunning { box.process.terminate() }
        }
    }

    private static func readBounded(_ handle: FileHandle, limit: Int, _ exceeded: @Sendable () -> Void) -> Data {
        var data = Data()
        var over = false
        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            if over { continue }
            if data.count + chunk.count > limit {
                over = true
                exceeded()
            } else {
                data.append(chunk)
            }
        }
        return data
    }

    private static func onThread(_ name: String, _ work: @escaping @Sendable () -> Void) {
        let thread = Thread(block: work)
        thread.name = name
        thread.start()
    }
}

/// Why a command was ended before it finished on its own.
public enum ProcessLimitError: Error, Equatable, CustomStringConvertible {
    case outputTooLarge(Int)
    case timedOut(Duration)

    public var description: String {
        switch self {
        case .outputTooLarge(let bytes): "the command printed more than \(bytes / 1024 / 1024) MB and was ended"
        case .timedOut(let limit): "the command ran longer than \(limit.components.seconds) s and was ended"
        }
    }
}

/// Collects one run's output and exit status and resumes the caller once all three are in, or at
/// once with `CancellationError` when the caller is cancelled. Called from GCD threads, Foundation's
/// termination thread, and the cancel handler, so every field is behind the lock.
private final class RunCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProcessResult, any Error>?
    private var stdoutData: Data?
    private var stderrData: Data?
    private var status: Int32?
    private var cancelled = false
    private var done = false
    private var cleanup: (@Sendable () -> Void)?

    /// Runs when the run finishes (or now, when it already has), to stop the timeout timer.
    func setCleanup(_ work: @escaping @Sendable () -> Void) {
        lock.lock()
        if done {
            lock.unlock()
            work()
        } else {
            cleanup = work
            lock.unlock()
        }
    }

    var isCancelled: Bool { lock.withLock { cancelled } }

    /// Stores the continuation; false (and the continuation resumed) when already cancelled.
    func start(_ continuation: CheckedContinuation<ProcessResult, any Error>) -> Bool {
        lock.lock()
        if cancelled {
            done = true
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func stdout(_ data: Data) { update { $0.stdoutData = data } }
    func stderr(_ data: Data) { update { $0.stderrData = data } }
    func exited(_ code: Int32) { update { $0.status = code } }

    func fail(_ error: any Error) { finish(.failure(error)) }

    func cancel() {
        lock.withLock { cancelled = true }
        finish(.failure(CancellationError()))
    }

    private func update(_ change: (RunCompletion) -> Void) {
        lock.lock()
        change(self)
        guard let stdoutData, let stderrData, let status else {
            lock.unlock()
            return
        }
        lock.unlock()
        finish(.success(ProcessResult(exitCode: status, stdout: stdoutData, stderr: stderrData)))
    }

    private func finish(_ result: Result<ProcessResult, any Error>) {
        lock.lock()
        guard !done, let continuation else {
            lock.unlock()
            return
        }
        done = true
        self.continuation = nil
        let work = cleanup
        cleanup = nil
        lock.unlock()
        work?()
        continuation.resume(with: result)
    }
}

/// `Process` is not `Sendable`; it is configured before the run and afterwards only started,
/// checked, and terminated.
private struct UncheckedProcess: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}
