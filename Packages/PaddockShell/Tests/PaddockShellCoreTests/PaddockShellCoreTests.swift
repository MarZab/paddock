import Foundation
import Testing
@testable import PaddockShellCore

/// Collects terminal output until `done` returns true or the timeout passes.
func collect(_ output: AsyncStream<Data>, timeout: Duration = .seconds(5), until done: @escaping @Sendable (String) -> Bool) async -> String {
    await withTaskGroup(of: String?.self) { group in
        group.addTask {
            var text = ""
            for await chunk in output {
                text += String(decoding: chunk, as: UTF8.self)
                if done(text) { return text }
            }
            return text
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first ?? "(timed out)"
    }
}

@Suite("PosixPseudoTerminal")
struct PseudoTerminalTests {
    let pty = PosixPseudoTerminal()

    @Test func childSeesATerminalOfTheGivenSize() async throws {
        let process = try pty.spawn("/bin/sh", arguments: ["-c", "stty size; [ -t 0 ] && [ -t 1 ] && echo is-a-tty; echo done"],
                                    environment: ["PATH": "/usr/bin:/bin"], size: TerminalSize(cols: 100, rows: 30))
        let text = await collect(process.output) { $0.contains("done") }
        #expect(text.contains("30 100"))
        #expect(text.contains("is-a-tty"))
        #expect(await process.waitForExit() == 0)
    }

    @Test func inputReachesTheChild() async throws {
        let process = try pty.spawn("/bin/sh", arguments: ["-c", "read line; echo \"got:$line\""],
                                    environment: ["PATH": "/usr/bin:/bin"], size: .standard)
        process.write(Data("hello\n".utf8))
        let text = await collect(process.output) { $0.contains("got:hello") }
        #expect(text.contains("got:hello"))
    }

    @Test func resizeIsSignalled() async throws {
        let script = "trap 'stty size' WINCH; echo ready; while true; do sleep 0.05; done"
        let process = try pty.spawn("/bin/bash", arguments: ["-c", script], environment: ["PATH": "/usr/bin:/bin"], size: .standard)
        let ready = await collect(process.output) { $0.contains("ready") }
        #expect(ready.contains("ready"))
        process.resize(TerminalSize(cols: 120, rows: 40))
        let resized = await collect(process.output) { $0.contains("40 120") }
        #expect(resized.contains("40 120"))
        process.terminate()
        #expect(await process.waitForExit() > 128)  // ended by a signal
    }

    @Test func exitCodeAndEnvironment() async throws {
        let process = try pty.spawn("/bin/sh", arguments: ["-c", "echo \"term=$TERM\"; exit 7"],
                                    environment: ["TERM": "xterm-256color"], size: .standard)
        let text = await collect(process.output) { $0.contains("term=") && $0.contains("\n") }
        #expect(text.contains("term=xterm-256color"))
        #expect(await process.waitForExit() == 7)
    }

    @Test func missingExecutableIsAnError() {
        #expect(throws: PseudoTerminalError.self) {
            _ = try pty.spawn("/nonexistent/sbx", arguments: [], environment: [:], size: .standard)
        }
    }
}

/// A process whose output the test writes.
final class FakeTerminalProcess: PseudoTerminalProcess, @unchecked Sendable {
    let output: AsyncStream<Data>
    let continuation: AsyncStream<Data>.Continuation
    private let lock = NSLock()
    private var _written = Data()
    private var _sizes: [TerminalSize] = []
    var written: Data { lock.withLock { _written } }
    var sizes: [TerminalSize] { lock.withLock { _sizes } }

    init() {
        (output, continuation) = AsyncStream<Data>.makeStream()
    }

    func emit(_ text: String) { continuation.yield(Data(text.utf8)) }
    func finish() { continuation.finish() }
    func write(_ data: Data) { lock.withLock { _written.append(data) } }
    func resize(_ size: TerminalSize) { lock.withLock { _sizes.append(size) } }
    func terminate() { finish() }
    func waitForExit() async -> Int32 { 0 }
}

final class FakeSpawner: PseudoTerminalSpawning, @unchecked Sendable {
    private let lock = NSLock()
    private var _spawned: [(executable: String, arguments: [String], environment: [String: String], process: FakeTerminalProcess, size: TerminalSize)] = []
    var spawned: [(executable: String, arguments: [String], environment: [String: String], process: FakeTerminalProcess, size: TerminalSize)] {
        lock.withLock { _spawned }
    }

    func spawn(_ executable: String, arguments: [String], environment: [String: String], size: TerminalSize) throws -> any PseudoTerminalProcess {
        let process = FakeTerminalProcess()
        lock.withLock { _spawned.append((executable, arguments, environment, process, size)) }
        return process
    }
}

@Suite("SandboxShellSession")
struct SandboxShellSessionTests {
    func text(_ events: [SandboxShellSession.Event]) -> String {
        events.compactMap { if case .output(let data) = $0 { String(decoding: data, as: UTF8.self) } else { nil } }.joined()
    }

    @Test func theSessionsGetTheirVariablesInTheSandbox() async throws {
        let spawner = FakeSpawner()
        let agent = SandboxShellSession(sandbox: "paddock-app", kind: .agent, sbx: "/sbx", environment: [:],
                                        sandboxEnvironment: ["PADDOCK_TAB": "T1", "A": "b", "bad name": "x"], spawner: spawner)
        // PAD-64: a shell gets them through env, so an agent started in it reports its tab
        let shell = SandboxShellSession(sandbox: "paddock-app", kind: .bash, sbx: "/sbx", environment: [:],
                                        sandboxEnvironment: ["PADDOCK_TAB": "T1"], spawner: spawner)
        try await agent.start()
        try await shell.start()
        #expect(spawner.spawned.map(\.arguments) == [["run", "--name", "paddock-app", "-e", "A=b", "-e", "PADDOCK_TAB=T1"],
                                                    ["exec", "-it", "paddock-app", "env", "PADDOCK_TAB=T1", "bash"]])
    }

    @Test func agentAndShellCommands() async throws {
        let spawner = FakeSpawner()
        let agent = SandboxShellSession(sandbox: "paddock-app", kind: .agent, sbx: "/opt/homebrew/bin/sbx", environment: ["HOME": "/Users/op"], spawner: spawner)
        let shell = SandboxShellSession(sandbox: "paddock-app", kind: .bash, sbx: "/opt/homebrew/bin/sbx", environment: [:], spawner: spawner)
        try await agent.start()
        try await shell.start()
        #expect(spawner.spawned.map(\.arguments) == [["run", "--name", "paddock-app"], ["exec", "-it", "paddock-app", "bash"]])
        #expect(spawner.spawned.first?.executable == "/opt/homebrew/bin/sbx")
        #expect(spawner.spawned.first?.environment["TERM"] == "xterm-256color")
        #expect(spawner.spawned.first?.environment["HOME"] == "/Users/op")
    }

    @Test func aShellOnThisMacStartsInTheFolderWithoutSbx() async throws {
        let spawner = FakeSpawner()
        let folder = "/Users/op/My Project; rm -rf ~"
        let mac = SandboxShellSession(sandbox: "paddock-app", kind: .mac(folder: folder, shell: "/bin/zsh"), sbx: "/sbx",
                                      environment: [:], spawner: spawner)
        try await mac.start()
        // the folder and shell are arguments of the script, never part of it
        #expect(spawner.spawned.first?.executable == "/bin/sh")
        #expect(spawner.spawned.first?.arguments == ["-c", #"cd -- "$1" && exec "$2" -l"#, "sh", folder, "/bin/zsh"])
        var tabs = TerminalTabs()
        #expect(tabs.add(.mac).title == "mac" && tabs.add(.mac).title == "mac 2")
    }

    @Test func liveAttachKeepsTheScrollbackApart() async throws {
        let spawner = FakeSpawner()
        let session = SandboxShellSession(sandbox: "paddock-app", kind: .agent, sbx: "/sbx", spawner: spawner)
        try await session.start()
        let process = try #require(spawner.spawned.first?.process)
        process.emit("\u{1B}[c")  // a terminal query, answered when it was live
        try await Task.sleep(for: .milliseconds(50))
        let first = await session.attachLive()
        #expect(first.scrollback == Data("\u{1B}[c".utf8))
        #expect(!first.answered)  // no view was live: the first one answers the replayed query
        process.emit("new")
        var iterator = first.events.makeAsyncIterator()
        #expect(await iterator.next() == .output(Data("new".utf8)))
        await session.viewWentLive(first.id)
        #expect(await session.attachLive().answered)  // a later view does not answer again
        // Run again while that view is live: it answers the new run's queries itself.
        process.finish()
        try await Task.sleep(for: .milliseconds(100))
        try await session.start()
        #expect(await session.attachLive().answered)
    }

    @Test func endEndsTheProcessBeforeReturning() async throws {
        let spawner = FakeSpawner()
        let session = SandboxShellSession(sandbox: "paddock-app", kind: .bash, sbx: "/sbx", spawner: spawner)
        await session.end()  // nothing runs yet
        try await session.start()
        await session.end()
        var events = await session.attach().makeAsyncIterator()
        #expect(await events.next() == .exited(0))
    }

    @Test func aSizeReportedBeforeTheStartIsTheStartSize() async throws {
        // A new tab's view lays out before its process starts; that size used to be dropped.
        let spawner = FakeSpawner()
        let session = SandboxShellSession(sandbox: "paddock-app", kind: .bash, sbx: "/sbx", spawner: spawner)
        await session.resize(TerminalSize(cols: 132, rows: 40))
        try await session.start()
        #expect(spawner.spawned.first?.size == TerminalSize(cols: 132, rows: 40))
        // And a run started again (Run Again) starts at the last size too.
        await session.resize(TerminalSize(cols: 100, rows: 30))
        #expect(spawner.spawned.first?.process.sizes == [TerminalSize(cols: 100, rows: 30)])
    }

    /// Short, so the tests do not wait for the real schedule.
    static let resends: [Duration] = [.milliseconds(100), .milliseconds(300)]

    @Test func aSizeChangedWhileStartingIsSentAgainOnceTheProgramIsUp() async throws {
        // sbx can miss a SIGWINCH while it starts; the program then drew for the start size.
        let spawner = FakeSpawner()
        let session = SandboxShellSession(sandbox: "paddock-app", kind: .agent, sbx: "/sbx", spawner: spawner,
                                          resendAfter: Self.resends)
        await session.resize(TerminalSize(cols: 100, rows: 30))
        try await session.start()
        let process = try #require(spawner.spawned.first?.process)
        let final = TerminalSize(cols: 132, rows: 40)
        await session.resize(final)
        process.emit("drawn\n")
        try await Task.sleep(for: .milliseconds(200))
        #expect(process.sizes == [final, final])
        try await Task.sleep(for: .milliseconds(300))
        #expect(process.sizes == [final, final, TerminalSize(cols: 132, rows: 39), final])
    }

    @Test func theStartSizeIsSentAgainAndNudgedOnceTheProgramIsUp() async throws {
        // sbx can miss the start size too: the agent drew for a smaller terminal until the
        // operator resized the window (PAD-57).
        let spawner = FakeSpawner()
        let session = SandboxShellSession(sandbox: "paddock-app", kind: .agent, sbx: "/sbx", spawner: spawner,
                                          resendAfter: Self.resends)
        let size = TerminalSize(cols: 132, rows: 40)
        await session.resize(size)
        try await session.start()
        let process = try #require(spawner.spawned.first?.process)
        try await Task.sleep(for: .milliseconds(200))
        #expect(process.sizes.isEmpty)  // nothing before the program's first output
        process.emit("drawn\n")
        try await Task.sleep(for: .milliseconds(500))
        #expect(process.sizes == [size, TerminalSize(cols: 132, rows: 39), size])
    }

    @Test func anEarlierRunsResendsDoNothing() async throws {
        let spawner = FakeSpawner()
        let session = SandboxShellSession(sandbox: "paddock-app", kind: .agent, sbx: "/sbx", spawner: spawner,
                                          resendAfter: Self.resends)
        try await session.start()
        let first = try #require(spawner.spawned.first?.process)
        first.emit("drawn\n")
        first.finish()
        try await Task.sleep(for: .milliseconds(50))
        try await session.start()
        try await Task.sleep(for: .milliseconds(500))
        #expect(first.sizes.isEmpty)
        #expect(spawner.spawned.last?.process.sizes.isEmpty == true)  // the new run has no output yet
    }

    @Test func aShellOnThisMacIsNotResized() async throws {
        let spawner = FakeSpawner()
        let session = SandboxShellSession(sandbox: "paddock-app", kind: .mac(folder: "/src/app", shell: "/bin/zsh"),
                                          sbx: "/sbx", spawner: spawner, resendAfter: Self.resends)
        try await session.start()
        let process = try #require(spawner.spawned.first?.process)
        process.emit("% ")
        try await Task.sleep(for: .milliseconds(500))
        #expect(process.sizes.isEmpty)
    }

    @Test func aLateViewReplaysTheScrollbackThenGoesLive() async throws {
        let spawner = FakeSpawner()
        let session = SandboxShellSession(sandbox: "paddock-app", kind: .agent, sbx: "/sbx", spawner: spawner)
        try await session.start()
        let process = try #require(spawner.spawned.first?.process)
        process.emit("hello ")
        process.emit("world\n")
        try await Task.sleep(for: .milliseconds(100))

        var events: [SandboxShellSession.Event] = []
        let stream = await session.attach()
        process.emit("live\n")
        process.finish()
        for await event in stream {
            events.append(event)
            if case .exited = event { break }
        }
        #expect(text(events) == "hello world\nlive\n")
        #expect(events.last == .exited(0))
        #expect(await session.state == .exited(0))
    }

    @Test func scrollbackIsBounded() async throws {
        let spawner = FakeSpawner()
        let session = SandboxShellSession(sandbox: "paddock-app", kind: .agent, sbx: "/sbx", spawner: spawner, scrollbackLimit: 8)
        try await session.start()
        let process = try #require(spawner.spawned.first?.process)
        process.emit("0123456789abcdef")
        try await Task.sleep(for: .milliseconds(100))
        let stream = await session.attach()
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .output(Data("89abcdef".utf8)))
    }

    @Test func inputAndResizeGoToTheProcess() async throws {
        let spawner = FakeSpawner()
        let session = SandboxShellSession(sandbox: "paddock-app", kind: .bash, sbx: "/sbx", spawner: spawner)
        try await session.start()
        await session.write(Data("ls\r".utf8))
        await session.resize(TerminalSize(cols: 132, rows: 50))
        let process = try #require(spawner.spawned.first?.process)
        #expect(process.written == Data("ls\r".utf8))
        #expect(process.sizes == [TerminalSize(cols: 132, rows: 50)])
    }
}

@Suite("TerminalSize")
struct TerminalSizeTests {
    @Test func aViewNotLaidOutYetIsNotATerminalSize() {
        #expect(!TerminalSize(cols: 0, rows: 0).isUsable)  // clamped to 1x1
        #expect(!TerminalSize(cols: 120, rows: 3).isUsable)
        #expect(TerminalSize.standard.isUsable)
        #expect(TerminalSize(cols: 40, rows: 10).isUsable)
    }
}

@Suite("TerminalTabs")
struct TerminalTabsTests {
    @Test func aTabHoldsWhatItsProgramIsDoing() {
        var tabs = TerminalTabs()
        let agent = tabs.add(.agent)
        #expect(tabs.tabs.first?.activity == TerminalTabs.HostTab.Activity.none)
        tabs.setActivity(.attention, for: agent.id)
        #expect(tabs.tabs.first?.activity == .attention)
        tabs.setActivity(.busy, for: UUID())
        #expect(tabs.tabs.first?.activity == .attention)
    }

    @Test func titlesPerKindFillGaps() {
        var tabs = TerminalTabs()
        let agent = tabs.add(.agent)
        let shell = tabs.add(.shell)
        let shell2 = tabs.add(.shell)
        let agent2 = tabs.add(.agent)
        #expect(tabs.tabs.map(\.title) == ["agent", "shell", "shell 2", "agent 2"])
        #expect(tabs.selection == agent2.id)
        tabs.close(shell.id)
        #expect(tabs.add(.shell).title == "shell")
        _ = agent
        _ = shell2
    }

    @Test func theProgramSetsTheTabsTitleAndIcon() {
        var tabs = TerminalTabs()
        let agent = tabs.add(.agent)
        #expect(tabs.tabs[0].label.symbol == nil && tabs.tabs[0].label.text == "agent")
        tabs.setTerminalTitle("✳ Claude Code", for: agent.id)
        #expect(tabs.tabs[0].label.symbol == "✳" && tabs.tabs[0].label.text == "Claude Code")
        tabs.setTerminalTitle("Fixing tests", for: agent.id)
        #expect(tabs.tabs[0].label.symbol == nil && tabs.tabs[0].label.text == "Fixing tests")
        tabs.setTerminalTitle("  ", for: agent.id)
        #expect(tabs.tabs[0].label.text == "agent")  // an empty title brings back the tab's own
        #expect(tabs.add(.agent).title == "agent 2")  // unique titles do not depend on what programs set
    }

    @Test func titlesFromTheSandboxAreSanitized() {
        // Control characters, a right-to-left override, and a zero-width space are dropped.
        #expect(TerminalTitle.sanitized("a\u{07}b\u{202E}c\u{200B}d\n") == "abcd")
        #expect(TerminalTitle.sanitized("\u{1B}") == nil)
        let long = String(repeating: "x", count: 100)
        #expect(TerminalTitle.sanitized(long)?.count == TerminalTitle.maxLength)
        #expect(TerminalTitle.split("⠂ Working").symbol == "⠂")
        #expect(TerminalTitle.split("~/src").symbol == nil)
        #expect(TerminalTitle.split("a b").symbol == nil)
    }

    @Test func closingSelectsTheNeighbourOrNothing() {
        var tabs = TerminalTabs()
        let first = tabs.add(.agent)
        let second = tabs.add(.shell)
        tabs.close(second.id)
        #expect(tabs.selection == first.id)
        tabs.close(first.id)
        #expect(tabs.selection == nil && tabs.selected == nil)  // back to the host's first tab
    }

    @Test func theHostOffersTabsOfItsOwn() {
        var tabs = TerminalTabs()
        let shell = tabs.add(.shell)
        tabs.selectHost("browser")
        #expect(tabs.selection == nil && tabs.shownHostTab(offered: ["browser"]) == "browser")
        // a tab the host no longer offers falls back to its first
        #expect(tabs.shownHostTab(offered: []) == nil)
        tabs.selection = shell.id
        #expect(tabs.shownHostTab(offered: ["browser"]) == nil)
        tabs.selectHost(nil)
        #expect(tabs.selection == nil && tabs.shownHostTab(offered: ["browser"]) == nil)
    }

    @Test func aTabMovesToAnotherBarWithItsIdentity() throws {
        var left = TerminalTabs(), right = TerminalTabs()
        let agent = left.add(.agent), shell = left.add(.shell)
        let taken = left.take(shell.id)
        let moved = try #require(taken)
        #expect(left.tabs.map(\.id) == [agent.id] && left.selection == agent.id)
        right.insert(moved)
        #expect(right.tabs == [shell] && right.selection == shell.id)
        right.insert(moved)  // already there
        #expect(right.tabs.count == 1)
        let agent2 = left.add(.agent)
        let taken2 = left.take(agent2.id)
        right.insert(try #require(taken2), before: .session(shell.id))
        #expect(right.arranged(hosts: []) == [.session(agent2.id), .session(shell.id)])
        #expect(left.take(UUID()) == nil)
    }

    @Test func hostTabsMixWithSessionsInOneOrder() {
        var tabs = TerminalTabs()
        let agent = tabs.add(.agent)
        // a host tab that just appeared comes last
        #expect(tabs.arranged(hosts: ["web1"]) == [.session(agent.id), .host("web1")])
        let shell = tabs.add(.shell)
        // not placed yet: still last (the host places a tab when it appears, so later tabs follow it)
        #expect(tabs.arranged(hosts: ["web1"]) == [.session(agent.id), .session(shell.id), .host("web1")])
        // dragged between sessions, it stays there
        tabs.move(.host("web1"), onto: .session(agent.id), hosts: ["web1"])
        #expect(tabs.arranged(hosts: ["web1"]) == [.host("web1"), .session(agent.id), .session(shell.id)])
        tabs.move(.session(shell.id), onto: .host("web1"), hosts: ["web1"])
        #expect(tabs.arranged(hosts: ["web1"]) == [.session(shell.id), .host("web1"), .session(agent.id)])
        // a host tab the host no longer has drops out; a placed one arrives where it was put
        #expect(tabs.arranged(hosts: []) == [.session(shell.id), .session(agent.id)])
        #expect(!tabs.isPlaced(.host("web2")))
        tabs.place(.host("web2"), before: .session(agent.id))
        #expect(tabs.isPlaced(.host("web2")))
        #expect(tabs.arranged(hosts: ["web1", "web2"]) == [.session(shell.id), .host("web1"), .host("web2"), .session(agent.id)])
    }

    @Test func dragPayloadsNameSessionsAndHostTabs() {
        let id = UUID()
        #expect(TerminalTabs.Item(payload: TerminalTabs.Item.session(id).payload) == .session(id))
        #expect(TerminalTabs.Item(payload: TerminalTabs.Item.host("browser:show-1").payload) == .host("browser:show-1"))
        #expect(TerminalTabs.Item(payload: "something else") == nil)
    }

    @Test func aDraggedTabTakesTheTargetsPlace() {
        var tabs = TerminalTabs()
        let a = tabs.add(.agent), b = tabs.add(.shell), c = tabs.add(.shell)
        let ids = { tabs.arranged(hosts: []).map { item -> UUID? in if case .session(let id) = item { id } else { nil } } }
        tabs.move(.session(c.id), onto: .session(a.id), hosts: [])
        #expect(ids() == [c.id, a.id, b.id])
        tabs.move(.session(c.id), onto: .session(b.id), hosts: [])
        #expect(ids() == [a.id, b.id, c.id])
        tabs.move(.session(a.id), onto: .session(a.id), hosts: [])
        tabs.move(.session(UUID()), onto: .session(a.id), hosts: [])
        #expect(ids() == [a.id, b.id, c.id])
        #expect(tabs.selection == c.id)  // moving does not change the selection
    }
}

struct TerminalThemeTests {
    @Test func everyThemeIsCompleteAndItsOwn() {
        #expect(TerminalTheme.all.allSatisfy { $0.ansi.count == 16 })
        #expect(Set(TerminalTheme.all.map(\.id)).count == TerminalTheme.all.count)
        #expect(Set(TerminalTheme.all.map(\.background)).count == TerminalTheme.all.count)
    }

    @Test func anUnknownThemeIsTheTerminalsOwnColors() {
        #expect(TerminalTheme.named("nord")?.name == "Nord")
        #expect(TerminalTheme.named("gone") == nil && TerminalTheme.named(nil) == nil)
        #expect(TerminalTheme.RGB(0x2E3440) == TerminalTheme.named("nord")?.background)
        #expect(TerminalTheme.RGB(0x123456).green == 0x34)
    }
}
