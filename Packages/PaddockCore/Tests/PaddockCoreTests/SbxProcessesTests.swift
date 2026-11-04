import Foundation
import Synchronization
import Testing
@testable import PaddockCore

/// PAD-31: sbx's processes on the Mac, from a real `ps` capture (four forgotten dashboards).
@Suite("SbxProcesses")
struct SbxProcessesTests {
    func classified() throws -> [Int32: SbxProcessKind] {
        let processes = HostProcesses.parse(String(decoding: try Fixture.data("host", "ps.txt"), as: UTF8.self))
        return Dictionary(uniqueKeysWithValues: SbxProcesses.classify(processes, user: "operator").map { ($0.process.pid, $0.kind) })
    }

    @Test func sortsTheCaptureByKind() throws {
        let kinds = try classified()
        for pid: Int32 in [90476, 91574, 93238, 93979] { #expect(kinds[pid] == .orphanedTool) }
        #expect(kinds[81351] == .daemon)
        #expect(kinds[81365] == .llmman)
        #expect(kinds[36710] == .watcher && kinds[36711] == .watcher)
        // the live dashboard and what it started
        #expect(kinds[20191] == .toolInUse && kinds[20203] == .toolInUse && kinds[19782] == .toolInUse)
        #expect(kinds[20206] == .sandboxVM(containerID: "be318788758086599d590834809dee7ca4e056b58aea3f437dc5a21bfd4cd1ab"))
        #expect(kinds[19786] == .sandboxVM(containerID: "2dd33fce1ab79f42f07ed0a9f5a78588d7c44ed4ec8a742bc14d56d878c7d067"))
        // not sbx's: Paddock itself, Docker Desktop's VM, Chrome, WindowServer (another user), launchd
        for pid: Int32 in [36688, 29192, 2337, 405, 1, 1306, 37253] { #expect(kinds[pid] == nil) }
    }

    @Test func onlyOrphansAndLeftoverWatchersAreStoppable() {
        #expect(SbxProcessKind.orphanedTool.isStoppable && SbxProcessKind.leftoverWatcher.isStoppable)
        for kind: SbxProcessKind in [.watcher, .toolInUse, .daemon, .llmman, .sandboxVM(containerID: "x"), .helper("y")] {
            #expect(!kind.isStoppable)
        }
    }

    @Test func stopsOnlyWhatIsStillTheSameOrphan() async throws {
        let text = String(decoding: try Fixture.data("host", "ps.txt"), as: UTF8.self)
        let all = SbxProcesses.classify(HostProcesses.parse(text), user: "operator")
        let chosen = all.filter { [90476, 91574, 81351, 20206].contains($0.process.pid) }
        // Meanwhile 91574 ended and its pid went to something else.
        let later = text.replacingOccurrences(of: "91574     1 operator         125344   7.0 04-07:11:46 /opt/homebrew/bin/sbx",
                                              with: "91574     1 operator         125344   7.0 04-07:11:46 /usr/bin/other")
        let runner = FakeRunner()
        runner.respond(to: HostProcesses.arguments, with: Data(later.utf8))
        let signalled = Mutex<[Int32]>([])
        let stopped = try await SbxProcesses.stop(chosen, runner: runner, user: "operator") { pid in
            signalled.withLock { $0.append(pid) }
            return true
        }
        // the daemon and the VM are never stopped; the reused pid is left alone
        #expect(stopped.map(\.process.pid) == [90476])
        #expect(signalled.withLock { $0 } == [90476])
    }
}
