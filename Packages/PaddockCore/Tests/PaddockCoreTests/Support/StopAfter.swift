import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension Process {
    /// Ends a program that never ends on its own (a kit's watcher) `seconds` after it started:
    /// SIGTERM first, SIGKILL 2 s later if it is still there. A child started from a Swift worker
    /// thread can inherit a mask that blocks SIGTERM (PAD-30), and its loop then ignored the
    /// terminate: on the macOS CI runner the watcher tests waited for its output forever (PAD-91).
    func stop(after seconds: TimeInterval) {
        let pid = processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [self] in
            guard isRunning else { return }
            terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
                if isRunning { kill(pid, SIGKILL) }
            }
        }
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
