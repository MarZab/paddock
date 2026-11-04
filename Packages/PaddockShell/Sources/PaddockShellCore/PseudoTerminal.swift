import CPaddockPTY
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A terminal size in character cells.
public struct TerminalSize: Sendable, Equatable {
    public var cols: Int
    public var rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = max(cols, 1)
        self.rows = max(rows, 1)
    }

    public static let standard = TerminalSize(cols: 80, rows: 24)

    /// Smaller than this, a size is a view still being laid out (it starts at zero), not a real
    /// terminal. Programs that draw to fit (sbx's dashboard) can crash on one, so it is not sent.
    public static let minimum = TerminalSize(cols: 40, rows: 10)

    public var isUsable: Bool { cols >= Self.minimum.cols && rows >= Self.minimum.rows }
}

/// Starts processes on a pseudo-terminal. Inject a fake in tests.
public protocol PseudoTerminalSpawning: Sendable {
    func spawn(_ executable: String, arguments: [String], environment: [String: String], size: TerminalSize) throws
        -> any PseudoTerminalProcess
}

/// A process running on a pseudo-terminal.
public protocol PseudoTerminalProcess: Sendable {
    /// Everything the process writes. Ends when the terminal closes.
    var output: AsyncStream<Data> { get }
    func write(_ data: Data)
    func resize(_ size: TerminalSize)
    func terminate()
    /// The exit status (128 + signal when killed by one).
    func waitForExit() async -> Int32
}

public struct PseudoTerminalError: Error, Equatable, CustomStringConvertible {
    public let call: String
    public let code: Int32

    public var description: String { "\(call) failed: \(String(cString: strerror(code)))" }
}

/// The real pseudo-terminal: `posix_openpt` and `posix_spawn` (in `CPaddockPTY`), so no code runs
/// between fork and exec. The child gets a new session with the terminal as stdin, stdout, and
/// stderr; on macOS no other file descriptors of the app are inherited.
public struct PosixPseudoTerminal: PseudoTerminalSpawning {
    public init() {}

    public func spawn(_ executable: String, arguments: [String], environment: [String: String], size: TerminalSize) throws
        -> any PseudoTerminalProcess {
        var name = [CChar](repeating: 0, count: 1024)
        let master = paddock_pty_open(&name, name.count)
        guard master >= 0 else { throw PseudoTerminalError(call: "posix_openpt", code: errno) }
        Self.setSize(master, size)

        let argv = CStringArray([executable] + arguments)
        let envp = CStringArray(environment.map { "\($0.key)=\($0.value)" }.sorted())
        var error: Int32 = 0
        let pid = paddock_pty_spawn(executable, argv.pointers, envp.pointers, name, &error)
        guard pid > 0 else {
            close(master)
            throw PseudoTerminalError(call: "posix_spawn", code: error)
        }
        return PosixTerminalProcess(pid: pid, master: master)
    }

    static func setSize(_ fd: Int32, _ size: TerminalSize) {
        _ = paddock_pty_set_size(fd, UInt16(clamping: size.rows), UInt16(clamping: size.cols))
    }
}

/// NUL-terminated C strings that live as long as this value.
private final class CStringArray {
    var pointers: [UnsafeMutablePointer<CChar>?]

    init(_ strings: [String]) {
        pointers = strings.map { strdup($0) } + [nil]
    }

    deinit {
        for pointer in pointers { free(pointer) }
    }
}

/// One child on a pseudo-terminal. The reader thread owns the master side: it reads until EOF and
/// then closes it. Writes and resizes check under a lock that it is still open, so they never touch
/// a descriptor number the system has reused.
final class PosixTerminalProcess: PseudoTerminalProcess, @unchecked Sendable {
    let pid: pid_t
    private let master: Int32
    let output: AsyncStream<Data>
    private let writeQueue = DispatchQueue(label: "paddock.pty.write")
    private let exit = ExitBox()
    private let lock = NSLock()
    private var isClosed = false

    init(pid: pid_t, master: Int32) {
        self.pid = pid
        self.master = master
        var continuation: AsyncStream<Data>.Continuation?
        output = AsyncStream { continuation = $0 }
        let stream = continuation
        let exit = exit
        Thread.detachNewThread { [self] in
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let count = read(master, &buffer, buffer.count)
                if count > 0 {
                    stream?.yield(Data(buffer[0..<count]))
                } else if count < 0 && errno == EINTR {
                    continue
                } else {
                    break  // EOF, or EIO once the child side is closed
                }
            }
            lock.withLock {
                isClosed = true
                close(master)
            }
            stream?.finish()
        }
        Thread.detachNewThread {
            var status: Int32 = 0
            while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
            exit.set(Self.exitCode(status))
        }
    }

    /// Runs `body` with the master descriptor while it is still open.
    private func withOpenMaster(_ body: (Int32) -> Void) {
        lock.withLock {
            if !isClosed { body(master) }
        }
    }

    func write(_ data: Data) {
        writeQueue.async { [self] in
            withOpenMaster { fd in
                data.withUnsafeBytes { raw in
                    guard var pointer = raw.baseAddress else { return }
                    var left = raw.count
                    while left > 0 {
                        let written = Foundation.write(fd, pointer, left)
                        if written < 0 {
                            if errno == EINTR { continue }
                            return
                        }
                        left -= written
                        pointer += written
                    }
                }
            }
        }
    }

    func resize(_ size: TerminalSize) {
        withOpenMaster { PosixPseudoTerminal.setSize($0, size) }
        // The kernel signals the foreground process group; sending it directly as well covers a
        // child that did not get the terminal as its controlling terminal.
        kill(pid, SIGWINCH)
    }

    func terminate() {
        kill(pid, SIGHUP)
        kill(pid, SIGTERM)
    }

    func waitForExit() async -> Int32 {
        await exit.value()
    }

    private static func exitCode(_ status: Int32) -> Int32 {
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }
}

/// The exit status, awaited by any number of callers.
private final class ExitBox: @unchecked Sendable {
    private let lock = NSLock()
    private var code: Int32?
    private var waiters: [CheckedContinuation<Int32, Never>] = []

    func set(_ value: Int32) {
        let pending = lock.withLock {
            code = value
            defer { waiters = [] }
            return waiters
        }
        for waiter in pending { waiter.resume(returning: value) }
    }

    func value() async -> Int32 {
        await withCheckedContinuation { continuation in
            let ready: Int32? = lock.withLock {
                if let code { return code }
                waiters.append(continuation)
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }
}
