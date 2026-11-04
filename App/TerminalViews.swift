import PaddockCore
import PaddockShellCore
import PaddockShellUI
import SwiftUI

/// A project's tabs, kept by the app model so the sessions keep running while another project is
/// shown: terminal sessions (agent sessions and shells) and a browser tab per page the agent has
/// open, in two halves. The right half appears when a tab moves there and goes when it is empty
/// (backlog doc UI).
@Observable
@MainActor
final class ProjectTerminals {
    enum Half {
        case left, right

        var other: Half { self == .left ? .right : .left }
    }

    let sandbox: String
    private let sbx: String
    /// The project folder, where a shell on this Mac starts.
    private let folder: String

    /// The left half's tabs; Info is its first tab.
    var tabs = TerminalTabs()
    /// The right half's tabs.
    var rightTabs = TerminalTabs()
    private(set) var sessions: [UUID: SandboxShellSession] = [:]
    /// Each session's terminal view, kept while its tab is hidden (`TerminalViewCache`).
    let views = TerminalViewCache()
    /// Exit statuses of sessions that ended, by tab.
    private(set) var exits: [UUID: Int32] = [:]
    private(set) var problem: String?
    /// The agent's browser and shown tabs (from `paddock-browser-watch`), the half each host tab
    /// shows in (the left unless moved), host tabs with something the operator has not looked at,
    /// show tabs the operator closed (gone once the sandbox says so), and whether they closed the
    /// Playwright tab (it comes back with the next change).
    private(set) var browser = BrowserSessions()
    private var hostHalves: [String: Half] = [:]
    private(set) var unseen: Set<String> = []
    private var closedShows: Set<String> = []
    private var playwrightClosed = false
    /// The Processes tab is open (backlog doc UI, Resources); opened from Info, closed by the operator.
    private var processesOpen = false
    /// The renderer's form state for each interactive tab (`OpenUIMessage.state`), kept for the
    /// next view of it, and the last problems sent to the sandbox, so the same ones go once.
    private(set) var uiStates: [String: String] = [:]
    var uiProblemsSent: [String: String] = [:]

    func keepUIState(_ state: String, for id: String) {
        uiStates[id] = state
    }

    /// Native Markdown tabs the operator switched to the file's source (backlog doc Browser).
    var sourceShows: Set<String> = []

    /// Whether the operator's last answer in an interactive tab reached the sandbox, for the
    /// confirmation the tab shows (a serial, so each answer shows once).
    struct UIDelivery: Equatable {
        let serial: Int
        let sent: Bool
        let detail: String
    }

    private(set) var uiDeliveries: [String: UIDelivery] = [:]
    private var deliverySerial = 0

    func delivered(_ id: String, sent: Bool, detail: String) {
        deliverySerial += 1
        uiDeliveries[id] = UIDelivery(serial: deliverySerial, sent: sent, detail: detail)
    }

    /// What a host tab's view should do next (its menu's Refresh or Back), with a serial so the
    /// same command twice still counts.
    struct ViewCommand: Equatable {
        enum Kind: Equatable { case reload, back }
        let kind: Kind
        let serial: Int
    }

    private(set) var viewCommands: [String: ViewCommand] = [:]
    private var commandSerial = 0

    func send(_ kind: ViewCommand.Kind, to tab: String) {
        commandSerial += 1
        viewCommands[tab] = ViewCommand(kind: kind, serial: commandSerial)
    }

    /// The host tab menus' commands.
    static let refresh = TerminalTabs.HostTab.Action(id: "refresh", title: "Refresh", systemImage: "arrow.clockwise")
    static let back = TerminalTabs.HostTab.Action(id: "back", title: "Back", systemImage: "chevron.backward")

    init(sandbox: String, sbx: String, folder: String) {
        self.sandbox = sandbox
        self.sbx = sbx
        self.folder = folder
    }

    func tabs(_ half: Half) -> TerminalTabs { half == .left ? tabs : rightTabs }

    /// The tab the operator selected last, in either half; nil when it was Info or a host tab. The
    /// sidebar highlights its agent row (PAD-63).
    private(set) var activeTab: UUID?

    func setTabs(_ value: TerminalTabs, _ half: Half) {
        let changed = tabs(half).selection != value.selection
        if half == .left { tabs = value } else { rightTabs = value }
        if changed || value.selection != nil { activeTab = value.selection }
        // Selecting a session tab (a click in its bar, the shown one too, or a new tab) puts the
        // keyboard in its terminal.
        if let selected = value.selection, sessions[selected] != nil {
            focusRequest = (selected, (focusRequest?.serial ?? 0) + 1)
        }
        // Selecting an agent tab on screen is looking at it.
        if isOnScreen, let selected = value.selection { agentMarks.seen(selected) }
        showAgentActivity()
    }

    /// Whether the right half shows: it has a session or a browser tab.
    var isSplit: Bool { !rightTabs.tabs.isEmpty || !browserHostTabs(.right).isEmpty }

    /// Tabs whose session waits for its view: it starts once the terminal is laid out, so a
    /// full-screen program (OpenCode, for example) gets its terminal queries answered live,
    /// at the real size, as in any terminal app. Without that OpenCode never drew.
    private var waitingForView: Set<UUID> = []

    /// Opens a tab. An agent session (`sbx run --name N`) also starts a stopped sandbox.
    func open(_ kind: TerminalTabs.Kind, in half: Half = .left) {
        var bar = tabs(half)
        let tab = bar.add(kind)
        // The agent's status hooks report this ID with the state (backlog doc Kits, Agent status); a
        // shell has it too, for an agent the operator starts in it (PAD-64).
        let session = SandboxShellSession(sandbox: sandbox, kind: sessionKind(kind), sbx: sbx,
                                          sandboxEnvironment: ["PADDOCK_TAB": tab.id.uuidString])
        sessions[tab.id] = session
        // After the session is there, so selecting the new tab focuses its terminal.
        setTabs(bar, half)
        watch(session, tab: tab.id)
        waitingForView.insert(tab.id)
        // Started anyway if the view never reports in, so a tab never stays empty.
        Task { [weak self, id = tab.id] in
            try? await Task.sleep(for: .seconds(2))
            self?.viewIsReady(id)
        }
    }

    private func sessionKind(_ kind: TerminalTabs.Kind) -> SandboxShellSession.Kind {
        switch kind {
        case .agent: .agent
        case .shell: .bash
        // The operator's login shell, as in Terminal (`ExternalShell.hostScript`).
        case .mac: .mac(folder: folder, shell: ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? "/bin/zsh")
        }
    }

    /// The tab whose terminal should take keyboard focus, and a serial that rises with each request
    /// (`SandboxTerminalView`'s `focus`).
    private(set) var focusRequest: (tab: UUID, serial: Int)?

    /// Focuses the terminal of the selected tab: the left half's, else the right half's.
    func focusSelectedTerminal() {
        guard let tab = [tabs.selected, rightTabs.selected].compactMap({ $0 }).first(where: { sessions[$0.id] != nil }) else {
            return
        }
        focusRequest = (tab.id, (focusRequest?.serial ?? 0) + 1)
    }

    /// This tab's focus request for its terminal view; 0 when the last request was another tab's.
    func focus(for tab: UUID) -> Int {
        focusRequest.map { $0.tab == tab ? $0.serial : 0 } ?? 0
    }

    /// The tab's terminal view is laid out and live.
    func viewIsReady(_ id: UUID) {
        guard waitingForView.remove(id) != nil else { return }
        start(id)
    }

    /// The tab's own title ("agent 2"), in either half.
    func title(of tab: UUID) -> String? {
        (tabs.tabs + rightTabs.tabs).first { $0.id == tab }?.title
    }

    /// The title the tab's program set (untrusted; `TerminalTabs` sanitizes it).
    func setTitle(_ raw: String, for id: UUID) {
        tabs.setTerminalTitle(raw, for: id)
        rightTabs.setTerminalTitle(raw, for: id)
    }

    // MARK: Agent status

    /// What the agents in this sandbox say they are doing (from `paddock-agent-watch`, backlog doc Kits,
    /// Agent status). Display only: it marks tabs and the project, and decides nothing.
    private(set) var agents = AgentStates()

    func receiveAgent(_ line: String) {
        agents.apply(line: line)
        showAgentActivity()
    }

    func clearAgent() {
        agents = AgentStates()
        showAgentActivity()
    }

    /// The watcher starts again: keep what is shown until it reported every session (`AgentStates`).
    func beginAgentResync() {
        agents.beginResync()
    }

    func endAgentResync() {
        agents.endResync()
        showAgentActivity()
    }

    private var agentMarks = AgentTabMarks()

    /// The project is on screen and Paddock is the active app: only then is a selected tab looked at
    /// (PAD-63). The app sets it.
    private(set) var isOnScreen = false

    func setOnScreen(_ value: Bool) {
        guard value != isOnScreen else { return }
        isOnScreen = value
        if value {
            for selected in [tabs.selection, rightTabs.selection].compactMap({ $0 }) { agentMarks.seen(selected) }
        }
        showAgentActivity()
    }

    /// The agents under the project in the sidebar (`SidebarAgents`): its session tabs in tab-bar
    /// order, left half first, then the sessions in no open tab.
    func sidebarAgents(now: Date) -> [SidebarAgentRow] {
        let bars = [tabs, rightTabs].flatMap { bar in
            bar.arranged(hosts: []).compactMap { item -> TerminalTabs.Tab? in
                guard case .session(let id) = item else { return nil }
                return bar.tabs.first { $0.id == id }
            }
        }
        let sessionTabs = bars.filter { $0.kind != .mac }
            .map { tab in
                // The text the tab bar shows: the program's title (its leading symbol split off), else the name.
                SidebarAgents.Tab(id: tab.id, title: tab.title, label: tab.terminalTitle == nil ? nil : tab.label.text,
                                  isAgent: tab.kind == .agent)
            }
        return SidebarAgents.rows(tabs: sessionTabs, marks: { self.agentMarks.mark(of: $0) }, states: agents, now: now)
    }

    /// Shows a tab from the sidebar: selects it in its half, which focuses its terminal and clears
    /// its finished mark (`setTabs`).
    func select(tab id: UUID) {
        for half in [Half.left, .right] where tabs(half).tabs.contains(where: { $0.id == id }) {
            var bar = tabs(half)
            bar.selection = id
            setTabs(bar, half)
        }
    }

    /// Each agent tab, and each shell tab an agent runs in, shows its own session: a mark while it
    /// works, another while it waits for the operator, and a third once it stopped while the tab was
    /// not in view, until the operator opens it.
    private func showAgentActivity() {
        for tab in tabs.tabs + rightTabs.tabs where tab.kind == .agent || tab.kind == .shell {
            let shown = isOnScreen && (tabs.selection == tab.id || rightTabs.selection == tab.id)
            let mark = agentMarks.update(tab: tab.id, activity: agents.activity(ofTab: tab.id), isShown: shown)
            let activity: TerminalTabs.HostTab.Activity = switch mark {
            case .none: .none
            case .working: .busy
            case .waiting: .attention
            case .finished: .unseen
            }
            tabs.setActivity(activity, for: tab.id)
            rightTabs.setActivity(activity, for: tab.id)
        }
    }

    /// Runs an ended session again in the same tab.
    func restart(_ id: UUID) {
        start(id)
    }

    func close(_ tab: TerminalTabs.Tab) {
        if let session = sessions[tab.id] {
            views.release(session)
            Task { await session.terminate() }
        }
        sessions[tab.id] = nil
        exits[tab.id] = nil
        waitingForView.remove(tab.id)
        agentMarks.forget(tab.id)
        tabs.close(tab.id)
        rightTabs.close(tab.id)
        if activeTab == tab.id { activeTab = tabs.selection ?? rightTabs.selection }
    }

    /// Moves a tab to the other half, from its context menu or a drag; before `target` when it
    /// was dropped on a tab. Its session keeps running.
    func move(_ item: TerminalTabs.Item, to half: Half, before target: TerminalTabs.Item? = nil) {
        switch item {
        case .session(let id):
            var source = tabs(half.other), destination = tabs(half)
            guard let tab = source.take(id) else { return }
            destination.insert(tab, before: target)
            setTabs(source, half.other)
            setTabs(destination, half)
        case .host(let id):
            guard id == Self.playwrightTab || id == Self.processesTab || Self.showID(id).map({ show in browser.shows.contains { $0.id == show } }) == true else { return }
            hostHalves[id] = half
            var source = tabs(half.other), destination = tabs(half)
            if source.shownHostTab(offered: [id]) == id { source.selectHost(nil) }
            destination.place(item, before: target)
            destination.selectHost(id)
            setTabs(source, half.other)
            setTabs(destination, half)
        }
    }

    // MARK: Browser and show tabs

    /// The Playwright tab: the dashboard with all the agent's sessions.
    static let playwrightTab = "playwright"

    /// The Processes tab: what runs in the sandbox (backlog doc UI, Resources).
    static let processesTab = "processes"

    /// Opens the Processes tab, or shows it if it is open.
    func openProcesses() {
        processesOpen = true
        place(Self.processesTab)
        var bar = tabs(half(of: Self.processesTab))
        bar.selectHost(Self.processesTab)
        setTabs(bar, half(of: Self.processesTab))
    }

    /// The host tab id of a `paddock` tab.
    static func showTab(_ id: String) -> String { "show:" + id }

    static func showID(_ tab: String) -> String? {
        tab.hasPrefix("show:") ? String(tab.dropFirst("show:".count)) : nil
    }

    func half(of tab: String) -> Half { hostHalves[tab] ?? .left }

    /// The agent's own sessions (not the one shown tabs live in).
    private var agentSessions: [String] {
        Array(Set(browser.pages.map(\.session))).filter { $0 != BrowserShow.session }.sorted()
    }

    /// One half's host tabs: the Playwright tab (once the agent has a session; green) and a tab per
    /// shown thing (the accent color, orange when it renders on the Mac), with their activity.
    func browserHostTabs(_ half: Half) -> [TerminalTabs.HostTab] {
        var result: [TerminalTabs.HostTab] = []
        if processesOpen, self.half(of: Self.processesTab) == half {
            result.append(TerminalTabs.HostTab(
                id: Self.processesTab, title: "Processes", systemImage: "cpu",
                help: "What runs in the sandbox now: CPU and memory by app, read every 5 seconds while shown",
                style: .standard, closable: true, activity: .none, actions: []))
        }
        let sessions = agentSessions
        if !sessions.isEmpty, !playwrightClosed, self.half(of: Self.playwrightTab) == half {
            let busy = !browser.busy.subtracting([BrowserShow.session]).isEmpty
            // An agent waits for the operator to annotate its page (show --annotate): it says so.
            let waiting = !browser.annotating.isEmpty
            let help = waiting
                ? "The agent asks you to mark something on its page (\(browser.annotating.sorted().joined(separator: ", "))): open this tab"
                : "The agent's browser: \(sessions.joined(separator: ", "))"
            result.append(TerminalTabs.HostTab(
                id: Self.playwrightTab, title: "Playwright", systemImage: "theatermasks",
                help: help,
                style: .browser, closable: true,
                activity: waiting ? .attention : busy ? .busy : unseen.contains(Self.playwrightTab) ? .unseen : .none,
                actions: [Self.refresh]))
        }
        for show in browser.shows where !closedShows.contains(show.id) && self.half(of: Self.showTab(show.id)) == half {
            let tab = Self.showTab(show.id)
            let place = show.isInteractive ? "Asks you for an answer; the agent gets your clicks and form values"
                : show.isNative ? "Renders on this Mac; opens only when you click it" : "Renders in the sandbox"
            result.append(TerminalTabs.HostTab(
                id: tab, title: show.title,
                systemImage: show.isInteractive ? "rectangle.and.pencil.and.ellipsis" : show.isNative ? "doc.richtext" : "eye",
                help: [show.title, show.note, place].filter { !$0.isEmpty }.joined(separator: "\n"),
                style: show.isInteractive ? .interactive : show.isNative ? .local : .web, closable: true,
                activity: show.annotating ? .attention : unseen.contains(tab) ? .unseen : .none,
                actions: show.isInteractive ? [Self.refresh] : [Self.refresh, Self.back]))
        }
        return result
    }

    /// Whether either half shows the host tab now.
    func isShown(_ tab: String) -> Bool {
        [Half.left, .right].contains { tabs($0).shownHostTab(offered: [tab]) == tab }
    }

    /// A line from `paddock-browser-watch`. New shown things and changes in the agent's browser are
    /// marked unseen unless the operator is looking; nothing switches the operator's view.
    func receiveBrowser(_ line: String) {
        switch browser.apply(line: line) {
        case .pages(let changed, _):
            let agentChanges = changed.contains { BrowserSessions.sessionAndIndex(of: $0)?.session != BrowserShow.session }
            if agentChanges {
                playwrightClosed = false
                if !isShown(Self.playwrightTab) { unseen.insert(Self.playwrightTab) }
                place(Self.playwrightTab)
            }
        case .idle(let session):
            if session != BrowserShow.session, !isShown(Self.playwrightTab) { unseen.insert(Self.playwrightTab) }
        case .annotate(_, let active):
            // A closed Playwright tab comes back for it.
            if active {
                playwrightClosed = false
                place(Self.playwrightTab)
            }
        case .shows(let added, let gone):
            for id in added {
                unseen.insert(Self.showTab(id))
                place(Self.showTab(id))
            }
            for id in gone {
                let tab = Self.showTab(id)
                uiStates[id] = nil
                uiProblemsSent[id] = nil
                sourceShows.remove(id)
                closedShows.remove(id)
                unseen.remove(tab)
                hostHalves[tab] = nil
                deselect(tab)
            }
        case .busy, .none:
            break
        }
    }

    /// The operator looks at a host tab now.
    func markSeen(_ tab: String) {
        unseen.remove(tab)
    }

    /// The operator closed a show tab (the app tells the sandbox) or the Playwright tab (it comes
    /// back with the next change).
    func closeHostTab(_ tab: String) {
        if tab == Self.playwrightTab {
            playwrightClosed = true
        } else if tab == Self.processesTab {
            processesOpen = false
        } else if let id = Self.showID(tab) {
            closedShows.insert(id)
        }
        unseen.remove(tab)
        deselect(tab)
    }

    /// The sandbox stopped: its browser and shown tabs are gone.
    func clearBrowser() {
        deselect(Self.playwrightTab)
        for show in browser.shows { deselect(Self.showTab(show.id)) }
        browser = BrowserSessions()
        hostHalves = [:]
        unseen = []
        closedShows = []
        sourceShows = []
        playwrightClosed = false
    }

    /// A new host tab takes its place among the tabs now, so tabs opened later come after it.
    private func place(_ tab: String) {
        var bar = tabs(half(of: tab))
        guard !bar.isPlaced(.host(tab)) else { return }
        bar.place(.host(tab))
        setTabs(bar, half(of: tab))
    }

    private func deselect(_ tab: String) {
        for half in [Half.left, .right] {
            var bar = tabs(half)
            if bar.shownHostTab(offered: [tab]) == tab {
                bar.selectHost(nil)
                setTabs(bar, half)
            }
        }
    }

    // MARK: Sessions

    /// Ends every session's process (the sandbox itself keeps its state).
    func terminateAll() {
        views.releaseAll()
        for session in sessions.values {
            Task { await session.terminate() }
        }
    }

    /// Ends every session's process and waits for them, before the sandbox stops. The tabs stay,
    /// with Run Again.
    func endAll() async {
        await withTaskGroup(of: Void.self) { group in
            for session in sessions.values {
                group.addTask { await session.end() }
            }
        }
    }

    private func start(_ id: UUID) {
        guard let session = sessions[id] else { return }
        exits[id] = nil
        Task {
            do {
                try await session.start()
                problem = nil
            } catch {
                problem = "The session did not start: \(String(describing: error))"
            }
        }
    }

    private func watch(_ session: SandboxShellSession, tab: UUID) {
        Task { [weak self] in
            for await event in await session.attach() {
                if case .exited(let code) = event {
                    self?.exits[tab] = code
                }
            }
        }
    }
}

/// The project view's tabs, in one half or two side by side (the standard split view, with a
/// divider to drag). The left half starts with Info, an icon that turns orange when something
/// needs the operator. Terminal tabs, the Playwright tab (green; the agent's browser, one per
/// project), and a tab per thing the agent shows (the accent color, orange when it renders on the
/// Mac) follow, mixed in one order and alike except for color, then "+". Host tabs show activity:
/// the Playwright tab's icon gets an agent tab's marks (backlog doc UI, Status marks). A tab's context menu moves it to the other half, and so does
/// dragging it onto the other half's tab bar.
struct ProjectTabs<Info: View>: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let needsAttention: Bool
    let info: Info

    init(project: Project, needsAttention: Bool, @ViewBuilder info: () -> Info) {
        self.project = project
        self.needsAttention = needsAttention
        self.info = info()
    }

    var body: some View {
        let terminals = model.terminals[project.name]
        Group {
            if let terminals, terminals.isSplit {
                HSplitView {
                    half(.left, terminals: terminals)
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                    half(.right, terminals: terminals)
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                half(.left, terminals: terminals)
            }
        }
        // Selecting the project (in the sidebar) puts the keyboard in its open terminal.
        .task(id: project.name) { model.terminals[project.name]?.focusSelectedTerminal() }
    }

    private func half(_ half: ProjectTerminals.Half, terminals: ProjectTerminals?) -> some View {
        let bar = terminals?.tabs(half) ?? TerminalTabs()
        let hostTabs = terminals?.browserHostTabs(half) ?? []
        // Only a tab the operator selected: a tab rendered on the Mac must never open by itself.
        let shownHost = bar.shownHostTab(offered: hostTabs.map(\.id))
        return VStack(spacing: 0) {
            TerminalTabBar(
                tabs: Binding(get: { terminals?.tabs(half) ?? TerminalTabs() },
                              set: { model.openTerminals(for: project)?.setTabs($0, half) }),
                hostTabs: hostTabs,
                showsLeading: half == .left,
                offersAgent: half == .left,
                moveTitle: half == .left ? "Move to Right Half" : "Move to Left Half",
                add: { kind in model.openSession(kind, in: project, half: half) },
                close: { terminals?.close($0) },
                closeHost: { host in model.closeHostTab(host.id, of: project) },
                hostAction: { host, action in model.hostAction(action.id, on: host.id, of: project) },
                move: { item in terminals?.move(item, to: half.other) },
                receive: { item, before in terminals?.move(item, to: half, before: before) }
            ) {
                Image(systemName: needsAttention ? "info.circle.fill" : "info.circle")
                    .foregroundStyle(needsAttention ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .help(needsAttention ? "Info: something needs your attention" : "Info")
                    .accessibilityLabel(needsAttention ? "Info, needs attention" : "Info")
            }
            // The bar keeps its own height; the content below takes the rest.
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            if let terminals, let tab = bar.selected, let session = terminals.sessions[tab.id] {
                ZStack(alignment: .topTrailing) {
                    SandboxTerminalView(session: session, cache: terminals.views, focus: terminals.focus(for: tab.id),
                                        theme: TerminalTheme.named(project.terminalTheme),
                                        onTitle: { terminals.setTitle($0, for: tab.id) },
                                        onReady: { terminals.viewIsReady(tab.id) })
                        .id(tab.id)
                    if terminals.exits[tab.id] != nil {
                        Button("Run Again", systemImage: "arrow.clockwise") { terminals.restart(tab.id) }
                            .padding(8)
                    }
                    // An agent's question: over its own tab, or the left half's when its tab is not shown.
                    let ask = model.voice.asks(for: project).first(where: { $0.tab == tab.id })
                        ?? (half == .left ? model.voice.asks(for: project).first : nil)
                    let agentTab = tab.kind == .agent && model.voice.isChosen(project) ? tab.id : nil
                    let entries = model.voice.conversation(for: project, tab: agentTab, untabbed: half == .left)
                    if agentTab != nil || ask != nil || !entries.isEmpty {
                        VoiceControls(project: project, terminal: tab.id, tab: agentTab, ask: ask, entries: entries)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
                .task(id: tab.id) { model.voice.focus(project: project, tab: tab.kind == .agent ? tab.id : nil) }
                if let problem = terminals.problem {
                    Text(problem).foregroundStyle(.red).font(.callout).padding(6)
                }
                // Under the terminal, where the operator is when the agent stops to wait (one half
                // only: the left when both show a terminal). A row of its own, so nothing covers it;
                // Info lists the requests anyway.
                if half == .left || terminals.tabs.selected == nil, let request = model.approvalRequests(for: project).first {
                    ApprovalBanner(project: project, request: request, more: model.approvalRequests(for: project).count - 1)
                }
            } else if let shownHost, let terminals {
                hostContent(shownHost, terminals: terminals)
                    .id(shownHost)
                    .task(id: shownHost) { model.openedHostTab(shownHost, of: project) }
                    // A placeholder is not as tall as the half: without this the bar would sit mid-height.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if half == .left {
                info
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The Playwright tab's dashboard, a show tab's page, or a native tab's file.
    @ViewBuilder
    private func hostContent(_ tab: String, terminals: ProjectTerminals) -> some View {
        if tab == ProjectTerminals.playwrightTab {
            BrowserTab(project: project, content: .dashboard)
        } else if tab == ProjectTerminals.processesTab {
            SandboxProcessesTab(project: project)
        } else if let id = ProjectTerminals.showID(tab), let show = terminals.browser.shows.first(where: { $0.id == id }) {
            if show.isInteractive {
                OpenUIView(project: project, show: show)
            } else if show.isNative {
                NativeShowView(project: project, show: show)
            } else {
                BrowserTab(project: project, content: .show(show))
            }
        } else {
            Color.clear
        }
    }
}
