import AppKit
import PaddockCore
import SwiftUI

/// The Log page (sidebar, System; also File > Log): the errors the status popover showed, what long
/// work (a create) reported, what sbx said the sandboxes did, and voice, oldest first, in
/// full, with what each came from: this session's, or an earlier session's read back from its
/// file (PAD-78). Filtered by category (none chosen shows all), errors only, and text (`LogFilter`).
/// The same lines are in `LogFile`.
struct ErrorLogView: View {
    @Environment(AppModel.self) private var model
    @State private var errorsOnly = false
    @State private var search = ""
    /// The chosen categories, kept across launches (`LogFilter.categoriesStored`).
    @AppStorage("logCategories") private var categoriesStored = ""
    /// The earlier session shown (its file name), or nil for this one.
    @State private var session: String?
    @State private var sessions: [LogFiles.Session] = []
    @State private var earlier: [LogEntry] = []

    private var lines: [LogEntry] { session == nil ? model.errorLog : earlier }

    private var filter: LogFilter {
        LogFilter(categories: LogFilter.categories(stored: categoriesStored), errorsOnly: errorsOnly, text: search)
    }

    var body: some View {
        let filter = filter
        let all = lines
        let entries = filter.apply(all)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(LogCategory.allCases) { category in
                    Toggle(category.title, isOn: Binding(
                        get: { filter.categories.contains(category) },
                        set: { _ in
                            var next = filter
                            next.toggle(category)
                            categoriesStored = next.categoriesStored
                        }))
                    .toggleStyle(.button)
                }
                .help("Show only these kinds of lines; with none chosen, every kind shows")
                Spacer(minLength: 12)
                Picker("Show", selection: $errorsOnly) {
                    Text("All").tag(false)
                    Text("Errors").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                TextField("Filter", text: $search, prompt: Text("Filter"))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120, maxWidth: 220)
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            HStack {
                Picker("Session", selection: $session) {
                    Text("This session").tag(String?.none)
                    ForEach(sessions) { past in
                        Text(past.started.formatted(date: .abbreviated, time: .standard)).tag(Optional(past.name))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help("This session's lines, or an earlier session's from its file")
                Text(entries.count == all.count ? "\(entries.count) lines" : "\(entries.count) of \(all.count) lines")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy All", systemImage: "doc.on.doc") { copy(entries) }
                    .disabled(entries.isEmpty)
                    .help("Copy every line shown; select lines and press Cmd-C for some")
                Button("Show File", systemImage: "folder") {
                    let file = session.map { LogFile.shared.folder.appendingPathComponent($0) }
                        ?? URL(fileURLWithPath: LogFile.shared.path)
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
                .help("The session's log file, which keeps every line after Paddock quits")
                Button("Clear", systemImage: "trash") { model.clearErrorLog() }
                    .disabled(session != nil || model.errorLog.isEmpty)
                    .help("Clear this session's lines here (the file keeps them)")
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            Divider()
            if all.isEmpty {
                ContentUnavailableView(
                    "Nothing logged", systemImage: "checkmark.circle",
                    description: Text("Errors, sandbox setup and activity, and voice are listed here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView("No matching lines", systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("Choose other categories, or change the filter."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LogTextView(entries: entries)
            }
        }
        .onAppear { sessions = LogFile.shared.sessions() }
        .onChange(of: session) { _, name in load(name) }
    }

    /// Reads an earlier session's file; nil shows this session again.
    private func load(_ name: String?) {
        earlier = []
        guard let name else { return }
        Task {
            let read = await LogFile.shared.entries(ofSession: name)
            if session == name { earlier = read }
        }
    }

    private func copy(_ entries: [LogEntry]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entries.map(\.fileLine).joined(separator: "\n"), forType: .string)
    }
}

/// The lines as one read-only text: a selection can span any number of lines (Cmd-C copies it),
/// and a long message wraps under its own column when the page resizes. Columns: time, category,
/// source (cut to its column), message. New lines at the end are appended, not the whole text
/// redrawn, and the view follows them while it is scrolled to the bottom.
@MainActor
private struct LogTextView: NSViewRepresentable {
    let entries: [LogEntry]

    static let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    /// 24-hour time, whatever the Mac's locale: the column has room for eight characters.
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    /// Column widths in characters: time, category, source; the message takes the rest.
    static let columns = [8, 16, 28]
    static let gap = 2

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = true
            text.drawsBackground = false
            text.isRichText = false
            text.textContainerInset = NSSize(width: 8, height: 6)
            text.textContainer?.widthTracksTextView = true
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView, let storage = text.textStorage else { return }
        context.coordinator.show(entries, in: storage, scroll: scroll)
    }

    @MainActor
    final class Coordinator {
        /// What the text shows now, by entry, with each line's length in the text.
        private var shown: [UUID] = []
        private var lengths: [Int] = []

        func show(_ entries: [LogEntry], in storage: NSTextStorage, scroll: NSScrollView) {
            let ids = entries.map(\.id)
            guard ids != shown else { return }
            let atBottom = Self.isAtBottom(scroll)
            storage.beginEditing()
            // Lines that went off the front (the log keeps the newest 5000) are cut; the ones after
            // what is shown are appended. Anything else (a new filter) draws it all again.
            if let first = ids.first, let start = shown.firstIndex(of: first),
               ids.starts(with: shown[start...]) {
                let cut = lengths[..<start].reduce(0, +)
                storage.deleteCharacters(in: NSRange(location: 0, length: cut))
                shown.removeFirst(start)
                lengths.removeFirst(start)
                for entry in entries[shown.count...] { append(entry, to: storage) }
            } else {
                storage.setAttributedString(NSAttributedString())
                shown = []
                lengths = []
                for entry in entries { append(entry, to: storage) }
            }
            storage.endEditing()
            if atBottom, let text = scroll.documentView as? NSTextView {
                text.scrollToEndOfDocument(nil)
            }
        }

        private func append(_ entry: LogEntry, to storage: NSTextStorage) {
            let line = LogTextView.line(entry)
            storage.append(line)
            shown.append(entry.id)
            lengths.append(line.length)
        }

        private static func isAtBottom(_ scroll: NSScrollView) -> Bool {
            guard let document = scroll.documentView else { return true }
            let visible = scroll.contentView.documentVisibleRect
            return visible.maxY >= document.bounds.maxY - 20
        }
    }

    /// One entry: its columns separated by tabs, at fixed stops, and the message's wrapped lines
    /// indented to the message column.
    static func line(_ entry: LogEntry) -> NSAttributedString {
        let char = ("0" as NSString).size(withAttributes: [.font: font]).width
        var stops: [CGFloat] = []
        var position = 0
        for width in columns {
            position += width + gap
            stops.append(CGFloat(position) * char)
        }
        let style = NSMutableParagraphStyle()
        style.tabStops = stops.map { NSTextTab(textAlignment: .left, location: $0) }
        style.headIndent = stops.last ?? 0
        style.lineBreakMode = .byWordWrapping
        let secondary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor,
                                                        .paragraphStyle: style]
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: time.string(from: entry.date) + "\t", attributes: secondary))
        result.append(NSAttributedString(string: cut(entry.category.title, columns[1]) + "\t", attributes: secondary))
        result.append(NSAttributedString(string: cut(entry.source ?? "", columns[2]) + "\t", attributes: secondary))
        let color = entry.isError ? NSColor.systemRed : NSColor.labelColor
        result.append(NSAttributedString(string: entry.message + "\n",
                                         attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
        return result
    }

    /// Text cut to a column's width, the cut marked; the whole of it stays in the file and Copy All.
    private static func cut(_ text: String, _ width: Int) -> String {
        text.count <= width ? text : String(text.prefix(width - 1)) + "…"
    }
}
