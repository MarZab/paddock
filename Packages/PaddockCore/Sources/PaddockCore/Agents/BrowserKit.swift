import Foundation

/// Paddock's browser kit, on top of sbx's Playwright kit (`docker.io/sbx/playwright-kit`, which
/// brings Chromium's system libraries and `/opt/ms-playwright`): Microsoft's `playwright-cli`, a
/// browser CLI made for coding agents, with its skill for Claude Code and for agents that read
/// `~/.agents/skills` (OpenCode). Any agent with a shell can drive it, so it is not tied to one.
///
/// Every page the agent opens gets a browser tab in Paddock, with its activity (`BrowserActivity`:
/// a wrapper under playwright-cli's name, and the watcher Paddock follows, which the base kit
/// installs; `BaseKit`). `paddock`, the tab helper, is the base kit's too; Playwright MCP is its own
/// kit on this one (`BrowserMCPKit`; PAD-147). Those tabs show
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
    /// `@playwright/mcp`, released with playwright-cli: 0.0.83 is built on the same Playwright
    /// (1.64.0-alpha-1790635538000) as playwright-cli 0.1.22, so it uses the Chromium build the kit
    /// already installs. Raise the two together.
    public static let mcpVersion = "0.0.83"
    public static let mcpPackage = "@playwright/mcp"
    /// The MCP server's name in Claude Code (its tools are `mcp__playwright__*`).
    public static let mcpServerName = "playwright"
    /// One Playwright MCP server per sandbox, shared by every agent (PAD-142): a kept profile (logins,
    /// extensions) allows one browser at a time, so agents cannot each start their own. HTTP on
    /// `localhost` inside the sandbox only: no `ports` entry, so sbx publishes nothing on the Mac,
    /// and Playwright MCP's Host check accepts only `localhost:PORT`.
    public static let mcpPort = 38324
    public static var mcpURL: String { "http://localhost:\(mcpPort)/mcp" }
    /// The real playwright-mcp, for the launcher (the npm bin link may move).
    public static let realMCP = "/usr/local/lib/paddock-browser/playwright-mcp"
    /// The launcher (`paddock-browser-mcp start|restart|stop|status`).
    public static let mcpLauncherPath = "/usr/local/bin/paddock-browser-mcp"
    /// The kept profile, in the sandbox's home: it lasts across sandbox restarts, not a recreate.
    public static let mcpProfile = "/home/agent/.cache/paddock-browser/profile"
    /// Unpacked Chromium extensions, one folder each with its `manifest.json`.
    public static let mcpExtensions = "/home/agent/.config/paddock-browser/extensions"
    /// Registers the shared server with Claude Code in the sandbox (user scope, in `~/.claude.json`),
    /// on every start, so a changed registration replaces the old one. Without Claude Code it does
    /// nothing.
    public static var registerMCPScript: String {
        "export HOME=/home/agent PATH=\"/home/agent/.local/bin:$PATH\"; command -v claude >/dev/null || exit 0; "
            + "claude mcp remove --scope user \(mcpServerName) >/dev/null 2>&1; "
            + "claude mcp add --scope user --transport http \(mcpServerName) \(mcpURL)"
    }

    /// Starts and stops the shared server (Node, like the watcher, so its config is valid JSON).
    /// Its environment is its own: no `PLAYWRIGHT_MCP_*` from whoever runs it (no unrestricted file
    /// access), Playwright's full Chromium (`chromium`: Chrome Headless Shell loads no extensions;
    /// checked), and the same sockets folder and output folder as playwright-cli. The server leads
    /// its own process group, so `stop` ends the browser with it (killing only the server left its
    /// Chrome running, holding the profile; checked).
    public static var mcpLauncher: String {
        NodeScript.wrap(#"""
            // Written by Paddock's browser kit: the sandbox's one Playwright MCP server (PAD-142).
            'use strict';
            const fs = require('fs');
            const path = require('path');
            const { spawn } = require('child_process');

            const HOME = '/home/agent';
            const REAL = '\#(realMCP)';
            const PROFILE = '\#(mcpProfile)';
            const EXTENSIONS = '\#(mcpExtensions)';
            const STATE = '/tmp/paddock-browser';
            const CONFIG = path.join(STATE, 'mcp-config.json');
            const PID = path.join(STATE, 'mcp.pid');
            const LOG = path.join(STATE, 'mcp.log');
            const PORT = \#(mcpPort);
            const NAME = /^[A-Za-z0-9._-]{1,64}$/;

            function extensions() {
              try {
                return fs.readdirSync(EXTENSIONS).filter((n) => NAME.test(n) && fs.existsSync(path.join(EXTENSIONS, n, 'manifest.json')))
                  .sort().map((n) => path.join(EXTENSIONS, n));
              } catch { return []; }
            }
            function running() {
              try {
                const pid = Number(fs.readFileSync(PID, 'utf8'));
                if (!Number.isInteger(pid) || pid < 2) return 0;
                process.kill(pid, 0);
                return pid;
              } catch { return 0; }
            }
            function config(found) {
              const args = found.length ? [`--disable-extensions-except=${found.join(',')}`, `--load-extension=${found.join(',')}`] : [];
              return {
                browser: { browserName: 'chromium', userDataDir: PROFILE, launchOptions: { headless: true, args } },
                server: { host: 'localhost', port: PORT },
                sharedBrowserContext: true,
                outputDir: '/tmp/playwright-cli',
              };
            }
            function environment() {
              const env = {};
              for (const [key, value] of Object.entries(process.env)) if (!key.startsWith('PLAYWRIGHT_MCP_')) env[key] = value;
              return Object.assign(env, {
                HOME,
                PLAYWRIGHT_MCP_BROWSER: 'chromium',
                PLAYWRIGHT_BROWSERS_PATH: process.env.PLAYWRIGHT_BROWSERS_PATH || '/opt/ms-playwright',
                PWTEST_SOCKETS_DIR: '\#(socketsDirectory)',
              });
            }
            function names(found) { return found.length ? found.map((e) => path.basename(e)).join(', ') : 'none'; }
            async function stop() {
              const pid = running();
              if (pid) {
                try { process.kill(-pid, 'SIGTERM'); } catch { /* gone */ }
                for (let i = 0; i < 50 && running(); i++) await new Promise((r) => setTimeout(r, 100));
                try { process.kill(-pid, 'SIGKILL'); } catch { /* gone */ }
              }
              fs.rmSync(PID, { force: true });
            }
            function start() {
              if (running()) { console.log(`Playwright MCP runs on http://localhost:${PORT}/mcp`); return; }
              const found = extensions();
              fs.mkdirSync(STATE, { recursive: true });
              fs.mkdirSync(PROFILE, { recursive: true });
              fs.mkdirSync(EXTENSIONS, { recursive: true });
              fs.writeFileSync(CONFIG, JSON.stringify(config(found), null, 2) + '\n');
              const out = fs.openSync(LOG, 'a');
              const child = spawn(REAL, ['--config', CONFIG], { cwd: HOME, env: environment(), detached: true, stdio: ['ignore', out, out] });
              fs.writeFileSync(PID, String(child.pid));
              child.unref();
              console.log(`Playwright MCP started on http://localhost:${PORT}/mcp; extensions: ${names(found)}`);
            }

            const command = process.argv[2] || 'status';
            (async () => {
              if (command === 'start') start();
              else if (command === 'restart') { await stop(); start(); }
              else if (command === 'stop') { await stop(); console.log('Playwright MCP stopped'); }
              else if (command === 'status') {
                console.log(running() ? `Playwright MCP runs on http://localhost:${PORT}/mcp` : 'Playwright MCP is not running (paddock-browser-mcp start)');
                console.log(`Profile: ${PROFILE}`);
                console.log(`Extensions in ${EXTENSIONS} (unpacked, one folder each; restart after a change): ${names(extensions())}`);
              } else {
                console.error('usage: paddock-browser-mcp start|restart|stop|status');
                process.exit(2);
              }
            })();
            """#)
    }
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
        return #"""
        # syntax=docker/sandbox-kit:3
        # Written by Paddock. Changes are overwritten when Paddock creates a sandbox.
        schemaVersion: "3"
        kind: mixin
        version: "\#(KitFile.version)"
        displayName: Browser (Paddock)
        description: "Read this before you open a page for the operator or test one: playwright-cli is your browser, and paddock open shows its pages in tabs next to your terminal."
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
                  user: "0"
                  # A hook sees only the environment it names: npm's global bin is on the image's PATH.
                  env: [PATH, HOME, HTTP_PROXY, HTTPS_PROXY, NO_PROXY]
                  description: Install playwright-cli \#(version) (npm \#(package)), its Chromium build, certutil, and Paddock's wrapper
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
                ## Your browser, and live pages for the operator (Paddock)

                Paddock's base kit has `paddock` (tabs, `wait`, `feedback`); this kit adds a browser.

                - `playwright-cli -s=checkout open URL` starts a new session and prints its name, such as
                  `checkout-7f3a`; use it in every command after: `snapshot`, `click e3`, `fill e5 "text"`,
                  `goto URL`, `screenshot`, `close`. The operator sees your sessions live in the
                  Playwright tab (and may take over); `Paddock:` lines in the output say what they did.
                  `playwright-cli --help` has more.
                - `paddock open URL-or-FILE [--title T] [--note N]`: a live page for the operator in a
                  tab of its own (a URL, or a file opened as `file:`, no server needed). `reload ID`
                  after you changed it, `goto ID URL-or-FILE`, `back ID`.
                - `paddock annotate ID`: the operator marks up a live page; it waits, then prints their
                  comment and the annotated screenshot's path. If it fails, run `paddock feedback ID`:
                  they may have saved their markup anyway. `playwright-cli -s=checkout-7f3a show --annotate`
                  asks the same for your own session's page.

                ### Good to know
                - Pages on localhost work (the browser runs next to you); other sites may be blocked by
                  the network rules (a proxy error): ask the operator.
                - `npx playwright test` is headless; show its report afterwards with
                  `paddock open playwright-report/index.html --native`. If the project pins its own
                  `@playwright/test`, run `npx playwright install chromium` in it; do not change its
                  Playwright version.
                - Port \#(dashboardPort) is taken. Other agents may share this sandbox: use only the
                  session names you were given.

        """#
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
