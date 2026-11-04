import AppKit
import PaddockCore
import SwiftUI
import WebKit

/// llmman's own web UI (backlog doc UI, Models pane). Shown only while every hardening check is green.
/// `LlmmanWebPolicy` decides what may load: WebKit content rules cover every resource and
/// WebSocket, and the navigation delegate covers page navigations. If the rules cannot be
/// installed, nothing loads.
struct LlmmanWebView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
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
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private var loading: Task<Void, Never>?

        func load(into webView: WKWebView) {
            loading = Task { [weak webView] in
                do {
                    let store: WKContentRuleListStore? = WKContentRuleListStore.default()
                    let compiled: WKContentRuleList? = try await store?.compileContentRuleList(
                        forIdentifier: "paddock-llmman", encodedContentRuleList: LlmmanWebPolicy.contentRules)
                    guard let rules = compiled else {
                        webView?.loadHTMLString(Self.failClosedPage, baseURL: nil)
                        return
                    }
                    guard let webView, !Task.isCancelled else { return }
                    webView.configuration.userContentController.add(rules)
                    webView.load(URLRequest(url: LlmmanWebPolicy.homeURL))
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
            Paddock could not install its web content rules, so llmman's UI stays off.
            </body>
            """

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            switch LlmmanWebPolicy.decide(url: url, userClicked: navigationAction.navigationType == .linkActivated) {
            case .allow:
                return .allow
            case .openExternally:
                NSWorkspace.shared.open(url)
                return .cancel
            case .block:
                return .cancel
            }
        }

        /// `window.open` and `target=_blank`: never a second web view; other sites go to the browser.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url, LlmmanWebPolicy.decide(url: url, userClicked: true) == .openExternally {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}
