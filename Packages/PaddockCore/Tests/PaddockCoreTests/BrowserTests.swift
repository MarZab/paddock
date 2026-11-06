import Foundation
import Testing
@testable import PaddockCore

/// The browser tab shows playwright-cli's dashboard from the sandbox: untrusted, so it may reach
/// only its own origin (backlog doc Browser).
@Suite("BrowserWebPolicy")
struct BrowserWebPolicyTests {
    func url(_ text: String) throws -> URL { try #require(URL(string: text)) }

    @Test func onlyALoopbackDashboardIsAccepted() throws {
        let policy = try #require(BrowserWebPolicy(dashboard: try url("http://127.0.0.1:50002/")))
        #expect(policy.homeURL.absoluteString == "http://127.0.0.1:50002/")
        #expect(BrowserWebPolicy(dashboard: try url("http://0.0.0.0:50002/")) == nil)
        #expect(BrowserWebPolicy(dashboard: try url("https://127.0.0.1:50002/")) == nil)
        #expect(BrowserWebPolicy(dashboard: try url("http://127.0.0.1/")) == nil)
    }

    @Test func nothingButTheDashboardLoadsOrOpens() throws {
        let policy = try #require(BrowserWebPolicy(dashboard: try url("http://127.0.0.1:50002/")))
        for page in ["http://127.0.0.1:50002/", "http://127.0.0.1:50002/index.html?ws=abc", "ws://127.0.0.1:50002/abc", "about:blank"] {
            #expect(policy.allows(try url(page)), "\(page)")
        }
        // llmman, a gateway, another port, the sandbox's own localhost, the internet, files
        for page in ["http://127.0.0.1:17434/", "http://127.0.0.1:17480/v1/models", "http://127.0.0.1:50003/",
                     "http://localhost:3000/", "https://example.com/", "file:///etc/passwd", "http://127.0.0.1.evil.example:50002/"] {
            #expect(!policy.allows(try url(page)), "\(page)")
        }
    }

    @Test func contentRulesBlockAllButTheDashboard() throws {
        let policy = try #require(BrowserWebPolicy(dashboard: try url("http://127.0.0.1:50002/")))
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(policy.contentRules.utf8)) as? [[String: [String: String]]])
        #expect(rules.first?["action"]?["type"] == "block" && rules.first?["trigger"]?["url-filter"] == ".*")
        let allowed = rules.filter { $0["action"]?["type"] == "ignore-previous-rules" }.compactMap { $0["trigger"]?["url-filter"] }
        #expect(allowed == [#"^http://127\.0\.0\.1:50002/"#, #"^ws://127\.0\.0\.1:50002/"#, "^data:", "^blob:"])
        #expect(!policy.contentRules.contains("|") && !policy.contentRules.contains("(?"))
        #expect(policy.ruleListIdentifier == "paddock-browser-50002")
    }
}

/// Following the agent's browser: backlog doc Browser.
@Suite("BrowserActivity")
struct BrowserActivityTests {
    @Test func theKitInstallsTheWrapperAndTheWatcherAndFixesHTTPSAndFiles() throws {
        let spec = BrowserKit.spec
        // both go in as base64, so no shell changes them
        let encoded = spec.components(separatedBy: "printf '%s' '").dropFirst().compactMap { $0.components(separatedBy: "'").first }
        #expect(encoded.compactMap { Data(base64Encoded: $0) }
            == [Data(BrowserActivity.wrapper.utf8), Data(BrowserActivity.watcher.utf8), Data(BrowserShow.script.utf8),
                Data(BrowserKit.openUIReference.utf8)])
        #expect(spec.contains("/usr/local/bin/paddock"))
        #expect(spec.contains("ln -sf \"$real\" \(BrowserActivity.realCLI)"))
        #expect(spec.contains("/usr/local/bin/paddock-browser-watch"))
        // the dashboard starts from the real playwright-cli, so it is never activity, and with no
        // pgrep check first (it matched its own sh -c, so the dashboard never started)
        #expect(spec.contains("- \"\(BrowserKit.startDashboardScript)\""))
        #expect(BrowserKit.startDashboardScript.contains("setsid \(BrowserActivity.realCLI) show --port \(BrowserKit.dashboardPort) --host 0.0.0.0"))
        #expect(!spec.contains("pgrep"))
        // sbx's proxy CA in Chromium's own store; certificate checks stay on
        #expect(spec.contains("libnss3-tools") && spec.contains("certutil -d \"sql:$db\" -A -t \"C,,\" -n sbx-proxy -i \"$ca\""))
        #expect(!spec.contains("ignoreHTTPSErrors"))
        #expect(spec.contains("default: /tmp/playwright-cli\n    env: PLAYWRIGHT_MCP_OUTPUT_DIR"))
        // the agent is told how to use both tools, and to tell the operator what Paddock lacks
        #expect(spec.contains("paddock open http://localhost:3000") && spec.contains("--native"))
        #expect(spec.contains("If Paddock gets in your way or lacks something you needed, tell the operator"))
        #expect(BrowserActivity.watchCommand(sandbox: "paddock-app")
                == ["exec", "-i", "paddock-app", "sh", "-c", SandboxWatchers.replaceScript, "paddock-watch", "paddock-browser-watch", SandboxWatchers.owner])
        // pages the operator closes in the dashboard are noted for the agent; shown tabs are reported
        #expect(BrowserActivity.watcher.contains("closedByOperator(sessions)") && BrowserActivity.watcher.contains("type: 'shows'"))
    }

    /// The wrapper under sh, with a fake playwright-cli in place of the real one.
    @Test func theWrapperHandsOutSessionsAndRequiresThem() throws {
        let dir = NSTemporaryDirectory() + "paddock-wrapper-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir + "/work dir", withIntermediateDirectories: true)
        let real = dir + "/real"
        try Data("#!/bin/sh\nprintf '%s\\n' \"$@\" >> \"\(dir)/args\"\nexit 3\n".utf8).write(to: URL(fileURLWithPath: real))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: real)
        let wrapper = BrowserActivity.wrapper
            .replacingOccurrences(of: "real=\(BrowserActivity.realCLI)", with: "real='\(real)'")
            .replacingOccurrences(of: "state=/tmp/paddock-browser", with: "state='\(dir)/state'")
        try Data(wrapper.utf8).write(to: URL(fileURLWithPath: dir + "/playwright-cli"))
        func run(_ arguments: [String], environment: [String: String] = [:]) throws -> (status: Int32, stderr: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [dir + "/playwright-cli"] + arguments
            process.currentDirectoryURL = URL(fileURLWithPath: dir + "/work dir")
            process.environment = ["PATH": "/usr/bin:/bin"].merging(environment) { $1 }
            let errors = Pipe()
            process.standardError = errors
            try process.run()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        func args() -> String { String(decoding: FileManager.default.contents(atPath: dir + "/args") ?? Data(), as: UTF8.self) }

        // open always starts a new session: the suggestion plus a suffix, and says so
        let opened = try run(["--session", "counter", "open", "http://localhost:4173"])
        #expect(opened.status == 3)  // the real exit status passes through
        let name = try #require(opened.stderr.firstMatch(of: /your session is (counter-[0-9a-f]{4})\./)?.1).description
        #expect(args() == "-s=\(name)\nopen\nhttp://localhost:4173\n")
        #expect(FileManager.default.fileExists(atPath: dir + "/state/sessions/" + name))
        let unnamed = try run(["open"])
        #expect(unnamed.stderr.contains("your session is s-"))

        // every other command needs a session it handed out
        for refused in [["snapshot"], ["-s=counter", "click", "e3"], ["-s=x;rm", "click"], ["close-all"], ["kill-all"]] {
            #expect(try run(refused).status == 2, "\(refused)")
        }
        #expect(try run(["snapshot"], environment: ["PLAYWRIGHT_CLI_SESSION": name]).status == 2)  // no default session
        #expect(try run(["-s=\(name)", "click", "e3"]).status == 3)
        #expect(try run(["show", "--port", "9323"]).status == 3)  // no session's pages: passes through

        // a tab the operator closed: told once, the next time the agent uses that session
        try FileManager.default.createDirectory(atPath: dir + "/state/notes", withIntermediateDirectories: true)
        try Data("Paddock: the operator closed tab 1 (http://localhost:4173/b).\n".utf8).write(to: URL(fileURLWithPath: dir + "/state/notes/" + name))
        #expect(try run(["-s=\(name)", "snapshot"]).stderr.contains("the operator closed tab 1"))
        #expect(!FileManager.default.fileExists(atPath: dir + "/state/notes/" + name))

        // activity is noted per session; a session the agent closed is no longer one it can use
        let events = String(decoding: FileManager.default.contents(atPath: dir + "/state/events") ?? Data(), as: UTF8.self)
        #expect(events.hasPrefix("start \(name) open\nend \(name) 3\n"))
        // (the fake exits 3, so close does not succeed here; with 0 the handle goes)
        #expect(BrowserActivity.wrapper.contains(#"if [ "$command" = close ] && [ "$status" = 0 ]; then rm -f "$state/sessions/$session"; fi"#))
        // every workspace's sessions, each read in its own folder
        #expect(BrowserActivity.watcher.contains("['list', '--all', '--json']"))
    }

    @Test func eachViewSelectsItsOwnPage() throws {
        let script = try #require(BrowserActivity.selectScript(session: "counter", index: 1))
        #expect(script.contains(#"})("counter", 1);"#))
        #expect(script.contains(#"'[aria-label="Session ' + session + '"]'"#) && script.contains(#"'[role="option"]'"#))
        // nothing from the sandbox gets into the script unchecked
        #expect(BrowserActivity.selectScript(session: "x\"); alert(1); (\"", index: 0) == nil)
        #expect(BrowserActivity.selectScript(session: "counter", index: -1) == nil)
        #expect(BrowserActivity.watcher.contains(BrowserActivity.realCLI) && BrowserActivity.wrapper.contains(BrowserActivity.realCLI))
    }

    @Test func sessionsAndActivityFollowTheWatchedLines() {
        var browser = BrowserSessions()
        let tabs = #"{"type":"tabs","sessions":[{"name":"counter","tabs":[{"title":"Counter","url":"http://localhost:4173/","current":false},{"title":"Second","url":"http://localhost:4173/b","current":true}]}]}"#
        #expect(browser.apply(line: tabs) == .pages(changed: ["counter#0", "counter#1"], gone: []))
        #expect(browser.apply(line: tabs) == .none)
        #expect(browser.apply(line: #"{"type":"busy","session":"counter","command":"click"}"#) == .busy(session: "counter"))
        #expect(browser.busy == ["counter"])
        #expect(browser.apply(line: #"{"type":"idle","session":"counter"}"#) == .idle(session: "counter"))
        #expect(browser.busy.isEmpty)
        let navigated = #"{"type":"tabs","sessions":[{"name":"counter","tabs":[{"title":"Counter","url":"http://localhost:4173/c","current":true}]}]}"#
        #expect(browser.apply(line: navigated) == .pages(changed: ["counter#0"], gone: ["counter#1"]))
        #expect(BrowserSessions.sessionAndIndex(of: "counter#0")! == ("counter", 0))
        #expect(BrowserSessions.sessionAndIndex(of: "../x#0") == nil)
    }

    /// The lines come from the sandbox.
    @Test func untrustedLinesAreCheckedAndCleaned() {
        var browser = BrowserSessions()
        for line in ["not json", #"{"type":"busy","session":"../x"}"#, #"{"type":"tabs"}"#,
                     #"{"type":"tabs","sessions":[{"name":"a b","tabs":[{"url":"x"}]}]}"#] {
            _ = browser.apply(line: line)
        }
        #expect(browser.pages.isEmpty && browser.busy.isEmpty)
        let tab = #"{"title":"Pay‮load\u0007 now","url":"http://a/","current":true}"#
        let many = (1...30).map { #"{"name":"s\#($0)","tabs":[\#(tab)]}"# }.joined(separator: ",")
        _ = browser.apply(line: #"{"type":"tabs","sessions":[\#(many)]}"#)
        #expect(browser.pages.count == BrowserActivity.maxPages)
        #expect(browser.pages.first?.title == "Payload now")
        #expect(browser.apply(line: String(repeating: " ", count: 70000)) == .none)
    }
}

/// `paddock` tabs and native tabs: backlog doc Browser.
@Suite("BrowserShow")
struct BrowserShowTests {
    @Test func paddockShowRendersInItsOwnSessionWithFileAccess() {
        let script = BrowserShow.script
        #expect(script.hasPrefix(NodeScript.header + "\n"))
        #expect(script.contains("const SESSION = '\(BrowserShow.session)';") && script.contains("const MAX = \(BrowserShow.maxShows);"))
        #expect(script.contains("PLAYWRIGHT_MCP_ALLOW_UNRESTRICTED_FILE_ACCESS: '1'"))
        // several agents: records are claimed exclusively, the show session changes one at a time,
        // and a new tab's URL is the one playwright-cli reports for that command
        #expect(script.contains("fs.openSync(path.join(SHOWS, id + '.json'), 'wx')") && script.contains("locked(() => {"))
        #expect(script.contains("/^- Page URL: (.*)$/m"))
        #expect(BrowserKit.spec.contains("starts a new session and prints") && BrowserKit.spec.contains("session names and tab ids you were given"))
        // a native file is read only from beside it
        #expect(script.contains("if (real !== record.path && !real.startsWith(base + '/')) fail("))
        #expect(!script.contains("\u{2014}"))
    }

    /// Ids are handles: random, so no agent reaches another's by counting.
    @Test func showIDsAreFourHexDigits() {
        #expect(BrowserShow.isShowID("tab-a1b2") && BrowserShow.isShowID("tab-0000"))
        for bad in ["show-1", "show-A1B2", "tab-a1b2c", "show-g1b2", "../x", "show-"] {
            #expect(!BrowserShow.isShowID(bad), "\(bad)")
        }
        #expect(BrowserShow.script.contains("'tab-' + crypto.randomBytes(2).toString('hex')"))
        // the same verbs as playwright-cli, each with the id; no list of other agents' tabs
        for verb in ["case 'open':", "case 'status': status(args[1]); break;", "case 'goto': navigate(args[1], 'goto', args[2], false); break;",
                     "case 'close': close(args[1]); break;"] {
            #expect(BrowserShow.script.contains(verb), "\(verb)")
        }
        #expect(!BrowserShow.script.contains("'--list'") && !BrowserShow.script.contains("case '--status'"))
    }

    @Test func paddockSendsOnlyCheckedCommands() {
        #expect(BrowserShow.operatorCommand(sandbox: "paddock-app", id: "tab-c3d4", event: .dismissed)
            == ["exec", "paddock-app", "paddock", "--operator", "tab-c3d4", "dismissed"])
        #expect(BrowserShow.operatorCommand(sandbox: "paddock-app", id: "../x", event: .opened) == nil)
        #expect(BrowserShow.readCommand(sandbox: "paddock-app", id: "tab-e5f6", relativePath: "img/a.png")
            == ["exec", "paddock-app", "paddock", "--read", "tab-e5f6", "img/a.png"])
        for bad in ["../secret", "/etc/passwd", "a/../../b", "a\\b", "./a"] {
            #expect(BrowserShow.readCommand(sandbox: "paddock-app", id: "tab-e5f6", relativePath: bad) == nil, "\(bad)")
        }
    }

    @Test func aShowTabSeesOnlyItsPage() throws {
        let script = try #require(BrowserActivity.showScript(index: 2))
        #expect(script.contains(".split-view-sidebar, .split-view-resizer { display: none !important; }"))
        // kept selected, and the session list comes back when the page cannot be found
        #expect(script.contains("setInterval(") && script.contains("hide.remove();"))
        #expect(script.contains(#"})("paddock-tabs", 2);"#))
        #expect(BrowserActivity.showScript(index: -1) == nil)
    }

    @Test func showsFollowTheWatchedLines() {
        var browser = BrowserSessions()
        let line = #"{"type":"shows","shows":[{"id":"tab-a1b2","mode":"page","title":"Chart","note":"Look","url":"file:///a/page.html","state":"new"},{"id":"tab-e5f6","mode":"native","title":"notes.md","path":"/a/notes.md","state":"opened"}]}"#
        #expect(browser.apply(line: line) == .shows(added: ["tab-a1b2", "tab-e5f6"], gone: []))
        #expect(browser.apply(line: line) == .none)
        #expect(browser.shows.map(\.id) == ["tab-a1b2", "tab-e5f6"])
        #expect(browser.shows[0].mode == .page(url: "file:///a/page.html") && !browser.shows[0].isNative)
        #expect(browser.shows[1].isNative && browser.shows[1].opened && browser.shows[1].fileName == "notes.md")
        // the page a page show is, in the show session
        _ = browser.apply(line: #"{"type":"tabs","sessions":[{"name":"paddock-tabs","tabs":[{"title":"Chart","url":"file:///a/page.html","current":true}]}]}"#)
        #expect(browser.page(of: browser.shows[0])?.id == "paddock-tabs#0")
        #expect(browser.apply(line: #"{"type":"shows","shows":[]}"#) == .shows(added: [], gone: ["tab-a1b2", "tab-e5f6"]))
    }

    /// Refresh and Back on a page shown in the sandbox happen there; afterwards its URL may differ.
    @Test func refreshAndBackReachTheSandboxAndThePageIsStillFound() {
        // the operator's, kept as the operator's in the tab's history
        #expect(BrowserShow.navigateCommand(sandbox: "paddock-app", id: "tab-a1b2", .back)
            == ["exec", "paddock-app", "paddock", "--operator", "tab-a1b2", "back"])
        #expect(BrowserShow.navigateCommand(sandbox: "paddock-app", id: "nope", .reload) == nil)
        // the agent's own
        #expect(BrowserShow.script.contains("case 'back': navigate(args[1], 'back', '', false); break;"))
        #expect(BrowserShow.script.contains("navigate(id, event, '', true);"))
        var native = BrowserSessions()
        _ = native.apply(line: #"{"type":"shows","shows":[{"id":"tab-0789","mode":"native","path":"/r/a.md","revision":3}]}"#)
        #expect(native.shows.first?.revision == 3)
        #expect(BrowserKit.spec.contains("`goto ID URL-or-FILE`"))

        var browser = BrowserSessions()
        _ = browser.apply(line: #"{"type":"shows","shows":[{"id":"tab-a1b2","mode":"page","url":"http://a/1"},{"id":"tab-c3d4","mode":"native","path":"/r/index.html"},{"id":"tab-e5f6","mode":"page","url":"http://a/2"}]}"#)
        // the second page show's page went back to another URL: found by its place among page shows
        _ = browser.apply(line: #"{"type":"tabs","sessions":[{"name":"paddock-tabs","tabs":[{"url":"http://a/1"},{"url":"http://a/0"}]}]}"#)
        #expect(browser.page(of: browser.shows[2])?.id == "paddock-tabs#1")
        #expect(browser.page(of: browser.shows[0])?.id == "paddock-tabs#0")
        // when shows and tabs no longer pair up, nothing is guessed
        _ = browser.apply(line: #"{"type":"tabs","sessions":[{"name":"paddock-tabs","tabs":[{"url":"http://a/1"}]}]}"#)
        #expect(browser.page(of: browser.shows[2]) == nil)
        // the report opens on the operator's screen by default
        #expect(BrowserKit.spec.contains("paddock open playwright-report/index.html --native"))
    }

    /// The lines come from the sandbox.
    @Test func untrustedShowsAreChecked() {
        var browser = BrowserSessions()
        let bad = #"{"type":"shows","shows":[{"id":"x","mode":"page","url":"a"},{"id":"tab-a1b2","mode":"native","path":"relative"},{"id":"tab-c3d4","mode":"other"},{"id":"tab-0789","mode":"page"}]}"#
        #expect(browser.apply(line: bad) == .none)
        #expect(browser.shows.isEmpty)
        let many = (1...20).map { #"{"id":"tab-\#(String(format: "%04x", $0))","mode":"page","url":"http://a/","title":"T\u202E"}"# }.joined(separator: ",")
        _ = browser.apply(line: #"{"type":"shows","shows":[\#(many)]}"#)
        #expect(browser.shows.count == BrowserShow.maxShows && browser.shows[0].title == "T")
    }

    @Test func nativeTabsLoadOnlyTheirOwnFiles() throws {
        let policy = try #require(NativeShowPolicy(showID: "tab-e5f6", fileName: "page.html"))
        #expect(policy.homeURL?.absoluteString == "paddock-file://tab-e5f6/page.html")
        #expect(policy.rendering == .web)
        #expect(policy.relativePath(of: try #require(URL(string: "paddock-file://tab-e5f6/img/a.png"))) == "img/a.png")
        #expect(policy.relativePath(of: try #require(URL(string: "paddock-file://tab-0789/page.html"))) == nil)
        #expect(policy.relativePath(of: try #require(URL(string: "https://example.com/page.html"))) == nil)
        #expect(policy.relativePath(of: try #require(URL(string: "paddock-file://tab-e5f6/a/../../secret"))) == nil)
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(policy.contentRules.utf8)) as? [[String: [String: String]]])
        #expect(rules.first?["action"]?["type"] == "block" && rules.first?["trigger"]?["url-filter"] == ".*")
        let allowed = rules.filter { $0["action"]?["type"] == "ignore-previous-rules" }.compactMap { $0["trigger"]?["url-filter"] }
        #expect(allowed == ["^paddock-file://tab-e5f6/", "^data:", "^blob:"])
        #expect(NativeShowPolicy(showID: "tab-e5f6", fileName: "notes.md")?.rendering == .markdown)
        #expect(NativeShowPolicy(showID: "tab-e5f6", fileName: "build.log")?.rendering == .text)
        #expect(NativeShowPolicy(showID: "bad", fileName: "a.html") == nil)
        #expect(NativeShowPolicy(showID: "tab-e5f6", fileName: "../a.html") == nil)
        #expect(NativeShowPolicy.mimeType(for: "a/b.SVG") == "image/svg+xml" && NativeShowPolicy.mimeType(for: "x.bin") == "application/octet-stream")
    }
}

/// The operator's screenshots, recordings, and annotations reach the agent (backlog doc Browser).
@Suite("BrowserCapture")
struct BrowserCaptureTests {
    @Test func aCaptureGoesIntoTheSandboxAndToTheRightAgent() {
        let date = Date(timeIntervalSince1970: 1_792_900_000)
        let name = BrowserCapture.fileName(suggested: "screenshot 1.png", at: date)
        #expect(name == "1792900000000-screenshot-1.png")
        // the dashboard's name comes from the sandbox: no path, nothing odd
        #expect(BrowserCapture.fileName(suggested: "../../etc/pass wd", at: date) == "1792900000000-pass-wd")
        #expect(BrowserCapture.fileName(suggested: "...", at: date) == "1792900000000-capture")
        #expect(BrowserCapture.kind(of: "a.webm") == .recording && BrowserCapture.kind(of: "a.png") == .screenshot)
        let path = BrowserCapture.folder + "/" + name
        #expect(BrowserCapture.commands(sandbox: "paddock-app", localFile: "/tmp/x.png", fileName: name, owner: .session("work-8574")) == [
            ["exec", "paddock-app", "mkdir", "-p", BrowserCapture.folder],
            ["cp", "/tmp/x.png", "paddock-app:" + path],
            ["exec", "paddock-app", "paddock-browser-watch", "--captured", "work-8574", path, "screenshot"],
        ])
        #expect(BrowserCapture.commands(sandbox: "paddock-app", localFile: "/tmp/x.png", fileName: name, owner: .show("tab-a1b2"))?.last
            == ["exec", "paddock-app", "paddock", "--operator", "tab-a1b2", "screenshot", path])
        #expect(BrowserCapture.commands(sandbox: "paddock-app", localFile: "/tmp/x.png", fileName: name, owner: .session("a b")) == nil)
        // the sandbox checks the path too, and tells the agent on its next command
        #expect(BrowserActivity.watcher.contains("process.argv[2] === '--captured'"))
        #expect(BrowserShow.script.contains("event === 'screenshot' || event === 'recording'"))
        #expect(BrowserCapture.selectedSessionScript.contains(#"[role="option"][aria-selected="true"]"#))
    }

    @Test func anAnnotationRequestIsFollowed() {
        var browser = BrowserSessions()
        _ = browser.apply(line: #"{"type":"tabs","sessions":[{"name":"work-8574","tabs":[{"url":"http://a/"}]}]}"#)
        #expect(browser.apply(line: #"{"type":"annotate","session":"work-8574","active":true}"#) == .annotate(session: "work-8574", active: true))
        #expect(browser.annotating == ["work-8574"])
        _ = browser.apply(line: #"{"type":"annotate","session":"work-8574","active":false}"#)
        #expect(browser.annotating.isEmpty)
        #expect(browser.apply(line: #"{"type":"annotate","session":"a b","active":true}"#) == .none)
        // the wrapper lets show --annotate through only with the agent's own session, and notes it
        #expect(BrowserActivity.wrapper.contains(#"show) case " $* " in *" --annotate "*) ;; *) PWTEST_SOCKETS_DIR=/tmp/paddock-browser/sockets exec "$real" "$@" ;; esac ;;"#))
        #expect(BrowserKit.spec.contains("show --annotate"))
    }
}

/// What an agent asked for after using the tabs: backlog doc Browser.
@Suite("Agent feedback")
struct AgentFeedbackTests {
    @Test func theAgentHearsWhatTheOperatorDidAndWhyThingsFail() {
        let script = BrowserShow.script
        // news on any command with the tab's id
        #expect(script.contains("function news(record)") && script.contains("process.stderr.write(`Paddock: ${line}\\n`)"))
        // a page that did not load says why, and suggests checking the server
        #expect(script.contains("net::ERR_[A-Z_]+") && script.contains("is the server at ${wanted} running? check: curl -I ${wanted}"))
        #expect(script.contains("it stayed on about:blank"))
        // annotate a shown tab by its id, with absolute paths in the answer
        #expect(script.contains("case 'annotate': annotate(args[1]); break;"))
        #expect(script.contains("cli([`-s=${SESSION}`, 'show', '--annotate'])"))
        #expect(BrowserKit.spec.contains("paddock annotate tab-k3f9") && BrowserKit.spec.contains("ask what they mean"))
    }

    @Test func aTabWaitingForAnAnnotationAsksForAttention() {
        var browser = BrowserSessions()
        _ = browser.apply(line: #"{"type":"shows","shows":[{"id":"tab-a1b2","mode":"page","url":"http://a/","annotating":true}]}"#)
        #expect(browser.shows.first?.annotating == true)
        _ = browser.apply(line: #"{"type":"shows","shows":[{"id":"tab-a1b2","mode":"page","url":"http://a/"}]}"#)
        #expect(browser.shows.first?.annotating == false)
    }
}

/// Interactive tabs: OpenUI's renderer in Paddock (backlog doc Browser, OpenUI tabs).
@Suite("OpenUI")
struct OpenUITests {
    @Test func thePageLoadsOnlyTheAppsRendererFiles() throws {
        #expect(OpenUIPolicy.homeURL?.absoluteString == "paddock-ui://renderer/index.html")
        #expect(OpenUIPolicy.file(for: try #require(URL(string: "paddock-ui://renderer/vendor/openui-bundle.min.js"))) == "vendor/openui-bundle.min.js")
        for other in ["paddock-ui://renderer/../secret", "paddock-ui://renderer/vendor/LICENSE", "paddock-ui://other/index.html",
                      "https://example.com/index.html", "paddock-file://tab-a1b2/index.html"] {
            #expect(OpenUIPolicy.file(for: try #require(URL(string: other))) == nil, "\(other)")
        }
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(OpenUIPolicy.contentRules.utf8)) as? [[String: [String: String]]])
        #expect(rules.first?["action"]?["type"] == "block")
        #expect(rules.filter { $0["action"]?["type"] == "ignore-previous-rules" }.compactMap { $0["trigger"]?["url-filter"] }
            == ["^paddock-ui://renderer/", "^data:", "^blob:"])
    }

    /// The document is data: it goes in as a JSON string, never as script.
    @Test func theDocumentGoesInAsAString() throws {
        let document = "root = Card([CardHeader(\"Hi\")])\n\"); alert(1); (\""
        let script = try #require(OpenUIPolicy.renderScript(document: document, state: #"{"deploy":{"env":{"value":"prod"}}}"#))
        #expect(script.hasPrefix("window.paddockRender(\"root = Card(") && script.hasSuffix(#", {"deploy":{"env":{"value":"prod"}}});"#))
        #expect(script.contains(#"\"); alert(1); (\""#))
        #expect(OpenUIPolicy.renderScript(document: "root = Card([])", state: "not json")?.hasSuffix(", null);") == true)
        #expect(OpenUIPolicy.renderScript(document: String(repeating: "x", count: OpenUIPolicy.maxDocumentBytes + 1), state: nil) == nil)
    }

    @Test func whatThePageSendsIsChecked() {
        let action = #"{"kind":"action","action":{"type":"continue_conversation","message":"Deploy","form":"deploy","values":{"env":"staging"}}}"#
        #expect(OpenUIMessage(action) == .action(#"{"form":"deploy","message":"Deploy","type":"continue_conversation","values":{"env":"staging"}}"#))
        #expect(OpenUIMessage(#"{"kind":"ready"}"#) == .ready)
        #expect(OpenUIMessage(#"{"kind":"state","state":{"deploy":{"env":{"value":"prod"}}}}"#) == .state(#"{"deploy":{"env":{"value":"prod"}}}"#))
        guard case .problems(let json)? = OpenUIMessage(#"{"kind":"problems","problems":[{"code":"missing-required","message":"x","extra":5}]}"#) else {
            Issue.record("problems"); return
        }
        #expect(json == #"[{"code":"missing-required","message":"x"}]"#)  // only text fields
        for bad in ["not json", #"{"kind":"action","action":{"message":"no type"}}"#, #"{"kind":"other"}"#,
                    #"{"kind":"action","action":{"type":"x","message":"\#(String(repeating: "y", count: 70000))"}}"#] {
            #expect(OpenUIMessage(bad) == nil)
        }
    }

    @Test func interactiveTabsReachTheSandbox() {
        #expect(BrowserShow.uiEventCommand(sandbox: "paddock-app", id: "tab-a1b2", .action, json: #"{"type":"x"}"#)
            == ["exec", "paddock-app", "paddock", "--operator", "tab-a1b2", "action", #"{"type":"x"}"#])
        #expect(BrowserShow.uiEventCommand(sandbox: "paddock-app", id: "nope", .action, json: "{}") == nil)
        var browser = BrowserSessions()
        _ = browser.apply(line: #"{"type":"shows","shows":[{"id":"tab-a1b2","mode":"ui","path":"/tmp/paddock-tabs/ui/tab-a1b2.oui","title":"Deploy"}]}"#)
        #expect(browser.shows.first?.isInteractive == true && browser.shows.first?.isNative == false)
        // the sandbox side: paddock ui, the read path, and wait printing actions as JSON
        let script = BrowserShow.script
        #expect(script.contains("case 'ui': {") && script.contains("if (record.mode === 'ui') {"))
        #expect(script.contains("event === 'action' || event === 'problems'"))
        #expect(script.contains("const action = / the operator acted: (\\{.*\\})$/.exec(line);"))
    }

    @Test func theAgentGetsTheLanguageAndHowToUseIt() {
        #expect(BrowserKit.openUIReference.hasPrefix("# OpenUI Lang reference (for paddock ui)"))
        #expect(BrowserKit.openUIReference.contains("## Component Signatures"))
        #expect(BrowserKit.spec.contains("paddock ui question.oui") && BrowserKit.spec.contains(BrowserKit.openUIReferencePath))
        #expect(BrowserKit.spec.contains("Never ask for passwords or keys."))
    }
}

/// An agent's report after using annotate: backlog doc Browser.
@Suite("Annotations and captures")
struct AnnotationTests {
    /// The cause of "Annotation client exited with code 1": the client finds the dashboard by a
    /// socket whose folder came from USER and TMPDIR, which differed between processes.
    @Test func everyProcessUsesOneSocketsFolder() {
        let folder = BrowserKit.socketsDirectory
        #expect(BrowserKit.spec.contains("default: \(folder)\n    env: PWTEST_SOCKETS_DIR"))
        #expect(BrowserKit.startDashboardScript.hasPrefix("PWTEST_SOCKETS_DIR=\(folder) setsid "))
        #expect(BrowserActivity.wrapper.contains("export PWTEST_SOCKETS_DIR=\(folder)"))
        #expect(BrowserActivity.watcher.contains("PWTEST_SOCKETS_DIR: '\(folder)'"))
        #expect(BrowserShow.script.contains("PWTEST_SOCKETS_DIR: '\(folder)'"))
    }

    @Test func theAgentReadsTheOperatorsMarkup() {
        let script = BrowserShow.script
        // annotation zips are unpacked; their comment is quoted in the news, and feedback prints it all
        #expect(script.contains("function unzip(file)") && script.contains("zlib.inflateRawSync"))
        #expect(script.contains("case 'feedback': feedbackOf(args[1]); break;"))
        #expect(BrowserActivity.watcher.contains("['--extract', file]"))
        // a failed annotate points to what was saved anyway
        #expect(script.contains("read them with: paddock feedback ${id}"))
        // the quick start and the kit's pointer say when to use it
        #expect(script.contains("When to use it"))
        #expect(BrowserKit.spec.contains(#"description: "Before you show the operator anything or ask them something, read this"#))
        #expect(BrowserKit.spec.contains("### Reach for it when") && BrowserKit.spec.contains("### The loop"))
    }
}
