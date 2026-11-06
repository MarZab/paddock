import Foundation

/// Paddock's browser kit, on top of sbx's Playwright kit (`docker.io/sbx/playwright-kit`, which
/// brings Chromium's system libraries and `/opt/ms-playwright`): Microsoft's `playwright-cli`, a
/// browser CLI made for coding agents, with its skill for Claude Code and for agents that read
/// `~/.agents/skills` (OpenCode). Any agent with a shell can drive it, so it is not tied to one.
///
/// Every page the agent opens gets a browser tab in Paddock, with its activity (`BrowserActivity`:
/// a wrapper under playwright-cli's name and a watcher Paddock follows). Those tabs show
/// playwright-cli's dashboard (`playwright-cli show`), which the kit starts on every sandbox start
/// and sbx publishes on the Mac's loopback (a random host port), each tab selecting its own page;
/// the operator can take over mouse and keyboard there (backlog doc Browser). Pages render in the
/// sandbox: the Mac only shows the dashboard.
public enum BrowserKit {
    /// sbx names a local kit after its folder, and the names in one sandbox must differ, so not
    /// `browser` (sbx 0.51 ships an `opencode` kit of its own; PAD-73.2).
    public static let directoryName = "paddock-browser"
    /// `@playwright/cli`; 0.1.22 is built on Playwright 1.64 (alpha), so it installs its own
    /// Chromium build next to the Playwright kit's.
    public static let version = "0.1.22"
    public static let package = "@playwright/cli"
    /// The dashboard's port inside the sandbox; sbx publishes it on `127.0.0.1` (backlog doc Browser).
    /// Not 9323: that is `npx playwright show-report`'s default, and a report server there took the
    /// dashboard's place.
    public static let dashboardPort = 38323
    /// playwright-cli's snapshots and logs; outside the project, so nothing lands in the repository.
    public static let outputDirectory = "/tmp/playwright-cli"
    /// sbx's proxy CA in the sandbox. Chromium on Linux checks its own store (`~/.pki/nssdb`), not
    /// the system's, so the kit imports it there; certificate checks stay on.
    public static let proxyCA = "/usr/local/share/ca-certificates/proxy-ca.crt"

    public static func directory(in paths: PaddockPaths) -> String {
        paths.kits + "/" + directoryName
    }

    public static var spec: String {
        let wrapper = Data(BrowserActivity.wrapper.utf8).base64EncodedString()
        let watcher = Data(BrowserActivity.watcher.utf8).base64EncodedString()
        let show = Data(BrowserShow.script.utf8).base64EncodedString()
        let reference = Data(openUIReference.utf8).base64EncodedString()
        return #"""
        # syntax=docker/sandbox-kit:3
        # Written by Paddock. Changes are overwritten when Paddock creates a sandbox.
        schemaVersion: "3"
        kind: mixin
        version: "\#(KitFile.version)"
        displayName: Browser (Paddock)
        description: "Before you show the operator anything or ask them something, read this: paddock puts pages, files, and questions in tabs next to your terminal (and gets their answers back); playwright-cli is your browser."
        provides: [paddock-browser]

        args:
          browser:
            # Playwright's own Chromium ("chrome-for-testing"); playwright-cli would otherwise ask
            # for Google Chrome, which has no Linux arm64 build.
            default: chromium
            env: PLAYWRIGHT_MCP_BROWSER
          outputDir:
            # Snapshots and logs outside the project folder.
            default: \#(outputDirectory)
            env: PLAYWRIGHT_MCP_OUTPUT_DIR
          socketsDir:
            # One sockets folder for every process, so annotations find the dashboard.
            default: \#(socketsDirectory)
            env: PWTEST_SOCKETS_DIR

        capabilities:
          # npm (install), and Playwright's browser downloads: playwright-cli fetches the Chromium
          # build it was made for, the same hosts the Playwright kit allows. apt (libnss3-tools)
          # uses the Ubuntu hosts the Playwright kit allows.
          - type: com.docker.sandbox/network-policy@2
            config:
              install:
                allow: [registry.npmjs.org:443, cdn.playwright.dev:443, playwright.download.prss.microsoft.com:443, storage.googleapis.com:443]
              runtime:
                allow: [registry.npmjs.org:443, cdn.playwright.dev:443, playwright.download.prss.microsoft.com:443, storage.googleapis.com:443]
          - type: com.docker.sandbox/port@1
            config:
              container: \#(dashboardPort)
              name: playwright-dashboard
              transport: tcp
          - type: com.docker.sandbox/lifecycle@1
            config:
              install:
                - command: |
                    set -eu
                    if [ -n "${HTTP_PROXY:-}" ]; then
                      npm config set proxy "$HTTP_PROXY"
                      npm config set https-proxy "$HTTP_PROXY"
                    fi
                    npm install --global --no-fund --no-audit --loglevel=error "\#(package)@\#(version)"
                    # The real playwright-cli, for the wrapper and the watcher.
                    real="$(readlink -f "$(command -v playwright-cli)")"
                    mkdir -p "$(dirname \#(BrowserActivity.realCLI))"
                    ln -sf "$real" \#(BrowserActivity.realCLI)
                    export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/ms-playwright}"
                    mkdir -p "$PLAYWRIGHT_BROWSERS_PATH"
                    \#(BrowserActivity.realCLI) install-browser chromium
                    chmod -R a+rwX "$PLAYWRIGHT_BROWSERS_PATH"
                    # certutil, to put sbx's proxy CA into Chromium's own certificate store.
                    apt-get update -qq && apt-get install -y -qq --no-install-recommends libnss3-tools
                    rm -rf /var/lib/apt/lists/*
                    # The wrapper under every playwright-cli name on the PATH (it runs the real one).
                    for bin in $(which -a playwright-cli) /usr/local/bin/playwright-cli; do
                      rm -f "$bin"
                      printf '%s' '\#(wrapper)' | base64 -d > "$bin"
                      chmod 755 "$bin"
                    done
                    printf '%s' '\#(watcher)' | base64 -d > /usr/local/bin/paddock-browser-watch
                    chmod 755 /usr/local/bin/paddock-browser-watch
                    printf '%s' '\#(show)' | base64 -d > /usr/local/bin/paddock
                    chmod 755 /usr/local/bin/paddock
                    mkdir -p "$(dirname \#(openUIReferencePath))"
                    printf '%s' '\#(reference)' | base64 -d > \#(openUIReferencePath)
                  user: "0"
                  # A hook sees only the environment it names: npm's global bin is on the image's PATH.
                  env: [PATH, HOME, HTTP_PROXY, HTTPS_PROXY, NO_PROXY]
                  description: Install playwright-cli \#(version) (npm \#(package)), its Chromium build, certutil, and Paddock's wrapper, watcher, and paddock
                - command: |
                    set -eu
                    cd /home/agent
                    export HOME=/home/agent
                    playwright-cli install --skills agents --global
                    # sbx mounts ~/.claude/skills read-only (its shared skills folder), so Claude
                    # Code's copy may not be writable; the agent instructions below cover the tool.
                    playwright-cli install --skills claude --global \
                      || echo "Paddock: playwright-cli's skill for Claude Code not installed (~/.claude/skills is read-only)" >&2
                  user: "1000"
                  env: [PATH]
                  description: Install playwright-cli's skill for Claude Code and for agents that read ~/.agents/skills
              startup:
                # sbx's proxy re-signs HTTPS with its own CA; Chromium trusts only its own store.
                - command:
                    - sh
                    - -c
                    - >-
                      ca=\#(proxyCA); db="$HOME/.pki/nssdb";
                      if [ -f "$ca" ] && command -v certutil >/dev/null; then
                      mkdir -p "$db";
                      [ -f "$db/cert9.db" ] || certutil -d "sql:$db" -N --empty-password;
                      certutil -d "sql:$db" -D -n sbx-proxy >/dev/null 2>&1;
                      certutil -d "sql:$db" -A -t "C,," -n sbx-proxy -i "$ca"; fi
                  user: "1000"
                  description: Trust sbx's proxy CA in Chromium's certificate store
                # The dashboard, on every start; 0.0.0.0 so sbx's published port reaches it.
                - command:
                    - sh
                    - -c
                    - "\#(startDashboardScript)"
                  user: "1000"
                  background: true
                  description: Start playwright-cli's dashboard on port \#(dashboardPort)
          - type: com.docker.sandbox/agent-context@1
            config:
              content: |
                ## Showing the operator things, asking them, and using a browser (Paddock)

                The operator works in Paddock: your terminal, and next to it tabs you can fill. Use them
                instead of pasting paths or URLs into the chat or asking questions in the terminal.

                ### Reach for it when
                | Situation | Run |
                |---|---|
                | You built or changed something they should see | `paddock open http://localhost:3000 --title "Checkout"` |
                | A document, plan, or report they should read | `paddock open plan.md --native` (on their screen, sharp text) |
                | Playwright's test report | `paddock open playwright-report/index.html --native` |
                | You need a decision, an approval, or values | `paddock ui question.oui --title "Deploy target"` |
                | You want them to point at something on a page | `paddock annotate tab-k3f9` |
                | You need to test or poke at a page yourself | `playwright-cli -s=checkout open http://localhost:3000` |

                ### The loop
                1. Show it: `paddock open ...` or `paddock ui ...` prints the tab's id, such as `tab-k3f9`.
                   Keep it; every other command needs it.
                2. Tell the operator in one line what to look at (new tabs never take their focus).
                3. Wait for them: `paddock wait tab-k3f9` prints what they did: opened or closed it, an
                   answer from a ui tab (one JSON line with the form's values), or a saved screenshot.
                   Run it again for the next thing.
                4. Act on it. `paddock feedback tab-k3f9` prints their screenshots and annotations with
                   comments and file paths; `paddock status tab-k3f9` the whole history.

                ### paddock, in detail
                - `open URL-or-FILE [--title T] [--note N]`: a live page (a URL, or a file opened as
                  `file:`, no server needed). `--native` opens a file on their screen instead, once they
                  click it: for documents to read or copy from.
                - `ui FILE` (or `ui -` with the document on stdin): an interactive tab from an OpenUI Lang
                  document: forms, choices, tables, charts, buttons. Read
                  \#(openUIReferencePath) before your first one. A small one:
                  ```
                  root = Card([header, form])
                  header = CardHeader("Deploy", "Choose how to roll out")
                  form = Form("deploy", buttons, [env])
                  env = FormControl("Environment", Select("env", [SelectItem("staging", "Staging"), SelectItem("prod", "Production")], "Select...", {required: true}))
                  buttons = Buttons([Button("Deploy", @ToAssistant("Deploy", {step: "deploy"}), "primary")])
                  ```
                  Its answer: `{"type":"continue_conversation","message":"Deploy","context":{"step":"deploy"},"form":"deploy","values":{"env":"staging"}}`.
                  If part of it cannot be drawn, `paddock wait` says what (with the component's
                  signature); fix the file and run `paddock goto tab-k3f9 question.oui`. The tab is
                  offline (no images or internet links). Never ask for passwords or keys.
                - `annotate ID`: the operator marks up a live page; it waits, then prints their comment
                  and the annotated screenshot's path. If it fails, run `paddock feedback ID`: they may
                  have saved their markup anyway.
                - `reload ID` (after you changed it), `goto ID URL-or-FILE`, `back ID`, `note ID TEXT`,
                  `close ID`. Any command with the id first prints what is new, as `Paddock:` lines.
                - Before telling the operator you cannot see their review, run `paddock feedback ID`. If
                  a comment is unclear (one word, a box over several things), ask what they mean.

                ### playwright-cli, your browser
                - `playwright-cli -s=checkout open URL` starts a new session and prints its name, such as
                  `checkout-7f3a`; use it in every command after: `snapshot`, `click e3`, `fill e5 "text"`,
                  `goto URL`, `screenshot`, `close`. The operator sees your sessions live (and may take
                  over); `Paddock:` lines in the output say what they did. `playwright-cli --help` has more.
                - `playwright-cli -s=checkout-7f3a show --annotate` asks them to mark up your own session's
                  page, like `paddock annotate`.

                ### Good to know
                - Pages on localhost work (the browser runs next to you); other sites may be blocked by
                  the network rules (a proxy error): ask the operator.
                - `npx playwright test` is headless; show its report afterwards. If the project pins its
                  own `@playwright/test`, run `npx playwright install chromium` in it; do not change its
                  Playwright version.
                - Port \#(dashboardPort) is taken. Other agents may share this sandbox: use only the
                  session names and tab ids you were given.
                - If Paddock gets in your way or lacks something you needed, tell the operator what you
                  tried and what would have helped. They are building it and want to know.

        """#
    }

    /// The OpenUI Lang reference the kit installs for agents (`tools/tasks/vendor/openui.sh`).
    public static let openUIReferencePath = "/usr/local/share/paddock/openui.md"

    public static var openUIReference: String {
        guard let url = Bundle.module.url(forResource: "openui-reference", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    /// The dashboard on the Mac: the loopback port sbx publishes for `dashboardPort`. Nil when sbx
    /// publishes none (no browser kit, or the sandbox is stopped), or only on another address.
    public static func dashboardURL(ports: [SbxPort]) -> URL? {
        guard let port = ports.first(where: { $0.sandboxPort == dashboardPort && $0.hostIP == Ports.hostIP }) else { return nil }
        return URL(string: "http://\(Ports.hostIP):\(port.hostPort)/")
    }

    /// Whether a project's sandbox gets this kit, so Paddock follows its browser.
    public static func isChosen(by project: Project, app: AppConfig) -> Bool {
        project.chosenKits(app).contains { app.kits[$0]?.source == .builtin(.browser) }
    }

    /// Starts the dashboard (the kit's startup step, and Paddock through `sbx exec` when a browser
    /// tab finds nothing on the port). The dashboard is a singleton: a second start finds the first
    /// and exits, so no check comes first. (A `pgrep -f 'playwright-cli show'` check matched its own
    /// `sh -c`, whose command line holds the same words, so the dashboard never started.)
    public static let startDashboardScript =
        "PWTEST_SOCKETS_DIR=\(socketsDirectory) setsid \(BrowserActivity.realCLI) show --port \(dashboardPort) --host 0.0.0.0 >>/tmp/playwright-dashboard.log 2>&1 </dev/null &"

    /// Where playwright-cli keeps its sockets, the same for every process in the sandbox. Without
    /// it the folder comes from USER and TMPDIR, which the kit's startup step and the agent's
    /// shell may see differently: then `show --annotate` (its client finds the dashboard by socket)
    /// failed with "Annotation client exited with code 1" (reproduced).
    public static let socketsDirectory = "/tmp/paddock-browser/sockets"

    /// `sbx exec` command that starts the dashboard in a running sandbox.
    public static func startDashboardCommand(sandbox: String) -> [String] { ["exec", sandbox, "sh", "-c", startDashboardScript] }

    /// What answered on the dashboard's published port.
    public enum DashboardAnswer: Sendable, Equatable {
        case dashboard
        /// Something else serves there (a report server, say).
        case otherServer
        /// Nothing: the dashboard is not running.
        case none
    }

    /// `answered`: whether an HTTP response came back at all; `finalURL`: where `/` led.
    public static func dashboardAnswer(answered: Bool, finalURL: URL?) -> DashboardAnswer {
        guard answered else { return .none }
        return isDashboard(finalURL: finalURL) ? .dashboard : .otherServer
    }

    /// Whether a response from the dashboard's published port came from the dashboard: its `/`
    /// redirects to `/index.html?ws=...`. Anything else means another server holds the port.
    public static func isDashboard(finalURL: URL?) -> Bool {
        guard let finalURL, finalURL.path == "/index.html",
              let query = URLComponents(url: finalURL, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        return query.contains { $0.name == "ws" && !($0.value ?? "").isEmpty }
    }

    /// Whether the project's sandbox was created with this kit, any version of it; nil when
    /// Paddock did not record its kits (`Project.sandboxKits`).
    public static func isInSandbox(of project: Project, paths: PaddockPaths) -> Bool? {
        let dir = directory(in: paths)
        return project.sandboxKits.map { kits in kits.contains { $0 == dir || $0.hasPrefix(dir + "#") } }
    }

    /// Writes the kit if it is missing or differs. Returns the kit directory.
    @discardableResult
    public static func install(in paths: PaddockPaths) throws -> String {
        try KitFile.write(spec, to: directory(in: paths))
    }
}
