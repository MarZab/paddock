import Foundation
import Testing
@testable import PaddockCore

@Suite("FoundationProcessRunner")
struct ProcessRunnerTests {
    let runner = FoundationProcessRunner()
    let sh = URL(fileURLWithPath: "/bin/sh")

    @Test func capturesStdoutStderrAndExitCode() async throws {
        let result = try await runner.run(sh, arguments: ["-c", "echo out; echo err >&2; exit 3"])
        #expect(String(decoding: result.stdout, as: UTF8.self) == "out\n")
        #expect(result.stderrText == "err\n")
        #expect(result.exitCode == 3)
    }

    @Test func passesStdinWithoutArgv() async throws {
        // How secrets reach sbx: on stdin, never in arguments.
        let result = try await runner.run(sh, arguments: ["-c", "cat"], environment: nil, stdin: Data("s3cret".utf8))
        #expect(String(decoding: result.stdout, as: UTF8.self) == "s3cret")
    }

    @Test func passesEnvironment() async throws {
        // How the gateway token reaches `sbx create -e ANTHROPIC_API_KEY`: in the environment, not argv.
        let result = try await runner.run(sh, arguments: ["-c", "printf %s \"$PADDOCK_TEST\""],
                                          environment: ["PADDOCK_TEST": "from-env", "PATH": "/usr/bin:/bin"], stdin: nil)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "from-env")
    }

    @Test func largeOutputDoesNotDeadlock() async throws {
        let result = try await runner.run(sh, arguments: ["-c", "head -c 1048576 /dev/zero; head -c 1048576 /dev/zero >&2"])
        #expect(result.stdout.count == 1_048_576)
        #expect(result.stderr.count == 1_048_576)
    }

    @Test func endsACommandThatPrintsPastTheCap() async throws {
        // PAD-87: output comes from sandboxes, so it is bounded.
        let capped = FoundationProcessRunner(maxOutputBytes: 100_000, timeout: .seconds(30))
        await #expect(throws: ProcessLimitError.outputTooLarge(100_000)) {
            try await capped.run(sh, arguments: ["-c", "head -c 1048576 /dev/zero; sleep 20"])
        }
        let fits = try await capped.run(sh, arguments: ["-c", "head -c 99999 /dev/zero"])
        #expect(fits.stdout.count == 99_999)
    }

    @Test func endsACommandThatNeverReturns() async throws {
        let impatient = FoundationProcessRunner(timeout: .milliseconds(300))
        await #expect(throws: ProcessLimitError.self) { try await impatient.run(sh, arguments: ["-c", "sleep 20"]) }
    }

    @Test func waitingCommandsHoldNoConcurrencyThreads() async throws {
        // PAD-28: blocked commands used to hold one cooperative thread each, so more of them than
        // CPU cores stalled every other task. These wait for a file (or give up after 10 s).
        let gate = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-gate-\(UUID())")
        defer { try? FileManager.default.removeItem(at: gate) }
        let waitScript = "for i in $(seq 200); do [ -f '\(gate.path)' ] && exit 0; sleep 0.05; done; exit 1"
        let blocked = ProcessInfo.processInfo.activeProcessorCount * 2 + 2

        try await withThrowingTaskGroup(of: Int32.self) { group in
            for _ in 0..<blocked {
                group.addTask { try await runner.run(sh, arguments: ["-c", waitScript]).exitCode }
            }
            try await Task.sleep(for: .milliseconds(300))

            let clock = ContinuousClock()
            let start = clock.now
            let quick = try await runner.run(sh, arguments: ["-c", "echo ok"])
            #expect(String(decoding: quick.stdout, as: UTF8.self) == "ok\n")
            #expect(clock.now - start < .seconds(3))

            FileManager.default.createFile(atPath: gate.path, contents: nil)
            for try await code in group { #expect(code == 0) }
        }
    }

    @Test func cancellingReturnsAtOnceAndEndsTheProcess() async throws {
        // The command says it is up (its pid) and then lives for a minute, so a loaded runner that
        // stalls the test for seconds (13 s on the macOS CI runner, PAD-91) cannot let it end on
        // its own before the cancel: the test waits for the pid instead of a fixed time.
        let started = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-cancel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: started) }
        let task = Task {
            try await runner.run(sh, arguments: ["-c", "echo $$ > '\(started.path)'; exec sleep 60"])
        }
        let pid = try #require(try await Self.poll(for: .seconds(30)) {
            (try? String(contentsOf: started, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        })

        let clock = ContinuousClock()
        let start = clock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        // Well short of the minute the command would take.
        #expect(clock.now - start < .seconds(20))

        // Terminated: the process is gone long before its minute is up.
        let gone = try await Self.poll(for: .seconds(30)) { kill(pid, 0) != 0 ? true : nil }
        #expect(gone == true)
    }

    /// Asks `value` every 50 ms until it answers, for at most `limit`; nil when it never did.
    private static func poll<T>(for limit: Duration, _ value: () -> T?) async throws -> T? {
        let clock = ContinuousClock()
        let end = clock.now + limit
        while clock.now < end {
            if let found = value() { return found }
            try await Task.sleep(for: .milliseconds(50))
        }
        return value()
    }

    @Test func cancelledBeforeStartingNeverRuns() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-never-\(UUID())")
        defer { try? FileManager.default.removeItem(at: marker) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await runner.run(sh, arguments: ["-c", "touch '\(marker.path)'"])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        try await Task.sleep(for: .milliseconds(300))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }
}

@Suite("BinaryLocator")
struct BinaryLocatorTests {
    @Test func searchesFixedDirectoriesBeforeLoginPath() {
        let locator = BinaryLocator(loginPath: "/usr/bin:/opt/homebrew/bin:relative/dir") { $0 == "/opt/homebrew/bin/sbx" || $0 == "/usr/bin/sbx" }
        #expect(locator.searchPath == ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"])
        #expect(locator.locate("sbx")?.path == "/opt/homebrew/bin/sbx")
    }

    @Test func missingBinaryIsNil() {
        let locator = BinaryLocator(loginPath: nil) { _ in false }
        #expect(locator.locate("sbx") == nil)
    }
}
