import A2UICore
import A2UISwiftUI
import BasicCatalog
import Combine
import Foundation
import Observation
import OrderedJSON
import PaddockCore

/// An A2UI tab's way to its sandbox, which the app provides through `A2UICommands` and sbx.
public protocol A2UITabLink: Sendable {
    /// Hands one line to the sandbox, where `paddock wait` prints it.
    func deliver(_ line: Data) async throws
    /// The bytes of a media file in the sandbox (`.sandboxFetch` or `.sandboxFile`), checked
    /// for `kind` (`A2UIMedia.decodeFetched`).
    func media(_ source: A2UIMedia.Source, kind: A2UIMedia.Kind) async throws -> (mimeType: String, data: Data)
    /// Opens a page in a browser tab in the sandbox (`openUrl`, a web link in a Text), never on the Mac.
    func openInSandbox(_ url: URL) async throws
    /// Opens a file next to the tab's messages as a native tab (a file link in a Text; PAD-149).
    func openFile(_ relativePath: String) async throws
}

/// One A2UI tab (`paddock ui`; backlog doc Browser, interactive tabs): the agent's surfaces,
/// rendered by A2UI's own message processor with Paddock's catalog. What comes from the sandbox is
/// checked by `A2UIInbox` first; everything the tab sends back goes through
/// `A2UIPolicy.lineForAgent`, one line at a time and in order. The app keeps the tab while the
/// operator switches tabs, so what they typed stays.
@MainActor
@Observable
public final class A2UITab {
    /// How long a surface waits for the agent to answer a function call it does not have:
    /// an agent in a terminal answers in its next turn, not in A2UI's default 30 seconds.
    public static let agentFunctionTimeout: TimeInterval = 600

    public let id: String
    /// The agent's surfaces, in the order they arrived.
    public private(set) var surfaces: [SurfaceViewModel] = []
    /// The function calls a surface sent the agent and still waits for, by call id.
    public private(set) var waitingCalls: Set<String> = []
    /// The latest thing the operator should know about: an answer sent or not, a link opened.
    public private(set) var notice: Notice?

    public struct Notice: Sendable, Equatable {
        public let serial: Int
        public let ok: Bool
        public let text: String
    }

    public let catalog: Catalog<ComponentImplementation>
    let media: A2UIMediaStore
    private let processor: MessageProcessor
    private let link: any A2UITabLink
    private let opener: SandboxURLOpener
    private let links: A2UILinkOpener
    @ObservationIgnored private var inbox = A2UIInbox()
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var subscription: AnyCancellable?
    /// The delivery in flight: each waits for the one before, so the agent hears them in order.
    @ObservationIgnored private var lastDelivery: Task<Void, Never>?
    @ObservationIgnored private var notices = 0

    /// `folder` holds the tab's media files while it is open; `dispose` removes it.
    public init(id: String, link: any A2UITabLink, folder: URL) {
        self.id = id
        self.link = link
        let opener = SandboxURLOpener()
        self.opener = opener
        let media = A2UIMediaStore(link: link, folder: folder)
        self.media = media
        let links = A2UILinkOpener()
        self.links = links
        let catalog = PaddockCatalog.make(media: media, links: links, openURLHandler: opener)
        self.catalog = catalog
        processor = MessageProcessor(catalogs: [catalog])
        processor.agentFunctionTimeoutSeconds = Self.agentFunctionTimeout
        opener.handler = { [weak self] url in self?.openInSandbox(url) }
        links.handler = { [weak self] link in self?.open(link) }
        processor.outboundListener = { [weak self] message in
            Self.onMain { [weak self] in self?.send(message) }
        }
        subscription = processor.surfaceGroupModel.$surfacesMap.sink { [weak self] map in
            Self.onMain { [weak self] in self?.surfacesChanged(map) }
        }
    }

    /// Bytes of the tab's message log already taken; the next read starts there.
    public var offset: Int { inbox.offset }

    /// Takes the log's bytes from `offset` (`A2UICommands.messages`) and renders the messages.
    /// Each refused one goes to the agent as an `A2UIEvent`, and is returned for the app's log.
    @discardableResult
    public func take(_ chunk: Data) -> [A2UIEvent] {
        let intake = inbox.take(chunk)
        for message in intake.messages {
            process(message)
        }
        for refusal in intake.refusals {
            deliver(refusal.json, kind: nil)
        }
        return intake.refusals
    }

    /// Ends the tab: pending calls stop, its media files go.
    public func dispose() {
        lastDelivery?.cancel()
        processor.cancelPendingCalls()
        processor.dispose()
        media.removeFiles()
    }

    // MARK: - From the agent

    private func process(_ message: Data) {
        // A2UIInbox passed it as a JSON object already.
        guard let payload = try? JSONDecoder().decode(OrderedJSON.JSONValue.self, from: message) else { return }
        if let answered = try? JSONDecoder().decode(PaddockCore.JSONValue.self, from: message)["agentFunctionResponse"]?["functionCallId"]?.stringValue {
            waitingCalls.remove(answered)
        }
        processor.process(payload: payload)
    }

    private func surfacesChanged(_ map: [String: SurfaceViewModel]) {
        order = order.filter { map[$0] != nil } + map.keys.filter { !order.contains($0) }.sorted()
        surfaces = order.compactMap { map[$0] }
    }

    // MARK: - To the agent

    private func send(_ message: RendererToAgentMessage) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(message) else { return }
        let kind: String
        switch message {
        case .action: kind = "action"
        case .error: kind = "error"
        case .rendererFunctionResponse: kind = "rendererFunctionResponse"
        case .callAgentFunction:
            kind = "callAgentFunction"
            if let id = try? JSONDecoder().decode(PaddockCore.JSONValue.self, from: data)["callAgentFunction"]?["functionCallId"]?.stringValue {
                waitingCalls.insert(id)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.agentFunctionTimeout))
                    self?.waitingCalls.remove(id)
                }
            }
        }
        deliver(A2UIPolicy.lineForAgent(data), kind: kind)
    }

    /// Delivers after the delivery before it; an action's outcome becomes the notice.
    private func deliver(_ line: Data, kind: String?) {
        let previous = lastDelivery
        lastDelivery = Task { [weak self, link] in
            await previous?.value
            do {
                try await link.deliver(line)
                if kind == "action" { self?.show(ok: true, "Sent to the agent") }
            } catch {
                if kind == "action" { self?.show(ok: false, "Not sent: \(error)") }
            }
        }
    }

    private func openInSandbox(_ url: URL) {
        Task { [weak self, link] in
            do {
                try await link.openInSandbox(url)
                self?.show(ok: true, "Opened \(url.host ?? url.absoluteString) in the sandbox's browser")
            } catch {
                self?.show(ok: false, "Could not open \(url.absoluteString): \(error)")
            }
        }
    }

    /// A link the operator clicked in a Text (PAD-149): a page in the sandbox's browser, or a file
    /// next to the messages as a native tab.
    func open(_ link: A2UIMarkdown.Link) {
        switch link {
        case .web(let url):
            openInSandbox(url)
        case .file(let path):
            Task { [weak self, tabLink = self.link] in
                do {
                    try await tabLink.openFile(path)
                    self?.show(ok: true, "Opened \(path) in a tab")
                } catch {
                    self?.show(ok: false, "Could not open \(path): \(error)")
                }
            }
        }
    }

    private func show(ok: Bool, _ text: String) {
        notices += 1
        notice = Notice(serial: notices, ok: ok, text: text)
    }

    /// A2UI calls its listeners on the main actor; anything else waits for it.
    nonisolated static func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            Task { @MainActor in work() }
        }
    }
}

/// `openUrl`'s handler: the basic catalog's function checks the URL (http, https, mailto, tel)
/// and that the operator clicked; the tab opens it in the sandbox's browser.
final class SandboxURLOpener: OpenURLHandler, @unchecked Sendable {
    /// Set once, on the main actor, before any surface exists.
    var handler: (@MainActor @Sendable (URL) -> Void)?

    func open(_ url: URL) {
        let handler = handler
        A2UITab.onMain { handler?(url) }
    }
}
