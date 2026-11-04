import Foundation

/// One terminal session in a sandbox: the agent (`sbx run --name N`) or a shell
/// (`sbx exec -it N bash`), on a pseudo-terminal; or a login shell on this Mac, in a folder.
///
/// The session outlives any view: it keeps the recent output, so a terminal view that attaches
/// later (after the operator switched projects) replays the screen before going live.
public actor SandboxShellSession {
    public enum Kind: Sendable, Equatable {
        /// The sandbox's agent. Starts the sandbox if it is stopped.
        case agent
        /// An interactive shell inside the sandbox.
        case shell(String)
        /// The operator's login shell on this Mac (not in the sandbox), in `folder`.
        case mac(folder: String, shell: String)

        public static let bash = Kind.shell("bash")
    }

    public enum State: Sendable, Equatable {
        case notStarted
        case running
        case exited(Int32)
    }

    public enum Event: Sendable, Equatable {
        case output(Data)
        case exited(Int32)
    }

    public nonisolated let id = UUID()
    public nonisolated let sandbox: String
    public nonisolated let kind: Kind

    private let sbx: String
    private let sandboxEnvironment: [String: String]
    private let spawner: any PseudoTerminalSpawning
    private let environment: [String: String]
    private let scrollbackLimit: Int

    public private(set) var state: State = .notStarted
    private var process: (any PseudoTerminalProcess)?
    /// The terminal's size as its view last reported it, kept while no process runs: a view lays
    /// out (and reports its size) before the process starts, which then starts at that size.
    private var size = TerminalSize.standard
    /// The current run, so a late task of an earlier run does nothing.
    private var run = 0
    /// After the run's first output: when its size is sent again. `sbx` can miss the start size or
    /// a `SIGWINCH` while it starts (it is not listening yet, or the sandbox is not attached yet),
    /// and the program then draws for another size until the operator resizes the window. The
    /// last send nudges the rows by one and back: a real change at every layer, as the operator's
    /// resize is, so the program inside the sandbox redraws even where the size already matched.
    /// Long enough for a sandbox that is still starting.
    public static let resendAfter: [Duration] = [.seconds(1), .seconds(3), .seconds(8)]
    private let resendSchedule: [Duration]
    private var scrollback = Data()
    /// Whether a view answered the program's queries so far (one was live while it ran).
    private var hasLiveView = false
    /// Views showing the output live now.
    private var liveViews: Set<UUID> = []
    private var subscribers: [UUID: AsyncStream<Event>.Continuation] = [:]

    /// - Parameters:
    ///   - sbx: the absolute path of the `sbx` binary.
    ///   - environment: the environment `sbx` runs with; `TERM` is set for the terminal.
    ///   - sandboxEnvironment: variables the session gets inside the sandbox: an agent session through
    ///     `sbx run -e`, a shell through `env` before it (so an agent started in the shell inherits them,
    ///     PAD-64); not a shell on this Mac.
    public init(
        sandbox: String,
        kind: Kind,
        sbx: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sandboxEnvironment: [String: String] = [:],
        spawner: any PseudoTerminalSpawning = PosixPseudoTerminal(),
        scrollbackLimit: Int = 2 * 1024 * 1024,
        resendAfter: [Duration] = SandboxShellSession.resendAfter
    ) {
        self.sandbox = sandbox
        self.kind = kind
        self.sbx = sbx
        self.sandboxEnvironment = sandboxEnvironment
        self.environment = environment.merging(["TERM": "xterm-256color", "COLORTERM": "truecolor"]) { _, terminal in terminal }
        self.spawner = spawner
        self.scrollbackLimit = scrollbackLimit
        resendSchedule = resendAfter
    }

    /// What runs: `sbx`, or `/bin/sh` for a shell on this Mac.
    public nonisolated var executable: String {
        if case .mac = kind { "/bin/sh" } else { sbx }
    }

    /// The arguments for `executable`. A shell on this Mac changes to its folder first; the folder
    /// and the shell are arguments of the script, never part of it.
    public nonisolated var arguments: [String] {
        switch kind {
        case .agent: ["run", "--name", sandbox] + variables.flatMap { ["-e", $0] }
        case .shell(let shell): ["exec", "-it", sandbox] + (variables.isEmpty ? [] : ["env"] + variables) + [shell]
        case .mac(let folder, let shell): ["-c", #"cd -- "$1" && exec "$2" -l"#, "sh", folder, shell]
        }
    }

    /// `NAME=value` for each sandbox variable, sorted; a name that is not a plain shell name is left out.
    private nonisolated var variables: [String] {
        sandboxEnvironment.sorted { $0.key < $1.key }.compactMap { name, value in
            let plain = name.first.map { $0 == "_" || ($0.isASCII && $0.isLetter) } == true
                && name.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
            return plain ? "\(name)=\(value)" : nil
        }
    }

    /// Starts the process, at the size its view last reported (or `size`). Starting again after it
    /// exited begins a new run; the old output stays in the scrollback above it.
    public func start(size: TerminalSize? = nil) throws {
        guard state != .running else { return }
        if let size { self.size = size }
        let process = try spawner.spawn(executable, arguments: arguments, environment: environment, size: self.size)
        self.process = process
        run += 1
        // A view live now answers the new run's queries; otherwise the next view does.
        hasLiveView = !liveViews.isEmpty
        state = .running
        Task { [run] in await self.pump(process, run: run) }
    }

    /// The scrollback so far, then everything new. Each call gets its own stream.
    public func attach() -> AsyncStream<Event> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        if !scrollback.isEmpty {
            continuation.yield(.output(scrollback))
        }
        if case .exited(let code) = state {
            continuation.yield(.exited(code))
        }
        subscribers[id] = continuation
        continuation.onTermination = { _ in
            Task { await self.detach(id) }
        }
        return stream
    }

    /// A view's attachment: the scrollback so far, whether a view already answered the terminal
    /// queries in it (a view was live while the program ran), and everything new.
    public struct LiveAttachment: Sendable {
        public let id: UUID
        public let scrollback: Data
        /// Then the view replays the scrollback without answering again: a second answer would
        /// reach the running program as input.
        public let answered: Bool
        public let events: AsyncStream<Event>
    }

    public func attachLive() -> LiveAttachment {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        if case .exited(let code) = state {
            continuation.yield(.exited(code))
        }
        subscribers[id] = continuation
        continuation.onTermination = { _ in
            Task { await self.detach(id) }
        }
        return LiveAttachment(id: id, scrollback: scrollback, answered: hasLiveView, events: stream)
    }

    /// The view of `attachment` shows the output live from here on, answering the program's
    /// terminal queries, until its stream ends.
    public func viewWentLive(_ attachment: UUID) {
        liveViews.insert(attachment)
        hasLiveView = true
    }

    public func write(_ data: Data) {
        process?.write(data)
    }

    /// The view's size: passed to the running process, and kept for the next start.
    public func resize(_ size: TerminalSize) {
        self.size = size
        if state == .running {
            process?.resize(size)
        }
    }

    /// Sends the size again (with a `SIGWINCH`, even when it is unchanged); `nudge` sends it one
    /// row shorter first (`resendAfter`).
    private func resendSize(run: Int, nudge: Bool) {
        guard run == self.run, state == .running, let process else { return }
        if nudge, size.rows > TerminalSize.minimum.rows {
            process.resize(TerminalSize(cols: size.cols, rows: size.rows - 1))
        }
        process.resize(size)
    }

    /// Ends the session's process (the sandbox keeps running).
    public func terminate() {
        process?.terminate()
    }

    /// Ends the session's process and waits until it exited, so it cannot start the sandbox again
    /// (`sbx exec` and `sbx run` start a stopped sandbox).
    public func end() async {
        guard state == .running, let process else { return }
        process.terminate()
        _ = await process.waitForExit()
    }

    private func detach(_ id: UUID) {
        subscribers[id] = nil
        liveViews.remove(id)
    }

    private func pump(_ process: any PseudoTerminalProcess, run: Int) async {
        var started = false
        for await chunk in process.output {
            // A shell on this Mac has no sbx between it and its terminal.
            if !started, case .mac = kind {
                started = true
            }
            if !started {
                started = true
                // The first output: the program is starting to draw, at whatever size it read.
                Task { [schedule = resendSchedule] in
                    var waited = Duration.zero
                    for (index, delay) in schedule.enumerated() {
                        try? await Task.sleep(for: delay - waited)
                        waited = delay
                        self.resendSize(run: run, nudge: index == schedule.count - 1)
                    }
                }
            }
            append(chunk)
            broadcast(.output(chunk))
        }
        let code = await process.waitForExit()
        state = .exited(code)
        broadcast(.exited(code))
    }

    private func append(_ chunk: Data) {
        scrollback.append(chunk)
        if scrollback.count > scrollbackLimit {
            scrollback.removeFirst(scrollback.count - scrollbackLimit)
        }
    }

    private func broadcast(_ event: Event) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }
}
