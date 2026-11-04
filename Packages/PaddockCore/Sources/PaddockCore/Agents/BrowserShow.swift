import Foundation

/// `paddock`, the browser kit's command for showing content to the operator (backlog doc
/// Browser): each call becomes a tab in Paddock that does not take the operator's focus, and
/// prints its id, the handle for everything else about it (`--status`, `--note`, `--close`). By
/// default the content renders in the sandbox, as a page of the `paddock` playwright-cli
/// session (with `file:` access, which other sessions do not get), shown in a view of the dashboard
/// trimmed to the page. With `--native`, which the agent asks for only when it needs sharp,
/// selectable text, a file renders on the operator's Mac (`NativeShowPolicy`); that tab has a
/// color of its own and loads nothing until the operator opens it, so they can dismiss it unseen.
public enum BrowserShow {
    /// The playwright-cli session the shown pages live in.
    public static let session = "paddock-tabs"
    /// Paddock shows at most this many show tabs per project; `paddock` refuses more too.
    public static let maxShows = 12

    /// `tab-` and four random hex digits: the handle `paddock` prints, which the agent passes
    /// back for everything about that tab.
    public static func isShowID(_ id: String) -> Bool {
        guard id.hasPrefix("tab-") else { return false }
        let suffix = id.dropFirst("tab-".count)
        return suffix.count == 4 && suffix.allSatisfy { $0.isASCII && $0.isHexDigit && !$0.isUppercase }
    }

    /// What the operator did with a tab, for `--operator`; the agent hears of it.
    public enum OperatorEvent: String, Sendable {
        case opened, closed, dismissed
    }

    /// `sbx exec` command that tells the sandbox what the operator did with a tab. Nil for an id
    /// `paddock` would not make.
    public static func operatorCommand(sandbox: String, id: String, event: OperatorEvent) -> [String]? {
        isShowID(id) ? ["exec", sandbox, "paddock", "--operator", id, event.rawValue] : nil
    }

    /// What an interactive tab reports to the sandbox (`OpenUIMessage`): an action, or the
    /// renderer's problems.
    public enum UIEvent: String, Sendable {
        case action, problems
    }

    /// `sbx exec` command that hands an interactive tab's action or problems to the sandbox, where
    /// `paddock wait` prints them. `json` comes checked from `OpenUIMessage`. Nil for an id
    /// `paddock` would not make.
    public static func uiEventCommand(sandbox: String, id: String, _ event: UIEvent, json: String) -> [String]? {
        guard isShowID(id), json.utf8.count <= OpenUIMessage.maxActionBytes else { return nil }
        return ["exec", sandbox, "paddock", "--operator", id, event.rawValue, json]
    }

    /// The operator's Refresh or Back on a tab rendered in the sandbox.
    public enum Navigation: String, Sendable {
        case reload, back
    }

    /// `sbx exec` command for the operator's Refresh or Back on a tab rendered in the sandbox: done
    /// to the page there, and kept in the tab's history as the operator's (the agent has its own
    /// `--reload`, `--back`, and `--goto`). Nil for an id `paddock` would not make.
    public static func navigateCommand(sandbox: String, id: String, _ navigation: Navigation) -> [String]? {
        isShowID(id) ? ["exec", sandbox, "paddock", "--operator", id, navigation.rawValue] : nil
    }

    /// `sbx exec` command that prints a native tab's file (or one beside it) as base64. Nil for an
    /// id or path Paddock would not ask for (`NativeShowPolicy.relativePath`).
    public static func readCommand(sandbox: String, id: String, relativePath: String) -> [String]? {
        guard isShowID(id), NativeShowPolicy.isRelativePath(relativePath) else { return nil }
        return ["exec", sandbox, "paddock", "--read", id, relativePath]
    }

    /// The script (Node, which playwright-cli needs anyway).
    public static let script = NodeScript.wrap(#"""
        // Written by Paddock's browser kit: `paddock`, for everything the operator sees as tabs in Paddock.
        'use strict';
        const fs = require('fs');
        const path = require('path');
        const { execFileSync } = require('child_process');
        const crypto = require('crypto');
        const zlib = require('zlib');

        const REAL = '/usr/local/lib/paddock-browser/playwright-cli';
        const SESSION = 'paddock-tabs';
        const SHOWS = '/tmp/paddock-tabs/shows';
        // Tabs the operator closed or dismissed, kept so --status can still say so.
        const GONE = '/tmp/paddock-tabs/gone';
        const MAX = 12;
        const READ_LIMIT = 20 * 1024 * 1024;
        const LOCK = '/tmp/paddock-tabs/lock';
        // The documents of interactive tabs (paddock ui), as shown.
        const UI = '/tmp/paddock-tabs/ui';
        const UI_LIMIT = 512 * 1024;
        const USAGE = `paddock: put things in front of the operator, in tabs next to your terminal. New tabs never take
        their focus; tell them in one line what to look at.

        When to use it
          You built or changed something they should see    paddock open http://localhost:3000 --title "Checkout"
          A document or report they should read             paddock open notes.md --native   (sharp, on their screen)
          You need a decision or values from them           paddock ui question.oui           (see /usr/local/share/paddock/openui.md)
          You want them to point at something on a page     paddock annotate ID
        Then wait for them instead of asking in the terminal:
          paddock wait ID          prints what they did: opened, closed, an answer (JSON), a saved screenshot
          paddock feedback ID      their screenshots and annotations, with comments and file paths

        Every command prints the tab's id (tab-k3f9) or needs it:
          paddock status ID | reload ID | back ID | close ID | goto ID URL-or-FILE | note ID TEXT`;

        function fail(message) { process.stderr.write(`paddock: ${message}\n`); process.exit(1); }
        function isId(id) { return /^tab-[0-9a-f]{4}$/.test(id || ''); }
        function shows() {
          try {
            return fs.readdirSync(SHOWS).filter((f) => /^tab-[0-9a-f]{4}\.json$/.test(f))
              .map((f) => JSON.parse(fs.readFileSync(path.join(SHOWS, f), 'utf8')))
              .sort((a, b) => a.created - b.created);
          } catch { return []; }
        }
        function save(record) {
          fs.mkdirSync(SHOWS, { recursive: true });
          fs.writeFileSync(path.join(SHOWS, record.id + '.json'), JSON.stringify(record));
        }
        function find(id) {
          if (!isId(id)) fail(`${id || 'that'} is not a tab id; use the tab-xxxx that paddock open printed`);
          try { return JSON.parse(fs.readFileSync(path.join(SHOWS, id + '.json'), 'utf8')); } catch { fail(`tab ${id} is not open; paddock status ${id} says what happened to it`); }
        }
        // What happened to a tab, kept in its record.
        function happened(record, text) {
          record.history = (record.history || []).concat(`${new Date().toISOString()} ${text}`);
        }
        // What the operator did with the tab since you last looked (any command with its id prints it).
        function news(record) {
          const all = record.history || [];
          const lines = all.slice(record.agentSeen || 0).filter((line) => line.includes('the operator'));
          record.agentSeen = all.length;
          for (const line of lines) process.stderr.write(`Paddock: ${line}\n`);
        }
        // Captures: what the operator saved from a dashboard view, put here by Paddock. An annotation is a
        // zip (feedback.md with the comments and boxes, a screenshot, a snapshot); it is unpacked next to
        // itself, so its comment can be quoted and its files read.
        const CAPTURES = '/tmp/paddock-browser/captures';
        function unzip(file) {
          const data = fs.readFileSync(file);
          let end = data.length - 22;
          while (end >= 0 && data.readUInt32LE(end) !== 0x06054b50) end--;
          if (end < 0) return null;
          const count = data.readUInt16LE(end + 10);
          let at = data.readUInt32LE(end + 16);
          const dir = file.replace(/\.zip$/i, '');
          const files = [];
          for (let i = 0; i < count && i < 64; i++) {
            if (data.readUInt32LE(at) !== 0x02014b50) break;
            // The central directory has the sizes (a local header may leave them 0).
            const method = data.readUInt16LE(at + 10);
            const compressedSize = data.readUInt32LE(at + 20);
            const size = data.readUInt32LE(at + 24);
            const nameLength = data.readUInt16LE(at + 28);
            const extra = data.readUInt16LE(at + 30) + data.readUInt16LE(at + 32);
            const local = data.readUInt32LE(at + 42);
            const name = data.slice(at + 46, at + 46 + nameLength).toString('utf8');
            at += 46 + nameLength + extra;
            const base = path.basename(name).replace(/[^A-Za-z0-9._-]/g, '-');
            if (!base || name.endsWith('/') || size > 50 * 1024 * 1024) continue;
            const start = local + 30 + data.readUInt16LE(local + 26) + data.readUInt16LE(local + 28);
            const compressed = data.slice(start, start + compressedSize);
            let content;
            try { content = method === 8 ? zlib.inflateRawSync(compressed) : method === 0 ? compressed : null; } catch { content = null; }
            if (!content) continue;
            fs.mkdirSync(dir, { recursive: true });
            fs.writeFileSync(path.join(dir, base), content);
            files.push(path.join(dir, base));
          }
          return { dir, files };
        }
        // A capture in one line: the comment and files of an annotation, or the file.
        function describeCapture(file) {
          if (!/\.zip$/i.test(file) || !fs.existsSync(file)) return file;
          let unpacked = null;
          try { unpacked = unzip(file); } catch { unpacked = null; }
          if (!unpacked || !unpacked.files.length) return file;
          const feedback = unpacked.files.find((f) => /feedback\.md$/i.test(f));
          const comment = feedback ? fs.readFileSync(feedback, 'utf8').replace(/\s+/g, ' ').trim().slice(0, 400) : '';
          return `annotations${comment ? ` saying: ${comment}` : ''} (files: ${unpacked.files.join(', ')})`;
        }
        // Every capture of a tab, in full: feedback.md as written, and the files.
        function feedbackOf(id) {
          let record = null;
          for (const dir of [SHOWS, GONE]) {
            try { record = JSON.parse(fs.readFileSync(path.join(dir, id + '.json'), 'utf8')); break; } catch { /* next */ }
          }
          if (!record) fail(`there is no tab ${id}`);
          // A capture's line ends with the file Paddock put here.
          const files = (record.history || []).filter((l) => l.includes('the operator saved'))
            .map((l) => l.trim().split(' ').pop()).filter((f) => /^\/tmp\/paddock-browser\/captures\/[A-Za-z0-9._-]+$/.test(f));
          if (!files.length) { console.log(`The operator has saved nothing from tab ${id} yet.`); return; }
          for (const file of files) {
            const dir = file.replace(/\.zip$/i, '');
            if (/\.zip$/i.test(file) && !fs.existsSync(dir)) { try { unzip(file); } catch { /* shown as the file */ } }
            console.log(`== ${file}`);
            const inside = fs.existsSync(dir) && fs.statSync(dir).isDirectory() ? fs.readdirSync(dir).map((f) => path.join(dir, f)) : [];
            const feedback = inside.find((f) => /feedback\.md$/i.test(f));
            if (feedback) console.log(fs.readFileSync(feedback, 'utf8').trim());
            for (const f of inside) console.log(`- ${f}`);
          }
        }

        // Why playwright-cli failed, in its own words (its last lines), for the error message.
        function why(e) {
          const raw = ((e.stdout || '') + '\n' + (e.stderr || '')).toString().replace(/\u001b\[[0-9;]*m/g, '');
          const loaded = notLoaded(raw, '');
          if (loaded) return loaded;
          const lines = raw.split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('###') && !l.startsWith('- navigating'));
          return lines.slice(0, 3).join(' / ') || e.message || 'no reason given';
        }
        // Whether playwright-cli's output says the page did not load: the reason, or null.
        function notLoaded(output, wanted) {
          const error = /(net::ERR_[A-Z_]+|ERR_[A-Z_]+|ECONNREFUSED)/.exec(output || '');
          const url = /^- Page URL: (.*)$/m.exec(output || '');
          if (error) return `${error[1]}${/^https?:/i.test(wanted) ? ` (is the server at ${wanted} running? check: curl -I ${wanted})` : ''}`;
          if (url && url[1].trim() === 'about:blank' && wanted !== 'about:blank') return 'it stayed on about:blank';
          return null;
        }
        function cli(args) {
          return execFileSync(REAL, args, {
            cwd: '/', encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
            // The same sockets folder as the dashboard, whatever USER and TMPDIR say (PWTEST_SOCKETS_DIR).
            env: { ...process.env, PLAYWRIGHT_MCP_ALLOW_UNRESTRICTED_FILE_ACCESS: '1', PWTEST_SOCKETS_DIR: '/tmp/paddock-browser/sockets' },
          });
        }
        // The show session's tab URLs, or null when it is not open.
        function sessionTabs() {
          try {
            const result = JSON.parse(cli([`-s=${SESSION}`, 'tab-list', '--json'])).result || '';
            return result.split('\n').map((l) => /^- (\d+): (\(current\) )?\[(.*)\]\((.*)\)$/.exec(l)).filter(Boolean).map((m) => m[4]);
          } catch { return null; }
        }
        // Several agents may share this sandbox: changes to the show session and the records happen one
        // at a time (a lock directory; one left behind by a killed call is taken over after 30 s).
        function locked(work) {
          fs.mkdirSync(path.dirname(LOCK), { recursive: true });
          const deadline = Date.now() + 30000;
          for (;;) {
            try { fs.mkdirSync(LOCK); break; } catch {
              try { if (Date.now() - fs.statSync(LOCK).mtimeMs > 30000) { fs.rmSync(LOCK, { recursive: true, force: true }); continue; } } catch { continue; }
              if (Date.now() > deadline) fail('another paddock call holds the lock; try again');
              Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
            }
          }
          try { return work(); } finally { fs.rmSync(LOCK, { recursive: true, force: true }); }
        }
        // A new record under a random id, created exclusively, so two calls never share one; the id is
        // the handle the agent passes back (no one gets another's by counting).
        function claim(record) {
          fs.mkdirSync(SHOWS, { recursive: true });
          for (let attempt = 0; attempt < 100; attempt++) {
            const id = 'tab-' + crypto.randomBytes(2).toString('hex');
            if (fs.existsSync(path.join(GONE, id + '.json'))) continue;
            try {
              const fd = fs.openSync(path.join(SHOWS, id + '.json'), 'wx');
              Object.assign(record, { id, created: Date.now() });
              fs.writeSync(fd, JSON.stringify(record));
              fs.closeSync(fd);
              return record;
            } catch (e) { if (e.code !== 'EEXIST') throw e; }
          }
          fail('no free tab id');
        }
        function closePage(url) {
          const tabs = sessionTabs() || [];
          const i = tabs.indexOf(url);
          if (i < 0) return;
          try { cli(tabs.length === 1 ? [`-s=${SESSION}`, 'close'] : [`-s=${SESSION}`, 'tab-close', String(i)]); } catch { /* gone */ }
        }

        function show(target, title, text, native) {
          if (!target) fail(`what should the operator see? paddock open URL-or-FILE\n${USAGE}`);
          const { url = null, file = null } = resolveTarget(target);
          if (native && !file) fail('--native opens a file on the operator\'s screen: give the file\'s path, not a URL');
          const record = { title: title || (file ? path.basename(file) : url), note: text || '', state: 'new', history: [] };
          locked(() => {
            if (shows().length >= MAX) fail(`${MAX} tabs are open; close one first: paddock close ID`);
            if (native) {
              record.mode = 'native';
              record.path = file;
              record.revision = 0;
            } else {
              record.mode = 'page';
              const wanted = url || 'file://' + encodeURI(file);
              let output;
              try {
                output = cli(sessionTabs() === null ? [`-s=${SESSION}`, 'open', wanted] : [`-s=${SESSION}`, 'tab-new', wanted]);
              } catch (e) {
                const raw = ((e.stdout || '') + (e.stderr || '')).toString();
                fail(`could not open ${wanted}: ${notLoaded(raw, wanted) || why(e)}`);
              }
              const problem = notLoaded(output, wanted);
              if (problem) fail(`${wanted} did not load: ${problem}`);
              // The URL of the page this command opened, as playwright-cli reports it.
              const reported = /^- Page URL: (.*)$/m.exec(output || '');
              record.url = reported ? reported[1].trim() : wanted;
            }
            claim(record);
          });
          const id = record.id;
          console.log(native
            ? `Opened tab ${id} for the operator; it opens on their screen when they click it. Use the id: paddock status ${id}`
            : `Opened tab ${id} for the operator. Use the id: paddock status|reload|goto|close ${id}`);
        }

        // An interactive tab: an OpenUI Lang document, rendered by Paddock (reference:
        // /usr/local/share/paddock/openui.md). Paddock reads the copy kept here.
        function readDocument(source) {
          let text;
          try { text = source === '-' ? fs.readFileSync(0, 'utf8') : fs.readFileSync(path.resolve(source), 'utf8'); } catch { fail(`${source} cannot be read`); }
          if (Buffer.byteLength(text) > UI_LIMIT) fail(`the document is over ${UI_LIMIT / 1024} KB; split it`);
          if (!/^\s*root\s*=/m.test(text)) fail('the document needs a root statement: root = Card(...) (see /usr/local/share/paddock/openui.md)');
          return text;
        }
        function keepDocument(record, text) {
          fs.mkdirSync(UI, { recursive: true });
          record.path = path.join(UI, record.id + '.oui');
          fs.writeFileSync(record.path, text);
        }
        function ui(source, title, text) {
          if (!source) fail(`which document? paddock ui FILE (or - for stdin)\n${USAGE}`);
          const doc = readDocument(source);
          const record = { title: title || (source === '-' ? 'Interactive' : path.basename(source)), note: text || '', state: 'new', history: [], mode: 'ui', revision: 0, actions: [] };
          locked(() => {
            if (shows().length >= MAX) fail(`${MAX} tabs are open; close one first: paddock close ID`);
            claim(record);
            keepDocument(record, doc);
            save(record);
          });
          console.log(`Opened interactive tab ${record.id} for the operator. Wait for their answer: paddock wait ${record.id}`);
        }

        function close(id) {
          const record = find(id);
          news(record);
          locked(() => gone(record, 'closed-by-agent', 'you closed it'));
          console.log(`Closed tab ${id}.`);
        }

        // A tab the operator closed or dismissed: its page closes, and its record moves to GONE for --status.
        function gone(record, state, text) {
          record.state = state;
          happened(record, text);
          fs.mkdirSync(GONE, { recursive: true });
          fs.writeFileSync(path.join(GONE, record.id + '.json'), JSON.stringify(record));
          if (record.mode === 'page') closePage(record.url);
          fs.rmSync(path.join(SHOWS, record.id + '.json'), { force: true });
        }

        // For Paddock: what the operator did with a tab; the agent sees it with --status ID.
        function operator(id, event) {
          const record = find(id);
          if (event === 'opened') {
            if (record.state !== 'opened') { record.state = 'opened'; happened(record, 'the operator opened it'); save(record); }
          } else if (event === 'reload' || event === 'back') {
            navigate(id, event, '', true);
          } else if (event === 'action' || event === 'problems') {
            // From Paddock, checked there: an action as JSON (a button or a submitted form), or what the
            // renderer could not draw.
            let value;
            try { value = JSON.parse(process.argv[5] || ''); } catch { fail('not JSON'); }
            if ((process.argv[5] || '').length > 65536) fail('too large');
            if (event === 'action') {
              record.actions = (record.actions || []).concat([value]);
              happened(record, `the operator acted: ${JSON.stringify(value)}`);
            } else {
              const list = Array.isArray(value) ? value : [];
              const text = list.length
                ? `the renderer could not draw parts of it: ${list.map((p) => `${p.code}${p.statementId ? ' in ' + p.statementId : ''}: ${p.message}${p.hint ? ' (expected ' + p.hint + ')' : ''}`).join('; ')}`
                : 'the renderer draws all of it now';
              if (record.lastProblems !== text) { record.lastProblems = text; happened(record, `the operator's screen says ${text}`); }
            }
            save(record);
          } else if (event === 'screenshot' || event === 'recording') {
            // The operator saved one from this tab; Paddock put it in the sandbox at the path given.
            const file = process.argv[5] || '';
            if (!/^\/tmp\/paddock-browser\/captures\/[A-Za-z0-9._-]+$/.test(file)) fail('not a capture path');
            // An annotation zip is unpacked, so the line can quote its comment (paddock feedback has it all).
            const described = describeCapture(file);
            happened(record, described === file ? `the operator saved a ${event}: ${file}` : `the operator saved ${described}, from ${file}`);
            save(record);
          } else if (event === 'closed' || event === 'dismissed') {
            locked(() => gone(record, event, event === 'dismissed' ? 'the operator dismissed it without opening it' : 'the operator closed it'));
          } else {
            fail(`unknown event ${event}`);
          }
        }

        // Where a target points: a URL as it is, a file as its real path (it must exist).
        function resolveTarget(target) {
          if (/^https?:\/\//i.test(target)) return { url: target };
          const file = /^file:\/\//i.test(target) ? decodeURIComponent(new URL(target).pathname) : path.resolve(target);
          let stat;
          try { stat = fs.statSync(file); } catch { fail(`${file} does not exist`); }
          if (!stat.isFile()) fail(`${file} is not a file`);
          return { file: fs.realpathSync(file) };
        }

        // Reload, back, or goto on a tab: the agent's (by default) or the operator's (from Paddock). A tab
        // rendered here acts on its page in the show session (found by its URL, else by its place among
        // the page tabs) and keeps the URL it lands on; a native tab gets a new revision, and Paddock
        // loads it again (goto points it at another file).
        function navigate(id, how, target, byOperator) {
          const record = find(id);
          if (!byOperator) news(record);
          const who = byOperator ? 'the operator' : 'you';
          if (record.mode === 'ui') {
            if (how === 'back') fail(`tab ${id} is interactive; it has no back (change it with paddock goto ${id} FILE)`);
            if (how === 'goto') keepDocument(record, readDocument(target || ''));
            record.revision = (record.revision || 0) + 1;
            happened(record, how === 'goto' ? `${who} changed the document` : `${who} reloaded it`);
            save(record);
            if (!byOperator) console.log(`Tab ${id} shows the ${how === 'goto' ? 'new' : 'same'} document again.`);
            return;
          }
          if (record.mode === 'native') {
            if (how === 'back') fail(`tab ${id} shows a file on the operator's screen; it has no back`);
            if (how === 'goto') {
              const next = resolveTarget(target || '');
              if (!next.file) fail(`tab ${id} shows a file on the operator's screen: give a file's path, not a URL`);
              record.path = next.file;
            }
            record.revision = (record.revision || 0) + 1;
            happened(record, how === 'goto' ? `${who} pointed it at ${record.path}` : `${who} reloaded it`);
            save(record);
            return;
          }
          locked(() => {
            const tabs = sessionTabs() || [];
            let i = tabs.indexOf(record.url);
            if (i < 0) {
              const pages = shows().filter((s) => s.mode === 'page');
              i = pages.findIndex((s) => s.id === id);
              if (pages.length !== tabs.length) i = -1;
            }
            if (i < 0) fail(`the page of tab ${id} is gone; open it again: paddock open URL-or-FILE`);
            let args;
            if (how === 'goto') {
              const next = resolveTarget(target || '');
              args = [`-s=${SESSION}`, 'goto', next.url || 'file://' + encodeURI(next.file)];
            } else {
              args = [`-s=${SESSION}`, how === 'back' ? 'go-back' : 'reload'];
            }
            let output = '';
            try {
              cli([`-s=${SESSION}`, 'tab-select', String(i)]);
              output = cli(args);
            } catch (e) { fail(`could not ${how} tab ${id}: ${why(e)}`); }
            const problem = notLoaded(output, args[args.length - 1]);
            if (problem) { happened(record, `you tried to ${how}; the page did not load: ${problem}`); save(record); fail(`tab ${id} did not load: ${problem}`); }
            const reported = /^- Page URL: (.*)$/m.exec(output);
            if (reported) record.url = reported[1].trim();
            happened(record, how === 'back' ? `${who} went back (${record.url})` : how === 'goto' ? `${who} went to ${record.url}` : `${who} reloaded it`);
            save(record);
          });
          if (!byOperator) console.log(`Tab ${id} shows ${record.url}.`);
        }

        // Waits until the operator does something new with the tab (opens, closes, dismisses, reloads, or
        // saves a capture of it; for an interactive tab, an action), prints what, and exits; exit code 3
        // when the timeout passes first.
        function wait(id, seconds) {
          if (!isId(id)) fail(`${id || 'that'} is not a tab id; use the tab-xxxx that paddock open printed`);
          const load = () => {
            for (const dir of [SHOWS, GONE]) {
              try { return JSON.parse(fs.readFileSync(path.join(dir, id + '.json'), 'utf8')); } catch { /* next */ }
            }
            return null;
          };
          const first = load();
          if (!first) fail(`there is no tab ${id}`);
          const seen = (first.history || []).length;
          const limit = Date.now() + Math.max(1, Math.min(Number(seconds) || 600, 86400)) * 1000;
          for (;;) {
            const record = load();
            // Only what the operator did; your own reloads and gotos are in the history too.
            const news = record ? (record.history || []).slice(seen).filter((line) => line.includes('the operator')) : [];
            if (news.length) {
              for (const line of news) {
                // An action prints as its JSON, ready to parse; anything else as the line.
                const action = / the operator acted: (\{.*\})$/.exec(line);
                console.log(action ? action[1] : line);
              }
              // Seen now: later commands do not print it again.
              if (fs.existsSync(path.join(SHOWS, id + '.json'))) { record.agentSeen = (record.history || []).length; save(record); }
              return;
            }
            if (!record) { console.log(`tab ${id} is gone`); return; }
            if (Date.now() > limit) { console.log(`nothing from the operator on ${id} yet`); process.exit(3); }
            Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 300);
          }
        }

        function status(id) {
          if (!id) fail('which tab? paddock status ID, with the tab-xxxx that paddock open (or ui) printed; each command for a tab needs its id');
          if (!isId(id)) fail(`${id || 'that'} is not a tab id; use the tab-xxxx that paddock open printed`);
          let record = null;
          for (const dir of [SHOWS, GONE]) {
            try { record = JSON.parse(fs.readFileSync(path.join(dir, id + '.json'), 'utf8')); break; } catch { /* next */ }
          }
          if (!record) fail(`there is no tab ${id}`);
          const states = { new: 'not looked at yet', opened: 'the operator opened it', closed: 'closed by the operator', dismissed: 'dismissed by the operator without opening it', 'closed-by-agent': 'you closed it' };
          const kind = { native: "A file on the operator's screen", ui: 'An interactive tab' }[record.mode] || 'A live page';
          console.log(`${id}: ${states[record.state] || record.state}. ${kind}: ${record.title} (${record.url || record.path})${record.note ? '. Note: ' + record.note : ''}`);
          for (const line of record.history || []) console.log(`  ${line}`);
          if (record.agentSeen !== (record.history || []).length && fs.existsSync(path.join(SHOWS, id + '.json'))) {
            record.agentSeen = (record.history || []).length;
            save(record);
          }
        }

        // Asks the operator to mark up a live page: every dashboard view, the operator's view of this tab
        // among them, switches to annotation mode on its page; this waits until they submit, then prints
        // their feedback and the paths to the annotated screenshot and snapshot (playwright-cli's own).
        function annotate(id) {
          let record = find(id);
          news(record);
          if (record.mode !== 'page') fail(`tab ${id} is a file on the operator's screen; annotate works on live pages (paddock open without --native)`);
          record.annotating = true;
          happened(record, 'you asked the operator to annotate it');
          save(record);
          let output = '';
          try {
            // From /, so the dashboard switches no view to another page: each annotates its own page, and
            // the operator's view of this tab has this tab's page.
            output = cli([`-s=${SESSION}`, 'show', '--annotate']);
          } catch (e) {
            output = null;
            const reason = why(e);
            process.stderr.write(`paddock: the annotation did not finish: ${/Annotation client exited/.test(reason)
              ? "playwright-cli could not reach the dashboard the operator sees (its own reason is in its session's log, not here); if this keeps happening, tell the operator: the sandbox may need recreating"
              : reason}\n`);
          } finally {
            try { record = find(id); record.annotating = false; save(record); } catch { /* closed meanwhile */ }
          }
          if (output === null) {
            // The operator may have marked it up and saved it anyway: say so.
            const saved = (record.history || []).filter((l) => /the operator saved/.test(l));
            if (saved.length) process.stderr.write(`paddock: the operator saved ${saved.length} capture(s) of ${id}; read them with: paddock feedback ${id}\n`);
            process.exit(1);
          }
          happened(record, 'the operator answered your annotation request');
          record.agentSeen = (record.history || []).length;
          save(record);
          // playwright-cli prints the files relative to where it ran (/): make them absolute.
          const absolute = output.replace(/\]\((?!\/|[a-z]+:)([^)]+)\)/g, '](/$1)');
          process.stdout.write(absolute.endsWith('\n') ? absolute : absolute + '\n');
        }

        // For Paddock: a file of a native tab, base64, only from the shown file's folder.
        function read(id, relative) {
          const record = find(id);
          if (record.mode === 'ui') {
            process.stdout.write(fs.readFileSync(record.path).toString('base64'));
            return;
          }
          if (record.mode !== 'native') fail(`${id} is not rendered on the Mac`);
          const base = path.dirname(record.path);
          let real;
          try { real = fs.realpathSync(relative ? path.resolve(base, relative) : record.path); } catch { fail('no such file'); }
          if (real !== record.path && !real.startsWith(base + '/')) fail('outside the shown file\'s folder');
          const stat = fs.statSync(real);
          if (!stat.isFile() || stat.size > READ_LIMIT) fail('not a file, or too large');
          process.stdout.write(fs.readFileSync(real).toString('base64'));
        }

        const args = process.argv.slice(2);
        const option = (flag) => { const i = args.indexOf(flag); if (i < 0) return undefined; const v = args[i + 1]; args.splice(i, 2); return v; };
        const flag = (name) => { const i = args.indexOf(name); if (i < 0) return false; args.splice(i, 1); return true; };
        function open() {
          const native = flag('--native');
          const title = option('--title');
          const text = option('--note');
          const unknown = args.find((a) => a.startsWith('--'));
          if (unknown) fail(`unknown option ${unknown}\n${USAGE}`);
          // An OpenUI Lang document is an interactive tab, not a page of its source.
          if (!native && /\.oui$/i.test(args[0] || '')) return ui(args[0], title, text);
          show(args[0], title, text, native);
        }
        const verb = args[0];
        switch (verb) {
          // Paddock's own (what the operator did, and a native tab's files); not in the help.
          case '--operator': operator(args[1], args[2]); break;
          case '--read': read(args[1], args[2] || ''); break;
          case 'open': args.shift(); open(); break;
          case 'status': status(args[1]); break;
          case 'feedback': feedbackOf(args[1]); break;
          // For Paddock's watcher: a capture in one line (an annotation's comment and files).
          case '--extract': console.log(describeCapture(args[1] || '')); break;
          case 'annotate': annotate(args[1]); break;
          case 'ui': {
            args.shift();
            const title = option('--title');
            const text = option('--note');
            ui(args[0], title, text);
            break;
          }
          case 'wait': { const id = args[1]; args.splice(0, 2); wait(id, option('--timeout')); break; }
          case 'reload': navigate(args[1], 'reload', '', false); break;
          case 'back': navigate(args[1], 'back', '', false); break;
          case 'goto': navigate(args[1], 'goto', args[2], false); break;
          case 'close': close(args[1]); break;
          case 'note': {
            const record = find(args[1]);
            news(record);
            record.note = args.slice(2).join(' ');
            save(record);
            console.log(`Tab ${record.id}'s note: ${record.note}`);
            break;
          }
          case undefined: case 'help': case '-h': case '--help': console.log(USAGE); break;
          default:
            // A bare URL or file is open; a stray option is a mistake.
            if (verb.startsWith('-')) fail(`unknown option ${verb}\n${USAGE}`);
            open();
        }
        """#)
}
