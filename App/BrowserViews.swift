import AppKit
import PaddockCore
import SwiftUI
import WebKit

/// playwright-cli's dashboard from the sandbox (backlog doc Browser), in a sealed web view: the whole
/// dashboard in the Playwright tab, or one shown page in a show tab (the session list hidden and
/// the page selected once it loaded, `BrowserActivity.showScript`). The operator watches it live
/// and can take over. Pages render in the sandbox; only the dashboard shows here.
struct BrowserTab: View {
    enum Content {
        case dashboard
        case show(BrowserSessions.Show)
    }

    @Environment(AppModel.self) private var model
    let project: Project
    let content: Content
    /// Bumped by Reload, so the web view loads again.
    @State private var generation = 0
    /// What answered on the published port (`BrowserKit.dashboardAnswer`); nil while checking.
    @State private var answer: BrowserKit.DashboardAnswer?

    var body: some View {
        let state = model.state(of: project)
        let dashboard = model.snapshots[project.name].flatMap { BrowserKit.dashboardURL(ports: $0.ports) }
        Group {
            if state != .running {
                placeholder("The sandbox is not running", detail: "Start it to see the agent's browser sessions.")
            } else if BrowserKit.isInSandbox(of: project, paths: model.paths) == false {
                placeholder("The sandbox was created without the browser kit", detail: "Recreate it from Needs attention on the Info tab.")
            } else if let dashboard, let policy = BrowserWebPolicy(dashboard: dashboard), answer == .otherServer {
                placeholder("Another server holds the dashboard's port",
                            detail: "Port \(BrowserKit.dashboardPort) in the sandbox does not answer like playwright-cli's dashboard. Stop what serves there, then restart the sandbox.") {
                    Button("Check Again") { generation += 1 }
                }
                .task(id: "\(policy.port)-\(generation)") { await check(policy) }
            } else if let dashboard, let policy = BrowserWebPolicy(dashboard: dashboard), answer == BrowserKit.DashboardAnswer.none {
                placeholder("The dashboard is not running",
                            detail: "Nothing answers on port \(BrowserKit.dashboardPort) in the sandbox. Its log is /tmp/playwright-dashboard.log there.") {
                    Button("Start Dashboard") { startDashboard() }
                }
                .task(id: "\(policy.port)-\(generation)") { await check(policy) }
            } else if let dashboard, let policy = BrowserWebPolicy(dashboard: dashboard) {
                VStack(spacing: 0) {
                    if case .show = content, script == nil {
                        // Until the watcher reports the shown page in the paddock session.
                        ProgressView("Waiting for the page").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if answer == .dashboard {
                        BrowserWebView(policy: policy, selectScript: script) { file, name, selectedSession in
                            model.captured(file: file, suggestedName: name, owner: captureOwner(selectedSession: selectedSession), of: project)
                        }
                            .id("\(policy.port)-\(generation)-\(script?.hashValue ?? 0)")
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .task(id: "\(policy.port)-\(generation)") { await check(policy) }
            } else {
                placeholder("The dashboard is not published yet",
                            detail: "sbx publishes it once the browser kit has started it in the sandbox (port \(BrowserKit.dashboardPort)).") {
                    Button("Check Again") { Task { await model.refreshSnapshot(project.name) } }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: project.name) { await model.refreshSnapshot(project.name) }
        // The tab menu's Refresh (the Playwright tab's dashboard; a shown page reloads in the sandbox).
        .onChange(of: model.terminals[project.name]?.viewCommands[tabID]) { _, command in
            if command?.kind == .reload { generation += 1 }
        }
    }

    /// Whose page a capture from this view shows: the show tab's, or in the Playwright tab the
    /// session selected in the dashboard.
    private func captureOwner(selectedSession: String?) -> BrowserCapture.Owner? {
        switch content {
        case .show(let show): .show(show.id)
        case .dashboard: selectedSession.map { .session($0) }
        }
    }

    /// This view's host tab, for the commands of its menu.
    private var tabID: String {
        switch content {
        case .dashboard: ProjectTerminals.playwrightTab
        case .show(let show): ProjectTerminals.showTab(show.id)
        }
    }

    /// The show tab's page in the `paddock` session; nil for the whole dashboard.
    private var script: String? {
        guard case .show(let show) = content, let page = model.terminals[project.name]?.browser.page(of: show) else { return nil }
        return BrowserActivity.showScript(index: page.index)
    }

    /// Whether this view started the dashboard already (once on its own; Start Dashboard again).
    @State private var startedDashboard = false

    /// Checks the port; when nothing answers, starts the dashboard once and checks again.
    private func check(_ policy: BrowserWebPolicy) async {
        let found = await Self.answer(policy.homeURL)
        if found == .none, !startedDashboard {
            startDashboard()
            return
        }
        answer = found
    }

    private func startDashboard() {
        startedDashboard = true
        answer = nil
        Task {
            await model.startBrowserDashboard(of: project)
            try? await Task.sleep(for: .seconds(3))
            generation += 1
        }
    }

    /// Asks the published port for `/`: the dashboard redirects to `/index.html?ws=...`. Only
    /// whether it answered and where it led are looked at, never the body (it comes from the sandbox).
    private static func answer(_ url: URL) async -> BrowserKit.DashboardAnswer {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        guard let (_, response) = try? await session.data(for: request) else { return .none }
        return BrowserKit.dashboardAnswer(answered: true, finalURL: response.url)
    }

    private func placeholder(_ title: String, detail: String) -> some View {
        placeholder(title, detail: detail) { EmptyView() }
    }

    private func placeholder(_ title: String, detail: String, @ViewBuilder actions: () -> some View) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "globe")
        } description: {
            Text(detail)
        } actions: {
            actions()
        }
    }
}

/// The dashboard in a web view that keeps no data and reaches only the dashboard's origin
/// (`BrowserWebPolicy`): WebKit content rules cover every resource and WebSocket, and the
/// navigation delegate covers page navigations. If the rules cannot be installed, nothing loads.
struct BrowserWebView: NSViewRepresentable {
    let policy: BrowserWebPolicy
    /// Run once the dashboard loaded, to select this view's page. Paddock's own script with a
    /// checked session name; its result is ignored.
    var selectScript: String?
    /// A screenshot or recording the operator saved from the dashboard (a download): the file in a
    /// temporary folder, its suggested name, and the session selected in this view (if any).
    var captured: @MainActor (URL, String, String?) -> Void = { _, _, _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(policy: policy, selectScript: selectScript, captured: captured)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Nothing the sandbox's page stores outlives the view.
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.load(into: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.cancel()
        nsView.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        private let policy: BrowserWebPolicy
        private let selectScript: String?
        private let captured: @MainActor (URL, String, String?) -> Void
        private var loading: Task<Void, Never>?
        /// Downloads in progress: where each goes, and its suggested name.
        private var downloads: [ObjectIdentifier: (file: URL, name: String)] = [:]

        init(policy: BrowserWebPolicy, selectScript: String?, captured: @escaping @MainActor (URL, String, String?) -> Void) {
            self.policy = policy
            self.selectScript = selectScript
            self.captured = captured
        }

        // The dashboard's Save screenshot and Record video end in a download (a blob: link). It
        // goes to a temporary file, never to the operator's folders, and from there to the sandbox.
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-captures", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = folder.appendingPathComponent(UUID().uuidString)
            downloads[ObjectIdentifier(download)] = (file, suggestedFilename)
            return file
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let (file, name) = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
            guard let webView = download.webView else {
                captured(file, name, nil)
                return
            }
            webView.evaluateJavaScript(BrowserCapture.selectedSessionScript) { [captured] result, _ in
                captured(file, name, result as? String)
            }
        }

        func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
            if let (file, _) = downloads.removeValue(forKey: ObjectIdentifier(download)) {
                try? FileManager.default.removeItem(at: file)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            guard let selectScript, webView.url.map(policy.allows) == true else { return }
            webView.evaluateJavaScript(selectScript, completionHandler: nil)
        }

        func load(into webView: WKWebView) {
            loading = Task { [weak webView, policy] in
                do {
                    let store: WKContentRuleListStore? = WKContentRuleListStore.default()
                    let compiled: WKContentRuleList? = try await store?.compileContentRuleList(
                        forIdentifier: policy.ruleListIdentifier, encodedContentRuleList: policy.contentRules)
                    guard let rules = compiled else {
                        webView?.loadHTMLString(Self.failClosedPage, baseURL: nil)
                        return
                    }
                    guard let webView, !Task.isCancelled else { return }
                    webView.configuration.userContentController.add(rules)
                    webView.load(URLRequest(url: policy.homeURL))
                } catch {
                    webView?.loadHTMLString(Self.failClosedPage, baseURL: nil)
                }
            }
        }

        func cancel() {
            loading?.cancel()
        }

        static let failClosedPage = """
            <body style="font: -apple-system-body; color: gray; padding: 2em">
            Paddock could not install its web content rules, so the browser dashboard stays off.
            </body>
            """

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.shouldPerformDownload { return .download }
            guard let url = navigationAction.request.url, policy.allows(url) else { return .cancel }
            return .allow
        }

        /// `window.open` and `target=_blank`: never a second web view, and nothing opens on the Mac.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            nil
        }
    }
}

/// A tab the agent asked to render on this Mac (`paddock --native`; backlog doc Browser). It is
/// only created once the operator opened the tab. Text renders natively; anything else renders in a
/// sealed web view whose files come one by one from the sandbox (`NativeShowWebView`), Markdown as
/// Paddock's own page (`MarkdownPage`), with a switch to the file's source.
struct NativeShowView: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let show: BrowserSessions.Show
    @State private var text: String?
    @State private var problem: String?

    var body: some View {
        let policy = NativeShowPolicy(showID: show.id, fileName: show.fileName)
        let command = model.terminals[project.name]?.viewCommands[ProjectTerminals.showTab(show.id)]
        Group {
            if let policy {
                switch policy.rendering {
                case .web:
                    NativeShowWebView(policy: policy, command: command) { path in
                        try await model.readShowFile(show: show.id, relativePath: path, of: project)
                    }
                    // The agent reloaded it or pointed it at another file: load it again.
                    .id(show.revision)
                case .markdown:
                    let source = model.terminals[project.name]?.sourceShows.contains(show.id) ?? false
                    Group {
                        if source {
                            plainText(policy, command: command)
                        } else {
                            NativeShowWebView(policy: policy, command: command) { path in
                                try await model.readShowFile(show: show.id, relativePath: path, of: project)
                            }
                            .id(show.revision)
                        }
                    }
                    .overlay(alignment: .topTrailing) { sourceSwitch(source: source) }
                case .text:
                    plainText(policy, command: command)
                }
            } else {
                ContentUnavailableView("Paddock does not show \(show.fileName)", systemImage: "doc.questionmark")
            }
        }
    }

    /// Rendered or the file as it is, kept per tab while Paddock runs.
    private func sourceSwitch(source: Bool) -> some View {
        Picker("View", selection: Binding(
            get: { source },
            set: { wantsSource in
                if wantsSource {
                    model.terminals[project.name]?.sourceShows.insert(show.id)
                } else {
                    model.terminals[project.name]?.sourceShows.remove(show.id)
                }
            }
        )) {
            Text("Rendered").tag(false)
            Text("Source").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .padding(8)
        .help("Show the Markdown rendered, or the file as it is")
    }

    private func plainText(_ policy: NativeShowPolicy, command: ProjectTerminals.ViewCommand?) -> some View {
        textContent()
            // Refresh reads the file again; Back means nothing here.
            .task(id: "\(show.revision)-\(command?.kind == .reload ? command?.serial ?? 0 : 0)") { await loadText(policy) }
    }

    @ViewBuilder
    private func textContent() -> some View {
        if let problem {
            ContentUnavailableView("The file did not load", systemImage: "exclamationmark.triangle", description: Text(problem))
        } else if let text {
            ScrollView {
                Text(text).monospaced()
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    // Room for the Rendered/Source switch above the first line.
                    .padding(.top, NativeShowPolicy.isMarkdown(show.fileName) ? 24 : 0)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadText(_ policy: NativeShowPolicy) async {
        do {
            let data = try await model.readShowFile(show: show.id, relativePath: policy.fileName, of: project)
            text = String(decoding: data, as: UTF8.self)
        } catch {
            problem = String(describing: error)
        }
    }
}

/// The web view for a native tab: keeps no data, loads only `paddock-file://<tab id>/...`, each
/// file read from the sandbox when the page asks for it (`NativeShowPolicy`). WebKit content rules
/// block every other load (network and WebSockets included), and the navigation delegate every
/// other navigation; nothing opens a window or anything on the Mac. If the rules cannot be
/// installed, nothing loads.
struct NativeShowWebView: NSViewRepresentable {
    let policy: NativeShowPolicy
    /// The tab menu's latest Refresh or Back.
    let command: ProjectTerminals.ViewCommand?
    let read: @MainActor (String) async throws -> Data

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(policy: policy, read: read)
        // A command from before this view existed is not for it.
        coordinator.lastCommand = command?.serial
        return coordinator
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // Markdown is Paddock's own page: it needs no JavaScript, so none runs.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = policy.allowsJavaScript
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: NativeShowPolicy.scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.load(into: webView)
        return webView
    }

    /// A new command from the tab menu: Refresh reads the files again, Back goes back in the page.
    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard let command, command.serial != context.coordinator.lastCommand else { return }
        context.coordinator.lastCommand = command.serial
        switch command.kind {
        case .reload: nsView.reload()
        case .back: nsView.goBack()
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.cancel()
        nsView.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKURLSchemeHandler {
        /// The serial of the last command done (`ProjectTerminals.ViewCommand`).
        var lastCommand: Int?
        private let policy: NativeShowPolicy
        private let read: @MainActor (String) async throws -> Data
        private var loading: Task<Void, Never>?
        /// Requests still running; a stopped one gets no more calls (WebKit forbids them).
        private var running: Set<ObjectIdentifier> = []

        init(policy: NativeShowPolicy, read: @escaping @MainActor (String) async throws -> Data) {
            self.policy = policy
            self.read = read
        }

        func load(into webView: WKWebView) {
            loading = Task { [weak webView, policy] in
                do {
                    let store: WKContentRuleListStore? = WKContentRuleListStore.default()
                    let compiled: WKContentRuleList? = try await store?.compileContentRuleList(
                        forIdentifier: policy.ruleListIdentifier, encodedContentRuleList: policy.contentRules)
                    guard let rules = compiled, let home = policy.homeURL else {
                        webView?.loadHTMLString(Self.failClosedPage, baseURL: nil)
                        return
                    }
                    guard let webView, !Task.isCancelled else { return }
                    webView.configuration.userContentController.add(rules)
                    webView.load(URLRequest(url: home))
                } catch {
                    webView?.loadHTMLString(Self.failClosedPage, baseURL: nil)
                }
            }
        }

        func cancel() {
            loading?.cancel()
        }

        static let failClosedPage = """
            <body style="font: -apple-system-body; color: gray; padding: 2em">
            Paddock could not install its web content rules, so this file stays closed.
            </body>
            """

        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            let id = ObjectIdentifier(urlSchemeTask)
            guard let url = urlSchemeTask.request.url, let path = policy.relativePath(of: url) else {
                urlSchemeTask.didFailWithError(URLError(.badURL))
                return
            }
            running.insert(id)
            Task {
                do {
                    // Markdown arrives as Paddock's rendered page (MarkdownPage).
                    let (data, mimeType) = NativeShowPolicy.response(for: path, data: try await read(path))
                    guard running.remove(id) != nil else { return }
                    let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil)
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                } catch {
                    guard running.remove(id) != nil else { return }
                    urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                }
            }
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
            running.remove(ObjectIdentifier(urlSchemeTask))
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            return url.absoluteString == "about:blank" || policy.relativePath(of: url) != nil ? .allow : .cancel
        }

        /// `window.open` and `target=_blank`: never a second web view, and nothing opens on the Mac.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            nil
        }
    }
}
