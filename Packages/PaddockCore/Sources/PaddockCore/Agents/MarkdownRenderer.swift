import Foundation
import Markdown

/// Markdown to HTML for `MarkdownPage` (backlog doc Browser, Native show tabs): every piece of text
/// escaped, raw HTML shown as text, links and images only where `MarkdownPage` allows them.
struct MarkdownRenderer {
    private var usedSlugs: [String: Int] = [:]
    /// Inside an item of a tight list: its paragraphs get no `<p>` (CommonMark's rendering).
    private var tight = false
    private var inLink = false

    mutating func render(_ markup: any Markup) -> String {
        if markup is InlineMarkup {
            return renderInline(markup)
        }
        return renderBlock(markup)
    }

    private mutating func renderBlock(_ markup: any Markup) -> String {
        switch markup {
        case let heading as Heading:
            let level = min(max(heading.level, 1), 6)
            return "<h\(level) id=\"\(MarkdownPage.escape(uniqueSlug(heading.plainText)))\">\(children(heading))</h\(level)>\n"
        case let paragraph as Paragraph:
            if tight, paragraph.parent is ListItem {
                return children(paragraph) + (paragraph.indexInParent + 1 < (paragraph.parent?.childCount ?? 0) ? "\n" : "")
            }
            return "<p>\(children(paragraph))</p>\n"
        case let block as CodeBlock:
            let language = block.language.map { " data-language=\"\(MarkdownPage.escape($0))\"" } ?? ""
            return "<pre\(language)><code>\(MarkdownPage.escape(block.code))</code></pre>\n"
        case let quote as BlockQuote:
            return "<blockquote>\n\(children(quote))</blockquote>\n"
        case let list as OrderedList:
            let start = list.startIndex == 1 ? "" : " start=\"\(list.startIndex)\""
            return "<ol\(start)>\n\(items(list))</ol>\n"
        case let list as UnorderedList:
            return "<ul>\n\(items(list))</ul>\n"
        case let item as ListItem:
            switch item.checkbox {
            case .checked?:
                return "<li class=\"task\"><input type=\"checkbox\" checked disabled> \(children(item))</li>\n"
            case .unchecked?:
                return "<li class=\"task\"><input type=\"checkbox\" disabled> \(children(item))</li>\n"
            case nil:
                return "<li>\(children(item))</li>\n"
            }
        case is ThematicBreak:
            return "<hr>\n"
        // Raw HTML in the file is shown, never parsed.
        case let html as HTMLBlock:
            return "<pre class=\"raw-html\">\(MarkdownPage.escape(String(html.rawHTML.trimmingSuffix("\n"))))</pre>\n"
        case let table as Table:
            return renderTable(table)
        default:
            return children(markup)
        }
    }

    private mutating func renderInline(_ markup: any Markup) -> String {
        switch markup {
        case let text as Markdown.Text:
            return inLink ? MarkdownPage.escape(text.string) : autolinked(text.string)
        case let emphasis as Emphasis:
            return "<em>\(children(emphasis))</em>"
        case let strong as Strong:
            return "<strong>\(children(strong))</strong>"
        case let strike as Strikethrough:
            return "<del>\(children(strike))</del>"
        case let code as InlineCode:
            return "<code>\(MarkdownPage.escape(code.code))</code>"
        case let link as Link:
            inLink = true
            defer { inLink = false }
            guard let destination = link.destination, let href = MarkdownPage.safeLink(destination) else {
                return "<span class=\"dead-link\" title=\"\(MarkdownPage.escape(link.destination ?? ""))\">\(children(link))</span>"
            }
            return "<a href=\"\(MarkdownPage.escape(href))\" title=\"\(MarkdownPage.escape(link.title ?? href))\">\(children(link))</a>"
        case let image as Image:
            let alt = image.plainText
            guard let source = image.source, let src = MarkdownPage.safeImage(source) else {
                return "<span class=\"dead-image\" title=\"\(MarkdownPage.escape(image.source ?? ""))\">[\(MarkdownPage.escape(alt.isEmpty ? "image" : alt))]</span>"
            }
            let title = image.title.map { " title=\"\(MarkdownPage.escape($0))\"" } ?? ""
            return "<img src=\"\(MarkdownPage.escape(src))\" alt=\"\(MarkdownPage.escape(alt))\"\(title)>"
        case is LineBreak:
            return "<br>\n"
        case is SoftBreak:
            return "\n"
        case let html as InlineHTML:
            return MarkdownPage.escape(html.rawHTML)
        case let link as SymbolLink:
            return "<code>\(MarkdownPage.escape(link.destination ?? ""))</code>"
        default:
            return children(markup)
        }
    }

    private mutating func children(_ markup: any Markup) -> String {
        markup.children.map { render($0) }.joined()
    }

    /// GFM's bare URLs (swift-markdown leaves out cmark's autolink extension): http(s) URLs in
    /// text become links, without trailing punctuation or an unmatched `)`.
    private func autolinked(_ text: String) -> String {
        guard text.contains("http") else { return MarkdownPage.escape(text) }
        var result = ""
        var rest = Substring(text)
        while let match = rest.firstMatch(of: /https?:\/\/[^\s<>"'`]+/) {
            var url = match.output
            while let last = url.last, ".,:;!?*_~".contains(last)
                || (last == ")" && url.filter { $0 == "(" }.count < url.filter { $0 == ")" }.count) {
                url = url.dropLast()
            }
            result += MarkdownPage.escape(String(rest[..<match.range.lowerBound]))
            result += "<a href=\"\(MarkdownPage.escape(String(url)))\" title=\"\(MarkdownPage.escape(String(url)))\">\(MarkdownPage.escape(String(url)))</a>"
            rest = rest[url.endIndex...]
        }
        return result + MarkdownPage.escape(String(rest))
    }

    private mutating func items(_ list: any ListItemContainer) -> String {
        let outer = tight
        tight = !isLoose(list)
        defer { tight = outer }
        return children(list)
    }

    /// CommonMark: a list is loose when a blank line separates two of its items, or two blocks
    /// directly inside one item. Told from source lines, which swift-markdown keeps.
    private func isLoose(_ list: any ListItemContainer) -> Bool {
        func separated(_ blocks: [any Markup]) -> Bool {
            zip(blocks, blocks.dropFirst()).contains { previous, next in
                guard let end = previous.range?.upperBound.line, let start = next.range?.lowerBound.line else { return false }
                return start > end + 1
            }
        }
        let items = Array(list.children)
        return separated(items) || items.contains { separated(Array($0.children)) }
    }

    private mutating func uniqueSlug(_ text: String) -> String {
        let base = MarkdownPage.slug(text)
        let seen = usedSlugs[base, default: 0]
        usedSlugs[base] = seen + 1
        return seen == 0 ? base : "\(base)-\(seen)"
    }

    private mutating func renderTable(_ table: Table) -> String {
        let alignments = table.columnAlignments
        func align(_ column: Int) -> String {
            guard column < alignments.count, let alignment = alignments[column] else { return "" }
            switch alignment {
            case .left: return " style=\"text-align:left\""
            case .center: return " style=\"text-align:center\""
            case .right: return " style=\"text-align:right\""
            }
        }
        func cells(_ row: some Markup, tag: String) -> String {
            var column = 0
            var result = ""
            for case let cell as Table.Cell in row.children {
                defer { column += Int(max(cell.colspan, 1)) }
                guard cell.colspan > 0, cell.rowspan > 0 else { continue }
                let span = (cell.colspan > 1 ? " colspan=\"\(cell.colspan)\"" : "")
                    + (cell.rowspan > 1 ? " rowspan=\"\(cell.rowspan)\"" : "")
                result += "<\(tag)\(span)\(align(column))>\(children(cell))</\(tag)>"
            }
            return result
        }
        var html = "<div class=\"table\"><table>\n<thead><tr>\(cells(table.head, tag: "th"))</tr></thead>\n<tbody>\n"
        for row in table.body.rows {
            html += "<tr>\(cells(row, tag: "td"))</tr>\n"
        }
        return html + "</tbody></table></div>\n"
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> Substring {
        hasSuffix(suffix) ? dropLast(suffix.count) : self[...]
    }
}
