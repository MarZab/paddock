import Foundation
@testable import PaddockCore
import Testing

/// PAD-149: the Markdown of an A2UI tab's Text (backlog doc Browser, interactive tabs).
@Suite("A2UI Markdown")
struct A2UIMarkdownTests {
    typealias Run = A2UIMarkdown.Run

    @Test func tablesKeepTheirCellsAndAlignment() throws {
        let blocks = A2UIMarkdown.blocks("""
            | Service | Replicas | State |
            |:--------|---------:|:-----:|
            | api     | 3        | **up** |
            | worker  | 1 |
            """)
        guard case .table(let table)? = blocks.first, blocks.count == 1 else {
            Issue.record("not one table: \(blocks)")
            return
        }
        #expect(table.alignments == [.leading, .trailing, .center])
        #expect(table.header.map(A2UIMarkdown.plainText) == ["Service", "Replicas", "State"])
        #expect(table.rows.map { $0.map(A2UIMarkdown.plainText) } == [["api", "3", "up"], ["worker", "1", ""]])
        #expect(table.rows[0][2] == [Run("up", bold: true)])
    }

    @Test func everyBlockKind() {
        let blocks = A2UIMarkdown.blocks("""
            ## Deploy *now*

            First, ~~maybe~~ run `make`.
            Same paragraph.

            1. one
            2. two
               - nested

            - [x] done
            - [ ] todo

            > quoted

            ```swift
            let x = 1
            ```

            ---

            <div>raw</div>
            """)
        #expect(blocks.count == 8)
        #expect(blocks[0] == .heading(level: 2, runs: [Run("Deploy "), Run("now", italic: true)]))
        #expect(blocks[1] == .paragraph([Run("First, "), Run("maybe", strikethrough: true), Run(" run "), Run("make", code: true),
                                         Run(". Same paragraph.")]))
        guard case .list(true, 1, let ordered) = blocks[2], case .list(false, 1, let tasks) = blocks[3] else {
            Issue.record("lists: \(blocks[2]) \(blocks[3])")
            return
        }
        #expect(ordered.count == 2 && ordered[1].blocks.count == 2)
        if case .list(false, _, let nested) = ordered[1].blocks[1] {
            #expect(nested.first?.blocks == [.paragraph([Run("nested")])])
        } else {
            Issue.record("no nested list: \(ordered[1].blocks)")
        }
        #expect(tasks.map(\.checkbox) == [true, false])
        #expect(blocks[4] == .quote([.paragraph([Run("quoted")])]))
        #expect(blocks[5] == .code(language: "swift", text: "let x = 1"))
        #expect(blocks[6] == .rule)
        // raw HTML is shown as it is, never parsed
        #expect(blocks[7] == .code(language: nil, text: "<div>raw</div>"))
    }

    /// Nothing loads: an image is its alt text, inline HTML is text.
    @Test func imagesAndHTMLAreText() {
        #expect(A2UIMarkdown.blocks("See ![the chart](https://x.example/c.png) and <b>this</b>.")
            == [.paragraph([Run("See the chart and <b>this</b>.")])])
        #expect(A2UIMarkdown.blocks("![](https://x.example/c.png)") == [.paragraph([Run("[image]")])])
    }

    @Test func linksOpenTheSandboxsPageOrAFileNextToTheMessages() throws {
        let web = try #require(URL(string: "https://docs.example.com/a2ui"))
        let blocks = A2UIMarkdown.blocks("[docs](https://docs.example.com/a2ui), [plan](notes/plan.md#step-2), [mail](mailto:a@b.c), [up](../secret.md)")
        #expect(blocks == [.paragraph([
            Run("docs", link: .web(web)), Run(", "), Run("plan", link: .file("notes/plan.md")), Run(", mail, up"),
        ])])
        #expect(A2UIMarkdown.Link("report%20one.html") == .file("report one.html"))
        for dead in ["file:///etc/passwd", "javascript:alert(1)", "/etc/hosts", "./x.md", "", "http://", "ftp://x/y"] {
            #expect(A2UIMarkdown.Link(dead) == nil, "\(dead)")
        }
    }

    @Test func plainTextStaysOneParagraph() {
        #expect(A2UIMarkdown.blocks("Sign in to your account") == [.paragraph([Run("Sign in to your account")])])
        #expect(A2UIMarkdown.blocks("").isEmpty)
        // a pipe in a sentence is no table
        #expect(A2UIMarkdown.blocks("a | b") == [.paragraph([Run("a | b")])])
    }

    /// Every Text of the A2UI fixtures parses (the upstream examples use headings, bold, and
    /// formatString text), with no block left out.
    @Test func everyFixtureTextParses() throws {
        let folder = try #require(Bundle.module.url(forResource: "a2ui", withExtension: nil, subdirectory: nil))
        let examples = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("examples").path)
        var texts = 0
        for name in examples where name.hasSuffix(".json") {
            let data = try Data(contentsOf: folder.appendingPathComponent("examples/" + name))
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            func walk(_ value: JSONValue) {
                switch value {
                case .object(let object):
                    if object["component"]?.stringValue == "Text", let text = object["text"]?.stringValue {
                        texts += 1
                        #expect(!A2UIMarkdown.blocks(text).isEmpty || text.isEmpty, "\(name): \(text)")
                    }
                    object.values.forEach(walk)
                case .array(let array):
                    array.forEach(walk)
                default:
                    break
                }
            }
            walk(value)
        }
        #expect(texts == 87)
    }

    @Test func fileLinksBecomeANativeTabCommand() {
        #expect(A2UICommands.openFile(sandbox: "web", id: "tab-a3f9", relativePath: "notes/plan.md")?.arguments
            == ["exec", "web", "paddock", "--show-file", "tab-a3f9", "notes/plan.md"])
        #expect(A2UICommands.openFile(sandbox: "web", id: "tab-a3f9", relativePath: "../x") == nil)
        #expect(A2UICommands.openFile(sandbox: "web", id: "tab-a3f9", relativePath: "") == nil)
        #expect(A2UICommands.openFile(sandbox: "web", id: "nope", relativePath: "a.md") == nil)
    }
}
