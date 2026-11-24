import Foundation

/// Paddock's base kit, recommended and optional (backlog doc Kits, Base): what the agent should know about
/// this sandbox and Paddock's rules (`SandboxGuide`), and the tabs it can fill next to its terminal
/// (backlog doc Browser): `paddock` (`BrowserShow`) for interactive A2UI tabs, native tabs, and
/// everything about a tab, the watcher Paddock follows for them (`BrowserActivity.watcher`, which
/// also reports the browser kit's sessions where that kit is), and the A2UI reference. Small Node
/// scripts and text, nothing downloaded: live pages and the browser are the browser kit's.
///
/// The helper and the watcher keep the names they had in the browser kit (PAD-147), so a sandbox
/// created before the split works until it is recreated.
public enum BaseKit {
    /// sbx names a local kit after its folder, and the names in one sandbox must differ.
    public static let directoryName = "paddock-base"
    /// The A2UI reference agents read before their first interactive tab (`tools/tasks/vendor/a2ui.sh`).
    public static let a2uiReferencePath = "/usr/local/share/paddock/a2ui.md"

    public static var a2uiReference: String {
        guard let url = Bundle.module.url(forResource: "a2ui-reference", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    public static func directory(in paths: PaddockPaths) -> String {
        paths.kits + "/" + directoryName
    }

    /// Whether a project's sandbox gets this kit: chosen, needed by the browser kit, or a kit choice
    /// from before it (`KitSelection.addedToOlderChoices`).
    public static func isChosen(by project: Project, app: AppConfig) -> Bool {
        project.chosenKits(app).contains { app.kits[$0]?.source == .builtin(.base) }
    }

    /// Whether the project's sandbox was created with this kit, any version of it; nil when
    /// Paddock did not record its kits (`Project.sandboxKits`).
    public static func isInSandbox(of project: Project, paths: PaddockPaths) -> Bool? {
        let dir = directory(in: paths)
        return project.sandboxKits.map { kits in kits.contains { $0 == dir || $0.hasPrefix(dir + "#") } }
    }

    /// Indented for `content: |` (16 spaces in the file); an interpolation keeps its own indent.
    static func indented(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "                \($0)" }.joined(separator: "\n")
    }

    public static var spec: String {
        let watcher = Data(BrowserActivity.watcher.utf8).base64EncodedString()
        let show = Data(BrowserShow.script.utf8).base64EncodedString()
        let reference = Data(a2uiReference.utf8).base64EncodedString()
        return #"""
        # syntax=docker/sandbox-kit:3
        # Written by Paddock. Changes are overwritten when Paddock creates a sandbox.
        schemaVersion: "3"
        kind: mixin
        version: "\#(KitFile.version)"
        displayName: Paddock
        description: "Read this before you show the operator anything or ask them something: paddock puts files and questions in tabs next to your terminal and gets their answers back. Also what this sandbox is and what Paddock refuses in its files."
        provides: [paddock-base]

        capabilities:
          - type: com.docker.sandbox/lifecycle@1
            config:
              install:
                - command: |
                    set -eu
                    printf '%s' '\#(show)' | base64 -d > /usr/local/bin/paddock
                    printf '%s' '\#(watcher)' | base64 -d > /usr/local/bin/\#(BrowserActivity.watchName)
                    chmod 755 /usr/local/bin/paddock /usr/local/bin/\#(BrowserActivity.watchName)
                    mkdir -p "$(dirname \#(a2uiReferencePath))"
                    printf '%s' '\#(reference)' | base64 -d > \#(a2uiReferencePath)
                  user: "0"
                  description: Install paddock, the tab watcher, and the A2UI reference

          # What the agent should know about this sandbox and Paddock's rules, so a project's own
          # files need not say it (PAD-71, backlog doc Kits), and how to use the tabs. @1, as sbx's
          # own kits use.
          - type: com.docker.sandbox/agent-context@1
            config:
              content: |
        \#(indented(SandboxGuide.context))

        \#(indented(tabsGuide))

        """#
    }

    /// How the agent shows the operator things and asks them (backlog doc Browser).
    static var tabsGuide: String {
        #"""
        ## Showing the operator things and asking them (Paddock)

        The operator works in Paddock: your terminal, and next to it tabs you can fill. Use them
        instead of pasting paths into the chat or asking questions in the terminal.

        ### Reach for it when
        | Situation | Run |
        |---|---|
        | You need a decision, an approval, or values | `paddock ui question.jsonl --title "Deploy target"` |
        | A document, plan, or report they should read | `paddock open plan.md --native` (on their screen, sharp text) |
        | Playwright's test report | `paddock open playwright-report/index.html --native` |
        | You built or changed a page they should see | `paddock open http://localhost:3000 --title "Checkout"` (needs the browser kit) |

        ### The loop
        1. Show it: `paddock ui ...` or `paddock open ...` prints the tab's id, such as `tab-a3f9`.
           Keep it; every other command needs it.
        2. Tell the operator in one line what to look at (new tabs never take their focus).
        3. Wait for them: `paddock wait tab-a3f9` prints what they did: opened or closed it, what
           a ui tab sent (one JSON line each: a pressed button with its values), or a saved screenshot.
           Run it again for the next thing.
        4. Act on it. `paddock feedback tab-a3f9` prints their screenshots and annotations with
           comments and file paths; `paddock status tab-a3f9` the whole history.

        ### paddock, in detail
        - `ui FILE` (or `ui -` for stdin): an interactive tab the operator answers: forms, choices,
          dates, sliders, tabs, images, video, buttons. You describe it in A2UI v1.0 messages, one
          JSON object per line; Paddock draws it natively on their Mac. Read
          \#(a2uiReferencePath) before your first one. `paddock ui tab-a3f9 more.jsonl` sends
          more messages to it (new values, more components).
          `paddock wait tab-a3f9` prints what the tab sent, one JSON line each: a pressed button
          as `{"version":"1.0","action":{"name":"deploy","context":{"env":["staging"]},...}}` with
          the values you bound in its context, an `error` when A2UI could not use a message (fix
          it and send it again), `{"paddock":"refused",...}` for a line Paddock did not draw.
          Images and video load through this sandbox (https, a path next to the file, or
          `data:`); links open in this sandbox's browser. Never ask for passwords or keys.
        - `open FILE --native [--title T] [--note N]`: a file on their screen, once they click it:
          for documents to read or copy from. `goto ID FILE` points it at another file.
        - `open URL-or-FILE` without `--native`, `annotate ID`, and `reload`/`back` on such a page
          are live pages in this sandbox's browser: they need Paddock's browser kit, and say so
          without it.
        - `note ID TEXT`, `close ID`. Any command with the id first prints what is new, as
          `Paddock:` lines.
        - Before telling the operator you cannot see their review, run `paddock feedback ID`. If
          a comment is unclear (one word, a box over several things), ask what they mean.
        - Other agents may share this sandbox: use only the tab ids you were given.
        - If Paddock gets in your way or lacks something you needed, tell the operator what you
          tried and what would have helped. They are building it and want to know.
        """#
    }

    /// Writes the kit if it is missing or differs. Returns the kit directory.
    @discardableResult
    public static func install(in paths: PaddockPaths) throws -> String {
        try KitFile.write(spec, to: directory(in: paths))
    }
}
