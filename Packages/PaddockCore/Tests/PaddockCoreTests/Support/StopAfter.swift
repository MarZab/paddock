import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension Process {
    /// Ends a program that never ends on its own (a kit's watcher) `seconds` after it started:
    /// SIGTERM first, SIGKILL 2 s later if it is still there. The timer is a thread of its own:
    /// on the 3-core macOS CI runner a `DispatchQueue.global().asyncAfter` never ran while the
    /// tests were blocked, so the watchers lived on and their tests waited forever (PAD-91). The
    /// signals go to the pid directly, not through `terminate()` or `isRunning`.
    func stop(after seconds: TimeInterval) {
        let pid = processIdentifier
        let timer = Thread {
            Thread.sleep(forTimeInterval: seconds)
            guard kill(pid, SIGTERM) == 0 else { return }
            Thread.sleep(forTimeInterval: 2)
            kill(pid, SIGKILL)
        }
        timer.name = "paddock-test-stop"
        timer.start()
    }
}

@Suite("Process.stop(after:)")
struct StopAfterTests {
    /// A watcher that ignores SIGTERM, as one with a blocked mask does, still ends and its
    /// output reaches the end.
    @Test func aProgramThatIgnoresTerminateIsKilled() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; echo up; while :; do sleep 0.2; done"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.stop(after: 0.5)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(String(decoding: data, as: UTF8.self) == "up\n")
        #expect(process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL)
    }
}
