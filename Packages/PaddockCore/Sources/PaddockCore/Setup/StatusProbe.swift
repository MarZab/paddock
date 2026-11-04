import Foundation

/// What the status bar shows (backlog doc UI). Read-only in M1.
public struct PaddockStatus: Sendable, Equatable {
    public enum Sbx: Sendable, Equatable {
        /// sbx is missing, too old, or failed; the reason is shown as is.
        case unavailable(String)
        case daemonStopped(version: String)
        case running(version: String, sandboxes: Int, running: Int)
    }

    public var dependencies: [DependencyReport]
    public var sbx: Sbx
    /// Every sbx sandbox, Paddock's projects and others alike.
    public var sandboxes: [SbxSandbox] = []
    /// Whether `sbx ls` answered. When it failed, `sandboxes` is empty but says nothing about
    /// which sandboxes exist, so nothing may be dropped because of it.
    public var sandboxesListed = false
    /// Why `sbx ls` failed, when it did.
    public var sandboxesError: String?
    /// Where sbx's state was read from: sandboxd's socket, or the CLI and why.
    public var sbxReadSource: FallbackSbxReads.Source?
    public var llmman: LlmmanHealth
    /// Models llmman has in memory, when it answers.
    public var loadedModels: Int?
    /// When `sbx ls` was asked, so a lifecycle event that came after it wins over its answer.
    public var checkedAt: Date

    public var missingDependencies: [DependencyReport] { dependencies.filter { !$0.isSatisfied } }
}

/// Gathers `PaddockStatus`. One per app; call `shutdown()` before releasing it.
public actor StatusProbe {
    private let runner: any ProcessRunner
    private let home: String
    private let transport: HTTPLlmmanTransport
    private var locator: BinaryLocator?
    private var sbxReads: (sbx: URL, reads: FallbackSbxReads)?

    public init(runner: any ProcessRunner = FoundationProcessRunner(), home: String = NSHomeDirectory()) {
        self.runner = runner
        self.home = home
        self.transport = HTTPLlmmanTransport()
    }

    /// Forgets the login PATH, so "Check again" finds binaries installed since launch.
    public func resetLookup() {
        locator = nil
        sbxReads = nil
    }

    /// Read-only sbx state for the sbx at `sbx`, shared by the whole app: sandboxd's socket while it
    /// works, sbx's CLI otherwise.
    public func reads(for sbx: URL) -> FallbackSbxReads {
        if let sbxReads, sbxReads.sbx == sbx { return sbxReads.reads }
        let reads = FallbackSbxReads.live(runner: runner, sbx: sbx)
        sbxReads = (sbx, reads)
        return reads
    }

    public func refresh() async -> PaddockStatus {
        let locator = await self.lookup()
        let dependencies = await DependencyCheck(locator: locator, runner: runner).check()

        let sbx: PaddockStatus.Sbx
        var sandboxes: [SbxSandbox] = []
        var listed = false
        var listError: String?
        var readSource: FallbackSbxReads.Source?
        var listedAt = Date()
        if let report = dependencies.first(where: { $0.dependency == .sbx }), report.isSatisfied, let path = report.path {
            let url = URL(fileURLWithPath: path)
            let fallback = reads(for: url)
            let service = SbxService(runner: runner, sbx: url, reads: fallback)
            sbx = await Self.sbxState(service)
            if case .running = sbx {
                listedAt = Date()
                do {
                    sandboxes = try await service.sandboxes()
                    listed = true
                } catch {
                    listError = String(describing: error)
                }
            }
            readSource = await fallback.source
        } else {
            sbx = .unavailable("sbx is not installed or too old")
        }

        let api = LlmmanAPI(transport: transport)
        let health = await LlmmanHealthChecker(api: api, runner: runner, home: home).check()
        let loaded = try? await api.loaded().models.count
        return PaddockStatus(dependencies: dependencies, sbx: sbx, sandboxes: sandboxes, sandboxesListed: listed,
                             sandboxesError: listError, sbxReadSource: readSource, llmman: health, loadedModels: loaded, checkedAt: listedAt)
    }

    /// Model names in llmman's store (`/api/tags`), for the New Project sheet; nil when llmman does not answer.
    public func installedModels() async -> [String]? {
        try? await LlmmanAPI(transport: transport).tags().models.map(\.name)
    }

    /// The sbx binary the last refresh found, for the events stream.
    public func sbxPath() async -> URL? {
        let locator = await lookup()
        return locator.locate(Dependency.sbx.id)
    }

    /// Empties llmman's saved prompts. Only on operator request.
    public func clearPromptHistory() throws {
        try LlmmanHealthChecker(api: LlmmanAPI(transport: transport), runner: runner, home: home).clearPromptHistory()
    }

    public func shutdown() async {
        try? await transport.shutdown()
    }

    private func lookup() async -> BinaryLocator {
        if let locator { return locator }
        let found = BinaryLocator(loginPath: await LoginShell.path(runner: runner))
        locator = found
        return found
    }

    static func sbxState(_ sbx: SbxService) async -> PaddockStatus.Sbx {
        do {
            let version = try await sbx.checkedVersion()
            let sandboxes = try await sbx.sandboxes()
            return .running(version: version.client.version, sandboxes: sandboxes.count, running: sandboxes.filter(\.isRunning).count)
        } catch SbxError.daemonNotRunning {
            let version = (try? await sbx.clientVersion()) ?? "?"
            return .daemonStopped(version: version)
        } catch {
            return .unavailable(String(describing: error))
        }
    }
}
