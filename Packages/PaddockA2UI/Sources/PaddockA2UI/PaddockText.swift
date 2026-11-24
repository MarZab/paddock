import A2UICore
import A2UISwiftUI
import BasicCatalogSwiftUI
import PaddockCore
import SwiftUI

/// Opens what the operator clicks in a tab's text: set once by the tab, before any surface exists.
@MainActor
final class A2UILinkOpener {
    var handler: (@MainActor (A2UIMarkdown.Link) -> Void)?

    func open(_ link: A2UIMarkdown.Link) {
        handler?(link)
    }
}

/// The basic catalog's Text, Paddock's (PAD-149): its Markdown drawn natively with tables
/// (`A2UIMarkdown`), which A2UI's own Text does not draw. `caption` is small, italic, and
/// secondary, as in A2UI. A link opens only as `A2UIMarkdown.Link` allows, through the tab.
struct PaddockText: View {
    let node: Node
    let links: A2UILinkOpener

    private var text: String { node.string(for: "text") ?? "" }

    var body: some View {
        let blocks = A2UIMarkdown.blocks(text)
        Group {
            if node.string(for: "variant") == "caption" {
                MarkdownBlocksView(blocks: blocks)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            } else {
                MarkdownBlocksView(blocks: blocks)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            // Classified again here: the URL came from the agent's text.
            if let link = A2UIMarkdown.Link(url.absoluteString) {
                MainActor.assumeIsolated { links.open(link) }
            }
            return .handled
        })
        .a2uiAccessibleText(MarkdownBlocksView.plainText(blocks))
    }
}

/// Blocks one under the other.
struct MarkdownBlocksView: View {
    let blocks: [A2UIMarkdown.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks.indices, id: \.self) { index in
                MarkdownBlockView(block: blocks[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The text without its Markdown, as it reads on screen.
    static func plainText(_ blocks: [A2UIMarkdown.Block]) -> String {
        blocks.map { block in
            switch block {
            case .heading(_, let runs), .paragraph(let runs): A2UIMarkdown.plainText(runs)
            case .list(_, _, let items): items.map { plainText($0.blocks) }.joined(separator: "\n")
            case .code(_, let text): text
            case .quote(let inner): plainText(inner)
            case .table(let table): ([table.header] + table.rows).map { $0.map(A2UIMarkdown.plainText).joined(separator: ", ") }.joined(separator: "\n")
            case .rule: ""
            }
        }.joined(separator: "\n")
    }

    /// A run's styles as SwiftUI draws them, and its link as a URL the tab's handler classifies again.
    static func attributed(_ runs: [A2UIMarkdown.Run]) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            var intent: InlinePresentationIntent = []
            if run.bold { intent.insert(.stronglyEmphasized) }
            if run.italic { intent.insert(.emphasized) }
            if run.code { intent.insert(.code) }
            if run.strikethrough {
                intent.insert(.strikethrough)
                piece.strikethroughStyle = .single
            }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            switch run.link {
            case .web(let url)?:
                piece.link = url
            case .file(let path)?:
                // Relative, percent-encoded: `A2UIMarkdown.Link` reads it back as the same file.
                piece.link = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap { URL(string: $0) }
            case nil:
                break
            }
            result += piece
        }
        return result
    }
}

/// One block. A quote and a list item hold blocks again, through `AnyView`.
struct MarkdownBlockView: View {
    let block: A2UIMarkdown.Block

    var body: some View {
        switch block {
        case .heading(let level, let runs):
            Text(MarkdownBlocksView.attributed(runs))
                .font(A2UIText.headingFont(level: level))
                .accessibilityAddTraits(.isHeader)
                .textSelection(.enabled)
        case .paragraph(let runs):
            Text(MarkdownBlocksView.attributed(runs))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        marker(items[index], ordered: ordered, number: start + index)
                        AnyView(MarkdownBlocksView(blocks: items[index].blocks))
                    }
                }
            }
        case .code(_, let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.12), in: .rect(cornerRadius: 6))
        case .quote(let inner):
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                AnyView(MarkdownBlocksView(blocks: inner)).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .table(let table):
            MarkdownTableView(table: table)
        case .rule:
            Divider()
        }
    }

    @ViewBuilder
    private func marker(_ item: A2UIMarkdown.ListItem, ordered: Bool, number: Int) -> some View {
        if let checked = item.checkbox {
            Image(systemName: checked ? "checkmark.square" : "square")
                .accessibilityLabel(checked ? "Done" : "Not done")
        } else {
            Text(ordered ? "\(number)." : "\u{2022}").monospacedDigit()
        }
    }
}

/// A table as a grid: the header in bold over a line, each column aligned as its separator row
/// says. A wide one scrolls sideways.
struct MarkdownTableView: View {
    let table: A2UIMarkdown.Table

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    ForEach(table.header.indices, id: \.self) { column in
                        Text(MarkdownBlocksView.attributed(table.header[column]))
                            .bold()
                            .gridColumnAlignment(alignment(column))
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(table.rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(table.rows[row].indices, id: \.self) { column in
                            Text(MarkdownBlocksView.attributed(table.rows[row][column]))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func alignment(_ column: Int) -> HorizontalAlignment {
        switch column < table.alignments.count ? table.alignments[column] : nil {
        case .center?: .center
        case .trailing?: .trailing
        default: .leading
        }
    }
}
