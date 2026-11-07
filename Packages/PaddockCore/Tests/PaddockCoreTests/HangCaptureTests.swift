import Foundation
import Testing
@testable import PaddockCore

@Suite("HangCapture")
struct HangCaptureTests {
    @Test func stepsAreWhatMiseRunHangTakesWithoutSudo() {
        let capture = HangCapture(pid: 4711, processName: "Paddock Dev")
        #expect(capture.steps.map(\.name) == ["sample (5 s)", "footprint", "vmmap summary", "heap", "open files", "system log (10 min)"])
        #expect(capture.steps.allSatisfy { $0.arguments.contains("4711") || $0.executable == "/usr/bin/log" })
        #expect(!capture.steps.contains { $0.executable.contains("spindump") || $0.executable.contains("sudo") })
        #expect(capture.steps.last?.arguments.last == "process == \"Paddock Dev\"")
        // A name cannot break out of the predicate.
        #expect(HangCapture(pid: 1, processName: "a\" OR 1==1").steps.last?.arguments.last == "process == \"a OR 1==1\"")
    }

    @Test func eachStepGoesToItsFileAndAFailureDoesNotStopTheRest() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-hang-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-hang-log-\(UUID()).log")
        try Data("a log line\n".utf8).write(to: log)
        defer { try? FileManager.default.removeItem(at: log) }

        let runner = FakeRunner()
        runner.respond(to: ["42", "5"], with: Data("Call graph:\n".utf8))
        runner.respond(to: ["42"], with: Data(), exitCode: 1, stderr: "footprint: no access")
        runner.succeedByDefault = true

        let summary = await HangCapture(pid: 42, processName: "Paddock")
            .capture(into: folder, reason: "the main thread did not answer for 6 s", logFile: log, runner: runner)

        #expect(runner.calls.count == 6)
        #expect(try String(contentsOf: folder.appendingPathComponent("sample.txt"), encoding: .utf8) == "Call graph:\n")
        #expect(try String(contentsOf: folder.appendingPathComponent("footprint.txt"), encoding: .utf8)
            .contains("footprint: no access"))
        #expect(try String(contentsOf: folder.appendingPathComponent("paddock.log"), encoding: .utf8) == "a log line\n")
        #expect(summary.contains("footprint: exit 1"))
        #expect(summary.contains("sample (5 s): ok") && summary.contains("paddock log: ok"))
        let written = try String(contentsOf: folder.appendingPathComponent("summary.txt"), encoding: .utf8)
        #expect(written.hasPrefix("Paddock (Paddock, pid 42): the main thread did not answer for 6 s\n"))
    }

    @Test func foldersAreNamedByTime() {
        let date = Date(timeIntervalSince1970: 0)
        #expect(HangCapture.folderName(at: date).count == "yyyyMMdd-HHmmss".count)
    }
}

@Suite("HangWatchdogClock")
struct HangWatchdogClockTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    /// The seconds after `start` at which the watchdog, checking every 2 s from `from` to `to`,
    /// would capture.
    private func captures(_ clock: inout HangWatchdogClock, from: Int, to: Int) -> [Int] {
        stride(from: from, through: to, by: 2).filter { clock.shouldCapture(at: start + TimeInterval($0)) }
    }

    @Test func capturesOnceAfterSixSecondsAndSaysHowLongOnRecovery() {
        var clock = HangWatchdogClock(now: start)
        let captured = captures(&clock, from: 2, to: 60)
        #expect(captured == [6])
        let stuck = clock.answered(at: start + 61)
        #expect(stuck == 61)
        // A quick answer after that says nothing.
        let next = clock.answered(at: start + 63)
        #expect(next == nil)
    }

    @Test func aShortStallIsNoHang() {
        var clock = HangWatchdogClock(now: start)
        let early = captures(&clock, from: 2, to: 4)
        let quiet = clock.answered(at: start + 5)
        #expect(early.isEmpty && quiet == nil)
        let later = captures(&clock, from: 6, to: 12)
        #expect(later == [12])
    }

    @Test func notAgainWithinTenMinutes() {
        var clock = HangWatchdogClock(now: start)
        let first = captures(&clock, from: 2, to: 6)
        #expect(first == [6])
        _ = clock.answered(at: start + 7)
        let second = captures(&clock, from: 8, to: 20)
        #expect(second.isEmpty)
        // Nothing was captured, so recovery from that one says nothing.
        let quiet = clock.answered(at: start + 21)
        #expect(quiet == nil)
        _ = captures(&clock, from: 22, to: 600)
        _ = clock.answered(at: start + 601)
        let third = captures(&clock, from: 602, to: 612)
        #expect(third == [608])
    }

    @Test func aWatchdogThatWasAsleepStartsOver() {
        var clock = HangWatchdogClock(now: start)
        // The Mac slept an hour: the watchdog's next check is late, which is no hang.
        let afterSleep = captures(&clock, from: 3600, to: 3600)
        #expect(afterSleep.isEmpty)
        let stuck = captures(&clock, from: 3602, to: 3610)
        #expect(stuck == [3606])
    }
}
