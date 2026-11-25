import AppKit
import PaddockCore
import SwiftUI
import WebKit

/// An interactive tab (`paddock ui`; backlog doc Browser, interactive tabs): the agent's A2UI
/// surfaces, drawn by CopilotKit's renderer with the A2UI Playground's catalog in the app's page
/// (`App/A2UI`, `A2UIWebPolicy`). The tab (`A2UIWebTab`) and its web view live while the tab does,
/// so switching tabs loses nothing; the app model reads what the agent sent at each new revision
/// and draws it again from the first message on the tab menu's Refresh.
struct A2UIShowView: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let show: BrowserSessions.Show
    /// The confirmation of the operator's last answer, shown for a few seconds.
    @State private var confirmation: ProjectTerminals.UIDelivery?

    var body: some View {
        let command = model.terminals[project.name]?.viewCommands[ProjectTerminals.showTab(show.id)]
        let redraw = command?.kind == .reload ? command?.serial ?? 0 : 0
        Group {
            if let tab = model.terminals[project.name]?.a2uiTabs[show.id] {
                A2UIWebView(tab: tab).id(ObjectIdentifier(tab))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(show.revision)-\(redraw)") {
            await model.syncA2UI(show: show, redraw: redraw, of: project)
        }
        // After a button: whether it reached the agent.
        .overlay(alignment: .top) {
            if let confirmation {
                Label(confirmation.detail, systemImage: confirmation.sent ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.callout)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .foregroundStyle(confirmation.sent ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: model.terminals[project.name]?.uiDeliveries[show.id]) { _, delivery in
            guard let delivery else { return }
            withAnimation { confirmation = delivery }
            Task {
                try? await Task.sleep(for: .seconds(delivery.sent ? 3 : 8))
                withAnimation { if confirmation == delivery { confirmation = nil } }
            }
        }
    }
}

/// Shows a tab's own web view; the tab keeps it while it is hidden.
struct A2UIWebView: NSViewRepresentable {
    let tab: A2UIWebTab

    func makeNSView(context: Context) -> WKWebView {
        tab.webView.removeFromSuperview()
        return tab.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// What an A2UI tab needs from the app: every sandbox command through `ProjectRunner` (and so
/// `A2UICommands`), and where to say what went wrong.
struct A2UIWebLink {
    let project: Project
    let show: String
    let runner: @Sendable () async throws -> ProjectRunner
    /// A problem for the status bar and the log.
    let report: @MainActor (String) -> Void
    /// Whether the operator's answer reached the agent, for the tab's confirmation.
    let delivered: @MainActor (_ sent: Bool, _ detail: String) -> Void
}

/// One interactive tab: its messages from the sandbox (`A2UIInbox`) and the web view that draws
/// them. The web view keeps no data and loads only the app's page through `paddock-a2ui://app/`
/// (the page's manifest and media through the sandbox, `A2UIWebPolicy`); WebKit content rules
/// block everything else, and if they cannot be installed nothing loads. The messages go in as
/// one JSON string (`A2UIWebPolicy.renderScript`); what the page posts is checked
/// (`A2UIWebMessage`) and reaches the agent in order (`A2UIPolicy.lineForAgent`). A link the
/// operator clicks opens in the sandbox (`A2UILink`), never on the Mac.
@MainActor
final class A2UIWebTab: NSObject, WKNavigationDelegate, WKUIDelegate, WKURLSchemeHandler, WKScriptMessageHandler {
    let webView: WKWebView
    private let link: A2UIWebLink
    private(set) var inbox = A2UIInbox()
    private var messages: [Data] = []
    private var ready = false
    private var rendered = -1
    private var loading: Task<Void, Never>?
    /// The page's answers, one after the other, so the agent reads them in the operator's order.
    private var outbox: Task<Void, Never>?
    /// Scheme requests being answered; one WebKit stopped is never answered.
    private var requests: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Media fetched through the sandbox, by the URL its component named: video asks in parts.
    private var mediaKept: [String: (mimeType: String, data: Data)] = [:]
    private var mediaOrder: [String] = []
    private var mediaProblems: Set<String> = []
    private var problemsReported: Set<String> = []
    private static let mediaCacheBytes = 160 * 1024 * 1024

    /// The page's files (`App/A2UI/manifest.json`); nil when the app has no page.
    private static let page: (folder: URL, manifest: A2UIWebPolicy.Manifest)? = {
        guard let folder = Bundle.main.url(forResource: "A2UI", withExtension: nil),
              let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let manifest = try? A2UIWebPolicy.Manifest(data: data) else { return nil }
        return (folder, manifest)
    }()

    init(link: A2UIWebLink) {
        self.link = link
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.setURLSchemeHandler(self, forURLScheme: A2UIWebPolicy.scheme)
        // Through a weak proxy: the controller keeps its handlers alive.
        configuration.userContentController.add(WeakScriptMessageHandler(self), name: A2UIWebPolicy.messageHandler)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        load()
    }

    private func load() {
        loading = Task { [weak self] in
            do {
                let store: WKContentRuleListStore? = WKContentRuleListStore.default()
                let compiled: WKContentRuleList? = try await store?.compileContentRuleList(
                    forIdentifier: A2UIWebPolicy.ruleListIdentifier, encodedContentRuleList: A2UIWebPolicy.contentRules)
                guard let self, !Task.isCancelled else { return }
                guard let rules = compiled, let home = A2UIWebPolicy.homeURL, Self.page != nil else {
                    self.webView.loadHTMLString(Self.failClosedPage, baseURL: nil)
                    return
                }
                self.webView.configuration.userContentController.add(rules)
                self.webView.load(URLRequest(url: home))
            } catch {
                self?.webView.loadHTMLString(Self.failClosedPage, baseURL: nil)
            }
        }
    }

    static let failClosedPage = """
        <body style="font: -apple-system-body; color: gray; padding: 2em">
        Paddock could not install its web content rules or find its A2UI page, so this tab stays closed.
        </body>
        """

    /// The tab ends (closed, drawn again, or the sandbox stopped): nothing more loads or reaches the agent.
    func dispose() {
        loading?.cancel()
        for request in requests.values { request.cancel() }
        requests = [:]
        mediaKept = [:]
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: A2UIWebPolicy.messageHandler)
        webView.removeFromSuperview()
    }

    // MARK: - From the sandbox

    /// Takes the log's bytes from `inbox.offset` and draws what is new. Lines Paddock does not draw
    /// go to the agent as `A2UIEvent`s; returns them for the status bar.
    func take(_ chunk: Data) -> [A2UIEvent] {
        let intake = inbox.take(chunk)
        messages += intake.messages
        render()
        for refusal in intake.refusals { send(refusal.json, isAnswer: false) }
        return intake.refusals
    }

    private func render() {
        guard ready, rendered != messages.count, let script = A2UIWebPolicy.renderScript(messages: messages) else { return }
        rendered = messages.count
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - From the page

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String, let parsed = A2UIWebMessage(body) else { return }
        switch parsed {
        case .ready:
            ready = true
            rendered = -1
            render()
        case .action(let data):
            send(A2UIPolicy.lineForAgent(data), isAnswer: true)
        case .error(let data):
            send(A2UIPolicy.lineForAgent(data), isAnswer: false)
        case .problem(let text):
            guard problemsReported.insert(text).inserted else { return }
            link.report("The A2UI tab's page: \(text)")
        }
    }

    /// Hands a line to `paddock wait`, after the ones before it.
    private func send(_ line: Data, isAnswer: Bool) {
        let previous = outbox
        let link = link
        outbox = Task {
            await previous?.value
            do {
                try await link.runner().a2uiDeliver(line, show: link.show, of: link.project)
                if isAnswer { link.delivered(true, "Sent to the agent") }
            } catch {
                link.report("Could not hand your answer to the agent in \(link.project.name): \(String(describing: error))")
                if isAnswer { link.delivered(false, "Not sent: \(String(describing: error))") }
            }
        }
    }

    // MARK: - The page's files and media

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let page = Self.page,
              let request = A2UIWebPolicy.request(for: url, manifest: page.manifest) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        switch request {
        case .file(let path, let mimeType):
            guard let data = try? Data(contentsOf: page.folder.appendingPathComponent(path)) else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            reply(urlSchemeTask, url: url, mimeType: mimeType, data: data)
        case .media(let kind, let original):
            let key = ObjectIdentifier(urlSchemeTask)
            requests[key] = Task { [weak self] in
                guard let self else { return }
                let result = await self.media(original, kind: kind)
                // WebKit stopped it meanwhile: it must not be answered.
                guard self.requests.removeValue(forKey: key) != nil else { return }
                switch result {
                case .success(let body):
                    self.reply(urlSchemeTask, url: url, mimeType: body.mimeType, data: body.data)
                case .failure(let error):
                    urlSchemeTask.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        requests.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }

    private func reply(_ task: any WKURLSchemeTask, url: URL, mimeType: String, data: Data) {
        var status = 200
        var body = data
        var headers = ["Content-Type": mimeType, "Accept-Ranges": "bytes", "Cache-Control": "no-store"]
        if let range = A2UIWebPolicy.byteRange(task.request.value(forHTTPHeaderField: "Range"), count: data.count) {
            if range.isEmpty {
                status = 416
                body = Data()
                headers["Content-Range"] = "bytes */\(data.count)"
            } else {
                status = 206
                body = data.subdata(in: range)
                headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(data.count)"
            }
        }
        headers["Content-Length"] = String(body.count)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }

    /// A picture, video, or audio clip through the sandbox (`A2UIMedia`), kept for the next part.
    private func media(_ original: String, kind: A2UIMedia.Kind) async -> Result<(mimeType: String, data: Data), Error> {
        let key = kind.rawValue + " " + original
        if let kept = mediaKept[key] { return .success(kept) }
        do {
            let source = try A2UIMedia.source(for: original, kind: kind).get()
            let link = link
            let body = try await link.runner().a2uiMedia(source, kind: kind, show: link.show, of: link.project)
            keep(body, for: key)
            return .success(body)
        } catch {
            if !(error is CancellationError), mediaProblems.insert(key).inserted {
                link.report("The A2UI tab could not load \(kind.rawValue) \(original.prefix(200)): \(String(describing: error))")
            }
            return .failure(error)
        }
    }

    private func keep(_ body: (mimeType: String, data: Data), for key: String) {
        mediaKept[key] = body
        mediaOrder.append(key)
        while mediaKept.values.reduce(0, { $0 + $1.data.count }) > Self.mediaCacheBytes, mediaOrder.count > 1 {
            mediaKept[mediaOrder.removeFirst()] = nil
        }
    }

    // MARK: - Links

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        let mainFrame = navigationAction.targetFrame?.isMainFrame ?? false
        // The page itself, an anchor in it, and the card media.ts puts in an embed's frame.
        if mainFrame, let home = A2UIWebPolicy.homeURL, Self.withoutFragment(url) == home { return .allow }
        if !mainFrame, ["data", "about"].contains(url.scheme?.lowercased() ?? "") { return .allow }
        open(url)
        return .cancel
    }

    /// `window.open` and `target=_blank`: never a second web view; the link opens in the sandbox.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url { open(url) }
        return nil
    }

    private func open(_ url: URL) {
        guard let destination = A2UIWebPolicy.link(for: url) else { return }
        let link = link
        Task {
            do {
                switch destination {
                case .web(let page): try await link.runner().a2uiOpen(page, of: link.project)
                case .file(let path): try await link.runner().a2uiOpenFile(path, show: link.show, of: link.project)
                }
            } catch {
                link.report("Could not open \(url.absoluteString.prefix(200)) in \(link.project.name): \(String(describing: error))")
            }
        }
    }

    private static func withoutFragment(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url
    }
}

/// Forwards the page's messages without the controller keeping the tab alive.
@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

extension AppModel {
    /// An interactive tab (backlog doc Browser, interactive tabs): reads what the agent sent since
    /// the last read into its A2UI tab, after drawing it again from the first message when the
    /// operator asked (Refresh, `redraw` above the last one). One read per tab at a time; a change
    /// meanwhile reads again after.
    func syncA2UI(show: BrowserSessions.Show, redraw: Int, of project: Project) async {
        guard let terminals = terminals[project.name] else { return }
        let id = show.id
        if redraw > (terminals.a2uiRedrawn[id] ?? 0) {
            terminals.a2uiRedrawn[id] = redraw
            terminals.resetA2UI(id)
            // The agent hears that the operator drew it again.
            Task { try? await runner().navigateShow(.reload, show: id, of: project) }
        }
        guard !terminals.a2uiReading.contains(id) else {
            terminals.a2uiAgain.insert(id)
            return
        }
        terminals.a2uiReading.insert(id)
        defer { terminals.a2uiReading.remove(id) }
        repeat {
            terminals.a2uiAgain.remove(id)
            let tab = terminals.a2uiTab(id) { makeA2UITab(show: id, of: project) }
            do {
                let chunk = try await runner().a2uiMessages(show: id, from: tab.inbox.offset, of: project)
                // Drawn again meanwhile: read the new tab from its start.
                guard terminals.a2uiTabs[id] === tab else {
                    terminals.a2uiAgain.insert(id)
                    continue
                }
                let refused = tab.take(chunk)
                if let first = refused.first {
                    fail("\(show.title): Paddock did not draw \(refused.count) of the agent's messages (line \(first.line ?? 0): \(first.reason)); the agent was told",
                         in: project.name)
                }
            } catch {
                fail("Could not read \(show.title) from the sandbox: \(String(describing: error))", in: project.name)
            }
        } while terminals.a2uiAgain.contains(id)
    }

    private func makeA2UITab(show id: String, of project: Project) -> A2UIWebTab {
        let link = A2UIWebLink(
            project: project,
            show: id,
            runner: { [weak self] in
                guard let self else { throw AppError("Paddock is closing") }
                return try await self.runner()
            },
            report: { [weak self] message in self?.fail(message, in: project.name) },
            delivered: { [weak self] sent, detail in self?.terminals[project.name]?.delivered(id, sent: sent, detail: detail) }
        )
        return A2UIWebTab(link: link)
    }
}
