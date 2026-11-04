import Foundation
import Synchronization

/// Long-running processes that report line by line (`sbx events --json`). Like `ProcessRunner`,
/// the only way PaddockCore starts such a process; tests inject a fake.
public protocol LineStreaming: Sendable {
    /// Lines of stdout, without their newlines. Ends when the process exits; a non-zero exit is
    /// an error. Cancelling the consumer terminates the process.
    func lines(_ executable: URL, arguments: [String]) -> AsyncThrowingStream<String, any Error>
}

public struct ProcessExitError: Error, Equatable, CustomStringConvertible {
    public let executable: String
    public let exitCode: Int32

    public var description: String { "\(executable) exited with \(exitCode)" }
}

public struct FoundationLineStreamer: LineStreaming {
    /// Every process a streamer started that has not ended yet, so quitting can end them.
    static let shared = RunningProcesses()

    /// Ends every streamed process still running (watchers, `sbx events`, image builds). Called
    /// when the app quits: a cancelled task would end its process too late, and a process the
    /// app leaves running keeps its counterpart in the sandbox alive (PAD-30). Synchronous.
    public static func terminateAll() {
        shared.terminateAll()
    }

    private let running: RunningProcesses

    /// Standard error joins the lines too (`docker build --progress=plain` writes there); otherwise
    /// it is dropped.
    private let mergesStandardError: Bool
    /// Standard input is a pipe Paddock holds open, written to never, until the process ends; the
    /// kernel closes it when Paddock dies, however it dies. A process that waits for the end of its
    /// input (`sbx exec -i`, which passes it on into the sandbox) learns so that Paddock is gone
    /// (backlog doc Kits, Watchers). Otherwise standard input is empty.
    private let holdsInputOpen: Bool

    public init(mergesStandardError: Bool = false, holdsInputOpen: Bool = false) {
        self.init(mergesStandardError: mergesStandardError, holdsInputOpen: holdsInputOpen, running: Self.shared)
    }

    init(mergesStandardError: Bool = false, holdsInputOpen: Bool = false, running: RunningProcesses) {
        self.mergesStandardError = mergesStandardError
        self.holdsInputOpen = holdsInputOpen
        self.running = running
    }

    public func lines(_ executable: URL, arguments: [String]) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let input = holdsInputOpen ? Pipe() : nil
            process.standardInput = input ?? FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = mergesStandardError ? pipe : FileHandle.nullDevice

            let box = UncheckedStreamProcess(process)
            continuation.onTermination = { _ in
                if box.process.isRunning { box.process.terminate() }
            }
            let tracked = running.add(process)
            do {
                try process.runUnmasked()
            } catch {
                running.remove(tracked)
                try? input?.fileHandleForWriting.close()
                continuation.finish(throwing: error)
                return
            }

            // One blocking reader: lines until EOF, then the exit status.
            let reader = pipe.fileHandleForReading
            DispatchQueue.global(qos: .utility).async {
                var splitter = LineSplitter()
                while true {
                    let chunk = reader.availableData
                    if chunk.isEmpty { break }
                    for line in splitter.append(chunk) { continuation.yield(line) }
                }
                for line in splitter.finish() { continuation.yield(line) }
                // Its output ended, so it is ending: the input goes first. On Linux, Foundation
                // never saw the exit of a child whose input was still held open.
                try? input?.fileHandleForWriting.close()
                box.process.waitUntilExit()
                running.remove(tracked)
                let status = box.process.terminationStatus
                if status == 0 || box.process.terminationReason == .uncaughtSignal {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: ProcessExitError(executable: executable.lastPathComponent, exitCode: status))
                }
            }
        }
    }
}

/// Splits bytes into lines across chunk boundaries. Used by one reader only.
struct LineSplitter {
    private var buffer = Data()

    mutating func append(_ chunk: Data) -> [String] {
        buffer.append(chunk)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }

    mutating func finish() -> [String] {
        defer { buffer.removeAll() }
        return buffer.isEmpty ? [] : [String(decoding: buffer, as: UTF8.self)]
    }
}

/// Processes by a key of their own, behind a lock: streams add and remove them from GCD threads,
/// and the app ends them all from the main thread.
final class RunningProcesses: Sendable {
    private let processes = Mutex<[UUID: UncheckedStreamProcess]>([:])

    func add(_ process: Process) -> UUID {
        let key = UUID()
        processes.withLock { $0[key] = UncheckedStreamProcess(process) }
        return key
    }

    func remove(_ key: UUID) {
        _ = processes.withLock { $0.removeValue(forKey: key) }
    }

    func terminateAll() {
        let all = processes.withLock { Array($0.values) }
        for box in all where box.process.isRunning { box.process.terminate() }
    }

    var count: Int { processes.withLock { $0.count } }
}

/// `Process` is not `Sendable`; the reader waits on it and the cancel callback only stops it.
private struct UncheckedStreamProcess: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}
