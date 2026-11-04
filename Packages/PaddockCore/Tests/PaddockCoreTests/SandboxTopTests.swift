import Foundation
import Testing
@testable import PaddockCore

/// PAD-32: what runs in a sandbox, from `SandboxTop`'s scripts. The fixtures are real output from a
/// Paddock sandbox (an 18-CPU microVM), the process one taken while `yes` kept one CPU busy.
@Suite("SandboxTop")
struct SandboxTopTests {
    func fixture(_ name: String) throws -> String {
        String(decoding: try Fixture.data("sandbox", name), as: UTF8.self)
    }

    @Test func parsesTheSummary() throws {
        let sample = SandboxTop.parse(try fixture("top-summary-1.txt"))
        #expect(sample.cpus == 18 && sample.pageSize == 16384)
        #expect(sample.load == [0.16, 0.27, 0.66])
        #expect(sample.memoryTotalKiB == 33_270_800 && sample.memoryAvailableKiB == 31_820_384)
        #expect(sample.memoryUsedKiB == 33_270_800 - 31_820_384)
        #expect(sample.diskTotalKiB == 20_466_256 && sample.diskUsedKiB == 4_822_568)
        #expect(sample.cpu == CPUTimes(total: 84758 + 89592 + 97162 + 20_735_805 + 1081 + 12624, idle: 20_735_805 + 1081))
        #expect(sample.processes.isEmpty)
        // One reading: CPU use needs the one before.
        #expect(sample.cpuBusy() == nil)
    }

    @Test func cpuUseIsTheDifferenceBetweenSummaries() throws {
        let first = SandboxTop.parse(try fixture("top-summary-1.txt"))
        let second = SandboxTop.parse(try fixture("top-summary-2.txt"))
        let busy = try #require(second.cpuBusy(since: first.cpu))
        // 14 of 3618 ticks were not idle.
        #expect(abs(busy - 14.0 / 3618.0) < 0.000_1)
    }

    @Test func parsesProcessesWithTheirCPUInTheSecond() throws {
        let sample = SandboxTop.parse(try fixture("top-process.txt"))
        #expect(sample.processes.count == 8)
        let busiest = try #require(sample.processes.first)
        #expect(busiest.name == "yes" && busiest.command == "yes")
        // 102 ticks while each CPU ticked 1824 / 18.
        #expect(abs(busiest.cores - 102.0 / (1824.0 / 18.0)) < 0.001)
        #expect(busiest.residentBytes > 0 && busiest.residentBytes % 16384 == 0)
        let claude = try #require(sample.processes.first { $0.name == "claude" })
        #expect(claude.command == "claude --dangerously-skip-permissions")
        #expect(claude.residentBytes > 100 * 1024 * 1024)
        // Busiest first.
        #expect(sample.processes.map(\.cores) == sample.processes.map(\.cores).sorted(by: >))
        let busy = try #require(sample.cpuBusy())
        #expect(busy > 0.05 && busy < 0.08)
    }

    @Test func statNamesWithSpacesAndParentheses() throws {
        let stat = try #require(ProcessStat("42 (Web (Content) 1) S 7 42 42 0 -1 0 0 0 0 0 30 12 0 0 20 0 1 0 100 4096 250 rest"))
        #expect(stat.pid == 42 && stat.name == "Web (Content) 1" && stat.ppid == 7)
        #expect(stat.cpuTicks == 42 && stat.residentPages == 250)
        #expect(ProcessStat("garbage") == nil)
    }

    @Test func lineOrderAndMissingToolsDoNotMatter() {
        // No df, no getconf: those lines are missing, the rest still reads.
        let sample = SandboxTop.parse("N 4\nM 1000 400\n--- 1\ncpu  1 0 1 8 0 0 0 0 0 0\nnoise\n")
        #expect(sample.cpus == 4 && sample.pageSize == 4096 && sample.diskTotalKiB == 0 && sample.memoryUsedKiB == 600)
        #expect(sample.cpu == CPUTimes(total: 10, idle: 8))
    }

    /// Command lines from a busy sandbox (paddock-app, 2026-10-28), paths shortened.
    @Test func groupsProcessesByApp() {
        func process(_ pid: Int32, _ name: String, _ cores: Double, _ command: String) -> SandboxProcess {
            SandboxProcess(pid: pid, ppid: 1, name: name, cores: cores, residentBytes: 100, command: command)
        }
        let chrome = "/opt/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-linux-arm64/chrome-headless-shell"
        let processes = [
            process(1, "workerd", 0.92, "/p/node_modules/.pnpm/@cloudflare+workerd-linux-arm64/bin/workerd serve --binary"),
            process(2, "chrome-headless", 0.67, "\(chrome) --type=renderer"),
            process(3, "chrome-headless", 0.58, "\(chrome) --type=gpu-process"),
            process(4, "node-MainThread", 0.36, "node /p/packages/admin/node_modules/.bin/../../node_modules/.pnpm/vite/bin/vite.js --port 8788"),
            process(5, "node-MainThread", 0.28, "/home/agent/.local/share/mise/installs/node/26.12.1/bin/node /p/node_modules/.bin/wrangler dev"),
            process(6, "claude", 0.01, "claude"),
            process(7, "kworker", 0, "[kworker]"),
        ]
        let apps = SandboxTop.apps(processes)
        #expect(apps.map(\.name) == ["chrome-headless-shell", "workerd", "vite", "wrangler", "claude", "kworker"])
        #expect(apps[0].processes.count == 2 && abs(apps[0].cores - 1.25) < 0.000_1)
    }

    @Test func pollsOnlyARunningSandboxWithNoActionUnderWay() {
        #expect(SandboxTop.mayPoll(.running, actionRunning: false))
        #expect(!SandboxTop.mayPoll(.running, actionRunning: true))
        for state: SandboxStates.State? in [.stopped, .other("stopping"), .other("starting"), nil] {
            #expect(!SandboxTop.mayPoll(state, actionRunning: false))
        }
    }

    @Test func readsThroughSbxExec() async throws {
        let runner = FakeRunner()
        let sbx = URL(fileURLWithPath: "/opt/homebrew/bin/sbx")
        let arguments = SandboxTop.arguments(sandbox: "paddock-app", script: SandboxTop.summaryScript)
        runner.respond(to: arguments, with: try Fixture.data("sandbox", "top-summary-1.txt"))
        let sample = try await SandboxTop.read(SandboxTop.summaryScript, in: "paddock-app", sbx: sbx, runner: runner)
        #expect(sample.cpus == 18)
        runner.respond(to: arguments, with: Data(), exitCode: 1, stderr: "no such sandbox")
        await #expect(throws: SandboxTopError.failed("paddock-app", 1, "no such sandbox")) {
            try await SandboxTop.read(SandboxTop.summaryScript, in: "paddock-app", sbx: sbx, runner: runner)
        }
    }

    @Test func scriptsUseOnlyPlainTools() {
        // AC: works without ps; the tools named in the doc, nothing else.
        for script in [SandboxTop.summaryScript, SandboxTop.processScript] {
            #expect(!script.contains("ps ") && !script.contains("awk") && !script.contains("grep"))
        }
        #expect(SandboxTop.arguments(sandbox: "paddock-app", script: "true") == ["exec", "paddock-app", "sh", "-c", "true"])
    }
}
