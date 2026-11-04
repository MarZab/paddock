#if canImport(AppKit) && canImport(SwiftTerm)
import AppKit
import PaddockShellCore
import SwiftTerm
import SwiftUI

/// Terminal views kept while their session's tab is hidden, by session. Showing a tab again puts
/// the same view back: a new view would replay the scrollback, and a full-screen program's trimmed
/// output (diffs without its first full draw) replays as a blank screen; replaying 2 MB also holds
/// up the main thread. A kept view stays live, answering the program's queries while hidden.
@MainActor
public final class TerminalViewCache {
    private var coordinators: [UUID: SandboxTerminalView.Coordinator] = [:]

    public init() {}

    func coordinator(for session: SandboxShellSession,
                     make: () -> SandboxTerminalView.Coordinator) -> SandboxTerminalView.Coordinator {
        if let kept = coordinators[session.id] { return kept }
        let coordinator = make()
        coordinators[session.id] = coordinator
        return coordinator
    }

    /// The session's tab closed: its view and output go.
    public func release(_ session: SandboxShellSession) {
        coordinators.removeValue(forKey: session.id)?.detach()
    }

    /// Every view goes (the project's tabs go).
    public func releaseAll() {
        for coordinator in coordinators.values { coordinator.detach() }
        coordinators = [:]
    }
}

/// A terminal showing one `SandboxShellSession`. The session keeps running when the view goes
/// away. With a `TerminalViewCache` the view itself is kept for the next time it shows; without
/// one, a new view replays the scrollback (and with it the last title the program set).
public struct SandboxTerminalView: NSViewRepresentable {
    private let session: SandboxShellSession
    private let cache: TerminalViewCache?
    private let onTitle: @MainActor (String) -> Void
    private let onReady: @MainActor () -> Void
    private let focus: Int
    private let theme: TerminalTheme?

    /// - Parameters:
    ///   - onTitle: the raw title the program sets (OSC 0 or 2); untrusted, see `TerminalTitle`.
    ///   - onReady: the view is laid out and shows the session live, so a program started now gets
    ///     its terminal queries answered at once, at the real size.
    ///   - cache: keeps the view while it is hidden; release the session from it when its tab closes.
    ///   - focus: a request for keyboard focus: each time it rises above the last one this view
    ///     took, the terminal becomes the window's first responder (once it is in a window).
    ///   - theme: the terminal's colors; nil keeps SwiftTerm's own.
    public init(session: SandboxShellSession, cache: TerminalViewCache? = nil, focus: Int = 0, theme: TerminalTheme? = nil,
                onTitle: @escaping @MainActor (String) -> Void = { _ in },
                onReady: @escaping @MainActor () -> Void = {}) {
        self.session = session
        self.cache = cache
        self.focus = focus
        self.theme = theme
        self.onTitle = onTitle
        self.onReady = onReady
    }

    public func makeCoordinator() -> Coordinator {
        let make = { Coordinator(session: session, onTitle: onTitle, onReady: onReady, kept: cache != nil) }
        return cache?.coordinator(for: session, make: make) ?? make()
    }

    public func makeNSView(context: Context) -> PaddedTerminalView {
        let coordinator = context.coordinator
        if let container = coordinator.container {
            // A kept view, shown again: out of where it was (another half, say) and into the new place.
            container.removeFromSuperview()
            coordinator.apply(theme, to: container)
            coordinator.focus(container, request: focus)
            return container
        }
        let container = PaddedTerminalView()
        coordinator.container = container
        container.terminal.terminalDelegate = coordinator
        coordinator.apply(theme, to: container)
        coordinator.attach(to: container.terminal)
        coordinator.focus(container, request: focus)
        return container
    }

    public func updateNSView(_ nsView: PaddedTerminalView, context: Context) {
        context.coordinator.apply(theme, to: nsView)
        context.coordinator.focus(nsView, request: focus)
    }

    public static func dismantleNSView(_ nsView: PaddedTerminalView, coordinator: Coordinator) {
        // A kept view lives until its cache releases it.
        if !coordinator.kept { coordinator.detach() }
    }

    /// The terminal inset from its edges; the margin has the terminal's own background color.
    public final class PaddedTerminalView: NSView {
        static let padding = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)

        let terminal = PaddockTerminalView(frame: .zero)

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            terminal.translatesAutoresizingMaskIntoConstraints = false
            addSubview(terminal)
            let padding = Self.padding
            NSLayoutConstraint.activate([
                terminal.topAnchor.constraint(equalTo: topAnchor, constant: padding.top),
                terminal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding.left),
                terminal.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding.right),
                terminal.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding.bottom),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        /// Focus asked for before the view was in a window, taken once it is.
        var wantsFocus = false

        func takeFocus() {
            guard let window else {
                wantsFocus = true
                return
            }
            wantsFocus = false
            window.makeFirstResponder(terminal)
        }

        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if wantsFocus { takeFocus() }
        }

        override public var wantsUpdateLayer: Bool { true }

        override public func updateLayer() {
            // Resolved for the current appearance, so a dynamic color follows light and dark.
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = terminal.nativeBackgroundColor.cgColor
            }
        }

        override public func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }
    }

    /// SwiftTerm's terminal, with a copy that survives the program's output and a right-click menu.
    ///
    /// SwiftTerm drops the selection on every chunk of output while mouse reporting is on, so an
    /// agent redrawing its spinner wiped it before Cmd-C (PAD-65). This view keeps the text of the
    /// last selection made in it: Copy takes the live selection, else that text, until the next
    /// click in the terminal. While the program tracks the mouse, Shift-drag selects.
    ///
    /// What the program copies (OSC 52, such as Claude Code's own selection) never reaches the
    /// clipboard by itself: the right-click menu's Copy takes it when there is no selection of the
    /// terminal's own, newer than it. Cmd-C copies only the terminal's own selection (PAD-66).
    ///
    /// Ctrl-C copies like the menu's Copy when there is something to copy, then drops it, so the
    /// next Ctrl-C reaches the program as an interrupt (`TerminalCopy`, PAD-79).
    public final class PaddockTerminalView: TerminalView {
        /// Sees Ctrl-C before SwiftTerm, whose `keyDown` subclasses cannot override.
        private var controlCMonitor: Any?

        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let controlCMonitor {
                NSEvent.removeMonitor(controlCMonitor)
                self.controlCMonitor = nil
            }
            guard window != nil else { return }
            controlCMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard TerminalCopy.isControlC(key: event.charactersIgnoringModifiers, control: flags.contains(.control),
                                              command: flags.contains(.command), option: flags.contains(.option),
                                              shift: flags.contains(.shift)) else { return event }
                let eventWindow = event.windowNumber
                let taken = MainActor.assumeIsolated { self?.copyOnControlC(windowNumber: eventWindow) ?? false }
                return taken ? nil : event
            }
        }

        /// Ctrl-C in this focused terminal: copies and spends the text, or leaves the key to the
        /// program. Whether the key was taken.
        private func copyOnControlC(windowNumber: Int) -> Bool {
            guard let window, window.windowNumber == windowNumber, window.firstResponder === self else { return false }
            switch TerminalCopy.controlC(selection: selectedText, programCopy: programCopy) {
            case .interrupt:
                return false
            case .copy(let text):
                put(text)
                selection.selectNone()
                keptSelection = nil
                programCopy = nil
                needsDisplay = true
                return true
            }
        }

        /// The last selection's text, kept after output cleared the selection.
        private var keptSelection: String?

        override public func selectionChanged(source: Terminal) {
            super.selectionChanged(source: source)
            if selection.active, let text = getSelection(), !text.isEmpty {
                keptSelection = text
                programCopy = nil
            }
        }

        /// What the program last asked to copy (`ClipboardWrite`); the newer of it and a kept
        /// selection is the one the menu's Copy takes.
        var programCopy: String? {
            didSet { if programCopy != nil { keptSelection = nil } }
        }

        override public func mouseDown(with event: NSEvent) {
            // A new click: a new selection, or none.
            keptSelection = nil
            super.mouseDown(with: event)
        }

        /// The terminal's own selection: live, else kept.
        private var selectedText: String? {
            if selection.active, let text = getSelection(), !text.isEmpty { return text }
            return keptSelection
        }

        override public func copy(_ sender: Any) {
            put(selectedText)
        }

        /// The menu's Copy: the terminal's selection, else what the program copied.
        @objc private func copyFromMenu(_ sender: Any?) {
            put(TerminalCopy.text(selection: selectedText, programCopy: programCopy))
        }

        private func put(_ text: String?) {
            guard let text else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        override public func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
            if item.action == #selector(copy(_:)) { return selectedText != nil }
            if item.action == #selector(copyFromMenu(_:)) { return selectedText != nil || programCopy != nil }
            return super.validateUserInterfaceItem(item)
        }

        /// Right-click (SwiftTerm does not report the right button to the program, so this shows
        /// even while it tracks the mouse): Copy, Paste, Select All.
        override public func menu(for event: NSEvent) -> NSMenu? {
            let menu = NSMenu()
            // The key equivalents only label the items: Cmd-V and A reach the view through the Edit
            // menu. Copy has none, since Cmd-C leaves out what the program copied.
            for (title, action, key) in [("Copy", #selector(copyFromMenu(_:)), ""),
                                         ("Paste", #selector(paste(_:)), "v"),
                                         ("Select All", #selector(selectAll(_:)), "a")] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
                item.target = self
                menu.addItem(item)
            }
            return menu
        }
    }

    @MainActor
    public final class Coordinator: NSObject {
        enum Input {
            case write(Data)
            case resize(TerminalSize)
        }

        private let session: SandboxShellSession
        let onTitle: @MainActor (String) -> Void
        let onReady: @MainActor () -> Void
        /// Kept by a `TerminalViewCache`, which then owns the view.
        let kept: Bool
        /// The view, held only while kept (the cache holds the coordinator, the coordinator the view).
        var container: PaddedTerminalView? {
            get { kept ? strongContainer : nil }
            set { if kept { strongContainer = newValue } }
        }
        private var strongContainer: PaddedTerminalView?
        private weak var view: TerminalView?
        private var output: Task<Void, Never>?
        /// While the scrollback replays, the terminal's answers to the queries in it are dropped:
        /// they were answered when they were live, and a second answer reaches the running program.
        private var replaying = false
        private var input: Task<Void, Never>?
        /// Keystrokes and resizes reach the session in the order they happened.
        private let queue: AsyncStream<Input>.Continuation

        init(session: SandboxShellSession, onTitle: @escaping @MainActor (String) -> Void,
             onReady: @escaping @MainActor () -> Void, kept: Bool = false) {
            self.session = session
            self.onTitle = onTitle
            self.onReady = onReady
            self.kept = kept
            let (stream, continuation) = AsyncStream<Input>.makeStream()
            queue = continuation
            super.init()
            input = Task { [session] in
                for await item in stream {
                    switch item {
                    case .write(let data): await session.write(data)
                    case .resize(let size): await session.resize(size)
                    }
                }
            }
        }

        func attach(to view: TerminalView) {
            self.view = view
            startOutputIfLaidOut()
        }

        /// The theme this view shows (`apply`), and SwiftTerm's own colors to go back to.
        private var themeApplied = false
        private var appliedTheme: String?
        private var ownColors: (background: NSColor, foreground: NSColor, caret: NSColor)?

        /// Shows `theme`, or SwiftTerm's own colors for nil; only when it changed.
        func apply(_ theme: TerminalTheme?, to container: PaddedTerminalView) {
            guard !themeApplied || appliedTheme != theme?.id else { return }
            themeApplied = true
            appliedTheme = theme?.id
            let terminal = container.terminal
            let own = ownColors ?? (terminal.nativeBackgroundColor, terminal.nativeForegroundColor, terminal.caretColor)
            ownColors = own
            if let theme {
                terminal.nativeBackgroundColor = Self.native(theme.background)
                terminal.nativeForegroundColor = Self.native(theme.foreground)
                terminal.caretColor = Self.native(theme.cursor)
                terminal.installColors(theme.ansi.map(Self.swiftTerm))
            } else {
                terminal.nativeBackgroundColor = own.background
                terminal.nativeForegroundColor = own.foreground
                terminal.caretColor = own.caret
                terminal.installColors(SwiftTerm.Color.defaultInstalledColors)
            }
            // The margin takes the terminal's background.
            container.needsDisplay = true
        }

        private static func native(_ rgb: TerminalTheme.RGB) -> NSColor {
            NSColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
        }

        private static func swiftTerm(_ rgb: TerminalTheme.RGB) -> SwiftTerm.Color {
            SwiftTerm.Color(red: UInt16(rgb.red) * 257, green: UInt16(rgb.green) * 257, blue: UInt16(rgb.blue) * 257)
        }

        /// The highest focus request this view took.
        private var focused = 0

        func focus(_ container: PaddedTerminalView, request: Int) {
            guard request > focused else { return }
            focused = request
            // After this update, when a view just made is in its window.
            Task { @MainActor in container.takeFocus() }
        }

        /// Output starts once the view has a real size: before layout the terminal is tiny, and a
        /// program that asks for the size then draws for it (sbx's dashboard panicked on one).
        func startOutputIfLaidOut() {
            guard output == nil, let view else { return }
            let terminal = view.getTerminal()
            guard TerminalSize(cols: terminal.cols, rows: terminal.rows).isUsable else { return }
            output = Task { [weak self, session] in
                let attachment = await session.attachLive()
                if !attachment.scrollback.isEmpty, let self, let view = self.view {
                    // Answered already by a view that was live: replay without answering again.
                    self.replaying = attachment.answered
                    view.feed(byteArray: ArraySlice([UInt8](attachment.scrollback)))
                    self.replaying = false
                }
                await session.viewWentLive(attachment.id)
                self?.onReady()
                for await event in attachment.events {
                    guard let view = self?.view else { break }
                    switch event {
                    case .output(let data):
                        view.feed(byteArray: ArraySlice([UInt8](data)))
                    case .exited(let code):
                        view.feed(text: "\r\n[exited with status \(code)]\r\n")
                    }
                }
            }
        }

        func send(_ data: Data) {
            guard !replaying else { return }
            enqueue(.write(data))
        }

        func detach() {
            output?.cancel()
            input?.cancel()
            queue.finish()
            strongContainer = nil
        }

        func enqueue(_ item: Input) {
            queue.yield(item)
        }
    }
}

extension SandboxTerminalView.Coordinator: @preconcurrency TerminalViewDelegate {
    public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        // sbx's dashboard panicked ("negative Repeat count") on the 1x1 size of a view not laid out yet.
        let size = TerminalSize(cols: newCols, rows: newRows)
        guard size.isUsable else { return }
        enqueue(.resize(size))
        startOutputIfLaidOut()
    }

    public func send(source: TerminalView, data: ArraySlice<UInt8>) {
        send(Data(data))
    }

    /// OSC 52 from the program: kept for the right-click menu, never put on the clipboard here,
    /// and not from a replay (`ClipboardWrite`). Reads stay refused (SwiftTerm's default).
    public func clipboardCopy(source: TerminalView, content: Data) {
        guard !replaying, let view = source as? SandboxTerminalView.PaddockTerminalView,
              let text = ClipboardWrite.text(content) else { return }
        view.programCopy = text
    }

    public func setTerminalTitle(source: TerminalView, title: String) {
        onTitle(title)
    }
    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    public func scrolled(source: TerminalView, position: Double) {}
    public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

/// The terminal tab bar: a leading tab of the host's own (Paddock's Info), the host's other tabs,
/// one button per session tab with a close button (drag a tab onto another to reorder them), and
/// "+" with a menu for a new agent session or shell. Without an agent session, a dimmed "agent" tab
/// opens one. The host's tabs mix with the session tabs in one order (`TerminalTabs.arranged`) and
/// look the same, web tabs in the accent color. With `moveTitle`, every tab's context menu moves it
/// to another bar (`move`), and tabs dragged here from another bar arrive (`receive`).
public struct TerminalTabBar<Leading: View>: View {
    @Binding private var tabs: TerminalTabs
    private let leading: Leading
    private let showsLeading: Bool
    private let hostTabs: [TerminalTabs.HostTab]
    private let add: (TerminalTabs.Kind) -> Void
    private let close: (TerminalTabs.Tab) -> Void
    private let closeHost: (TerminalTabs.HostTab) -> Void
    private let hostAction: (TerminalTabs.HostTab, TerminalTabs.HostTab.Action) -> Void
    private let offersAgent: Bool
    private let moveTitle: String?
    private let move: (TerminalTabs.Item) -> Void
    private let receive: (TerminalTabs.Item, _ before: TerminalTabs.Item?) -> Void

    /// - Parameter offersAgent: shows the dimmed "agent" tab while no agent session is open.
    /// - Parameter hostTabs: the host's tabs after `leading`; `TerminalTabs.shownHostTab` says which shows.
    /// - Parameter showsLeading: false for a bar without the host's first tab (a split's second half).
    /// - Parameter moveTitle: the context menu item that moves a tab to another bar, such as "Move to Right Half".
    public init(tabs: Binding<TerminalTabs>, hostTabs: [TerminalTabs.HostTab] = [], showsLeading: Bool = true, offersAgent: Bool = true,
                moveTitle: String? = nil,
                add: @escaping (TerminalTabs.Kind) -> Void,
                close: @escaping (TerminalTabs.Tab) -> Void,
                closeHost: @escaping (TerminalTabs.HostTab) -> Void = { _ in },
                hostAction: @escaping (TerminalTabs.HostTab, TerminalTabs.HostTab.Action) -> Void = { _, _ in },
                move: @escaping (TerminalTabs.Item) -> Void = { _ in },
                receive: @escaping (TerminalTabs.Item, _ before: TerminalTabs.Item?) -> Void = { _, _ in },
                @ViewBuilder leading: () -> Leading) {
        _tabs = tabs
        self.leading = leading()
        self.showsLeading = showsLeading
        self.hostTabs = hostTabs
        self.add = add
        self.close = close
        self.closeHost = closeHost
        self.hostAction = hostAction
        self.offersAgent = offersAgent
        self.moveTitle = moveTitle
        self.move = move
        self.receive = receive
    }

    public var body: some View {
        let shownHost = tabs.shownHostTab(offered: hostTabs.map(\.id))
        HStack(spacing: 2) {
            if showsLeading {
                Button { tabs.selectHost(nil) } label: { leading }
                    .buttonStyle(.plain)
                    .modifier(TabBackground(selected: tabs.selection == nil && shownHost == nil) { tabs.selectHost(nil) })
            }
            ForEach(tabs.arranged(hosts: hostTabs.map(\.id)), id: \.payload) { item in
                switch item {
                case .session(let id):
                    if let tab = tabs.tabs.first(where: { $0.id == id }) {
                        sessionTab(tab)
                    }
                case .host(let id):
                    if let host = hostTabs.first(where: { $0.id == id }) {
                        hostTab(host, selected: shownHost == host.id)
                    }
                }
            }
            if offersAgent && !tabs.tabs.contains(where: { $0.kind == .agent }) {
                Button { add(.agent) } label: {
                    Label("agent", systemImage: "sparkles")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .modifier(TabBackground(selected: false) { add(.agent) })
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .help("Start the agent")
            }
            Menu {
                Section("Sandbox") {
                    Button("New Agent Session", systemImage: "sparkles") { add(.agent) }
                    Button("New Shell", systemImage: "terminal") { add(.shell) }
                }
                Section("This Mac") {
                    Button("New Shell on This Mac", systemImage: "laptopcomputer") { add(.mac) }
                }
            } label: {
                Label("New Tab", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .labelStyle(.iconOnly)
            .fixedSize()
            .padding(.horizontal, 6)
            .help("New agent session or shell in the sandbox, or a shell on this Mac")
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        // A tab dragged here from another bar, onto the bar itself.
        .dropDestination(for: String.self) { dropped, _ in
            guard let item = dropped.first.flatMap(TerminalTabs.Item.init(payload:)), !holds(item) else { return false }
            receive(item, nil)
            return true
        }
    }

    private func holds(_ item: TerminalTabs.Item) -> Bool {
        switch item {
        case .session(let id): tabs.tabs.contains { $0.id == id }
        case .host(let id): hostTabs.contains { $0.id == id }
        }
    }

    /// A shell on this Mac looks different from one in the sandbox: it can reach everything.
    private static func symbol(_ kind: TerminalTabs.Kind) -> String {
        switch kind {
        case .agent: "sparkles"
        case .shell: "terminal"
        case .mac: "laptopcomputer"
        }
    }

    private func sessionTab(_ tab: TerminalTabs.Tab) -> some View {
        HStack(spacing: 4) {
            activityMark(tab.activity)
            Button { tabs.selection = tab.id } label: {
                // The program's own symbol (a spinner frame, say) replaces the kind's icon.
                let label = tab.label
                if let symbol = label.symbol {
                    HStack(spacing: 5) {
                        Text(symbol).monospaced()
                        Text(label.text)
                    }
                } else {
                    Label(label.text, systemImage: Self.symbol(tab.kind))
                }
            }
            .buttonStyle(.plain)
            .lineLimit(1)
            .frame(maxWidth: 220)
            .help(tab.terminalTitle ?? tab.title)
            Button("Close \(tab.title)", systemImage: "xmark") { close(tab) }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .modifier(TabBackground(selected: tabs.selection == tab.id) { tabs.selection = tab.id })
        .contextMenu {
            if let moveTitle {
                Button(moveTitle) { move(.session(tab.id)) }
            }
            Button("Close") { close(tab) }
        }
        .draggable(TerminalTabs.Item.session(tab.id).payload)
        .dropDestination(for: String.self) { dropped, _ in drop(dropped, onto: .session(tab.id)) }
    }

    /// What a session tab's program is doing, as the project's mark shows it (backlog doc UI, Status
    /// marks): a green ellipsis while it works, an orange exclamation while it waits for the operator,
    /// a checkmark in the accent color once it stopped while the tab was not in view. Static shapes,
    /// so no one has to watch for a pulse. Nothing otherwise, so an idle tab looks as it always did.
    @ViewBuilder
    private func activityMark(_ activity: TerminalTabs.HostTab.Activity) -> some View {
        if let mark = Self.mark(activity) {
            Image(systemName: mark.symbol).font(.system(size: 10)).foregroundStyle(mark.color)
                .accessibilityLabel(mark.label)
                .help(mark.help)
        }
    }

    struct Mark {
        let symbol: String
        let color: AnyShapeStyle
        let label: String
        let help: String
    }

    static func mark(_ activity: TerminalTabs.HostTab.Activity) -> Mark? {
        switch activity {
        case .busy:
            Mark(symbol: "ellipsis.circle.fill", color: AnyShapeStyle(.green), label: "working", help: "Working")
        case .attention:
            Mark(symbol: "exclamationmark.circle.fill", color: AnyShapeStyle(.orange), label: "waits for you", help: "Waits for you")
        case .unseen:
            Mark(symbol: "checkmark.circle.fill", color: AnyShapeStyle(.tint), label: "finished",
                 help: "Finished while you were elsewhere")
        case .none: nil
        }
    }

    /// Drag a tab onto another to reorder them, or onto a tab in another bar to move it there.
    private func drop(_ dropped: [String], onto target: TerminalTabs.Item) -> Bool {
        guard let item = dropped.first.flatMap(TerminalTabs.Item.init(payload:)) else { return false }
        if holds(item) {
            withAnimation(.snappy(duration: 0.2)) { tabs.move(item, onto: target, hosts: hostTabs.map(\.id)) }
        } else {
            receive(item, target)
        }
        return true
    }

    /// A host tab's color: the same design as every tab, in a color that says what it is.
    static func tint(_ style: TerminalTabs.HostTab.Style) -> SwiftUI.Color? {
        switch style {
        case .standard: nil
        case .web: .accentColor
        case .browser: .green
        case .local: .orange
        case .interactive: .purple
        }
    }

    private func hostTab(_ host: TerminalTabs.HostTab, selected: Bool) -> some View {
        let label = HStack(spacing: 4) {
            Button { tabs.selectHost(host.id) } label: {
                Label {
                    Text(host.title)
                } icon: {
                    // The same marks as a session tab, small on the icon's corner; nothing pulses.
                    Image(systemName: host.systemImage)
                        .overlay(alignment: .topTrailing) {
                            if let mark = Self.mark(host.activity) {
                                Image(systemName: mark.symbol).font(.system(size: 8)).foregroundStyle(mark.color)
                                    .background(Circle().fill(.background).padding(1))
                                    .offset(x: 4, y: -3)
                                    .accessibilityLabel(mark.label)
                            }
                        }
                }
            }
                .buttonStyle(.plain)
                .lineLimit(1)
                .frame(maxWidth: 200)
                .help(host.help)
            if host.closable {
                Button("Close \(host.title)", systemImage: "xmark") { closeHost(host) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        return label
            .modifier(TabBackground(selected: selected, tint: Self.tint(host.style)) { tabs.selectHost(host.id) })
            .contextMenu {
                ForEach(host.actions) { action in
                    Button(action.title, systemImage: action.systemImage) { hostAction(host, action) }
                }
                if !host.actions.isEmpty {
                    Divider()
                }
                if let moveTitle {
                    Button(moveTitle) { move(.host(host.id)) }
                }
                if host.closable {
                    Button("Close") { closeHost(host) }
                }
            }
            .draggable(TerminalTabs.Item.host(host.id).payload)
            .dropDestination(for: String.self) { dropped, _ in drop(dropped, onto: .host(host.id)) }
    }
}

/// Every tab's look; a tinted tab (a web page, Paddock's browser, content rendered on the Mac)
/// differs only in color: the tint for its text and icon, and for its selected background. A click
/// anywhere on the tab, its padding included, does `action` (the buttons inside it, such as close,
/// keep their own).
private struct TabBackground: ViewModifier {
    let selected: Bool
    var tint: SwiftUI.Color?
    let action: () -> Void

    init(selected: Bool, tint: SwiftUI.Color? = nil, action: @escaping () -> Void) {
        self.selected = selected
        self.tint = tint
        self.action = action
    }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture(perform: action)
    }

    private var background: AnyShapeStyle {
        guard selected else { return AnyShapeStyle(.clear) }
        return tint.map { AnyShapeStyle($0.opacity(0.18)) } ?? AnyShapeStyle(.quaternary)
    }
}
#endif
