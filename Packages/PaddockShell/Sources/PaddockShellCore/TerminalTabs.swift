import Foundation

/// A sandbox's terminal tabs: agent sessions ("agent", "agent 2") and shells ("shell", "shell 2"),
/// opened with "+" (backlog doc UI). No selection means one of the host's own tabs: its first
/// (Paddock's Info), or another it offers (`hostSelection`, such as Paddock's browser tab).
public struct TerminalTabs: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        /// `sbx run --name N`
        case agent
        /// `sbx exec -it N bash`
        case shell
        /// A login shell on this Mac, in the project folder (not in the sandbox)
        case mac
    }

    public struct Tab: Sendable, Equatable, Identifiable {
        public let id: UUID
        /// "agent", "shell 2": unique per kind, for the tab when its program sets no title.
        public let title: String
        public let kind: Kind
        /// What the program in the tab set as its title (OSC 0 or 2), sanitized.
        public private(set) var terminalTitle: String?
        /// What the program in the tab is doing, as the host reports it (`TerminalTabs.setActivity`):
        /// `busy` marks the tab as working, `attention` as waiting for the operator (backlog doc UI, Status marks).
        public internal(set) var activity: HostTab.Activity = .none

        public init(id: UUID = UUID(), title: String, kind: Kind) {
            self.id = id
            self.title = title
            self.kind = kind
        }

        /// The tab's label: the program's title, with a leading symbol split off as its icon, or
        /// the tab's own title.
        public var label: (symbol: String?, text: String) {
            terminalTitle.map(TerminalTitle.split) ?? (nil, title)
        }

        mutating func setTerminalTitle(_ raw: String) {
            terminalTitle = TerminalTitle.sanitized(raw)
        }
    }

    /// One of the host's own tabs after its first, such as a web view of its own.
    public struct HostTab: Identifiable, Sendable, Equatable {
        public enum Style: Sendable, Equatable {
            /// Looks like a session tab.
            case standard
            /// A web page: looks like a session tab, in the accent color.
            case web
            /// A browser of the host's (Paddock's Playwright tab): looks like a session tab, in green.
            case browser
            /// Content rendered on this Mac rather than in the sandbox: looks like a session tab,
            /// in orange, so the operator sees the difference before opening it.
            case local
            /// Something that asks the operator for an answer: looks like a session tab, in purple.
            case interactive
        }

        /// What happens in the tab, for an animation in the tab bar.
        public enum Activity: Sendable, Equatable {
            case none
            /// Something works in it now (a green ellipsis).
            case busy
            /// Something changed since the operator last looked (a dot).
            case unseen
            /// Something waits for the operator (an orange exclamation).
            case attention
        }

        public let id: String
        public let title: String
        /// An SF Symbol name.
        public let systemImage: String
        public let help: String
        public let style: Style
        /// Shows a close button; the host decides what closing means.
        public let closable: Bool
        public let activity: Activity
        /// Commands in the tab's context menu (Refresh, Back); the host does them.
        public let actions: [Action]

        /// A command in a host tab's context menu.
        public struct Action: Sendable, Equatable, Identifiable {
            public let id: String
            public let title: String
            /// An SF Symbol name.
            public let systemImage: String

            public init(id: String, title: String, systemImage: String) {
                self.id = id
                self.title = title
                self.systemImage = systemImage
            }
        }

        public init(id: String, title: String, systemImage: String, help: String = "", style: Style = .standard,
                    closable: Bool = false, activity: Activity = .none, actions: [Action] = []) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
            self.help = help
            self.style = style
            self.closable = closable
            self.activity = activity
            self.actions = actions
        }
    }

    /// A tab being dragged or moved between tab bars (two halves of a split, say).
    public enum Item: Sendable, Equatable {
        case session(UUID)
        case host(String)

        /// The drag payload: a session's UUID, or `host:` and the host tab's id.
        public var payload: String {
            switch self {
            case .session(let id): id.uuidString
            case .host(let id): Self.hostPrefix + id
            }
        }

        public init?(payload: String) {
            if payload.hasPrefix(Self.hostPrefix) {
                self = .host(String(payload.dropFirst(Self.hostPrefix.count)))
            } else if let id = UUID(uuidString: payload) {
                self = .session(id)
            } else {
                return nil
            }
        }

        static let hostPrefix = "host:"
    }

    public private(set) var tabs: [Tab] = []
    /// The selected tab, or nil for one of the host's tabs.
    public var selection: UUID?
    /// While no terminal tab is selected: the host tab shown, by the host's id; nil for its first.
    public private(set) var hostSelection: String?

    public init() {}

    public var selected: Tab? { tabs.first { $0.id == selection } }

    /// Shows one of the host's tabs: nil for its first, or the id of another it offers.
    public mutating func selectHost(_ id: String?) {
        selection = nil
        hostSelection = id
    }

    /// The host tab shown, nil for the first; `offered` are the host's other tabs now, so a tab it
    /// no longer offers falls back to the first.
    public func shownHostTab(offered: [String]) -> String? {
        guard selection == nil, let hostSelection, offered.contains(hostSelection) else { return nil }
        return hostSelection
    }

    /// Adds a tab with the lowest free title of its kind and selects it.
    @discardableResult
    public mutating func add(_ kind: Kind) -> Tab {
        let used = Set(tabs.map(\.title))
        var number = 1
        while used.contains(Self.title(kind, number)) { number += 1 }
        let tab = Tab(title: Self.title(kind, number), kind: kind)
        tabs.append(tab)
        order.append(.session(tab.id))
        selection = tab.id
        return tab
    }

    /// The order the bar shows its tabs in, sessions and host tabs mixed; dragging changes it.
    /// Items not placed yet (a host tab that just appeared) come last.
    private var order: [Item] = []

    /// The bar's tabs in order: sessions and the host's tabs after its first (`hosts`, their ids).
    public func arranged(hosts: [String]) -> [Item] {
        let sessions = tabs.map { Item.session($0.id) }
        let all = sessions + hosts.map { Item.host($0) }
        return order.filter(all.contains) + all.filter { !order.contains($0) }
    }

    /// Whether a tab has its place in the order.
    public func isPlaced(_ item: Item) -> Bool { order.contains(item) }

    /// Puts a tab at the end of the order, or before `target`.
    public mutating func place(_ item: Item, before target: Item? = nil) {
        order.removeAll { $0 == item }
        let index = target.flatMap { order.firstIndex(of: $0) } ?? order.endIndex
        order.insert(item, at: index)
    }

    /// Moves a tab to where another one is (dragged onto it), sessions and host tabs alike: before
    /// it when coming from the right, after it when coming from the left, as in a browser's tab bar.
    public mutating func move(_ item: Item, onto target: Item, hosts: [String]) {
        var arranged = arranged(hosts: hosts)
        guard item != target, let from = arranged.firstIndex(of: item), let to = arranged.firstIndex(of: target) else { return }
        arranged.insert(arranged.remove(at: from), at: to)
        order = arranged
    }

    /// Takes a tab out to move it to another bar (its session keeps running); the selection moves
    /// as for `close`.
    public mutating func take(_ id: UUID) -> Tab? {
        guard let tab = tabs.first(where: { $0.id == id }) else { return nil }
        close(id)
        return tab
    }

    /// Puts a tab taken from another bar here, at the end or before `target`, and selects it. Its
    /// title stays: titles are unique per kind within a bar only when they were made here.
    public mutating func insert(_ tab: Tab, before target: Item? = nil) {
        guard !tabs.contains(where: { $0.id == tab.id }) else { return }
        tabs.append(tab)
        place(.session(tab.id), before: target)
        selection = tab.id
    }

    /// Closes a tab; if it was selected, selects its neighbour, or nothing when it was the last.
    public mutating func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        order.removeAll { $0 == .session(id) }
        if selection == id {
            selection = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }

    /// The title a tab's program set; an empty one brings back the tab's own title.
    public mutating func setTerminalTitle(_ raw: String, for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].setTerminalTitle(raw)
    }

    /// What a tab's program is doing, as the host reports it. Unknown tabs are ignored.
    public mutating func setActivity(_ activity: HostTab.Activity, for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].activity = activity
    }

    static func title(_ kind: Kind, _ number: Int) -> String {
        number == 1 ? kind.rawValue : "\(kind.rawValue) \(number)"
    }
}

/// A terminal title set by a program in the sandbox (OSC 0 or 2). **Untrusted:** anything in the
/// sandbox can set it, so only its visible text is kept.
public enum TerminalTitle {
    public static let maxLength = 60

    /// Without control, format (bidi overrides, zero-width), or line characters, trimmed and cut
    /// to `maxLength` characters; nil when nothing is left.
    public static func sanitized(_ raw: String) -> String? {
        let kept = raw.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned: false
            default: true
            }
        }
        let text = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return text.count > maxLength ? String(text.prefix(maxLength - 1)) + "…" : text
    }

    /// A leading symbol (not a letter or digit) followed by a space, as in "✳ Claude Code" or a
    /// spinner frame, becomes the icon; the rest is the text.
    public static func split(_ title: String) -> (symbol: String?, text: String) {
        guard let first = title.first, let space = title.firstIndex(of: " "), space == title.index(after: title.startIndex),
              !first.isLetter, !first.isNumber else { return (nil, title) }
        let text = title[title.index(after: space)...].trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? (String(first), title) : (String(first), text)
    }
}
