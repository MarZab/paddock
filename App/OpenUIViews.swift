import AppKit
import PaddockCore
import SwiftUI
import WebKit

/// An interactive tab (`paddock ui`; backlog doc Browser, OpenUI tabs): the agent's OpenUI Lang
/// document, read from the sandbox, rendered by OpenUI's renderer from the app (`OpenUIWebView`).
/// The operator's actions go back to the sandbox for `paddock wait`; the renderer's problems too;
/// form state stays with Paddock, so switching tabs loses nothing.
struct OpenUIView: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let show: BrowserSessions.Show
    @State private var document: String?
    @State private var problem: String?
    /// The confirmation of the operator's last answer, shown for a few seconds.
    @State private var confirmation: ProjectTerminals.UIDelivery?

    var body: some View {
        let command = model.terminals[project.name]?.viewCommands[ProjectTerminals.showTab(show.id)]
        Group {
            if let problem {
                ContentUnavailableView("The document did not load", systemImage: "exclamationmark.triangle", description: Text(problem))
            } else if let document {
                OpenUIWebView(document: document, state: model.terminals[project.name]?.uiStates[show.id]) { message in
                    model.received(message, from: show, of: project)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // A new revision (the agent changed it) or the tab menu's Refresh: read it again.
        .task(id: "\(show.revision)-\(command?.kind == .reload ? command?.serial ?? 0 : 0)") { await load() }
        // After a button or a submitted form: whether it reached the agent.
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

    private func load() async {
        do {
            let data = try await model.readShowFile(show: show.id, relativePath: "", of: project)
            guard data.count <= OpenUIPolicy.maxDocumentBytes else { throw AppError("the document is too large") }
            document = String(decoding: data, as: UTF8.self)
            problem = nil
        } catch {
            problem = String(describing: error)
        }
    }
}

/// The renderer's web view: keeps no data, loads only the app's renderer files through
/// `paddock-ui://renderer/` (`OpenUIPolicy`), and hears the page through one message handler, whose
/// messages are checked (`OpenUIMessage`) before anything uses them. The document goes in as data
/// (`OpenUIPolicy.renderScript`) once the page is ready, and again whenever it changes. Nothing
/// opens a window or anything on the Mac. If the content rules cannot be installed, nothing loads.
struct OpenUIWebView: NSViewRepresentable {
    let document: String
    /// The form state Paddock kept from an earlier view of this tab.
    let state: String?
    let received: @MainActor (OpenUIMessage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(received: received)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: OpenUIPolicy.scheme)
        // Through a weak proxy: the controller keeps its handlers alive.
        configuration.userContentController.add(WeakMessageHandler(context.coordinator), name: OpenUIPolicy.messageHandler)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.show(document, state: state)
        context.coordinator.load(into: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.show(document, state: state)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.cancel()
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: OpenUIPolicy.messageHandler)
        nsView.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKURLSchemeHandler, WKScriptMessageHandler {
        private let received: @MainActor (OpenUIMessage) -> Void
        weak var webView: WKWebView?
        private var loading: Task<Void, Never>?
        private var ready = false
        /// What the page shows now, and what it should show.
        private var rendered: String?
        private var wanted: (document: String, state: String?)?

        init(received: @escaping @MainActor (OpenUIMessage) -> Void) {
            self.received = received
        }

        func load(into webView: WKWebView) {
            loading = Task { [weak webView] in
                do {
                    let store: WKContentRuleListStore? = WKContentRuleListStore.default()
                    let compiled: WKContentRuleList? = try await store?.compileContentRuleList(
                        forIdentifier: OpenUIPolicy.ruleListIdentifier, encodedContentRuleList: OpenUIPolicy.contentRules)
                    guard let rules = compiled, let home = OpenUIPolicy.homeURL else {
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
            Paddock could not install its web content rules, so this tab stays closed.
            </body>
            """

        /// Renders `document` once the page is ready; the same document again does nothing.
        func show(_ document: String, state: String?) {
            wanted = (document, state)
            renderIfReady()
        }

        private func renderIfReady() {
            guard ready, let wanted, wanted.document != rendered, let webView,
                  let script = OpenUIPolicy.renderScript(document: wanted.document, state: wanted.state) else { return }
            rendered = wanted.document
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        // The page's messages: checked, then ready renders, the rest goes to the app.
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String, let parsed = OpenUIMessage(body) else { return }
            if parsed == .ready {
                ready = true
                rendered = nil
                renderIfReady()
            } else {
                received(parsed)
            }
        }

        // The app's renderer files, from the list only.
        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            guard let url = urlSchemeTask.request.url, let file = OpenUIPolicy.file(for: url),
                  let folder = Bundle.main.url(forResource: "OpenUI", withExtension: nil),
                  let data = try? Data(contentsOf: folder.appendingPathComponent(file)) else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            let response = URLResponse(url: url, mimeType: OpenUIPolicy.files[file], expectedContentLength: data.count, textEncodingName: "utf-8")
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            return url.absoluteString == "about:blank" || url == OpenUIPolicy.homeURL ? .allow : .cancel
        }

        /// `window.open` and `target=_blank`: never a second web view, and nothing opens on the Mac
        /// (links reach the agent as actions instead).
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

/// Forwards the page's messages without the controller keeping the coordinator alive.
@MainActor
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
