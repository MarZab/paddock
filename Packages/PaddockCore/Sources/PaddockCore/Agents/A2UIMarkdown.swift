import Foundation
import Markdown

/// The Markdown of an A2UI tab's Text, as blocks PaddockA2UI draws natively (PAD-149; backlog doc
/// Browser, interactive tabs): GitHub Markdown with tables, which A2UI's own Text does not draw.
/// Parsed with swift-markdown (cmark-gfm), the same parser as native Markdown tabs. As in A2UI,
/// nothing in it loads: an image is its alt text and raw HTML is text. Links are the one thing
/// that does something, and only as `Link` says: a page of the sandbox's browser, or a file next to
/// the tab's messages opened as a native tab.
public enum A2UIMarkdown {
    /// A link's target, or nil for one that opens nothing (`mailto:`, `file:`, `javascript:`, an
    /// absolute path, a path out of the folder).
    public enum Link: Sendable, Equatable {
        /// An http(s) page, opened in the sandbox's browser (`A2UICommands.open`).
        case web(URL)
        /// A file next to the tab's messages, opened as a native tab (`A2UICommands.openFile`).
        case file(String)

        public init?(_ destination: String) {
            let text = destination.trimmingCharacters(in: .whitespaces)
            if let scheme = A2UIMedia.scheme(of: text) {
                guard ["http", "https"].contains(scheme), let url = URL(string: text), url.host?.isEmpty == false else { return nil }
                self = .web(url)
                return
            }
            // A file's fragment or query is not part of its path.
            let path = String(text.prefix { $0 != "#" && $0 != "?" })
            let decoded = path.removingPercentEncoding ?? path
            guard !decoded.isEmpty, NativeShowPolicy.isRelativePath(decoded) else { return nil }
            self = .file(decoded)
        }
    }

    /// A piece of text with one style.
    public struct Run: Sendable, Equatable {
        public var text: String
        public var bold = false
        public var italic = false
        public var strikethrough = false
        public var code = false
        public var link: Link?

        public init(_ text: String, bold: Bool = false, italic: Bool = false, strikethrough: Bool = false, code: Bool = false, link: Link? = nil) {
            self.text = text
            self.bold = bold
            self.italic = italic
            self.strikethrough = strikethrough
            self.code = code
            self.link = link
        }
    }

    public struct ListItem: Sendable, Equatable {
        /// A task list item's box: true when ticked; nil for an ordinary item.
        public var checkbox: Bool?
        public var blocks: [Block]
    }

    public enum Alignment: Sendable, Equatable {
        case leading, center, trailing
    }

    public struct Table: Sendable, Equatable {
        /// One per column; nil where the separator row sets none.
        public var alignments: [Alignment?]
        public var header: [[Run]]
        /// Each row with as many cells as the header (short rows are filled with empty cells).
        public var rows: [[[Run]]]
    }

    public enum Block: Sendable, Equatable {
        case heading(level: Int, runs: [Run])
        case paragraph([Run])
        case list(ordered: Bool, start: Int, items: [ListItem])
        case code(language: String?, text: String)
        case quote([Block])
        case table(Table)
        case rule
    }

    /// The blocks of `text`, the Text's whole content.
    public static func blocks(_ text: String) -> [Block] {
        let document = Document(parsing: MarkdownPage.repairTablePipes(text), options: [.disableSmartOpts])
        return document.children.compactMap(block)
    }

    static func block(_ markup: any Markup) -> Block? {
        switch markup {
        case let heading as Heading:
            return .heading(level: min(max(heading.level, 1), 6), runs: runs(heading))
        case let paragraph as Paragraph:
            return .paragraph(runs(paragraph))
        case let list as OrderedList:
            return .list(ordered: true, start: Int(list.startIndex), items: items(list))
        case let list as UnorderedList:
            return .list(ordered: false, start: 1, items: items(list))
        case let code as CodeBlock:
            let language = code.language.flatMap { $0.isEmpty ? nil : $0 }
            return .code(language: language, text: code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code)
        case let quote as BlockQuote:
            return .quote(quote.children.compactMap(block))
        case let table as Markdown.Table:
            return .table(self.table(table))
        case is ThematicBreak:
            return .rule
        // Raw HTML is shown, never parsed.
        case let html as HTMLBlock:
            let raw = html.rawHTML.hasSuffix("\n") ? String(html.rawHTML.dropLast()) : html.rawHTML
            return .code(language: nil, text: raw)
        default:
            let inner = runs(markup)
            return inner.isEmpty ? nil : .paragraph(inner)
        }
    }

    static func items(_ list: any ListItemContainer) -> [ListItem] {
        list.children.compactMap { child in
            guard let item = child as? Markdown.ListItem else { return nil }
            let checkbox: Bool? = switch item.checkbox {
            case .checked?: true
            case .unchecked?: false
            case nil: nil
            }
            return ListItem(checkbox: checkbox, blocks: item.children.compactMap(block))
        }
    }

    static func table(_ table: Markdown.Table) -> Table {
        let alignments: [Alignment?] = table.columnAlignments.map {
            switch $0 {
            case .left?: .leading
            case .center?: .center
            case .right?: .trailing
            case nil: nil
            }
        }
        func cells(_ row: some Markup) -> [[Run]] {
            row.children.compactMap { ($0 as? Markdown.Table.Cell).map { runs($0) } }
        }
        let header = cells(table.head)
        let width = max(header.count, alignments.count)
        func padded(_ row: [[Run]]) -> [[Run]] {
            row.count >= width ? Array(row.prefix(width)) : row + Array(repeating: [], count: width - row.count)
        }
        return Table(alignments: alignments + Array(repeating: nil, count: max(0, width - alignments.count)),
                     header: padded(header), rows: table.body.rows.map { padded(cells($0)) })
    }

    /// The inline content of `markup`, merged where neighbours share a style.
    static func runs(_ markup: any Markup) -> [Run] {
        var result: [Run] = []
        func append(_ run: Run) {
            guard !run.text.isEmpty else { return }
            if var last = result.last, last.bold == run.bold, last.italic == run.italic, last.strikethrough == run.strikethrough,
               last.code == run.code, last.link == run.link {
                last.text += run.text
                result[result.count - 1] = last
            } else {
                result.append(run)
            }
        }
        func walk(_ markup: any Markup, _ style: Run) {
            switch markup {
            case let text as Markdown.Text:
                append(with(style, text.string))
            case let code as InlineCode:
                var run = with(style, code.code)
                run.code = true
                append(run)
            case is SoftBreak:
                append(with(style, " "))
            case is LineBreak:
                append(with(style, "\n"))
            case let html as InlineHTML:
                append(with(style, html.rawHTML))
            case let image as Markdown.Image:
                // Not loaded: its alt text, as A2UI does.
                let alt = image.plainText
                append(with(style, alt.isEmpty ? "[image]" : alt))
            case let symbol as SymbolLink:
                var run = with(style, symbol.destination ?? "")
                run.code = true
                append(run)
            default:
                var inner = style
                switch markup {
                case is Strong: inner.bold = true
                case is Emphasis: inner.italic = true
                case is Strikethrough: inner.strikethrough = true
                case let link as Markdown.Link: inner.link = link.destination.flatMap(Link.init)
                default: break
                }
                for child in markup.children { walk(child, inner) }
            }
        }
        for child in markup.children { walk(child, Run("")) }
        return result
    }

    private static func with(_ style: Run, _ text: String) -> Run {
        var run = style
        run.text = text
        return run
    }

    /// The text of `runs` without styles, for accessibility and tests.
    public static func plainText(_ runs: [Run]) -> String {
        runs.map(\.text).joined()
    }
}
