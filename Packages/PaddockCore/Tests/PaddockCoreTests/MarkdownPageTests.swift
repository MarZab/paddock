import Foundation
@testable import PaddockCore
import Testing

/// PAD-67: Markdown from the sandbox renders as Paddock's own page in a native show tab
/// (backlog doc Browser). The fixture is a made-up document shaped like one an agent wrote: front matter, 9-column tables, `<id>`-style text that CommonMark reads as raw HTML, and a stray `"0"|"1"`.
@Suite("MarkdownPage")
struct MarkdownPageTests {
    func inventory() throws -> String {
        return try MarkdownPage.html(
            from: String(decoding: Fixture.data("markdown", "operation-inventory.md"), as: UTF8.self),
            title: "operation-inventory.md"
        )
    }

    func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    @Test func rendersTheAgentsInventory() throws {
        let html = try inventory()
        // Front matter is a key/value block, not a rule and a setext heading.
        #expect(html.contains("<table class=\"front-matter\"><tr><th>id</th><td>pantry-1</td></tr>"))
        #expect(html.contains("<th>created_date</th><td>2026-11-01T14:54:00Z</td>"))
        #expect(!html.contains("<hr>"))
        #expect(html.contains("<h1 id=\"operation-inventory-pantry-1\">Operation inventory (PANTRY-1)</h1>"))
        #expect(html.contains("<h2 id=\"questions-for-the-owner\">"))
        #expect(count("<h2 ", in: html) == 5)
        // Every table, with a header and rows.
        #expect(count("<div class=\"table\"><table>", in: html) == 2)
        #expect(html.contains("<th>Proposed op</th><th>Route today</th>"))
        #expect(!html.contains("|---|"))
        // Nested list in the summary, ordered list of questions.
        #expect(html.contains("<li>keep as a pair"))
        #expect(html.contains("<ol>\n<li>Uploads as one operation"))
        // Typed quotes stay as typed (no smart punctuation).
        #expect(html.contains("set_item&#39;s field patch"))
        // Raw HTML in the text shows literally.
        #expect(html.contains("credential: token:&lt;id&gt;|app:&lt;grant&gt;"))
        #expect(html.contains("SPA &lt;img src&gt; (editor/preview.tsx:82)"))
        #expect(!html.contains("<img"))
        #expect(!html.contains("<id>"))
    }

    @Test func aRowWithAStrayPipeKeepsItsCells() throws {
        let html = try inventory()
        let row = try #require(html.components(separatedBy: "\n").first { $0.contains("<td>get_logs</td>") })
        #expect(count("<td", in: row) == 9)
        #expect(row.contains("<td>refresh &quot;0&quot;|&quot;1&quot; vs boolean</td><td>keep, boolean</td><td>both</td>"))
    }

    @Test func repairsOnlyRowsWithTooManyCells() {
        let source = """
        | a | b |
        |---|---|
        | x|y | z |
        | `p|q` | r |
        | 1 | 2 | 3 |
        """
        let repaired = MarkdownPage.repairTablePipes(source).split(separator: "\n").map(String.init)
        #expect(repaired[2] == #"| x\|y | z |"#)
        #expect(repaired[3] == #"| `p\|q` | r |"#)
        // Three spaced cells: nothing tight to repair, GFM drops the extra one.
        #expect(repaired[4] == "| 1 | 2 | 3 |")
        let html = MarkdownPage.html(from: source, title: "t")
        #expect(html.contains("<td>x|y</td><td>z</td>"))
        #expect(html.contains("<td><code>p|q</code></td><td>r</td>"))
        // Pipes in code fences and outside tables are left alone.
        let fenced = "```\n| a | b |\n|---|---|\n| x|y | z | w |\n```\n"
        #expect(MarkdownPage.repairTablePipes(fenced) == fenced)
        #expect(MarkdownPage.repairTablePipes("a|b|c") == "a|b|c")
    }

    @Test func rendersGitHubFlavoredMarkdown() {
        let html = MarkdownPage.html(from: """
        # Title
        Some *em*, **strong**, ~~gone~~, `code` and a line\\
        break.

        > quoted

        1. one
        2. two
           - nested

        - [x] done
        - [ ] todo

        ```swift
        let a = "<b>"
        ```

        | Left | Mid | Right |
        |:-----|:---:|------:|
        | a | b | c |

        ---
        https://example.com
        """, title: "t")
        #expect(html.contains("<em>em</em>") && html.contains("<strong>strong</strong>") && html.contains("<del>gone</del>"))
        #expect(html.contains("<code>code</code>") && html.contains("<br>"))
        #expect(html.contains("<blockquote>"))
        #expect(html.contains("<ol>") && html.contains("<ul>\n<li>nested"))
        #expect(html.contains("<li class=\"task\"><input type=\"checkbox\" checked disabled>"))
        #expect(html.contains("<li class=\"task\"><input type=\"checkbox\" disabled>"))
        #expect(html.contains("<pre data-language=\"swift\"><code>let a = &quot;&lt;b&gt;&quot;\n</code></pre>"))
        #expect(html.contains("<th style=\"text-align:left\">Left</th><th style=\"text-align:center\">Mid</th><th style=\"text-align:right\">Right</th>"))
        #expect(html.contains("<hr>"))
        #expect(html.contains("<a href=\"https://example.com\" title=\"https://example.com\">https://example.com</a>"))
        // Bare URLs lose trailing punctuation; an empty cell is a cell, not a span.
        let more = MarkdownPage.html(from: "See (https://example.com/a_(b)). Done\n\n| a | b | c |\n|---|---|---|\n| x |  | z |", title: "t")
        #expect(more.contains("(<a href=\"https://example.com/a_(b)\" title=\"https://example.com/a_(b)\">https://example.com/a_(b)</a>)."))
        #expect(more.contains("<td>x</td><td></td><td>z</td>"))
    }

    @Test func nothingFromTheFileRuns() {
        let html = MarkdownPage.html(from: """
        <script>alert(1)</script>

        Inline <img src=x onerror=alert(1)> and <a href="javascript:x">a</a>.

        [js](javascript:alert(1)) [file](file:///etc/passwd) [net](//evil.example/x)
        ![remote](https://evil.example/p.png) ![local](shot.png) ![data](data:image/png;base64,AAAA)
        ![svg](data:text/html,<script>)
        """, title: "<title>")
        #expect(!html.contains("<script>") && !html.contains("<img src=x") && !html.contains("<a href=\"javascript"))
        #expect(html.contains("<pre class=\"raw-html\">&lt;script&gt;alert(1)&lt;/script&gt;</pre>"))
        #expect(html.contains("<span class=\"dead-link\" title=\"javascript:alert(1)\">js</span>"))
        #expect(html.contains("<span class=\"dead-link\" title=\"file:///etc/passwd\">file</span>"))
        #expect(html.contains("<span class=\"dead-link\" title=\"//evil.example/x\">net</span>"))
        #expect(html.contains("<span class=\"dead-image\" title=\"https://evil.example/p.png\">[remote]</span>"))
        #expect(html.contains("<img src=\"shot.png\" alt=\"local\">"))
        #expect(html.contains("<img src=\"data:image/png;base64,AAAA\" alt=\"data\">"))
        #expect(!html.contains("src=\"data:text/html"))
        #expect(html.contains("<title>&lt;title&gt;</title>"))
        #expect(html.contains("content=\"default-src 'none'; img-src paddock-file: data:; style-src 'unsafe-inline'"))
    }

    @Test func linksKeepRelativeTargetsAndAnchors() {
        let html = MarkdownPage.html(from: """
        ## Same name
        ## Same name
        [next](other.md) [part](#same-name-1) [web](https://example.com "Example")
        """, title: "t")
        #expect(html.contains("<h2 id=\"same-name\">") && html.contains("<h2 id=\"same-name-1\">"))
        #expect(html.contains("<a href=\"other.md\" title=\"other.md\">next</a>"))
        #expect(html.contains("<a href=\"#same-name-1\""))
        #expect(html.contains("<a href=\"https://example.com\" title=\"Example\">web</a>"))
    }

    @Test func frontMatter() {
        let (fields, body) = MarkdownPage.splitFrontMatter("---\na: 1\nb: \"two\"\n---\n# Hi")
        #expect(fields == .fields([("a", "1"), ("b", "two")]))
        #expect(body == "# Hi")
        let (nested, _) = MarkdownPage.splitFrontMatter("---\nlist:\n  - x\n---\n")
        #expect(nested == .raw("list:\n  - x"))
        // No closing line: no front matter, the rule stays.
        let (none, text) = MarkdownPage.splitFrontMatter("---\nnot closed")
        #expect(none == nil && text == "---\nnot closed")
        #expect(MarkdownPage.html(from: "\u{FEFF}---\r\nk: v\r\n---\r\nx", title: "t").contains("<th>k</th><td>v</td>"))
    }

    @Test func theTabServesMarkdownAsAPage() throws {
        let policy = try #require(NativeShowPolicy(showID: "tab-e5f6", fileName: "notes.md"))
        #expect(policy.rendering == .markdown && !policy.allowsJavaScript)
        #expect(NativeShowPolicy(showID: "tab-e5f6", fileName: "page.html")?.allowsJavaScript == true)
        let page = NativeShowPolicy.response(for: "docs/Other.MD", data: Data("# Hi".utf8))
        #expect(page.mimeType == "text/html")
        #expect(String(decoding: page.data, as: UTF8.self).contains("<h1 id=\"hi\">Hi</h1>"))
        #expect(String(decoding: page.data, as: UTF8.self).contains("<title>Other.MD</title>"))
        let image = NativeShowPolicy.response(for: "a.png", data: Data([1, 2]))
        #expect(image.mimeType == "image/png" && image.data == Data([1, 2]))
    }
}
