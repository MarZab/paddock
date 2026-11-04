import Foundation
import Synchronization
import Testing
@testable import PaddockCore

@Suite("HostProcesses")
struct HostProcessesTests {
    @Test func parsesPsFixture() throws {
        let processes = HostProcesses.parse(String(decoding: try Fixture.data("host", "ps.txt"), as: UTF8.self))
        #expect(processes.count == 21)
        let shim = try #require(processes.first { $0.pid == 20206 })
        #expect(shim.ppid == 1 && shim.user == "operator" && shim.rssKiB == 3_666_608 && shim.cpuPercent == 85.4)
        #expect(shim.elapsed == 1 * 3600 + 52 * 60 + 7)
        #expect(shim.command.hasPrefix("/opt/homebrew/Caskroom/sbx/0.49.2/Sbx.app/Contents/Helpers/containerd-shim-nerdbox-v1 "))
        #expect(shim.command.contains(" -namespace docker -id "))
        // days, and a command with spaces in its path
        #expect(processes.first { $0.pid == 1 }?.elapsed == 39 * 86_400 + 8 * 3600 + 9 * 60 + 10)
        #expect(processes.first { $0.pid == 2337 }?.command.hasPrefix("/Applications/Google Chrome.app/Contents/") == true)
        #expect(processes.first { $0.pid == 36710 }?.command == "/opt/homebrew/bin/sbx exec paddock-project-a paddock-agent-watch")
    }

    @Test func elapsedFormats() {
        #expect(HostProcesses.elapsedSeconds("00:05") == 5)
        #expect(HostProcesses.elapsedSeconds("17:10") == 1030)
        #expect(HostProcesses.elapsedSeconds("01:57:25") == 7045)
        #expect(HostProcesses.elapsedSeconds("04-07:23:37") == 4 * 86_400 + 26_617)
        #expect(HostProcesses.elapsedSeconds("abc") == nil)
        #expect(HostProcesses.elapsedSeconds("5") == nil)
    }

    @Test func readsThroughTheRunner() async throws {
        let runner = FakeRunner()
        runner.respond(to: HostProcesses.arguments, with: try Fixture.data("host", "ps.txt"))
        #expect(try await HostProcesses.read(runner: runner).count == 21)
        #expect(runner.calls == [HostProcesses.arguments])
    }
}

/// PAD-30: watchers left by an earlier Paddock, on the Mac and in the sandbox.
@Suite("SandboxWatchers")
struct SandboxWatchersTests {
    func row(_ pid: Int32, ppid: Int32 = 1, user: String = "operator", _ command: String) -> HostProcess {
        HostProcess(pid: pid, ppid: ppid, user: user, rssKiB: 86_000, cpuPercent: 0, elapsed: 3600, command: command)
    }

    @Test func runningWatchersOfThisPaddockAreNotLeftovers() throws {
        // In the fixture the watchers' parent is the running Paddock; the four orphaned `sbx`
        // dashboards are the operator's, not Paddock's.
        let processes = HostProcesses.parse(String(decoding: try Fixture.data("host", "ps.txt"), as: UTF8.self))
        #expect(SandboxWatchers.leftovers(in: processes, user: "operator").isEmpty)
    }

    @Test func findsOnlyOrphanedWatcherExecsOfTheUser() {
        let sbx = "/opt/homebrew/bin/sbx"
        let current = SandboxWatchers.arguments(sandbox: "paddock-app", command: "paddock-browser-watch")
        let processes = [
            row(1, "\(sbx) exec paddock-a paddock-browser-watch"),                  // earlier Paddock
            row(2, "\(sbx) exec paddock-a paddock-agent-watch"),                    // earlier Paddock
            row(3, ([sbx] + current).joined(separator: " ")),                        // this version, ps-joined
            row(4, ppid: 900, "\(sbx) exec paddock-a paddock-browser-watch"),       // parent alive
            row(5, user: "someone", "\(sbx) exec paddock-a paddock-browser-watch"), // another user's
            row(6, "\(sbx)"),                                                       // a dashboard
            row(7, "\(sbx) exec paddock-a paddock-browser-watch --captured s f png"),
            row(8, "\(sbx) exec paddock-a bash"),
            row(9, "/usr/bin/other exec paddock-a paddock-browser-watch"),
            row(10, "\(sbx) exec paddock-a sh -c echo paddock-watch paddock-browser-watch extra"),
            row(11, "\(sbx) exec bad;name paddock-agent-watch"),
            row(12, "\(sbx) exec -i paddock-a sh -c b=... paddock-watch paddock-agent-watch net.zabreznik.paddock.dev"),
            row(13, "\(sbx) exec -i paddock-a sh -c b=... paddock-watch paddock-agent-watch bad;owner"),
            row(14, "\(sbx) exec -i paddock-a sh -c b=... paddock-watch paddock-agent-watch")  // before PAD-61
        ]
        #expect(SandboxWatchers.leftovers(in: processes, user: "operator").map(\.pid) == [1, 2, 3, 12, 14])
    }

    @Test func stopsTheLeftoversItFinds() async throws {
        var text = String(decoding: try Fixture.data("host", "ps.txt"), as: UTF8.self)
        let watcher = "/opt/homebrew/bin/sbx exec paddock-project-a paddock-browser-watch"
        text += "23020     1 operator          86000   0.0    01:12:18 \(watcher)\n"
        text += "23021     1 someone           86000   0.0    01:12:18 \(watcher)\n"
        let runner = FakeRunner()
        runner.respond(to: HostProcesses.arguments, with: Data(text.utf8))
        let signalled = Mutex<[Int32]>([])
        let stopped = try await SandboxWatchers.stopLeftovers(runner: runner, user: "operator") { pid in
            signalled.withLock { $0.append(pid) }
            return true
        }
        #expect(stopped.map(\.pid) == [23020])
        #expect(signalled.withLock { $0 } == [23020])
    }

    @Test func theOwnerIsTheBundleIDOrPaddock() {
        #expect(SandboxWatchers.ownerName("net.zabreznik.paddock.dev") == "net.zabreznik.paddock.dev")
        #expect(SandboxWatchers.ownerName(nil) == "paddock")
        #expect(SandboxWatchers.ownerName("a b") == "paddock" && SandboxWatchers.ownerName("") == "paddock")
        #expect(SandboxWatchers.arguments(sandbox: "s", command: "paddock-agent-watch").last == SandboxWatchers.owner)
    }

    @Test func replaceScriptIsOneLine() {
        #expect(!SandboxWatchers.replaceScript.contains("\n"))
    }

    /// Fake watchers in a folder of their own, standing in for /usr/local/bin.
    struct FakeBin {
        let url: URL
        var environment: [String: String] { ["PATH": "\(url.path):/usr/bin:/bin", "PADDOCK_WATCH_BIN": url.path] }
        func path(_ name: String) -> String { url.appendingPathComponent(name).path }

        /// Short sleeps: a killed watcher's sleep lives on, and with it any pipe it inherited from a
        /// test running at the same time.
        init(agentBody: String = "sleep 3") throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-watch-\(UUID())")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for (name, body) in [("paddock-agent-watch", agentBody), ("paddock-browser-watch", "sleep 3")] {
                try "#!/bin/sh\n\(body)\n".write(toFile: path(name), atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path(name))
            }
        }
    }

    /// Runs `sh ARGUMENTS` with no signals blocked, as sbx starts the script in a sandbox. On Linux
    /// `runUnmasked` keeps SIGCHLD blocked, and the script's `wait` needs it.
    static let unmaskedShell = ["-c", "import os, signal, sys; signal.pthread_sigmask(signal.SIG_SETMASK, []); "
        + "os.execv('/bin/sh', ['/bin/sh'] + sys.argv[1:])"]
    static let python = URL(fileURLWithPath: "/usr/bin/python3")

    static func start(_ arguments: [String], environment: [String: String]? = nil, input: Pipe? = nil) throws -> Process {
        let process = Process()
        process.executableURL = python
        process.arguments = unmaskedShell + arguments
        if let environment { process.environment = environment }
        process.standardInput = input ?? FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.runUnmasked()
        return process
    }

    /// Running and not a zombie: Foundation reaps a killed child a little later, so /proc decides.
    static func alive(_ pid: Int32) -> Bool {
        let status = try? String(contentsOfFile: "/proc/\(pid)/status", encoding: .utf8)
        return status.map { !$0.contains("State:\tZ") } ?? false
    }

    /// The children of `parent` whose command line is `cmdline` (arguments joined by NUL).
    static func children(of parent: Int32, cmdline: String) -> [Int32] {
        let pids = (try? FileManager.default.contentsOfDirectory(atPath: "/proc"))?.compactMap { Int32($0) } ?? []
        return pids.filter { pid in
            guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
                  let close = stat.lastIndex(of: ")") else { return false }
            let fields = stat[stat.index(close, offsetBy: 2)...].split(separator: " ")
            guard fields.count > 1, Int32(fields[1]) == parent else { return false }
            return (try? String(contentsOfFile: "/proc/\(pid)/cmdline", encoding: .utf8)) == cmdline
        }
    }

    /// Runs the script on Linux the way `sbx exec` runs it in a sandbox: older watchers of the kind
    /// go, the kit's one-off call and other kinds stay, and the new watcher runs in their place.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/proc/self/cmdline") && FileManager.default.fileExists(atPath: "/usr/bin/python3")))
    func replaceScriptStopsOlderWatchersOfItsKind() async throws {
        let bin = try FakeBin()
        defer { try? FileManager.default.removeItem(at: bin.url) }
        let agent = bin.path("paddock-agent-watch")
        let olderOne = try Self.start([agent])
        let olderTwo = try Self.start([agent])
        let oneOff = try Self.start([agent, "--captured", "s"])
        let otherKind = try Self.start([bin.path("paddock-browser-watch")])
        // PAD-61: this app's earlier watcher goes, another app's (Paddock Dev next to Paddock) stays.
        let ownEarlier = try Self.start([agent, "--for=app.one"])
        let otherApp = try Self.start([agent, "--for=app.two"])
        defer { for process in [olderOne, olderTwo, oneOff, otherKind, ownEarlier, otherApp] where process.isRunning { process.terminate() } }
        try await Task.sleep(for: .milliseconds(200))

        let input = Pipe()
        let wrapper = try Self.start(["-c", SandboxWatchers.replaceScript, SandboxWatchers.label, "paddock-agent-watch", "app.one"],
                                     environment: bin.environment, input: input)
        defer { try? input.fileHandleForWriting.close() }
        try await Task.sleep(for: .milliseconds(500))

        #expect(!Self.alive(olderOne.processIdentifier) && !Self.alive(olderTwo.processIdentifier))
        #expect(Self.alive(oneOff.processIdentifier) && Self.alive(otherKind.processIdentifier))
        #expect(!Self.alive(ownEarlier.processIdentifier) && Self.alive(otherApp.processIdentifier))
        #expect(Self.alive(wrapper.processIdentifier))
        // The new watcher's command line is a watcher's, so the next start replaces it too.
        #expect(Self.children(of: wrapper.processIdentifier, cmdline: "/bin/sh\0\(agent)\0--for=app.one\0").count == 1)
    }

    /// A watcher that `NodeScript`'s header started runs as an absolute node and its path; it is
    /// replaced too, and a one-off call through the same node stays.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/proc/self/cmdline") && FileManager.default.fileExists(atPath: "/usr/bin/python3")))
    func replaceScriptStopsWatchersStartedThroughAnAbsoluteNode() async throws {
        let bin = try FakeBin()
        defer { try? FileManager.default.removeItem(at: bin.url) }
        // Stands in for the node the header found: an interpreter whose path ends in /node.
        let interpreter = bin.url.appendingPathComponent("node-dir")
        try FileManager.default.createDirectory(at: interpreter, withIntermediateDirectories: true)
        let node = interpreter.appendingPathComponent("node").path
        try FileManager.default.createSymbolicLink(atPath: node, withDestinationPath: "/bin/sh")
        let agent = bin.path("paddock-agent-watch")
        let older = try Self.start(["-c", "exec \"$0\" \"$@\"", node, agent])
        let oneOff = try Self.start(["-c", "exec \"$0\" \"$@\"", node, agent, "--captured", "s"])
        defer { for process in [older, oneOff] where process.isRunning { process.terminate() } }
        try await Task.sleep(for: .milliseconds(200))

        let input = Pipe()
        _ = try Self.start(["-c", SandboxWatchers.replaceScript, SandboxWatchers.label, "paddock-agent-watch", "app.one"],
                           environment: bin.environment, input: input)
        defer { try? input.fileHandleForWriting.close() }
        try await Task.sleep(for: .milliseconds(500))
        #expect(!Self.alive(older.processIdentifier))
        #expect(Self.alive(oneOff.processIdentifier))
    }

    /// Paddock gone: its end of the input closes (`sbx exec -i` passes that on), and the watcher stops.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/proc/self/cmdline") && FileManager.default.fileExists(atPath: "/usr/bin/python3")))
    func theWatcherStopsWhenItsInputEnds() async throws {
        let bin = try FakeBin(agentBody: "sleep 5")
        defer { try? FileManager.default.removeItem(at: bin.url) }
        let input = Pipe()
        let wrapper = try Self.start(["-c", SandboxWatchers.replaceScript, SandboxWatchers.label, "paddock-agent-watch", "app.one"],
                                     environment: bin.environment, input: input)
        try await Task.sleep(for: .milliseconds(300))
        let watchers = Self.children(of: wrapper.processIdentifier, cmdline: "/bin/sh\0\(bin.path("paddock-agent-watch"))\0--for=app.one\0")
        let watcher = try #require(watchers.first)
        #expect(Self.alive(watcher))

        try input.fileHandleForWriting.close()
        try await Task.sleep(for: .milliseconds(500))
        #expect(!Self.alive(watcher))
        #expect(!Self.alive(wrapper.processIdentifier))
    }

    /// A watcher that ends by itself ends the stream with its status, though Paddock's input stays
    /// open, so Paddock starts it again.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/python3")))
    func aWatcherThatEndsEndsTheStream() async throws {
        let bin = try FakeBin(agentBody: "echo hello; exit 3")
        defer { try? FileManager.default.removeItem(at: bin.url) }
        var arguments = Array(SandboxWatchers.arguments(sandbox: "unused", command: "paddock-agent-watch").dropFirst(4))
        arguments = Self.unmaskedShell + ["-c", "export PATH=\"$1\" PADDOCK_WATCH_BIN=\"$2\"; shift 2; exec sh \"$@\"", "env",
                     bin.environment["PATH"] ?? "", bin.url.path] + arguments
        let stream = FoundationLineStreamer(holdsInputOpen: true, running: RunningProcesses())
            .lines(Self.python, arguments: arguments)
        var lines: [String] = []
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: ProcessExitError(executable: "python3", exitCode: 3)) {
            for try await line in stream { lines.append(line) }
        }
        #expect(lines == ["hello"])
        #expect(clock.now - start < .seconds(2))
    }
}

@Suite("FoundationLineStreamer quit")
struct LineStreamerQuitTests {
    /// A child must get SIGTERM: Swift's worker threads block it, and a child inherits that.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/proc/self/status")))
    func childrenStartWithSigtermUnblocked() async throws {
        let result = try await FoundationProcessRunner().run(URL(fileURLWithPath: "/bin/sh"),
                                                             arguments: ["-c", "exec grep SigBlk /proc/self/status"])
        let line = String(decoding: result.stdout, as: UTF8.self)
        let hex = try #require(line.split(separator: "\t").last?.trimmingCharacters(in: .whitespacesAndNewlines))
        let blocked = try #require(UInt64(hex, radix: 16))
        #expect(blocked & (1 << (UInt64(SIGTERM) - 1)) == 0)
    }

    @Test func terminateAllEndsRunningStreams() async throws {
        // Its own list of running processes: the app-wide one would end other tests' streams too.
        let running = RunningProcesses()
        let stream = FoundationLineStreamer(running: running)
            .lines(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo up; exec sleep 10"])
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == "up")
        #expect(running.count == 1)

        let clock = ContinuousClock()
        let start = clock.now
        running.terminateAll()
        // Ended by a signal: the stream finishes without an error, at once.
        #expect(try await iterator.next() == nil)
        #expect(clock.now - start < .seconds(2))
        #expect(running.count == 0)
    }
}
