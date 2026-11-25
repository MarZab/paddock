import Foundation

/// How Paddock follows the agent's browser (backlog doc Browser). The agent uses playwright-cli as it
/// always would; the browser kit puts a wrapper first under its name, which notes the session of
/// each command (start and end), then runs playwright-cli unchanged. A
/// watcher in the sandbox (`paddock-browser-watch`, which Paddock follows through `sbx exec`)
/// turns that into JSON lines: each session's tabs, and when the agent is busy in a session. Paddock
/// shows a browser tab per page, and the operator looks at whichever they like: each tab's web view
/// selects its own page in its own view of the dashboard (`selectScript`); nothing switches the
/// operator's view for them.
public enum BrowserActivity {
    /// The real playwright-cli, linked here by the kit; the wrapper and the watcher run this one.
    public static let realCLI = "/usr/local/lib/paddock-browser/playwright-cli"
    /// Paddock shows at most this many browser tabs per project.
    public static let maxPages = 16

    /// The watcher the kit installs in /usr/local/bin.
    public static let watchName = "paddock-browser-watch"

    /// `sbx exec` command Paddock follows while the sandbox runs; it replaces older watchers there
    /// (`SandboxWatchers`).
    public static func watchCommand(sandbox: String) -> [String] { SandboxWatchers.arguments(sandbox: sandbox, command: watchName) }

    /// A session name the wrapper records and Paddock accepts.
    public static func isSessionName(_ name: String) -> Bool {
        (1...64).contains(name.count) && name.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "_" || $0 == "-")
        }
    }

    /// JavaScript for one browser tab's web view: selects page `index` of `session` in the
    /// dashboard's session list, in this view only, once the list shows it (up to 10 s). It depends
    /// on the dashboard's markup (a section labelled "Session NAME" with its tabs as options), which
    /// is pinned with `BrowserKit.version`. Nil for a name the watcher would not report.
    public static func selectScript(session: String, index: Int) -> String? {
        guard isSessionName(session), (0..<64).contains(index),
              let data = try? JSONEncoder().encode(session) else { return nil }
        let sessionJSON = String(decoding: data, as: UTF8.self)
        return """
        (function (session, index) {
          var deadline = Date.now() + 10000;
          function select() {
            var region = document.querySelector('[aria-label="Session ' + session + '"]');
            var options = region ? region.querySelectorAll('[role="option"]') : [];
            if (options.length > index) { options[index].click(); return; }
            if (Date.now() < deadline) setTimeout(select, 200);
          }
          select();
        })(\(sessionJSON), \(index));
        """
    }

    /// JavaScript for a show tab's view: keeps page `index` of the `paddock-tabs` session selected
    /// in this view (checking twice a second, so a reconnect or a late session list never leaves
    /// "Select a session"), and hides the dashboard's session list only while that page is
    /// selected: when it cannot be found for 5 s, the list comes back for the operator to choose.
    /// Depends on the dashboard's markup like `selectScript`.
    public static func showScript(index: Int) -> String? {
        guard (0..<64).contains(index), let data = try? JSONEncoder().encode(BrowserShow.session) else { return nil }
        let sessionJSON = String(decoding: data, as: UTF8.self)
        return """
            (function (session, index) {
              var hide = document.createElement('style');
              hide.textContent = '.split-view-sidebar, .split-view-resizer { display: none !important; }';
              var missingSince = Date.now();
              function select() {
                var region = document.querySelector('[aria-label="Session ' + session + '"]');
                var options = region ? region.querySelectorAll('[role="option"]') : [];
                if (options.length <= index) return false;
                if (options[index].getAttribute('aria-selected') !== 'true') options[index].click();
                return true;
              }
              setInterval(function () {
                if (select()) {
                  missingSince = Date.now();
                  if (!hide.isConnected) document.head.appendChild(hide);
                } else if (Date.now() - missingSince > 5000 && hide.isConnected) {
                  hide.remove();
                }
              }, 500);
            })(\(sessionJSON), \(index));
            """
    }

    /// The wrapper, installed under playwright-cli's name.
    public static let wrapper = #"""
        #!/bin/sh
        # Written by Paddock's browser kit: playwright-cli with session handles. `open` always starts a new
        # session under a name of its own (the agent's suggestion plus a unique suffix) and says so; every
        # other command needs -s with a session opened that way. So two agents never share a browser by
        # accident. It notes each command's session (for Paddock's activity), then runs playwright-cli.
        real=/usr/local/lib/paddock-browser/playwright-cli
        state=/tmp/paddock-browser
        session=""
        command=""
        next=""
        for arg in "$@"; do
          if [ -n "$next" ]; then session="$arg"; next=""; continue; fi
          case "$arg" in
            -s|--session) next=1 ;;
            -s=*) session="${arg#-s=}" ;;
            --session=*) session="${arg#--session=}" ;;
            -*) ;;
            *) [ -z "$command" ] && command="$arg" ;;
          esac
        done
        case "$command" in *[!a-z-]*) command="" ;; esac
        refuse() { echo "Paddock: $*" >&2; exit 2; }
        case "$command" in
          # Help, versions, and commands that act on no session's pages.
          ""|list|install|install-browser|tray) PWTEST_SOCKETS_DIR=/tmp/paddock-browser/sockets exec "$real" "$@" ;;
          # The dashboard itself; `show --annotate` asks the operator to annotate your page (below).
          show) case " $* " in *" --annotate "*) ;; *) PWTEST_SOCKETS_DIR=/tmp/paddock-browser/sockets exec "$real" "$@" ;; esac ;;
          close-all|kill-all) refuse "$command is not available here (other agents share this browser); close your session with: playwright-cli -s=NAME close" ;;
          open)
            base="$(printf '%s' "${session:-s}" | tr -c 'A-Za-z0-9._-' '-' | cut -c1-40)"
            suffix="$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
            session="$base-$suffix"
            # The same arguments without the agent's -s (the loop's list is read before set -- empties it).
            skip=""
            rebuilt=""
            for arg in "$@"; do
              if [ -z "$rebuilt" ]; then set --; rebuilt=1; fi
              if [ -n "$skip" ]; then skip=""; continue; fi
              case "$arg" in
                -s|--session) skip=1; continue ;;
                -s=*|--session=*) continue ;;
              esac
              set -- "$@" "$arg"
            done
            set -- "-s=$session" "$@"
            mkdir -p "$state/sessions" && : > "$state/sessions/$session"
            echo "Paddock: your session is $session. Use it with every command: playwright-cli -s=$session snapshot" >&2
            ;;
        esac
        case "$command" in
          open) ;;
          *)
            [ -n "$session" ] || refuse "add your session: playwright-cli -s=NAME $command (playwright-cli open prints NAME)"
            case "$session" in *[!A-Za-z0-9._-]*) refuse "$session is not a session name" ;; esac
            [ -f "$state/sessions/$session" ] || refuse "no session $session; start one with: playwright-cli -s=$session open URL (it prints the name to use)"
            ;;
        esac
        unset PLAYWRIGHT_CLI_SESSION
        # The same sockets folder as the dashboard, whatever USER and TMPDIR say.
        export PWTEST_SOCKETS_DIR=/tmp/paddock-browser/sockets
        # What the operator did in this session since (a tab they closed in Paddock).
        if [ -s "$state/notes/$session" ]; then
          cat "$state/notes/$session" >&2
          rm -f "$state/notes/$session"
        fi
        echo "start $session $command" >> "$state/events" 2>/dev/null
        "$real" "$@"
        status=$?
        echo "end $session $status" >> "$state/events" 2>/dev/null
        if [ "$command" = close ] && [ "$status" = 0 ]; then rm -f "$state/sessions/$session"; fi
        exit $status
        """#

    /// The watcher (Node, so its JSON is always valid). The base kit installs it (PAD-147); without
    /// the browser kit it reports show tabs and no sessions.
    public static let watcher = NodeScript.wrap(#"""
        // Written by Paddock's base kit: reports the tabs the agent shows with paddock, and where the
        // browser kit is, its playwright-cli sessions, their tabs, and when it runs a command in one,
        // as JSON lines for Paddock (sbx exec N paddock-browser-watch; the name is from before PAD-147).
        'use strict';
        const fs = require('fs');
        const path = require('path');
        const { execFile } = require('child_process');

        const REAL = '/usr/local/lib/paddock-browser/playwright-cli';
        const STATE = '/tmp/paddock-browser';
        const EVENTS = path.join(STATE, 'events');
        const NOTES = path.join(STATE, 'notes');
        const SHOWS = '/tmp/paddock-tabs/shows';
        const GONE = '/tmp/paddock-tabs/gone';
        const SHOW_SESSION = 'paddock-tabs';

        // When each session last ran a command: a page gone without one was closed by the operator.
        const lastCommand = new Map();
        let previous = new Map();
        // Sessions whose agent waits for the operator to annotate their page (playwright-cli show --annotate).
        const annotating = new Set();
        function note(session, text) {
          try {
            fs.mkdirSync(NOTES, { recursive: true });
            fs.appendFileSync(path.join(NOTES, session), `Paddock: ${text} (${new Date().toISOString()}).\n`);
          } catch { /* best effort */ }
        }
        function closedByOperator(sessions) {
          const now = Date.now();
          const current = new Map(sessions.map((s) => [s.name, s.tabs.map((t) => t.url)]));
          for (const [name, urls] of previous) {
            if (now - (lastCommand.get(name) || 0) < 3000) continue;
            const left = current.get(name) || [];
            for (const url of urls.filter((u) => !left.includes(u))) {
              if (name === SHOW_SESSION) {
                // A shown page closed in the dashboard: closed, as paddock --status ID reports it.
                for (const f of listShows()) {
                  if (f.url !== url) continue;
                  f.state = 'closed';
                  f.history = (f.history || []).concat(`${new Date().toISOString()} the operator closed it in the dashboard`);
                  try {
                    fs.mkdirSync(GONE, { recursive: true });
                    fs.writeFileSync(path.join(GONE, f.id + '.json'), JSON.stringify(f));
                  } catch { /* best effort */ }
                  fs.rmSync(path.join(SHOWS, f.id + '.json'), { force: true });
                }
              } else if (!mcpNames.has(name)) {
                // An MCP agent reads no playwright-cli output, so its browser gets no notes.
                note(name, `the operator closed a tab (${url}) in the dashboard`);
              }
            }
          }
          previous = current;
        }
        function listShows() {
          try {
            return fs.readdirSync(SHOWS).filter((f) => /^tab-[0-9a-f]{4}\.json$/.test(f))
              .map((f) => JSON.parse(fs.readFileSync(path.join(SHOWS, f), 'utf8')));
          } catch { return []; }
        }
        let lastShows = '';
        function readShows() {
          const shows = listShows().sort((a, b) => a.created - b.created)
            .map((s) => ({ id: s.id, mode: s.mode, title: s.title, note: s.note, url: s.url, path: s.path, state: s.state, revision: s.revision || 0, annotating: Boolean(s.annotating) }));
          const snapshot = JSON.stringify({ type: 'shows', shows });
          if (snapshot !== lastShows) { lastShows = snapshot; process.stdout.write(snapshot + '\n'); }
        }
        const NAME = /^[A-Za-z0-9._-]{1,64}$/;

        function out(object) { process.stdout.write(JSON.stringify(object) + '\n'); }
        function run(args, cwd) {
          return new Promise((resolve) => {
            // No browser kit in this sandbox (PAD-147): no sessions, and nothing to start.
            if (!fs.existsSync(REAL)) return resolve(null);
            execFile(REAL, args, { cwd, timeout: 15000, encoding: 'utf8', env: { ...process.env, PWTEST_SOCKETS_DIR: '/tmp/paddock-browser/sockets' } },
              (error, stdout) => resolve(error ? null : stdout));
          });
        }
        // A session belongs to a workspace (a folder with .playwright) or to the global one; its
        // commands work only from there. `list --all` names a workspace by its folder.
        function folderOf(workspace) {
          return typeof workspace === 'string' && workspace.startsWith('/') && fs.existsSync(workspace) ? workspace : '/';
        }

        async function sessionsList() {
          const list = await run(['list', '--all', '--json'], '/');
          try {
            const parsed = JSON.parse(list || '{}');
            return { browsers: Array.isArray(parsed.browsers) ? parsed.browsers : [], servers: Array.isArray(parsed.servers) ? parsed.servers : [] };
          } catch { return { browsers: [], servers: [] }; }
        }

        // Playwright MCP's browsers (PAD-141) are no playwright-cli sessions: `list --all` names them
        // with every other bound browser under `servers` (title: the MCP client's name). Their pages
        // come from a connection to each, through the same playwright-core as the real CLI; it stays
        // open (closing it would only disconnect) and changes in it read the tabs again.
        // Every name given to an MCP browser while this watcher runs (no notes for them, even once gone).
        const mcpNames = new Set();
        let playwright;
        function playwrightCore() {
          if (playwright === undefined) {
            try {
              playwright = require(require.resolve('playwright-core', { paths: [path.dirname(fs.realpathSync(REAL))] }));
            } catch { playwright = null; }
          }
          return playwright;
        }
        let soon = null;
        function readTabsSoon() {
          if (soon) return;
          soon = setTimeout(() => { soon = null; readTabs(); }, 300);
        }
        function watchContext(context) {
          const watchPage = (page) => {
            page.on('framenavigated', (frame) => { if (frame === page.mainFrame()) readTabsSoon(); });
            page.on('close', readTabsSoon);
          };
          context.pages().forEach(watchPage);
          context.on('page', (page) => { watchPage(page); readTabsSoon(); });
        }
        const connections = new Map();
        function connectTo(server) {
          const guid = server.browser.guid;
          if (!connections.has(guid)) {
            const pw = playwrightCore();
            const type = pw && ['chromium', 'firefox', 'webkit'].includes(server.browser.browserName) ? pw[server.browser.browserName] : null;
            const connecting = type
              ? type.connect(server.endpoint, { timeout: 5000 }).then((browser) => {
                browser.on('disconnected', () => { connections.delete(guid); readTabsSoon(); });
                const known = new Set();
                const watchAll = () => {
                  for (const context of browser.contexts()) if (!known.has(context)) { known.add(context); watchContext(context); }
                };
                watchAll();
                return { browser, watchAll };
              }, () => { connections.delete(guid); return null; })
              : Promise.resolve(null);
            connections.set(guid, connecting);
          }
          return connections.get(guid);
        }
        function within(promise, ms, fallback) {
          return Promise.race([promise.catch(() => fallback), new Promise((resolve) => setTimeout(() => resolve(fallback), ms))]);
        }
        function mcpName(title, taken) {
          const base = ('mcp-' + String(title || 'browser').toLowerCase().replace(/[^a-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '')).slice(0, 56);
          let name = base;
          for (let n = 2; taken.has(name); n++) name = `${base}-${n}`;
          return name;
        }
        async function mcpSessions(servers, taken) {
          const sessions = [];
          const own = servers.filter((s) => s && typeof s === 'object' && s.browser && typeof s.browser.guid === 'string'
            && typeof s.endpoint === 'string' && typeof s.title === 'string'
            && !s.title.startsWith('--playwright-internal') && !taken.has(s.title))
            .sort((a, b) => (a.browser.guid < b.browser.guid ? -1 : 1)).slice(0, 8);
          for (const server of own) {
            const connected = await within(connectTo(server), 6000, null);
            if (!connected) continue;
            connected.watchAll();
            const tabs = [];
            for (const context of connected.browser.contexts()) {
              for (const page of context.pages()) tabs.push({ title: await within(page.title(), 2000, ''), url: page.url(), current: false });
            }
            const name = mcpName(server.title, taken);
            taken.add(name);
            mcpNames.add(name);
            sessions.push({ name, tabs });
          }
          return sessions;
        }
        async function tabsOf(name, folder) {
          const text = await run([`-s=${name}`, 'tab-list', '--json'], folder);
          let result = '';
          try { result = JSON.parse(text || '{}').result || ''; } catch { result = ''; }
          const tabs = [];
          for (const line of result.split('\n')) {
            const m = /^- (\d+): (\(current\) )?\[(.*)\]\((.*)\)$/.exec(line);
            if (m) tabs.push({ title: m[3], url: m[4], current: Boolean(m[2]) });
          }
          return tabs;
        }

        let last = '';
        let reading = false;
        let again = false;
        async function readTabs() {
          if (reading) { again = true; return; }
          reading = true;
          const { browsers, servers } = await sessionsList();
          const sessions = [];
          const seen = new Set();
          for (const b of browsers) {
            // Two workspaces may each have a session of the same name; Paddock shows the first.
            if (b.status !== 'open' || !NAME.test(b.name || '') || seen.has(b.name)) continue;
            seen.add(b.name);
            const tabs = await tabsOf(b.name, folderOf(b.workspace));
            sessions.push({ name: b.name, tabs });
          }
          // playwright-cli's own sessions are bound browsers too, under their names: never twice.
          sessions.push(...await mcpSessions(servers, seen));
          closedByOperator(sessions);
          const snapshot = JSON.stringify({ type: 'tabs', sessions });
          if (snapshot !== last) { last = snapshot; process.stdout.write(snapshot + '\n'); }
          reading = false;
          if (again) { again = false; readTabs(); }
        }

        // For Paddock: the operator saved a screenshot or recording of a session's page; it is at PATH in
        // this sandbox, and the agent hears of it the next time it uses the session.
        if (process.argv[2] === '--captured') {
          const [session, file, what] = process.argv.slice(3);
          if (!NAME.test(session || '') || !/^\/tmp\/paddock-browser\/captures\/[A-Za-z0-9._-]+$/.test(file || '')) process.exit(2);
          let described = file;
          try { described = require('child_process').execFileSync('/usr/local/bin/paddock', ['--extract', file], { encoding: 'utf8' }).trim() || file; } catch { /* the path will do */ }
          note(session, described === file
            ? `the operator saved a ${what === 'recording' ? 'recording' : 'screenshot'} of your page: ${file}`
            : `the operator saved ${described}, from ${file}`);
          process.exit(0);
        }

        fs.mkdirSync(STATE, { recursive: true });
        if (!fs.existsSync(EVENTS)) fs.writeFileSync(EVENTS, '');
        let offset = fs.statSync(EVENTS).size;
        let rest = '';
        readTabs();
        readShows();
        setInterval(readTabs, 5000);
        setInterval(() => {
          readShows();
          let size;
          try { size = fs.statSync(EVENTS).size; } catch { return; }
          if (size < offset) offset = 0;
          if (size === offset) return;
          const fd = fs.openSync(EVENTS, 'r');
          const buffer = Buffer.alloc(size - offset);
          fs.readSync(fd, buffer, 0, buffer.length, offset);
          fs.closeSync(fd);
          offset = size;
          const lines = (rest + buffer.toString('utf8')).split('\n');
          rest = lines.pop();
          for (const line of lines) {
            const [kind, session, detail] = line.split(' ');
            if (!NAME.test(session || '')) continue;
            lastCommand.set(session, Date.now());
            if (kind === 'start' && detail === 'show') { annotating.add(session); out({ type: 'annotate', session, active: true }); }
            if (kind === 'end' && annotating.delete(session)) out({ type: 'annotate', session, active: false });
            if (kind === 'start') out({ type: 'busy', session, command: /^[a-z-]{1,32}$/.test(detail || '') ? detail : '' });
            if (kind === 'end') { out({ type: 'idle', session }); readTabs(); }
          }
        }, 250);
        """#)
}

/// The agent's browser as the watcher reports it: each session's pages, and the sessions it is
/// running a command in. **Untrusted:** anything in the sandbox can write the lines. Lines that
/// are not valid, or name a session the wrapper would not record, are ignored; at most
/// `BrowserActivity.maxPages` pages; titles and URLs are cleaned and shortened (they are shown,
/// never loaded).
public struct BrowserSessions: Sendable, Equatable {
    public struct Page: Sendable, Equatable, Identifiable {
        public let session: String
        /// Its place in the session's tabs; a tab closed before it shifts it.
        public let index: Int
        public let title: String
        public let url: String
        /// The session's current tab, where its commands act.
        public let current: Bool

        public var id: String { "\(session)#\(index)" }
    }

    /// Something the agent shows the operator with `paddock` (`BrowserShow`).
    public struct Show: Sendable, Equatable, Identifiable {
        public enum Mode: Sendable, Equatable {
            /// A page of the `paddock` session, rendered in the sandbox.
            case page(url: String)
            /// A file rendered on the operator's Mac (`NativeShowPolicy`).
            case native(path: String)
            /// An interactive tab: A2UI messages, drawn by Paddock (`A2UIWebPolicy`); their log in
            /// the sandbox.
            case ui(path: String)
        }

        public let id: String
        public let mode: Mode
        public let title: String
        public let note: String
        /// Whether the operator opened it (the sandbox keeps that).
        public let opened: Bool
        /// Raised when the agent reloads a native tab or points it at another file: Paddock loads it again.
        public let revision: Int
        /// The agent waits for the operator to annotate it (`paddock annotate ID`).
        public let annotating: Bool

        public var isNative: Bool {
            if case .native = mode { true } else { false }
        }

        public var isInteractive: Bool {
            if case .ui = mode { true } else { false }
        }

        /// The file name a native show starts from, for the content type.
        public var fileName: String {
            switch mode {
            case .page(let url): url
            case .native(let path), .ui(let path): (path as NSString).lastPathComponent
            }
        }
    }

    public enum Change: Sendable, Equatable {
        case none
        /// Pages that are new or show something else (by id), and pages that are gone.
        case pages(changed: Set<String>, gone: Set<String>)
        case busy(session: String)
        case idle(session: String)
        /// Shows that are new, and shows that are gone.
        case shows(added: Set<String>, gone: Set<String>)
        /// A session's agent asks the operator to annotate its page, or stopped asking.
        case annotate(session: String, active: Bool)
    }

    public private(set) var pages: [Page] = []
    public private(set) var busy: Set<String> = []
    public private(set) var shows: [Show] = []
    /// Sessions whose agent waits for the operator to annotate their page (`show --annotate`).
    public private(set) var annotating: Set<String> = []

    /// The page a page show is, in the `paddock` session: by its URL, or, after the page
    /// moved on (the operator went back, or navigated while in control), by its place among the
    /// page shows when they and the session's tabs still pair up one to one.
    public func page(of show: Show) -> Page? {
        guard case .page(let url) = show.mode else { return nil }
        let sessionPages = pages.filter { $0.session == BrowserShow.session }
        if let page = sessionPages.first(where: { $0.url == url }) { return page }
        let pageShows = shows.filter { if case .page = $0.mode { true } else { false } }
        guard pageShows.count == sessionPages.count, let place = pageShows.firstIndex(where: { $0.id == show.id }) else { return nil }
        return sessionPages.first { $0.index == place }
    }

    public init() {}

    public static func sessionAndIndex(of id: String) -> (session: String, index: Int)? {
        guard let hash = id.lastIndex(of: "#"), let index = Int(id[id.index(after: hash)...]) else { return nil }
        let session = String(id[..<hash])
        return BrowserActivity.isSessionName(session) ? (session, index) : nil
    }

    public mutating func apply(line: String) -> Change {
        guard line.utf8.count <= 65536, let data = line.data(using: .utf8),
              let event = try? JSONDecoder().decode(Event.self, from: data) else { return .none }
        switch event.type {
        case "tabs":
            var next: [Page] = []
            for session in event.sessions ?? [] where BrowserActivity.isSessionName(session.name) {
                for (index, tab) in (session.tabs ?? []).prefix(16).enumerated() where next.count < BrowserActivity.maxPages {
                    let url = Self.cleaned(tab.url ?? "", max: 300) ?? ""
                    next.append(Page(session: session.name, index: index, title: Self.cleaned(tab.title ?? "", max: 60) ?? url,
                                     url: url, current: tab.current ?? false))
                }
            }
            let before = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let changed = Set(next.filter { page in before[page.id].map { $0.url != page.url || $0.title != page.title } ?? true }.map(\.id))
            let gone = Set(before.keys).subtracting(next.map(\.id))
            pages = next
            busy = busy.filter { name in next.contains { $0.session == name } }
            annotating = annotating.filter { name in next.contains { $0.session == name } }
            return changed.isEmpty && gone.isEmpty ? .none : .pages(changed: changed, gone: gone)
        case "busy":
            guard let session = event.session, BrowserActivity.isSessionName(session) else { return .none }
            busy.insert(session)
            return .busy(session: session)
        case "idle":
            guard let session = event.session, BrowserActivity.isSessionName(session) else { return .none }
            busy.remove(session)
            return .idle(session: session)
        case "annotate":
            guard let session = event.session, BrowserActivity.isSessionName(session) else { return .none }
            let active = event.active ?? false
            if active { annotating.insert(session) } else { annotating.remove(session) }
            return .annotate(session: session, active: active)
        case "shows":
            var next: [Show] = []
            for raw in event.shows ?? [] where BrowserShow.isShowID(raw.id) && next.count < BrowserShow.maxShows {
                let mode: Show.Mode
                switch raw.mode {
                case "page":
                    guard let url = raw.url, url.utf8.count <= 4096 else { continue }
                    mode = .page(url: url)
                case "native":
                    guard let path = raw.path, path.hasPrefix("/"), path.utf8.count <= 4096 else { continue }
                    mode = .native(path: path)
                case "ui":
                    guard let path = raw.path, path.hasPrefix("/"), path.utf8.count <= 4096 else { continue }
                    mode = .ui(path: path)
                default:
                    continue
                }
                next.append(Show(id: raw.id, mode: mode, title: Self.cleaned(raw.title ?? "", max: 60) ?? raw.id,
                                 note: Self.cleaned(raw.note ?? "", max: 200) ?? "", opened: raw.state == "opened",
                                 revision: max(0, raw.revision ?? 0), annotating: raw.annotating ?? false))
            }
            let before = Set(shows.map(\.id))
            let after = Set(next.map(\.id))
            let changed = next != shows
            shows = next
            return changed ? .shows(added: after.subtracting(before), gone: before.subtracting(after)) : .none
        default:
            return .none
        }
    }

    /// Without control, format (bidi overrides, zero-width), or line characters, trimmed and cut.
    static func cleaned(_ raw: String, max: Int) -> String? {
        let kept = raw.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned: false
            default: true
            }
        }
        let text = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return text.count > max ? String(text.prefix(max - 1)) + "…" : text
    }

    private struct Event: Decodable {
        struct Session: Decodable {
            struct Tab: Decodable {
                let title: String?
                let url: String?
                let current: Bool?
            }

            let name: String
            let tabs: [Tab]?
        }

        struct RawShow: Decodable {
            let id: String
            let mode: String
            let title: String?
            let note: String?
            let url: String?
            let path: String?
            let state: String?
            let revision: Int?
            let annotating: Bool?
        }

        let type: String
        let session: String?
        let sessions: [Session]?
        let shows: [RawShow]?
        let active: Bool?
    }
}
