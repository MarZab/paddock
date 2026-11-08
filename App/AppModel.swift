import AppKit
import Foundation
import Observation
import PaddockCore
import PaddockShellCore

/// App-wide state (backlog doc UI). All logic lives in PaddockCore; this only holds what the views show.
@Observable
@MainActor
final class AppModel {
    private(set) var status: PaddockStatus?
    private(set) var isRefreshing = false
    /// The status button's popover with every check, dependencies included.
    var showsStatusChecks = false
    var showsNewProject = false
    /// The last failed operator action, shown in the status popover. Each one also goes to `errorLog`.
    private(set) var lastError: String? {
        get { currentError }
        set {
            if let newValue, newValue != currentError {
                appendLog(newValue, source: errorSource, isError: true)
                errorCount += 1
            }
            currentError = newValue
        }
    }
    private var currentError: String?
    /// What the error being set came from, for the Log (`fail(_:in:)`).
    private var errorSource: String?

    /// Sets `lastError`, with what it came from (a project's sandbox) for the Log's source column.
    func fail(_ message: String, in source: String) {
        errorSource = source
        lastError = message
        errorSource = nil
    }
    /// Errors from reads the app does by itself (the timer, events), by what was read: the next
    /// read of the same kind that works clears its error, so one sbx recovers from (a 503 after
    /// sleep) does not stay in the status popover.
    private var readErrors: [ReadKind: String] = [:]

    enum ReadKind: Hashable {
        case checks, sandboxes, snapshots
        case snapshot(String)
    }

    /// A failed background read. The same message again for the same kind is not logged again
    /// until that read worked (PAD-97: two projects failing in turn each logged every time).
    private func readFailed(_ kind: ReadKind, _ message: String) {
        guard readErrors[kind] != message else { return }
        readErrors[kind] = message
        lastError = message
    }

    private func readWorked(_ kinds: ReadKind...) {
        for kind in kinds {
            if let error = readErrors.removeValue(forKey: kind), error == currentError { currentError = nil }
        }
    }
    /// Errors so far this session; the status button flashes when it grows.
    private(set) var errorCount = 0
    /// Every error the status popover showed this session and what long work (a create) did,
    /// oldest first (the Log window). Also appended to `LogFile`, which outlives a restart.
    private(set) var errorLog: [LogEntry] = []

    let paths = PaddockPaths(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory())
    private(set) var appConfig = AppConfig()
    /// Problems with Paddock's config (unknown keys are listed, not fatal).
    private(set) var configProblems: [String] = []
    private(set) var projects = ProjectList()
    /// Project files that could not be loaded; each is shown, the rest still load.
    private(set) var projectProblems: [String] = []
    /// Live from `sbx events`; nil until the first replay finished.
    private(set) var sandboxStates: SandboxStates? {
        didSet { syncBrowserWatchers() }
    }
    /// llmman's installed models, for the New Project sheet.
    private(set) var installedModels: [String]?
    /// What each project's sbx command in flight is doing, for the spinner's tooltip.
    private(set) var activities: [String: String] = [:]
    /// Projects with an sbx command in flight.
    var busy: Set<String> { Set(activities.keys) }
    /// Ports with a running gateway listener, by project.
    private(set) var gatewayPorts: [String: Int] = [:]
    /// The gateway's metadata log (never bodies), newest last.
    private(set) var gatewayLog: [GatewayLogEntry] = []
    private var gatewayHost: GatewayHost?
    /// Terminal sessions per project, kept while the app runs.
    private(set) var terminals: [String: ProjectTerminals] = [:]
    /// The sbx binary found by the last refresh.
    private(set) var sbxPath: String?
    /// What sbx reports per sandbox (any sandbox, project or not): ports and its own rules.
    /// Read on demand and on `sandbox.ports` and `policy.network` events.
    private(set) var snapshots: [String: SandboxSnapshot] = [:]
    /// `sbx policy ls --json`, for the per-sandbox denies Paddock proposes.
    private(set) var globalRules: [SbxPolicyRule] = []

    /// Its runner also serves every sbx read (`probe.reads(for:)`): those end after `readTimeout`.
    private let probe = StatusProbe(runner: FoundationProcessRunner(timeout: AppModel.readTimeout))
    private var refreshLoop: Task<Void, Never>?
    private var eventsLoop: Task<Void, Never>?
    private var approvalsLoop: Task<Void, Never>?
    private let notifier = ApprovalNotifier()
    /// When each sandbox's rules were last read because of its network events (see watchEvents).
    private var rulesReadAt: [String: Date] = [:]
    private static let rulesReread: TimeInterval = 30
    /// Dependencies already reported missing, so the status checks open once per problem.
    private var reportedMissing: Set<String> = []

    /// Between the system's willSleep and its full wake. Dark wakes (Power Nap) run the app while
    /// sbx answers 503 or "not signed in"; the timed reads wait for the full wake (PAD-97).
    private var systemAsleep = false

    static let refreshInterval: Duration = .seconds(10)
    /// Background reads (snapshots) give up after this, not the 15 min a create may take (PAD-97).
    static let readTimeout: Duration = .seconds(90)
    static let eventsRetry: Duration = .seconds(3)

    private var projectDirectory: ProjectDirectory { ProjectDirectory(path: paths.projects) }

    func start() {
        guard refreshLoop == nil else { return }
        hangWatchdog.start { [weak self] stuck, folder in
            self?.appendLog("Paddock did not respond for \(Int(stuck)) s; diagnostics are in \(folder.path)", isError: true)
        }
        voice.app = self
        loadFiles()
        notifier.start()
        notifier.onAnswer = { [weak self] id, optionID in
            guard let self, let approval = self.approvals.first(where: { $0.id == id }),
                  let project = self.project(named: approval.sandboxName) else { return }
            if optionID == "block" {
                self.block(approval, for: project)
            } else if let option = approval.options.first(where: { $0.id == optionID }) {
                self.respond(to: approval, with: option, for: project)
            }
        }
        notifier.onOpen = { [weak self] sandbox in
            self?.requestedSelection = .project(sandbox)
            NSApp.activate()
        }
        gatewayHost = GatewayHost(models: appConfig.models) { entry in
            Task { @MainActor [weak self] in self?.record(entry) }
        }
        Task { await syncGateways() }
        // Agent and shell processes end with the app, and so do the streams it follows (watchers,
        // `sbx events`): left running, a watcher keeps its twin in the sandbox alive (PAD-30). The
        // sandboxes keep running.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                for terminals in self?.terminals.values.map({ $0 }) ?? [] { terminals.terminateAll() }
                FoundationLineStreamer.terminateAll()
            }
        }
        // Files edited by hand (project files, `sbxenv.yaml`, `paddock.yaml`) are read again when
        // the app comes back to the front, not on a timer.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.loadFiles()
                self?.showOnScreen()
            }
        }
        // An agent that finishes while Paddock is in the background was not looked at (PAD-63).
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showOnScreen() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemAsleep = true }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.systemAsleep = false
                Task { await self.refresh() }
            }
        }
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                if self?.systemAsleep == false { await self?.refresh() }
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
        hostProcessesLoop = Task { [weak self] in
            while !Task.isCancelled {
                if self?.systemAsleep == false { await self?.readHostProcesses() }
                try? await Task.sleep(for: Self.hostProcessesInterval)
            }
        }
    }

    /// Reads `paddock.yaml`, the project files, and each project's `sbxenv.yaml`: at launch, on
    /// Refresh, and when the app comes to the front.
    func loadFiles() {
        paths.secure()
        reloadConfig()
        let loaded = projectDirectory.load()
        if loaded.projects != projects { projects = loaded.projects }
        let problems = loaded.problems.map(\.description)
        if problems != projectProblems { projectProblems = problems }
        readProjectFiles()
    }

    /// Reads `paddock.yaml` again, so sections edited by hand apply without a restart. Called
    /// whenever its sections are about to be used.
    func reloadConfig() {
        do {
            let (config, unknownKeys) = try AppConfig.load(atPath: paths.appConfig)
            if config != appConfig { appConfig = config }
            let problems = unknownKeys.map { "paddock.yaml: unknown key \($0)" }
            if problems != configProblems { configProblems = problems }
        } catch {
            // Keep the last good config; show why the file was not used.
            let problems = ["paddock.yaml was not loaded: \(String(describing: error))"]
            if problems != configProblems { configProblems = problems }
        }
    }

    /// Each check's number: a newer one (Refresh) takes over from one that is stuck.
    private var checkGeneration = 0
    private static let checkTimeout: Duration = .seconds(30)

    func refresh() async {
        checkGeneration += 1
        let generation = checkGeneration
        isRefreshing = true
        let probe = self.probe
        let next: PaddockStatus
        do {
            next = try await Deadline.result(within: Self.checkTimeout) { await probe.refresh() }
        } catch {
            // Stuck (an sbx call that does not return): give up on it, keep the last status.
            // Asleep, or cancelled: not worth a log line.
            if generation == checkGeneration, systemAsleep || error is CancellationError {
                isRefreshing = false
            } else if generation == checkGeneration {
                isRefreshing = false
                readFailed(.checks, "The checks did not finish: \(String(describing: error)); try Refresh in the status popover")
            }
            return
        }
        // A newer check started meanwhile: its answer counts, not this one's.
        guard generation == checkGeneration else { return }
        readWorked(.checks)
        if let error = next.sandboxesError {
            if error != status?.sandboxesError { readFailed(.sandboxes, "Could not list the sandboxes (sbx ls): \(error)") }
        } else if next.sandboxesListed {
            readWorked(.sandboxes)
        }
        status = next
        isRefreshing = false
        // Sandboxes listed for the first time are projects whose files were not read yet.
        readProjectFiles(onlyMissing: true)

        let missing = Set(next.missingDependencies.map(\.id))
        if !missing.subtracting(reportedMissing).isEmpty {
            showsStatusChecks = true
        }
        reportedMissing = missing

        if case .running = next.sbx, let sbx = await probe.sbxPath() {
            // `sbx ls` is the truth for which sandboxes exist and their state, unless an event is newer.
            if next.sandboxesListed, var states = sandboxStates {
                states.reconcile(with: next.sandboxes, listedAt: next.checkedAt)
                if states != sandboxStates { sandboxStates = states }
            }
            sbxPath = sbx.path
            if !checkedLeftoverWatchers {
                checkedLeftoverWatchers = true
                await stopLeftoverWatchers()
            }
            syncBrowserWatchers()
            if eventsLoop == nil { watchEvents(sbx: sbx) }
            if approvalsLoop == nil { watchApprovals(sbx: sbx) }
            // Sandboxes that appeared since the last refresh get read once.
            await refreshAllSnapshots(onlyMissing: true)
        }
    }

    /// The Refresh button: project files, Paddock's config, sbx's sandboxes, and every sandbox's ports and rules.
    func reloadAll() async {
        loadFiles()
        await refresh()
        await refreshAllSnapshots()
    }

    /// Follows `sbx events`, reconnecting when the stream ends. Each connection starts from a fresh
    /// replay, which is published once sbx says the replay is complete.
    private func watchEvents(sbx: URL) {
        let probe = self.probe
        eventsLoop = Task { [weak self] in
            while !Task.isCancelled {
                var states = SandboxStates()
                // The replay is the whole network log; each live event updates one entry.
                var log = SbxPolicyLog(allowed: [], blocked: [])
                var replayed = false
                do {
                    for try await event in await probe.reads(for: sbx).events() {
                        states.apply(event)
                        let change = log.apply(event)
                        if replayed, let entry = self?.timeline.record(event, change: change) {
                            self?.appendLog(entry.logLine, category: .sandbox, source: entry.sandbox)
                        }
                        if event.isSyncComplete || (replayed && change != .none) {
                            replayed = true
                            self?.receive(log)
                        }
                        // The same as in refresh(), or this copy would bring back a gone sandbox or an old state.
                        if let status = self?.status, status.sandboxesListed {
                            states.reconcile(with: status.sandboxes, listedAt: status.checkedAt)
                        }
                        if states.isSynced {
                            self?.sandboxStates = states
                        }
                        // Ports and rules are not in the events, so these events trigger a re-read.
                        // Starting a sandbox republishes its ports, so lifecycle events count too.
                        // Network events come with every connection; they re-read the rules (which
                        // an approval may have changed) at most every `rulesReread` seconds.
                        if states.isSynced, let name = event.sandboxName, event.action != "deleted", let self {
                            if [.sandboxPorts, .sandboxLifecycle].contains(event.kind) || self.rulesAreStale(name, after: event) {
                                await self.refreshSnapshot(name)
                            }
                        }
                        // The project list comes from `sbx ls`, so a sandbox it does not list yet
                        // (or still lists after it was deleted) re-reads it instead of waiting.
                        if states.isSynced, event.kind == .sandboxLifecycle, let name = event.sandboxName, let self {
                            let listed = self.sandboxes.contains { $0.name == name }
                            if listed == (event.action == "deleted") { await self.refresh() }
                        }
                    }
                } catch {
                    // The stream ended (daemon restart, sbx update); try again shortly.
                }
                // Until the next replay, the log is read again with the rules.
                self?.logIsLive = false
                try? await Task.sleep(for: Self.eventsRetry)
            }
        }
    }

    /// A network event for `name`: whether its rules were read long enough ago to read them again.
    private func rulesAreStale(_ name: String, after event: SbxEvent) -> Bool {
        guard event.kind == .policyNetwork else { return false }
        let now = Date()
        if let last = rulesReadAt[name], now.timeIntervalSince(last) < Self.rulesReread { return false }
        rulesReadAt[name] = now
        return true
    }

    /// The network log built from the events: the Network page's activity, as it happens.
    private func receive(_ log: SbxPolicyLog) {
        logIsLive = true
        guard log != networkLog else { return }
        networkLog = log
        activity = log.activity
    }

    /// Follows the approval requests: from sandboxd's stream as they come, or every few seconds
    /// through sbx's CLI.
    private func watchApprovals(sbx: URL) {
        let probe = self.probe
        approvalsLoop = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    for try await list in await probe.reads(for: sbx).approvalUpdates() {
                        self?.receive(list)
                    }
                } catch {
                    // As with the events: try again shortly.
                }
                try? await Task.sleep(for: Self.eventsRetry)
            }
        }
    }

    private func receive(_ list: [SbxApproval]) {
        if list != approvals { approvals = list }
        notifier.update(allProjects.flatMap { approvalRequests(for: $0) })
    }

    /// What happened in each sandbox since Paddock started watching (its Info's Recent Activity).
    private(set) var timeline = ActivityTimeline()
    /// Whether the network log comes from the events right now (then it is not read again).
    private(set) var logIsLive = false

    /// From the events stream; for a sandbox it has no state for, what `sbx ls` last reported.
    func state(of project: Project) -> SandboxStates.State? {
        state(ofSandbox: project.name)
    }

    func loadInstalledModels() async {
        installedModels = await probe.installedModels()
    }

    /// Validates and saves a new project. Throws what the sheet shows.
    /// `writesFiles`: also writes `sbxenv.yaml` and a kit for it into the folder (New Project's
    /// "Create sbxenv.yaml"); the project is kept when that fails, and the status bar says why.
    func addProject(_ draft: ProjectDraft, writesFiles: Bool = false) throws {
        reloadConfig()
        let policy = FolderPolicy(home: NSHomeDirectory(), paddockConfigDirectory: paths.configDirectory)
        let sandboxes = Set(sandboxStates?.states.keys.map { $0 } ?? [])
        let project = try NewProject.make(draft, app: appConfig, existing: projects, sandboxes: sandboxes, folderPolicy: policy)
        try projectDirectory.save(project)
        try projects.insert(project)
        if writesFiles {
            do {
                try writeSandboxFiles(for: project)
            } catch {
                fail("\(project.name) was added, but its sbxenv.yaml was not written: \(String(describing: error))", in: project.name)
            }
        }
        Task { await syncGateways() }
    }

    /// Forgets a project that has no sandbox. Its folder is not touched.
    func removeProject(_ project: Project) {
        do {
            try projectDirectory.delete(named: project.name)
            projects.remove(named: project.name)
            lastError = nil
        } catch {
            fail("Could not remove \(project.name): \(error.localizedDescription)", in: project.name)
        }
        Task { await syncGateways() }
    }

    // MARK: - Sandboxes

    enum SandboxAction: String {
        case create, start, stop, remove

        var activity: String {
            switch self {
            case .create: "Creating the sandbox"
            case .start: "Starting the sandbox"
            case .stop: "Stopping the sandbox"
            case .remove: "Removing the sandbox"
            }
        }
    }

    /// Runs one sbx action for a project; errors show in the status popover. `then` runs after it
    /// succeeded.
    func perform(_ action: SandboxAction, on project: Project, then: (@MainActor () -> Void)? = nil) {
        guard withSaved(project, { self.perform(action, on: $0, then: then) }) else { return }
        guard activities[project.name] == nil else { return }
        activities[project.name] = action.activity
        Task {
            var succeeded = false
            defer {
                activities[project.name] = nil
                // After the activity ended, so `then` can start one of its own.
                if succeeded { then?() }
            }
            do {
                guard let sbx = await probe.sbxPath() else { throw AppError("sbx is not installed") }
                reloadConfig()
                let runner = ProjectRunner(sbx: SbxService(runner: FoundationProcessRunner(), sbx: sbx, reads: await probe.reads(for: sbx)), paths: paths,
                                         log: activityLog(for: project.name))
                switch action {
                case .create:
                    let created = try await runner.create(project, app: appConfig, models: await probe.installedModels(),
                                                          projectFolders: projectFolders, progress: activityReporter(for: project.name))
                    recordCreated(created)
                case .start: try await runner.start(project, app: appConfig, models: await probe.installedModels())
                case .stop:
                    // An open terminal (`sbx exec`, `sbx run`) would start the sandbox again.
                    await terminals[project.name]?.endAll()
                    try await runner.stop(project)
                case .remove:
                    closeTerminals(of: project.name)
                    try await runner.remove(project)
                }
                lastError = nil
                succeeded = true
            } catch {
                fail("Could not \(action.rawValue) \(project.name): \(String(describing: error))", in: project.name)
            }
            // sbx's list, in case the events missed the change (or it failed halfway).
            await refresh()
            await syncGateways()
        }
    }

    func isBusy(_ project: Project) -> Bool { activities[project.name] != nil }

    /// How far to take a project down, mildest first (the title bar's stop and remove button).
    enum Teardown: CaseIterable, Identifiable {
        case stop, removeSandbox, removeProject

        var id: Self { self }

        var title: String {
            switch self {
            case .stop: "Stop"
            case .removeSandbox: "Remove Sandbox"
            case .removeProject: "Remove Project"
            }
        }

        var systemImage: String {
            switch self {
            case .stop: "stop.fill"
            case .removeSandbox: "trash"
            case .removeProject: "folder.badge.minus"
            }
        }
    }

    /// The steps the project can take now, mildest first; the first is the button's own action.
    /// Stop needs a running sandbox, Remove Sandbox a sandbox, and Remove Project a project file.
    func teardownSteps(for project: Project) -> [Teardown] {
        let state = state(of: project)
        return Teardown.allCases.filter { step in
            switch step {
            case .stop: state == .running
            case .removeSandbox: state != nil
            case .removeProject: isSaved(project)
            }
        }
    }

    /// Takes the project down to `goal` in one go: stops a running sandbox, removes it, and forgets
    /// the project, as far as the goal goes. Each step starts after the one before it succeeded.
    func tearDown(_ project: Project, to goal: Teardown) {
        let forget: @MainActor () -> Void = { [weak self] in
            if goal == .removeProject { self?.removeProject(project) }
        }
        let remove: @MainActor () -> Void = { [weak self] in
            guard goal != .stop else { return }
            self?.perform(.remove, on: project, then: forget)
        }
        switch state(of: project) {
        case .running?: perform(.stop, on: project, then: remove)
        case nil: forget()
        default: remove()
        }
    }

    /// Shows a long step as the project's activity while its action runs.
    private func activityReporter(for name: String) -> @Sendable (String) async -> Void {
        { text in await self.showActivity(text, for: name) }
    }

    /// Only while the action runs, so a late report never brings a finished spinner back.
    private func showActivity(_ text: String, for name: String) {
        if activities[name] != nil { activities[name] = text }
    }

    /// Every project's folder: a local kit inside one is refused (`KitSelection.ordered`).
    private var projectFolders: [String] { projects.projects.map(\.folder) }

    /// After a create: keeps the kits and the `sbxenv.yaml` the sandbox was created from in its
    /// project file.
    private func recordCreated(_ created: Project) {
        guard let updated = projects.project(named: created.name)?.recordingCreate(created) else { return }
        do {
            try projectDirectory.save(updated)
            projects.remove(named: updated.name)
            try projects.insert(updated)
        } catch {
            fail("Could not save what \(created.name)'s sandbox was created from: \(String(describing: error))", in: created.name)
        }
    }

    /// What the project's spinner is waiting for.
    func activity(of project: Project) -> String? { activities[project.name] }

    // MARK: - Ports

    private func runner() async throws -> ProjectRunner {
        guard let sbx = await probe.sbxPath() else { throw AppError("sbx is not installed") }
        return ProjectRunner(sbx: SbxService(runner: FoundationProcessRunner(), sbx: sbx, reads: await probe.reads(for: sbx)), paths: paths,
                             log: activityLog(for: nil))
    }

    /// For background reads: the same, with `readTimeout` instead of a create's 15 minutes.
    private func readRunner() async throws -> ProjectRunner {
        guard let sbx = await probe.sbxPath() else { throw AppError("sbx is not installed") }
        return ProjectRunner(sbx: SbxService(runner: FoundationProcessRunner(timeout: Self.readTimeout), sbx: sbx,
                                             reads: await probe.reads(for: sbx)),
                             paths: paths, log: activityLog(for: nil))
    }

    // MARK: - Sync

    /// Every sbx sandbox; Paddock's projects and the others.
    var sandboxes: [SbxSandbox] { status?.sandboxes ?? [] }

    /// Every project: the saved project files, and every other sbx sandbox as a project built from
    /// its actual state. One list; a sandbox's file is written the first
    /// time something changes.
    var allProjects: [Project] {
        let saved = projects.projects
        let names = Set(saved.map(\.name))
        let unsaved = sandboxes.filter { !names.contains($0.name) }.map { sandbox in
            snapshots[sandbox.name].map { SandboxSync.adopt($0, app: appConfig) } ?? SandboxSync.unsaved(sandbox, app: appConfig)
        }
        return (saved + unsaved).sorted { $0.name < $1.name }
    }

    func project(named name: String) -> Project? {
        projects.project(named: name) ?? allProjects.first { $0.name == name }
    }

    /// Whether the project has a file yet.
    func isSaved(_ project: Project) -> Bool {
        projects.project(named: project.name) != nil
    }

    /// True when the project has a file, so the caller goes on. Otherwise writes the file from the
    /// sandbox's state first, then runs `retry` with the saved project, and returns false.
    func withSaved(_ project: Project, _ retry: @escaping @MainActor (Project) -> Void) -> Bool {
        if projects.project(named: project.name) != nil { return true }
        Task {
            if let saved = await adopt(project.name) { retry(saved) }
        }
        return false
    }

    func state(ofSandbox name: String) -> SandboxStates.State? {
        if let state = sandboxStates?[name] { return state }
        return sandboxes.first { $0.name == name }.map { SandboxStates.State(sbxStatus: $0.status) }
    }

    func refreshSnapshot(_ name: String) async {
        guard !systemAsleep else { return }
        do {
            let runner = try await readRunner()
            if let snapshot = try await runner.snapshot(named: name) {
                snapshots[name] = snapshot
            } else {
                snapshots[name] = nil
            }
            globalRules = try await runner.globalRules()
            await refreshActivity(runner)
            readWorked(.snapshot(name))
        } catch is CancellationError {
            // The view that asked went away.
        } catch {
            readFailed(.snapshot(name), "Could not read \(name) from sbx: \(String(describing: error))")
        }
    }

    /// Reads every sandbox (or only the ones not read yet), with one `sbx ls` for all of them.
    func refreshAllSnapshots(onlyMissing: Bool = false) async {
        guard !systemAsleep else { return }
        do {
            let runner = try await readRunner()
            for sandbox in sandboxes where !onlyMissing || snapshots[sandbox.name] == nil {
                if let snapshot = try? await runner.snapshot(of: sandbox) {
                    snapshots[sandbox.name] = snapshot
                    readWorked(.snapshot(sandbox.name))
                }
            }
            globalRules = try await runner.globalRules()
            await refreshActivity(runner)
            readWorked(.snapshots)
        } catch is CancellationError {
        } catch {
            readFailed(.snapshots, "Could not read the sandboxes from sbx: \(String(describing: error))")
        }
        let names = Set(sandboxes.map(\.name))
        for name in snapshots.keys where !names.contains(name) {
            snapshots[name] = nil
        }
    }

    /// The folder the project's sandbox mounts for Claude's sessions (PAD-127): when the operator
    /// chose it for a Claude Code project; nil otherwise.
    func claudeSessionsFolder(of project: Project) -> String? {
        guard project.keepsClaudeSessions, appConfig.agents[project.agent] == .claudeCode else { return nil }
        return ClaudeSessions.folder(project: project.name, paths: paths)
    }

    /// The differences between the project file and its sandbox. Empty until the sandbox was read.
    func syncItems(for project: Project) -> [SyncItem] {
        let exists = state(of: project) != nil
        if exists && snapshots[project.name] == nil { return [] }
        let expectedKits: Result<[String], KitError>
        do throws(KitError) {
            expectedKits = .success(try project.resolvedKits(appConfig, paths: paths, projectFolders: projectFolders).map(\.recorded))
        } catch {
            expectedKits = .failure(error)
        }
        // A confirmation of an sbxenv.yaml that is gone no longer counts: nothing to recreate for it.
        var current = project
        let environment = environment(of: project)
        if environment == nil { current.approvedEnvironment = nil }
        // What changed is known only for the confirmed version as it is on disk.
        let record = environment.flatMap { $0.fingerprint == project.approvedEnvironment ? $0.record : nil }
        return SandboxSync.diff(project: current, snapshot: exists ? snapshots[project.name] : nil, globalRules: globalRules, app: appConfig,
                                expectedKits: expectedKits, environment: record, claudeSessions: claudeSessionsFolder(of: project))
    }

    /// What the kit field did: added a kit to Paddock's config (its name, for the picker to
    /// select), or added a catalog kit to the project's `sbxenv.yaml`.
    enum AddedKit {
        case paddock(String)
        case projectFile(String)
    }

    /// The kit field (backlog doc Kits, Adding a kit): a catalog kit (a contrib kit's name or a
    /// `docker.io/sbx/...` reference) goes to the project's `sbxenv.yaml` when it has one, so the
    /// file stays the whole setup for `sbx env run`; anything else, and any kit for a project
    /// without the file, goes to paddock.yaml. Throws what the field shows.
    func addKit(_ text: String, for project: Project?) throws -> AddedKit {
        if let project, environment(of: project) != nil, let reference = ProjectKitFile.catalogReference(text) {
            // Confirmed before the change: the operator's own addition is confirmed with it. A file
            // with changes they have not seen still asks (they are not confirmed along).
            let wasConfirmed = !needsConfirmation(for: project)
            try ProjectKitFile.add(reference, folder: project.folder)
            readProjectFiles()
            if wasConfirmed, let current = self.project(named: project.name) {
                approveEnvironment(current, declined: Set(current.declinedHosts))
            }
            return .projectFile(reference)
        }
        return .paddock(try addKit(text))
    }

    /// Adds a kit to Paddock's config from the kit field (a contrib kit's name or a `--kit` reference)
    /// and returns its name, for the picker to select. Throws what the field shows.
    func addKit(_ text: String) throws -> String {
        reloadConfig()
        let name = try AppConfigFile.addKit(text, app: appConfig, path: paths.appConfig)
        reloadConfig()
        guard appConfig.kits[name] != nil else { throw AppError("Paddock's config did not load; see the status checks") }
        return name
    }

    /// The operator chose other kits for a project. Only its file changes: an existing sandbox
    /// shows "recreate" under Needs attention, since sbx applies kits at create.
    func setKits(_ kits: [String], for project: Project) {
        guard withSaved(project, { self.setKits(kits, for: $0) }) else { return }
        guard var updated = projects.project(named: project.name) else { return }
        updated.kits = kits.sorted()
        do {
            try projectDirectory.save(updated)
            try projects.update(updated)
            lastError = nil
            syncBrowserWatchers()
        } catch {
            fail("Could not save \(project.name)'s kits: \(String(describing: error))", in: project.name)
        }
    }

    /// Changes sbx to match the project for one difference.
    func apply(_ item: SyncItem, for project: Project) {
        guard withSaved(project, { self.apply(item, for: $0) }) else { return }
        guard let change = item.apply else { return }
        if change == .create {
            createSandbox(project)
            return
        }
        run("apply \(item.summary)", on: project) { runner in
            if change == .recreate { self.closeTerminals(of: project.name) }
            self.reloadConfig()
            let created = try await runner.apply(change, for: project, app: self.appConfig, models: await self.probe.installedModels(),
                                                 projectFolders: self.projectFolders, progress: self.activityReporter(for: project.name))
            if let created { self.recordCreated(created) }
        }
    }

    /// Saves a sandbox Paddock did not create as a project file, from its actual state. The first
    /// action on such a sandbox does this; afterwards it is managed like any project.
    @discardableResult
    func adopt(_ name: String) async -> Project? {
        if let existing = projects.project(named: name) { return existing }
        do {
            let runner = try await runner()
            guard let snapshot = try await runner.snapshot(named: name) else { throw AppError("\(name) no longer exists") }
            snapshots[name] = snapshot
            reloadConfig()
            // An sbxenv.yaml in its folder is not confirmed by this: the operator does that.
            let project = SandboxSync.adopt(snapshot, app: appConfig)
            var list = projects
            try list.insert(project)
            try projectDirectory.save(project)
            projects = list
            lastError = nil
            return project
        } catch {
            fail("Could not save \(name) as a project: \(String(describing: error))", in: name)
            return nil
        }
    }

    /// Runs one sbx change for a project, then re-reads the sandbox.
    private func run(_ what: String, on project: Project, _ body: @escaping @MainActor (ProjectRunner) async throws -> Void) {
        guard activities[project.name] == nil else { return }
        activities[project.name] = what.prefix(1).uppercased() + what.dropFirst()
        Task {
            defer { activities[project.name] = nil }
            do {
                try await body(try await runner())
                lastError = nil
            } catch {
                lastError = "Could not \(what): \(String(describing: error))"
            }
            await refreshSnapshot(project.name)
        }
    }

    // MARK: - Ports and hosts (straight to sbx, the only store for them)

    /// What sbx publishes, by sandbox read so far.
    private var publishedPorts: [String: [SbxPort]] { snapshots.mapValues(\.ports) }

    func publish(sandboxPort: Int, on project: Project) {
        let mapping: Project.PortMapping
        do {
            mapping = try Ports.mapping(for: sandboxPort, sandbox: project.name, published: publishedPorts, app: appConfig)
        } catch {
            lastError = "Could not publish port \(sandboxPort): \(error.description)"
            return
        }
        run("publish port \(sandboxPort)", on: project) { runner in
            try await runner.publish(mapping, for: project)
        }
    }

    func addHostService(_ port: Int, to project: Project) {
        do {
            try Ports.checkHostService(port, app: appConfig)
        } catch {
            lastError = "Could not allow host port \(port): \(error.description)"
            return
        }
        run("allow host port \(port)", on: project) { runner in
            try await runner.allowHostService(port, for: project)
        }
    }

    func removeHostService(_ port: Int, from project: Project) {
        run("remove host port \(port)", on: project) { runner in
            try await runner.removeHostService(port, for: project)
        }
    }

    /// Allows or denies one host in the sandbox, or removes its rule (`nil`) so the policy section
    /// decides again.
    func setHostRule(_ decision: HostRules.Decision?, for text: String, on project: Project) {
        let host: String
        do {
            host = try HostRules.validated(text)
        } catch {
            lastError = "Could not change the rule for \(text): \(error.description)"
            return
        }
        let what = switch decision {
        case .allow?: "allow \(host)"
        case .deny?: "deny \(host)"
        case nil: "remove the rule for \(host)"
        }
        reloadConfig()
        let app = appConfig
        run(what, on: project) { runner in
            try await runner.setHostRule(decision, for: host, on: project, app: app)
        }
    }

    /// The project's host rules: its sandbox's own.
    func hostRows(for project: Project) -> [HostRules.Row] {
        let snapshot = snapshots[project.name]
        let planned = (try? SandboxSync.plan(project: project, snapshot: snapshot, globalRules: globalRules, app: appConfig))?.denies ?? []
        return HostRules.rows(snapshot: snapshot, globalAllows: Ports.globalAllows(globalRules), plannedDenies: Set(planned))
    }

    /// Denies `resources` for the project's sandbox (a deny Paddock suggests).
    func deny(_ resources: [String], on project: Project, summary: String) {
        guard !resources.isEmpty else { return }
        apply(SyncItem(id: "deny-\(summary)", kind: .network, summary: "deny \(summary)", apply: .deny(resources)), for: project)
    }

    /// Adds the per-sandbox denies Paddock always wants and the sandbox is missing (Ports, "not denied").
    /// Only the sandbox's own rules change; sbx's global rules stay as they are.
    func denyReserved(_ rows: [PortRow], on project: Project) {
        let resources = rows.flatMap(\.missingDenies)
        guard !resources.isEmpty else { return }
        let ports = rows.compactMap(\.hostPort).map(String.init).joined(separator: ", ")
        apply(SyncItem(id: "deny-reserved", kind: .network, summary: "deny port \(ports)", apply: .deny(resources)), for: project)
    }

    /// Every rule sbx reports, global and per sandbox.
    func ruleRows() -> [RuleRow] {
        RulesTable.rows(globalRules: globalRules, snapshots: snapshots, projects: allProjects, app: appConfig)
    }

    /// What each sandbox connected to, from `sbx policy log --json`, merged into the rules. Read
    /// with the sandboxes' rules and ports.
    private(set) var activity: [ActivityKey: HostActivity] = [:]
    /// The log itself, for the hosts each sandbox tried that no rule allows.
    private(set) var networkLog: SbxPolicyLog?
    /// Whether the network log was read; until then the activity columns say so.
    var hasNetworkLog: Bool { networkLog != nil }

    /// sbx's approval requests: what sandboxes tried that no rule decided, waiting for an answer.
    private(set) var approvals: [SbxApproval] = []

    /// Reads the network log, unless the events keep it current. A failure leaves the last one in
    /// place: the rules matter more. The approval requests have a stream of their own (watchApprovals).
    private func refreshActivity(_ runner: ProjectRunner) async {
        guard !logIsLive else { return }
        if let next = try? await runner.networkLog(), next != networkLog {
            networkLog = next
            activity = next.activity
        }
    }

    /// The project's sandbox's approval requests, newest first, for its Info.
    func approvalRequests(for project: Project) -> [SbxApproval] {
        ApprovalRequests.pending(approvals, sandbox: project.name, ignored: project.ignoredSuggestions, app: appConfig)
    }

    /// Approval requests being answered: only their own buttons wait, not the whole project.
    private(set) var answering: Set<String> = []

    /// Answers an approval request with one of sbx's options (Allow adds sbx's own rule). The
    /// request goes from the list as soon as sbx took the answer; a slow sbx gives up after a while
    /// instead of keeping the buttons disabled.
    func respond(to approval: SbxApproval, with option: SbxApproval.Option, for project: Project) {
        guard !answering.contains(approval.id) else { return }
        // Dismiss sticks in Paddock too: sbx asks again when the agent tries again.
        if option.id == "dismiss" {
            ignoreSuggestion(ApprovalRequests.ignoreID(approval), for: project)
        }
        answering.insert(approval.id)
        Task {
            defer { answering.remove(approval.id) }
            do {
                let runner = try await runner()
                try await Deadline.result(within: Self.answerTimeout) {
                    try await runner.respond(to: approval, with: option.id, for: project)
                }
                approvals.removeAll { $0.id == approval.id }
                lastError = nil
                if let next = try? await runner.approvals() { receive(next) }
                // Allow added a rule: the sandbox's rules changed.
                if option.id == "allow" { await refreshSnapshot(project.name) }
            } catch {
                lastError = "Could not \(option.label.lowercased()) \(approval.title): \(String(describing: error))"
            }
        }
    }

    /// Blocks the host an approval request is for: a deny rule for the sandbox (a sandbox deny beats
    /// any allow), then sbx's Dismiss so the request leaves. Unlike a plain Dismiss it is not kept
    /// as ignored: the rule decides now, so sbx does not ask again.
    func block(_ approval: SbxApproval, for project: Project) {
        let host: String
        do {
            host = try HostRules.validated(approval.host)
        } catch {
            lastError = "Could not block \(approval.title): \(error.description)"
            return
        }
        guard !answering.contains(approval.id), activities[project.name] == nil else { return }
        reloadConfig()
        let app = appConfig
        answering.insert(approval.id)
        activities[project.name] = "Deny \(host)"
        Task {
            defer {
                answering.remove(approval.id)
                activities[project.name] = nil
            }
            do {
                let runner = try await runner()
                try await runner.setHostRule(.deny, for: host, on: project, app: app)
                if let dismiss = approval.options.first(where: { $0.id == "dismiss" }) {
                    try await Deadline.result(within: Self.answerTimeout) {
                        try await runner.respond(to: approval, with: dismiss.id, for: project)
                    }
                }
                approvals.removeAll { $0.id == approval.id }
                lastError = nil
                if let next = try? await runner.approvals() { receive(next) }
            } catch {
                lastError = "Could not block \(approval.title): \(String(describing: error))"
            }
            await refreshSnapshot(project.name)
        }
    }

    private static let answerTimeout: Duration = .seconds(20)

    /// The Network page's sandbox choice (nil for all), kept here so a project can open the page on itself.
    var networkSandbox: String?
    /// A sidebar selection asked for from inside a page; ContentView follows it.
    var requestedSelection: SidebarSelection?

    /// Opens the Network page on one sandbox.
    func showNetwork(for sandbox: String) {
        networkSandbox = sandbox
        requestedSelection = .network
    }

    /// The Filesystem page's sandbox choice (nil for all).
    var filesystemSandbox: String?

    /// Opens the Filesystem page on one sandbox.
    func showFilesystem(for sandbox: String) {
        filesystemSandbox = sandbox
        requestedSelection = .filesystem
    }

    /// Opens the Processes page (System > Processes, the status popover).
    func showSbxProcesses() {
        requestedSelection = .processes
    }

    /// Opens the Log page (System > Log, the status popover).
    func showLog() {
        requestedSelection = .log
    }

    /// The filesystem rules and mounts, for one sandbox (with the rules for every sandbox) or all.
    func filesystemRows(for sandbox: String?) -> [RuleRow] {
        let rows = ruleRows().filter(\.kind.isFilesystem)
        return sandbox.map { RulesTable.applying(to: $0, rows) } ?? rows
    }

    /// The network rules with the log's activity, for one sandbox's table or (nil) every sandbox's.
    func networkRows(for sandbox: String?) -> [RuleRow] {
        let rows = ruleRows().filter { !$0.kind.isFilesystem }
        let scoped = sandbox.map { RulesTable.applying(to: $0, rows) } ?? rows
        return RulesTable.merging(scoped, activity: activity, sandbox: sandbox)
    }

    /// An sbx global rule the operator asked to remove, waiting for confirmation.
    var pendingGlobalRuleRemoval: SbxRuleReference?

    /// A host the operator asked to block for every sandbox, waiting for confirmation.
    var pendingGlobalDeny: String?

    /// Asks to block `text` for every sandbox: checked now, confirmed next (it changes every sandbox).
    func requestGlobalDeny(_ text: String) {
        do {
            pendingGlobalDeny = try HostRules.validated(text)
        } catch {
            lastError = "Could not block \(text): \(error.description)"
        }
    }

    /// Blocks a host for every sandbox with a global sbx deny, after the operator confirmed it.
    func addGlobalDeny(_ host: String) {
        Task {
            do {
                try await runner().addGlobalDeny(host)
                lastError = nil
            } catch {
                lastError = "Could not block \(host) for every sandbox: \(String(describing: error))"
            }
            await refreshAllSnapshots()
        }
    }

    /// Removes one of sbx's global rules after the operator confirmed it (CLAUDE.md: Paddock never
    /// changes global rules on its own).
    func removeGlobalRule(_ rule: SbxRuleReference) {
        Task {
            do {
                try await runner().removeGlobalRule(rule)
                lastError = nil
            } catch {
                lastError = "Could not remove the sbx rule: \(String(describing: error))"
            }
            await refreshAllSnapshots()
        }
    }

    /// Unpublishes a published port, in any sandbox.
    func unpublish(_ row: PortRow) {
        guard let hostPort = row.hostPort, let sandboxPort = row.sandboxPort, let project = project(named: row.sandbox) else { return }
        run("unpublish \(hostPort)", on: project) { runner in
            try await runner.unpublish(hostIP: row.hostIP, hostPort: hostPort, sandboxPort: sandboxPort, for: project)
        }
    }

    /// The project's `sbxenv.yaml` checked (backlog doc Project config file), or nil without one.
    func environment(of project: Project) -> ProjectEnvironment? {
        cachedEnvironment(of: project).environment
    }

    /// A project's `sbxenv.yaml` and own kits, as last read.
    struct CachedEnvironment: Equatable {
        let environment: ProjectEnvironment?
    }

    /// Every project's `sbxenv.yaml` by folder. Views ask for it on every redraw, and reading and
    /// checking it (its kits too) each time would make switching pages slow; it is read again with
    /// the project files (Refresh, the app coming to the front) and right before an action uses it.
    private var environmentCache: [String: CachedEnvironment] = [:]

    private func readEnvironment(of project: Project) -> CachedEnvironment {
        let others = Dictionary(allProjects.filter { $0.name != project.name }.map { ($0.name, $0.folder) },
                                uniquingKeysWith: { first, _ in first })
        let context = ProjectEnvironment.Context(
            folderPolicy: FolderPolicy(home: NSHomeDirectory(), paddockConfigDirectory: paths.configDirectory),
            app: appConfig, otherProjects: others)
        return CachedEnvironment(environment: ProjectEnvironment.read(folder: project.folder, context: context))
    }

    /// Reads every project's `sbxenv.yaml` again, or (`onlyMissing`) only the ones not read yet.
    func readProjectFiles(onlyMissing: Bool = false) {
        var next: [String: CachedEnvironment] = onlyMissing ? environmentCache : [:]
        for project in allProjects where next[project.folder] == nil {
            next[project.folder] = readEnvironment(of: project)
        }
        if next != environmentCache { environmentCache = next }
    }

    private func cachedEnvironment(of project: Project) -> CachedEnvironment {
        // A project that appeared since the last read is read now, without caching it mid-redraw.
        environmentCache[project.folder] ?? readEnvironment(of: project)
    }

    /// Every port across all sandboxes.
    func portRows() -> [PortRow] {
        PortsTable.rows(projects: allProjects, snapshots: snapshots, sandboxes: Set(sandboxes.map(\.name)),
                        globalRules: globalRules, app: appConfig)
    }

    // MARK: - Terminals

    /// Opens an agent session or shell, creating the project's sandbox first when it has none
    /// (`sbx run` starts a stopped one by itself). A shell on this Mac needs no sandbox.
    func openSession(_ kind: TerminalTabs.Kind, in project: Project, half: ProjectTerminals.Half = .left) {
        guard kind == .mac || state(of: project) != nil else {
            createSandbox(project, then: .open(kind))
            return
        }
        // OpenCode on a local model reads its config file, written again first (ProjectRunner).
        guard kind == .agent, appConfig.agents[project.agent] == .openCode, project.usesGateway(appConfig) else {
            openTerminals(for: project)?.open(kind, in: half)
            return
        }
        Task {
            do {
                try await runner().prepareAgentSession(project, app: appConfig)
            } catch {
                fail("Could not write OpenCode's config in \(project.name): \(String(describing: error))",
                     in: project.name)
            }
            openTerminals(for: project)?.open(kind, in: half)
        }
    }

    // MARK: - Resources (PAD-32, PAD-31)

    private var hostProcessesLoop: Task<Void, Never>?
    /// `ps` on the Mac, for the status button's mark (sbx tools without a terminal).
    static let hostProcessesInterval: Duration = .seconds(30)

    /// Whether Paddock may run a script in the project's sandbox now (`SandboxTop.mayPoll`): `sbx
    /// exec` would start a stopped one.
    func mayPoll(_ project: Project) -> Bool {
        SandboxTop.mayPoll(state(of: project), actionRunning: activity(of: project) != nil)
    }

    /// The sandbox's CPUs, load, memory, and disk, for Info while it is shown (backlog doc UI,
    /// Resources); nil when its sandbox may not be polled now.
    func readSummary(of project: Project) async throws -> SandboxSample? {
        guard let sbxPath, mayPoll(project) else { return nil }
        return try await SandboxTop.read(SandboxTop.summaryScript, in: project.name, sbx: URL(fileURLWithPath: sbxPath),
                                         runner: FoundationProcessRunner())
    }

    /// Opens (or shows) the project's Processes tab.
    func openProcesses(of project: Project) {
        openTerminals(for: project)?.openProcesses()
    }

    /// The project's processes over one second, for its Processes tab while it is shown; nil when its
    /// sandbox may not be polled now.
    func readProcesses(of project: Project) async throws -> SandboxSample? {
        guard let sbxPath, mayPoll(project) else { return nil }
        return try await SandboxTop.read(SandboxTop.processScript, in: project.name, sbx: URL(fileURLWithPath: sbxPath),
                                         runner: FoundationProcessRunner())
    }

    /// sbx's processes on the Mac (backlog doc UI, Processes), read every 30 s and when the window asks.
    private(set) var hostProcesses: [SbxProcess] = []

    /// sbx tools whose terminal is gone, for the status button and the Processes window.
    var orphanedSbxTools: [SbxProcess] { hostProcesses.filter { $0.kind == .orphanedTool } }

    func readHostProcesses() async {
        do {
            hostProcesses = SbxProcesses.classify(try await HostProcesses.read(runner: FoundationProcessRunner()), user: NSUserName())
        } catch {
            hostProcesses = []
        }
    }

    /// The operator chose to stop these (after a confirmation that listed them).
    func stop(_ processes: [SbxProcess]) async {
        do {
            let stopped = try await SbxProcesses.stop(processes, runner: FoundationProcessRunner(), user: NSUserName())
            if !stopped.isEmpty {
                let list = stopped.map { "\($0.process.pid) \($0.process.command)" }.joined(separator: "; ")
                appendLog("Stopped \(stopped.count) sbx process(es): \(list)", category: .processes)
            }
            if stopped.count < processes.count {
                lastError = "\(processes.count - stopped.count) of the chosen processes had already ended or changed; they were left alone."
            }
        } catch {
            lastError = "Could not stop the sbx processes: \(error)"
        }
        await readHostProcesses()
    }

    // MARK: - Templates

    /// sbx's templates with what uses them (backlog doc UI, Templates); nil until the page read them.
    private(set) var templates: [TemplateRow]?

    func readTemplates() async {
        do {
            templates = try await runner().templateRows()
        } catch {
            lastError = "Could not list sbx's templates: \(String(describing: error))"
            if templates == nil { templates = [] }
        }
    }

    /// The operator chose to remove these (after a confirmation that listed them). Core checks
    /// each again against fresh lists before sbx removes it.
    func removeTemplates(_ rows: [TemplateRow]) async {
        do {
            let result = try await runner().removeTemplates(rows.map(\.name))
            if !result.removed.isEmpty {
                appendLog("Removed \(result.removed.count) sbx template(s): " + result.removed.joined(separator: ", "))
            }
            for failure in result.failed.dropFirst() {
                appendLog("Did not remove \(failure.name): \(failure.reason)", isError: true)
            }
            if let first = result.failed.first {
                lastError = "Did not remove \(first.name): \(first.reason)"
                    + (result.failed.count > 1 ? " (and \(result.failed.count - 1) more, see the Log)" : "")
            }
        } catch {
            lastError = "Could not remove the templates: \(String(describing: error))"
        }
        await readTemplates()
    }

    // MARK: - Watchers left by an earlier Paddock

    private var checkedLeftoverWatchers = false

    /// Watchers an earlier Paddock left on the Mac when it crashed or was killed: stopped once at
    /// launch, before this one starts its own. Their twins in the sandboxes go when the new watchers
    /// start (backlog doc Kits, Watchers).
    private func stopLeftoverWatchers() async {
        do {
            let stopped = try await SandboxWatchers.stopLeftovers(runner: FoundationProcessRunner(), user: NSUserName())
            if !stopped.isEmpty {
                let pids = stopped.map { String($0.pid) }.joined(separator: ", ")
                appendLog("Stopped \(stopped.count) sbx watcher(s) an earlier Paddock left running (pid \(pids)).",
                          category: .processes)
            }
        } catch {
            appendLog("Could not look for sbx watchers an earlier Paddock left running: \(error)",
                      category: .processes, isError: true)
        }
    }

    // MARK: - Voice

    /// Voice for agents: speech, questions, and push-to-talk (backlog doc Voice).
    let voice = VoiceModel()

    // MARK: - Agent status

    /// One `paddock-agent-watch` per running project with the status kit (backlog doc Kits, Agent status).
    private var agentWatchers: [String: Task<Void, Never>] = [:]

    /// The project's one mark: its sandbox's state and its approval requests (backlog doc UI, Status
    /// marks). The agents are rows of their own under it (`agentRows(of:now:)`, PAD-63).
    func badge(of project: Project) -> ProjectBadge {
        ProjectBadge(state: state(of: project), requests: approvalRequests(for: project).count)
    }

    /// The mark in words, for its tooltip.
    func badgeHelp(of project: Project) -> String {
        ProjectBadge.help(state: state(of: project), requests: approvalRequests(for: project).count)
    }

    /// The agents under the project in the sidebar; none while its sandbox does not run.
    func agentRows(of project: Project, now: Date) -> [SidebarAgentRow] {
        guard state(of: project) == .running else { return [] }
        return terminals[project.name]?.sidebarAgents(now: now) ?? []
    }

    /// The project the window shows, set by the sidebar's selection.
    var shownProject: String? {
        didSet { if shownProject != oldValue { showOnScreen() } }
    }

    /// Tells each project's terminals whether they are on screen: their project is shown and
    /// Paddock is the active app, so an agent finishing elsewhere gets its finished mark.
    private func showOnScreen() {
        let active = NSApp?.isActive ?? false
        for (name, open) in terminals {
            open.setOnScreen(active && name == shownProject)
        }
    }

    /// The shown project's last selected tab, for the sidebar's highlight.
    var shownTab: UUID? {
        shownProject.flatMap { terminals[$0]?.activeTab }
    }

    /// Shows an agent's tab from the sidebar.
    func showAgentTab(_ tab: UUID, of name: String) {
        terminals[name]?.select(tab: tab)
    }

    /// Starts or stops the watchers to match: a project with the status kit whose sandbox runs.
    private func syncAgentWatchers() {
        guard let sbxPath else { return }
        var wanted = Set<String>()
        for project in projects.projects where state(of: project) == .running && AgentStatusKit.isChosen(by: project, app: appConfig) {
            wanted.insert(project.name)
        }
        for (name, task) in agentWatchers where !wanted.contains(name) {
            task.cancel()
            agentWatchers[name] = nil
            terminals[name]?.clearAgent()
        }
        for name in wanted where agentWatchers[name] == nil {
            agentWatchers[name] = watchAgents(name, sbx: URL(fileURLWithPath: sbxPath))
        }
    }

    /// Follows the sandbox's `paddock-agent-watch`. The lines are untrusted (`AgentState`). Started again
    /// after it ends, less often each time. What it reported stays on show across a restart until the
    /// new watcher's first pass (it prints every session at once) has had `agentResyncTime`; sessions
    /// it no longer reports go then (PAD-61). A watcher that reports nothing (a sandbox from before the
    /// kit) forgets everything, so no tab keeps a stale mark; a stopped sandbox is `syncAgentWatchers`'.
    private func watchAgents(_ name: String, sbx: URL) -> Task<Void, Never> {
        Task { [weak self] in
            var delay: Duration = .seconds(2)
            var restarted = false
            while !Task.isCancelled {
                var heard = false
                var problem = "it ended"
                let started = ContinuousClock.now
                if restarted { self?.terminals[name]?.beginAgentResync() }
                do {
                    for try await line in FoundationLineStreamer(holdsInputOpen: true).lines(sbx, arguments: AgentStatusKit.watchArguments(sandbox: name)) {
                        guard let self, let project = self.project(named: name) else { return }
                        let terminals = self.openTerminals(for: project)
                        terminals?.receiveAgent(line)
                        if !heard, restarted {
                            Task { [weak terminals] in
                                try? await Task.sleep(for: Self.agentResyncTime)
                                terminals?.endAgentResync()
                            }
                        }
                        heard = true
                        delay = .seconds(2)
                    }
                } catch {
                    problem = String(describing: error)
                }
                guard !Task.isCancelled else { return }
                if heard {
                    let ran = ContinuousClock.now - started
                    self?.appendLog("paddock-agent-watch in \(name) ended after \(ran.formatted(.units(allowed: [.seconds], width: .narrow))) (\(problem)); "
                                    + "starting it again", category: .sandbox, source: name)
                } else {
                    self?.terminals[name]?.clearAgent()
                }
                restarted = true
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, .seconds(60))
            }
        }
    }

    /// How long a restarted agent watcher's first pass may take (it prints every session at once).
    private static let agentResyncTime: Duration = .seconds(3)

    // MARK: - Browser tabs

    /// One `paddock-browser-watch` per running project with the browser kit (backlog doc Browser).
    private var browserWatchers: [String: Task<Void, Never>] = [:]

    /// Starts or stops the watchers to match: a project with the browser kit whose sandbox runs.
    /// A stopped sandbox's browser tabs go with its sessions.
    func syncBrowserWatchers() {
        syncAgentWatchers()
        voice.sync()
        guard let sbxPath else { return }
        var wanted = Set<String>()
        for project in projects.projects where state(of: project) == .running && BrowserKit.isChosen(by: project, app: appConfig) {
            wanted.insert(project.name)
        }
        for (name, task) in browserWatchers where !wanted.contains(name) {
            task.cancel()
            browserWatchers[name] = nil
            terminals[name]?.clearBrowser()
        }
        for name in wanted where browserWatchers[name] == nil {
            browserWatchers[name] = watchBrowser(name, sbx: URL(fileURLWithPath: sbxPath))
        }
    }

    /// Follows the sandbox's `paddock-browser-watch`: the agent's pages and its activity. The
    /// lines are untrusted (`BrowserSessions`). Started again after it ends (a sandbox from before
    /// the kit has no watcher), less often each time.
    private func watchBrowser(_ name: String, sbx: URL) -> Task<Void, Never> {
        Task { [weak self] in
            var delay: Duration = .seconds(2)
            var failures = 0
            while !Task.isCancelled {
                var heard = false
                var problem = "it ended"
                do {
                    for try await line in FoundationLineStreamer(holdsInputOpen: true).lines(sbx, arguments: BrowserActivity.watchCommand(sandbox: name)) {
                        guard let self, let project = self.project(named: name) else { return }
                        self.openTerminals(for: project)?.receiveBrowser(line)
                        heard = true
                        failures = 0
                        delay = .seconds(2)
                    }
                } catch {
                    problem = String(describing: error)
                }
                // Said once per sandbox: a watcher that never reports (a sandbox from before the
                // current browser kit has none) would otherwise fail without a word.
                if !heard {
                    failures += 1
                    if failures == 3, !Task.isCancelled {
                        self?.fail("Paddock cannot follow the browser in \(name): "
                                   + "paddock-browser-watch did not run (\(problem)). "
                                   + "Recreate the sandbox to get the current browser kit.", in: name)
                    }
                }
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, .seconds(60))
            }
        }
    }

    /// Starts the browser kit's dashboard in the project's sandbox (a browser tab found nothing on its port).
    func startBrowserDashboard(of project: Project) async {
        do {
            try await runner().startBrowserDashboard(project)
        } catch {
            fail("Could not start the browser dashboard in \(project.name): \(String(describing: error))",
                 in: project.name)
        }
    }

    /// Show tabs the app told the sandbox were opened, so it says so once.
    private var openedShows: Set<String> = []

    /// The operator looks at a host tab: it is seen, and a show tab counts as opened (the agent
    /// hears of it once).
    func openedHostTab(_ tab: String, of project: Project) {
        guard let terminals = terminals[project.name] else { return }
        terminals.markSeen(tab)
        guard let id = ProjectTerminals.showID(tab), let show = terminals.browser.shows.first(where: { $0.id == id }),
              !show.opened, openedShows.insert("\(project.name)/\(id)").inserted else { return }
        sendShowEvent(.opened, show: id, of: project)
    }

    /// The operator closed a host tab. A show tab closes in the sandbox too, as dismissed when it
    /// was never opened (the agent hears which); the Playwright tab comes back with the next change.
    func closeHostTab(_ tab: String, of project: Project) {
        guard let terminals = terminals[project.name] else { return }
        let show = ProjectTerminals.showID(tab).flatMap { id in terminals.browser.shows.first { $0.id == id } }
        terminals.closeHostTab(tab)
        guard let show else { return }
        let opened = show.opened || openedShows.contains("\(project.name)/\(show.id)")
        sendShowEvent(opened ? .closed : .dismissed, show: show.id, of: project)
    }

    /// What an interactive tab's page sent (checked): an action goes to the sandbox for
    /// `paddock wait`, problems too (only when they changed), and form state stays here.
    func received(_ message: OpenUIMessage, from show: BrowserSessions.Show, of project: Project) {
        guard let terminals = terminals[project.name] else { return }
        let event: BrowserShow.UIEvent
        let json: String
        switch message {
        case .ready:
            return
        case .state(let state):
            terminals.keepUIState(state, for: show.id)
            return
        case .action(let action):
            event = .action
            json = action
        case .problems(let problems):
            guard terminals.uiProblemsSent[show.id] != problems else { return }
            terminals.uiProblemsSent[show.id] = problems
            event = .problems
            json = problems
        }
        Task {
            do {
                try await runner().sendUIEvent(event, json: json, show: show.id, of: project)
                if event == .action { terminals.delivered(show.id, sent: true, detail: "Sent to the agent") }
            } catch {
                fail("Could not hand your answer to the agent in \(project.name): \(String(describing: error))",
                     in: project.name)
                if event == .action { terminals.delivered(show.id, sent: false, detail: "Not sent: \(String(describing: error))") }
            }
        }
    }

    /// A host tab menu's Refresh or Back. A page shown in the sandbox is reloaded or sent back
    /// there; the Playwright tab, native tabs, and interactive tabs act in their own view.
    func hostAction(_ action: String, on tab: String, of project: Project) {
        guard let terminals = terminals[project.name] else { return }
        let back = action == ProjectTerminals.back.id
        if let id = ProjectTerminals.showID(tab), let show = terminals.browser.shows.first(where: { $0.id == id }),
           case .page = show.mode {
            Task {
                do {
                    try await runner().navigateShow(back ? .back : .reload, show: id, of: project)
                } catch {
                    lastError = "Could not \(back ? "go back in" : "reload") \(show.title): \(String(describing: error))"
                }
            }
        } else {
            terminals.send(back ? .back : .reload, to: tab)
        }
    }

    private func sendShowEvent(_ event: BrowserShow.OperatorEvent, show id: String, of project: Project) {
        Task {
            do {
                try await runner().showEvent(event, show: id, of: project)
            } catch {
                fail("Could not tell \(project.name) that \(id) was \(event.rawValue): \(String(describing: error))",
                     in: project.name)
            }
        }
    }

    /// A screenshot or recording the operator saved from a dashboard view: copied into the sandbox
    /// for the agent whose page it shows (it hears of it), never kept on the Mac.
    func captured(file: URL, suggestedName: String, owner: BrowserCapture.Owner?, of project: Project) {
        Task {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let owner else {
                lastError = "Paddock could not tell whose page \(suggestedName) shows; select the page in the dashboard first"
                return
            }
            do {
                try await runner().sendCapture(localFile: file.path, suggestedName: suggestedName, owner: owner, of: project)
                lastError = nil
            } catch {
                fail("Could not hand \(suggestedName) to the agent in \(project.name): \(String(describing: error))",
                     in: project.name)
            }
        }
    }

    /// A file of a native show tab, through `sbx exec`.
    func readShowFile(show id: String, relativePath: String, of project: Project) async throws -> Data {
        try await runner().readShowFile(show: id, relativePath: relativePath, of: project)
    }

    // MARK: - Confirming sbxenv.yaml

    /// A project whose `sbxenv.yaml` waits for the operator, and what follows confirming it.
    struct ConfigConfirmation: Identifiable {
        enum After {
            case nothing, create
            case open(TerminalTabs.Kind)
        }

        let project: String
        let then: After
        var id: String { project }
    }

    /// Shows the confirmation sheet (ContentView).
    var confirmation: ConfigConfirmation?

    /// The project's `sbxenv.yaml` and own kits next to sbx's global rules, or nil without one.
    func environmentReview(for project: Project) -> EnvironmentReview? {
        environment(of: project).map { EnvironmentReview.make($0, project: project, globalRules: globalRules) }
    }

    /// Whether the operator has to confirm `sbxenv.yaml` (or see why it is refused) before the
    /// next create: never confirmed, or changed since.
    func needsConfirmation(for project: Project) -> Bool {
        environmentReview(for: project)?.needsApproval ?? false
    }

    /// Creates the sandbox once `sbxenv.yaml` is confirmed, asking first when it needs that.
    func createSandbox(_ project: Project, then after: ConfigConfirmation.After = .create) {
        readProjectFiles()
        if needsConfirmation(for: project) {
            confirmation = ConfigConfirmation(project: project.name, then: after)
            return
        }
        perform(.create, on: project) { [weak self] in
            guard let self, let created = self.project(named: project.name) else { return }
            if case .open(let kind) = after { self.openTerminals(for: created)?.open(kind) }
        }
    }

    /// Starts the sandbox as it was created; a changed `sbxenv.yaml` applies at the next create.
    func startSandbox(_ project: Project) {
        perform(.start, on: project)
    }

    /// The operator confirmed, declining `declined` hosts: records it, then does what waited for it.
    func confirm(_ confirmation: ConfigConfirmation, declined: Set<String>) {
        self.confirmation = nil
        guard let project = project(named: confirmation.project) else { return }
        approveEnvironment(project, declined: declined)
        guard let approved = self.project(named: project.name), !needsConfirmation(for: approved) else { return }
        switch confirmation.then {
        case .create: createSandbox(approved)
        case .open(let kind): createSandbox(approved, then: .open(kind))
        case .nothing: break
        }
    }

    /// The project's terminal sessions, created on first use. Nil until sbx was found.
    func openTerminals(for project: Project) -> ProjectTerminals? {
        if let existing = terminals[project.name] { return existing }
        guard let sbxPath else {
            lastError = "sbx was not found yet; see the status checks (click the dot)"
            return nil
        }
        let created = ProjectTerminals(sandbox: project.name, sbx: sbxPath, folder: project.folder)
        terminals[project.name] = created
        showOnScreen()
        return created
    }

    private func closeTerminals(of name: String) {
        terminals[name]?.terminateAll()
        terminals[name] = nil
    }

    // MARK: - Extra folders (PAD-73.5)

    /// The folder checks for this Mac (`FolderPolicy`).
    var folderPolicy: FolderPolicy {
        FolderPolicy(home: NSHomeDirectory(), paddockConfigDirectory: paths.configDirectory)
    }

    /// Adds a folder the operator chose to the project, read-only, after the same checks as a
    /// project folder (`ExtraFolders`). The sandbox mounts it at its next create (a recreate item).
    func addExtraFolder(_ path: String, to project: Project) {
        guard withSaved(project, { self.addExtraFolder(path, to: $0) }) else { return }
        guard var updated = projects.project(named: project.name) else { return }
        do throws(ExtraFolderProblem) {
            let checked = try ExtraFolders.check(path, for: updated, policy: folderPolicy)
            updated.extraFolders.append(Project.ExtraFolder(path: checked))
        } catch {
            fail("Could not add \((path as NSString).abbreviatingWithTildeInPath): \(error.description)", in: project.name)
            return
        }
        saveProject(updated)
    }

    func removeExtraFolder(_ path: String, from project: Project) {
        guard withSaved(project, { self.removeExtraFolder(path, from: $0) }) else { return }
        guard var updated = projects.project(named: project.name) else { return }
        updated.extraFolders.removeAll { $0.path == path }
        saveProject(updated)
    }

    /// Read-only, or writable: the agent can then change that folder's files too.
    func setExtraFolder(_ path: String, readOnly: Bool, in project: Project) {
        guard withSaved(project, { self.setExtraFolder(path, readOnly: readOnly, in: $0) }) else { return }
        guard var updated = projects.project(named: project.name),
              let index = updated.extraFolders.firstIndex(where: { $0.path == path }) else { return }
        guard ExtraFolders.allows(readOnly: readOnly, path: path, policy: folderPolicy) else {
            fail("\((path as NSString).abbreviatingWithTildeInPath) stays read-only: it is inside ~/Library/Logs", in: project.name)
            return
        }
        updated.extraFolders[index].readOnly = readOnly
        saveProject(updated)
    }

    /// Saves a change the operator made to a project: its file, then the list.
    func saveProject(_ project: Project, what: String = "extra folders") {
        do {
            try projectDirectory.save(project)
            try projects.update(project)
            lastError = nil
        } catch {
            fail("Could not save \(project.name)'s \(what): \(String(describing: error))", in: project.name)
        }
    }

    func setTerminalTheme(_ theme: String?, for project: Project) {
        guard withSaved(project, { self.setTerminalTheme(theme, for: $0) }) else { return }
        guard var updated = projects.project(named: project.name), updated.terminalTheme != theme else { return }
        updated.terminalTheme = theme
        do {
            try projectDirectory.save(updated)
            projects.remove(named: updated.name)
            try projects.insert(updated)
            lastError = nil
        } catch {
            lastError = "Could not set the terminal theme: \(String(describing: error))"
        }
    }

    /// Stops showing a suggestion for the project (kept in its project file).
    func ignoreSuggestion(_ id: String, for project: Project) {
        guard withSaved(project, { self.ignoreSuggestion(id, for: $0) }) else { return }
        guard let current = projects.project(named: project.name), !current.ignoredSuggestions.contains(id) else { return }
        var updated = current
        updated.ignoredSuggestions.append(id)
        do {
            try projectDirectory.save(updated)
            projects.remove(named: updated.name)
            try projects.insert(updated)
            lastError = nil
        } catch {
            lastError = "Could not ignore the suggestion: \(String(describing: error))"
        }
    }

    /// The operator confirms the project's current `sbxenv.yaml` (and own kits), declining `declined`
    /// runtime hosts. Refused entries cannot be confirmed.
    func approveEnvironment(_ project: Project, declined: Set<String>) {
        guard withSaved(project, { self.approveEnvironment($0, declined: declined) }) else { return }
        reloadConfig()
        readProjectFiles()
        guard let review = environmentReview(for: project), review.canApprove else { return }
        let approved = review.approve(project, declined: declined)
        do {
            try projectDirectory.save(approved)
            try projects.update(approved)
            lastError = nil
        } catch {
            fail("Could not confirm \(project.name)'s sbxenv.yaml: \(String(describing: error))", in: project.name)
            return
        }
        // The file the sandbox was created from, with other hosts declined: its denies change in
        // place (a sandbox deny beats a kit's allow), no recreate needed. A changed file waits for
        // its recreate, which applies the declines anyway.
        guard state(of: approved) != nil, approved.sandboxEnvironment == approved.approvedEnvironment else { return }
        let before = Set(project.declinedHosts)
        let after = Set(approved.declinedHosts)
        let newlyDeclined = after.subtracting(before).sorted()
        let allowedAgain = before.subtracting(after).sorted()
        guard !newlyDeclined.isEmpty || !allowedAgain.isEmpty else { return }
        let app = appConfig
        run("apply the declined hosts", on: approved) { runner in
            for host in newlyDeclined { try await runner.setHostRule(.deny, for: host, on: approved, app: app) }
            for host in allowedAgain { try await runner.setHostRule(nil, for: host, on: approved, app: app) }
        }
    }

    // MARK: - Gateway

    /// One listener per local-model project, matching the current files.
    func syncGateways() async {
        guard let gatewayHost else { return }
        let failures = await gatewayHost.sync(projects.projects, app: appConfig)
        let listeners = await gatewayHost.listeners
        gatewayPorts = Dictionary(uniqueKeysWithValues: projects.projects.compactMap { project in
            listeners[project.id].map { (project.name, $0.port) }
        })
        if let failure = failures.first {
            fail("The gateway for \(failure.key) did not start: \(failure.value)", in: failure.key)
        }
    }

    private static let maxLogEntries = 5000

    /// One entry per line. Entries from `activityLog` arrive from other tasks, so the sink hops to the main actor.
    /// - Parameter source: what it came from, when one thing (`LogEntry.source`).
    func appendLog(_ text: String, category: LogCategory = .paddock, source: String? = nil, isError: Bool = false) {
        let entries = Self.logEntries(text, category: category, source: source, isError: isError)
        for entry in entries { LogFile.shared.append(entry) }
        showLog(entries)
    }

    /// Verbose Log (System menu; the `verboseLog` default, off at first): `debugLog` lines say why
    /// things happen, such as what became of each voice message (PAD-119).
    var verboseLog = UserDefaults.standard.bool(forKey: "verboseLog") {
        didSet { UserDefaults.standard.set(verboseLog, forKey: "verboseLog") }
    }

    /// A line only Verbose Log keeps; the text is not even made otherwise.
    func debugLog(_ text: @autoclosure () -> String, category: LogCategory = .paddock, source: String? = nil) {
        guard verboseLog else { return }
        appendLog("[verbose] " + text(), category: category, source: source)
    }

    /// An error line reached the Log page while it was not shown: the sidebar's Log shows a red dot
    /// until the page is shown (PAD-122). Set only when it changes, so the dot redraws only then.
    private(set) var logHasUnseenErrors = false
    /// The Log page is shown now (set by the sidebar): its errors are seen as they come. Read by no
    /// view, so setting it redraws nothing.
    @ObservationIgnored var logIsShown = false {
        didSet { if logIsShown, logHasUnseenErrors { logHasUnseenErrors = false } }
    }

    /// How many denies Paddock suggests, for the sidebar's Network item (PAD-123). From the rules
    /// alone (suggestions do not depend on the network log), and only as often as a view asks.
    var suggestedDenyCount: Int {
        ruleRows().count(where: \.isSuggestion)
    }

    /// Adds lines already in the log file to the Log page.
    private func showLog(_ entries: [LogEntry]) {
        if !logIsShown, !logHasUnseenErrors, entries.contains(where: \.isError) { logHasUnseenErrors = true }
        errorLog.append(contentsOf: entries)
        if errorLog.count > Self.maxLogEntries { errorLog.removeFirst(errorLog.count - Self.maxLogEntries) }
    }

    nonisolated static func logEntries(_ text: String, category: LogCategory, source: String?, isError: Bool) -> [LogEntry] {
        LogEntry.lines(of: text, category: category, source: source, isError: isError)
    }

    /// For `ProjectRunner(log:)`: lines from a create, of `source` (the project) when
    /// known. They go to the log file at once, from the thread that reports them, and to the Log page
    /// when the main actor gets to them: a stuck main thread no longer keeps them out of the file (PAD-78).
    func activityLog(for source: String?) -> LogSink {
        { [weak self] text in
            let entries = AppModel.logEntries(text, category: .build, source: source, isError: false)
            for entry in entries { LogFile.shared.append(entry) }
            Task { @MainActor in self?.showLog(entries) }
        }
    }

    func clearErrorLog() {
        errorLog = []
        lastError = nil
    }

    private func record(_ entry: GatewayLogEntry) {
        gatewayLog.append(entry)
        if gatewayLog.count > 500 { gatewayLog.removeFirst(gatewayLog.count - 500) }
    }

    /// Opens paddock.yaml in the default editor, first writing one if there is none yet: every section with its defaults, commented out (`AppConfigFile.template`). The app
    /// reads it again when its sections are next used.
    func editAppConfig() {
        let path = paths.appConfig
        do {
            if !FileManager.default.fileExists(atPath: path) {
                try FileManager.default.createDirectory(atPath: paths.configDirectory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try Data(AppConfigFile.template.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            lastError = nil
        } catch {
            lastError = "Could not open \((path as NSString).lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Shows macOS's crash reports in Finder, with Paddock's newest one selected when there is one
    /// (`Paddock-<date>.ips`, written by the system; the app has no crash handler of its own).
    func revealCrashReports() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        let reports = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.lastPathComponent.hasPrefix("Paddock") && $0.pathExtension == "ips" } ?? []
        let newest = reports.max { modified($0) < modified($1) }
        if let newest {
            NSWorkspace.shared.activateFileViewerSelecting([newest])
        } else if !NSWorkspace.shared.open(dir) {
            lastError = "Could not open \(dir.path)"
        }
    }

    /// Captures Paddock when its main thread hangs, and says so once it answers again (PAD-121).
    @ObservationIgnored private let hangWatchdog = HangWatchdog()

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Opens a shell in the project's sandbox in the operator's own terminal app (`ExternalShell`).
    /// `sbx exec` starts a stopped sandbox.
    func openExternalShell(for project: Project) {
        guard let sbxPath else {
            lastError = "sbx was not found yet; see the status checks (click the dot)"
            return
        }
        openCommandFile(ExternalShell.fileName(sandbox: project.name), what: "a terminal for \(project.name)") {
            try ExternalShell.script(sbx: sbxPath, sandbox: project.name)
        }
    }

    /// Opens a shell on the Mac in the project folder, in the operator's own terminal app.
    func openHostShell(for project: Project) {
        openCommandFile(ExternalShell.hostFileName(project: project.name), what: "a shell in \(project.folder)") {
            try ExternalShell.hostScript(folder: project.folder, project: project.name)
        }
    }

    /// Shows the project folder in Finder.
    func showInFinder(_ project: Project) {
        let folder = URL(fileURLWithPath: project.folder, isDirectory: true)
        if NSWorkspace.shared.open(folder) {
            lastError = nil
        } else {
            lastError = "Could not open \(project.folder) in Finder"
        }
    }

    /// Writes a `.command` file into a folder of Paddock's own in the user's temporary folder and
    /// opens it with the app `.command` files open with (`ExternalShell`).
    private func openCommandFile(_ name: String, what: String, script: () throws -> String) {
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("paddock", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = dir.appendingPathComponent(name)
            try Data(try script().utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            guard NSWorkspace.shared.open(file) else { throw AppError("no app opens .command files") }
            lastError = nil
        } catch {
            lastError = "Could not open \(what): \(String(describing: error))"
        }
    }

    /// Opens the project folder's `sbxenv.yaml` in the default editor, first writing it and a kit
    /// for the project (`SandboxFiles`) when there is none. The agent can change these files too,
    /// so a change still needs the operator's confirmation.
    func openProjectConfig(_ project: Project) {
        let path = project.folder + "/" + SbxEnvFile.fileName
        do {
            if !FileManager.default.fileExists(atPath: path) {
                try writeSandboxFiles(for: project)
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            lastError = nil
        } catch {
            lastError = "Could not open \(SbxEnvFile.fileName): \(String(describing: error))"
        }
    }

    /// The project detail's "Create sbxenv.yaml" for a project added without one; errors show in the status popover.
    func createSandboxFiles(for project: Project) {
        do {
            try writeSandboxFiles(for: project)
            lastError = nil
        } catch {
            lastError = "Could not write \(SbxEnvFile.fileName): \(String(describing: error))"
        }
    }

    /// Writes `sbxenv.yaml` and the project's kit into its folder (New Project's "Create
    /// sbxenv.yaml", the Config button); refuses when one of them exists. What Paddock wrote on the
    /// operator's request is recorded as confirmed; their own edits afterwards ask again.
    func writeSandboxFiles(for project: Project) throws {
        reloadConfig()
        let sbxAgent = appConfig.agents[project.agent]?.sbxAgent ?? project.agent
        // sbx's own agents name their workload kit themselves.
        let input = SandboxFiles.Input(name: project.name, agent: sbxAgent)
        try SandboxFiles.write(SandboxFiles.files(input), into: project.folder)
        readProjectFiles()
        if let current = self.project(named: project.name) {
            approveEnvironment(current, declined: [])
        }
    }

    /// After the operator confirms. Errors show in the status popover.
    func clearPromptHistory() {
        Task {
            do {
                try await probe.clearPromptHistory()
                lastError = nil
            } catch {
                lastError = "Could not clear llmman's prompt history: \(error.localizedDescription)"
            }
            await refresh()
        }
    }

    /// The status popover's Refresh: finds the tools again, then reads everything again.
    func checkAgain() async {
        await probe.resetLookup()
        await reloadAll()
    }
}

/// A failure the app itself detects, with the text the status popover shows.
struct AppError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
