import Foundation

/// Paddock's voice kit: `paddock-voice`, so an agent can talk with the operator (backlog doc Voice).
/// The agent tells the operator something (`say`) and asks a question and waits for the answer
/// (`ask`), both shown in Paddock's voice popup and read aloud while voice reply is on; it supplies
/// the words it works with so dictation of code names comes out right (`words`). The agent learns only what it acts on: the prompt hook
/// says with each prompt whether it was spoken and whether voice reply is on.
/// Audio never enters the sandbox: the Mac transcribes and speaks, and only text crosses.
///
/// Messages are files in `/tmp/paddock-voice/out` that `paddock-voice-watch` prints once and
/// removes; the app follows the watcher like the other kits' (`SandboxWatchers`). Answers, the
/// dictation record, and the voice settings go in with `sbx exec -i` and standard input, never in
/// argv. Everything the kit sends is untrusted: `VoiceMessage` checks it, and nothing of it is used
/// for any decision.
///
/// Named `paddock-voice`, not `paddock voice`: `paddock` belongs to the browser kit, and this kit
/// needs only the status kit.
public enum VoiceKit {
    /// sbx names a local kit after its folder, and the names in one sandbox must differ, so not
    /// `voice` (sbx 0.51 ships an `opencode` kit of its own; PAD-73.2).
    public static let directoryName = "paddock-voice"
    public static let command = "paddock-voice"
    public static let watchCommand = "paddock-voice-watch"
    public static let voiceDirectory = "/tmp/paddock-voice"

    public static func directory(in paths: PaddockPaths) -> String {
        paths.kits + "/" + directoryName
    }

    /// `sbx exec` command Paddock follows; it replaces older watchers there (`SandboxWatchers`).
    public static func watchArguments(sandbox: String) -> [String] { SandboxWatchers.arguments(sandbox: sandbox, command: watchCommand) }

    /// Whether a project's sandbox gets this kit, so Paddock follows its messages.
    public static func isChosen(by project: Project, app: AppConfig) -> Bool {
        project.chosenKits(app).contains { app.kits[$0]?.source == .builtin(.voice) }
    }

    // MARK: Commands the app runs

    /// `sbx exec -i` command that answers an `ask`; the answer (`VoiceAnswer.line`)
    /// goes on standard input. Nil for an id the kit did not give out.
    public static func answerArguments(sandbox: String, id: String) -> [String]? {
        VoiceMessage.isMessageID(id) ? ["exec", "-i", sandbox, command, "--answer", id] : nil
    }

    /// `sbx exec -i` command that records what the operator dictated into a tab, just before it is
    /// pasted, so the prompt hook can tell the agent the prompt was spoken. The text goes on
    /// standard input.
    public static func dictatedArguments(sandbox: String, tab: UUID) -> [String] {
        ["exec", "-i", sandbox, command, "--dictated", tab.uuidString]
    }

    /// `sbx exec -i` command that sets a tab's `VoiceSettings` (`json` on standard input), which
    /// `say`, `ask`, and the prompt hook read for voice reply.
    public static func settingsArguments(sandbox: String, tab: UUID) -> [String] {
        ["exec", "-i", sandbox, command, "--set-status", tab.uuidString]
    }

    // MARK: Files in the sandbox

    /// `paddock-voice`. Node, which every agent image has (Claude Code and OpenCode are npm
    /// packages). Waits poll on timers, so a SIGINT or SIGTERM from the agent's shell still runs
    /// the handler that takes the question back.
    static let script = NodeScript.wrap(#"""
    // Written by Paddock's voice kit: paddock-voice, to talk with the operator.
    'use strict';
    const fs = require('fs');
    const path = require('path');
    const crypto = require('crypto');

    const DIR = process.env.PADDOCK_VOICE_DIR || '\#(voiceDirectory)';
    const TAB = /^[A-Za-z0-9-]{1,64}$/.test(process.env.PADDOCK_TAB || '') ? process.env.PADDOCK_TAB : '';
    const LIMITS = { text: \#(VoiceMessage.maxText), question: \#(VoiceMessage.maxQuestion), choices: \#(VoiceMessage.maxChoices),
      choice: \#(VoiceMessage.maxChoice), words: \#(VoiceMessage.maxWords), word: \#(VoiceMessage.maxWord), answer: \#(VoiceAnswer.maxLength) };
    const WAIT_DEFAULT = 300;
    const WAIT_MAX = 1800;
    // How long a dictation counts as the next prompt's source.
    const DICTATION_FRESH = 900;
    const WORD = /^[\p{L}\p{N}][\p{L}\p{N} ._+#\/'-]*$/u;
    const USAGE = `paddock-voice: talk with the operator through Paddock's voice popup (read aloud while they
    have voice reply on).

      paddock-voice say TEXT               Tell them one or two sentences.
      paddock-voice ask QUESTION [--choice A]...
                                           Ask for a decision; prints "choice: A", "answer: TEXT",
                                           "dismissed", or "timeout".
      paddock-voice words add NAME...      Names you work with, so dictation spells them right.
                          remove NAME...   Also: words list, words clear.`;

    function fail(message, code = 2) {
      process.stderr.write(`paddock-voice: ${message}\n`);
      process.exit(code);
    }
    function sub(name) {
      const dir = path.join(DIR, name);
      fs.mkdirSync(dir, { recursive: true });
      return dir;
    }
    function writeAtomic(file, text) {
      const tmp = path.join(path.dirname(file), `.${path.basename(file)}.${process.pid}`);
      fs.writeFileSync(tmp, text);
      fs.renameSync(tmp, file);
    }
    function readJSON(file) {
      try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
    }
    function now() { return Math.floor(Date.now() / 1000); }
    // One line, no control characters.
    function line(text) { return String(text).replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ').replace(/\s+/g, ' ').trim(); }
    // Named by time first, so the watcher prints them in order (a question before its cancel).
    function send(message) {
      const file = path.join(sub('out'), `${Date.now()}-${message.id}-${message.kind}.json`);
      writeAtomic(file, JSON.stringify({ ...message, tab: TAB, time: now() }) + '\n');
    }
    function newID() { return 'v-' + crypto.randomBytes(4).toString('hex'); }
    const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

    // Waits for Paddock's answer to `id`; null when the time is up.
    async function answerTo(id, seconds) {
      const file = path.join(sub('answers'), id);
      const end = Date.now() + seconds * 1000;
      while (Date.now() < end) {
        try {
          const answer = fs.readFileSync(file, 'utf8').trim();
          fs.rmSync(file, { force: true });
          return answer;
        } catch { /* not yet */ }
        await sleep(250);
      }
      return null;
    }
    // A question is pending while this process waits; taken back if it ends early.
    function pending(id) {
      const marker = path.join(sub('pending'), id);
      fs.writeFileSync(marker, '');
      const done = () => fs.rmSync(marker, { force: true });
      const stop = () => { send({ id, kind: 'cancel' }); done(); process.exit(130); };
      process.on('SIGINT', stop);
      process.on('SIGTERM', stop);
      process.on('SIGHUP', stop);
      return done;
    }
    async function readStdin() {
      let text = '';
      for await (const chunk of process.stdin) { text += chunk; if (text.length > 65536) break; }
      return text;
    }
    // Words of the rest of the arguments, with the flags taken out.
    function parse(args, flags) {
      const out = { rest: [] };
      for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        const [name, inline] = arg.startsWith('--') ? arg.split(/=(.*)/s) : [arg];
        const kind = flags[name];
        if (kind === 'bool') { out[name] = true; continue; }
        if (kind) {
          const value = inline !== undefined ? inline : args[++i];
          if (value === undefined) fail(`${name} needs a value\n${USAGE}`);
          if (kind === 'list') (out[name] = out[name] || []).push(value);
          else out[name] = value;
          continue;
        }
        out.rest.push(arg);
      }
      return out;
    }

    // Voice reply is the operator's switch in Paddock, per tab (muted counts as off): the hook asks for
    // a spoken summary while it is on.
    function replyOn() {
      const settings = TAB ? readJSON(path.join(sub('status'), `${TAB}.json`)) : null;
      return !!(settings && settings.voice === true && settings.voiceReply === true);
    }

    async function say(args) {
      const opts = parse(args, {});
      let text = opts.rest.join(' ');
      if (text === '-') text = await readStdin();
      text = line(text);
      if (!text) fail(`what should Paddock say?\n${USAGE}`);
      if (text.length > LIMITS.text) fail(`too long (${text.length} characters, at most ${LIMITS.text}); say one or two sentences and leave the rest in the terminal`);
      send({ id: newID(), kind: 'say', text });
    }

    async function ask(args) {
      const opts = parse(args, { '--choice': 'list', '--timeout': 'value' });
      const question = line(opts.rest.join(' '));
      if (!question) fail(`what is the question?\n${USAGE}`);
      if (question.length > LIMITS.question) fail(`question too long (at most ${LIMITS.question} characters)`);
      const choices = (opts['--choice'] || []).map(line).filter(Boolean);
      if (choices.length > LIMITS.choices) fail(`at most ${LIMITS.choices} choices`);
      if (choices.some((c) => c.length > LIMITS.choice)) fail(`a choice has at most ${LIMITS.choice} characters`);
      if (new Set(choices.map((c) => c.toLowerCase())).size !== choices.length) fail('choices must differ');
      const timeout = opts['--timeout'] === undefined ? WAIT_DEFAULT : Number(opts['--timeout']);
      if (!Number.isInteger(timeout) || timeout < 5 || timeout > WAIT_MAX) fail(`--timeout is whole seconds from 5 to ${WAIT_MAX}`);
      const id = newID();
      const done = pending(id);
      send({ id, kind: 'ask', text: question, choices, deadline: now() + timeout });
      const answer = await answerTo(id, timeout);
      done();
      if (answer === null) {
        send({ id, kind: 'cancel' });
        console.log('timeout');
      } else {
        console.log(answer);
      }
    }

    function words(args) {
      const file = path.join(sub('state'), 'words.json');
      let list = readJSON(file);
      if (!Array.isArray(list)) list = [];
      const [verb, ...names] = args;
      const given = names.map((n) => line(n)).filter(Boolean);
      const bad = given.find((n) => n.length > LIMITS.word || !WORD.test(n));
      if (bad !== undefined) fail(`not a word Paddock takes: "${bad}" (letters, digits, spaces, and . _ + # / ' -, at most ${LIMITS.word} characters)`);
      switch (verb) {
        case 'add':
          if (!given.length) fail('words add NAME...');
          for (const name of given) if (!list.includes(name)) list.push(name);
          if (list.length > LIMITS.words) fail(`at most ${LIMITS.words} words; remove some first (words list shows them)`);
          break;
        case 'remove':
          list = list.filter((name) => !given.includes(name));
          break;
        case 'clear':
          list = [];
          break;
        case 'list':
        case undefined:
          console.log(list.length ? list.join('\n') : '(no words yet)');
          return;
        default:
          fail(`words add|remove|list|clear\n${USAGE}`);
      }
      writeAtomic(file, JSON.stringify({ id: 'v-00000000', kind: 'words', words: list, tab: '', time: now() }) + '\n');
      console.log(`${list.length} word${list.length === 1 ? '' : 's'} for dictation`);
    }

    // For Paddock: the answer to a pending ask, on stdin.
    async function answer(id) {
      if (!/^v-[0-9a-f]{8}$/.test(id || '')) fail('bad id');
      if (!fs.existsSync(path.join(sub('pending'), id))) return;
      const text = line(await readStdin()).slice(0, LIMITS.answer);
      if (!/^(dismissed|timeout|choice: .+|answer: .+)$/s.test(text)) fail('bad answer');
      writeAtomic(path.join(sub('answers'), id), text + '\n');
    }

    // For Paddock: what the operator dictated into a tab, on stdin, just before it is pasted.
    async function dictated(tab) {
      if (!/^[A-Za-z0-9-]{1,64}$/.test(tab || '')) fail('bad tab');
      const text = line(await readStdin()).slice(0, 8000);
      writeAtomic(path.join(sub('dictated'), `${tab}.json`), JSON.stringify({ text, time: now() }) + '\n');
    }

    // For Paddock: {"voice": bool, "voiceReply": bool} for a tab, on stdin.
    async function setStatus(tab) {
      if (!/^[A-Za-z0-9-]{1,64}$/.test(tab || '')) fail('bad tab');
      let settings;
      try { settings = JSON.parse(await readStdin()); } catch { fail('bad settings'); }
      if (!settings || typeof settings.voice !== 'boolean' || typeof settings.voiceReply !== 'boolean') fail('bad settings');
      writeAtomic(path.join(sub('status'), `${tab}.json`),
        JSON.stringify({ voice: settings.voice, voiceReply: settings.voiceReply }) + '\n');
    }

    // Claude Code's UserPromptSubmit hook: tells the agent when the prompt is what the operator just
    // dictated, and how to reply: by voice when the operator turned voice reply on, as usual otherwise.
    // Never prints anything else and never fails (that would change what the agent does).
    async function hook() {
      try {
        const input = JSON.parse(await readStdin());
        const prompt = typeof input.prompt === 'string' ? input.prompt : '';
        if (!TAB) return;
        const recordFile = path.join(sub('dictated'), `${TAB}.json`);
        const record = readJSON(recordFile);
        const plain = (text) => line(text).toLowerCase();
        const spoken = !!(record && typeof record.text === 'string' && record.text
          && now() - record.time <= DICTATION_FRESH && plain(prompt).includes(plain(record.text)));
        if (spoken) fs.rmSync(recordFile, { force: true });
        const reply = replyOn();
        const notes = [];
        if (spoken) {
          notes.push('The operator dictated this prompt: words may be misheard, so read it for what they meant and ask ' +
            'if a name is unclear.');
        }
        if (reply) {
          notes.push('Voice reply is on: the operator listens instead of reading. When you finish, run ' +
            'paddock-voice say "..." with one or two plain sentences (the details stay in the terminal); for a decision, ' +
            'run paddock-voice ask "..." --choice A --choice B.');
        } else if (spoken) {
          notes.push('Voice reply is off: reply in the terminal as usual.');
        }
        if (notes.length === 0) return;
        process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: 'UserPromptSubmit',
          additionalContext: 'Paddock: ' + notes.join(' ') } }) + '\n');
      } catch { /* never in the agent's way */ }
    }

    async function main() {
      const [verb, ...args] = process.argv.slice(2);
      switch (verb) {
        case 'say': return say(args);
        case 'ask': return ask(args);
        case 'words': return words(args);
        case '--answer': return answer(args[0]);
        case '--dictated': return dictated(args[0]);
        case '--set-status': return setStatus(args[0]);
        case '--hook': return hook();
        case undefined: case 'help': case '--help': case '-h': console.log(USAGE); return;
        default: fail(`unknown command "${verb}"\n${USAGE}`);
      }
    }
    main().catch((error) => fail(error && error.message ? error.message : String(error)));

    """#)

    /// Prints the words once at start and when they change, and each message in `out` once (then
    /// removes it), for `sbx exec`. A message file is written whole (rename), so it is never read half.
    static let watchScript = #"""
    #!/bin/sh
    # Written by Paddock. Follows paddock-voice's messages.
    dir="${PADDOCK_VOICE_DIR:-\#(voiceDirectory)}"
    mkdir -p "$dir/out" "$dir/state" 2>/dev/null
    trap 'exit 0' INT TERM HUP
    words=""
    while :; do
      cur=$(cat "$dir/state/words.json" 2>/dev/null)
      if [ -n "$cur" ] && [ "$cur" != "$words" ]; then
        printf '%s\n' "$cur"
        words="$cur"
      fi
      for file in "$dir"/out/*.json; do
        [ -f "$file" ] || continue
        cat "$file" 2>/dev/null
        rm -f "$file"
      done
      sleep 0.3 2>/dev/null || sleep 1
    done

    """#

    /// Claude Code's prompt hook (merged into `~/.claude/settings.json` like the status kit's).
    static var claudeHooksJSON: String {
        let hooks: [String: [[String: Any]]] = [
            "UserPromptSubmit": [["hooks": [["type": "command", "command": "\(command) --hook claude", "timeout": 5]]]]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: hooks, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    public static var spec: String {
        let tool = Data(script.utf8).base64EncodedString()
        let watch = Data(watchScript.utf8).base64EncodedString()
        let merge = Data(AgentStatusKit.claudeMergeScript.utf8).base64EncodedString()
        let hooks = Data(claudeHooksJSON.utf8).base64EncodedString()
        return #"""
        # syntax=docker/sandbox-kit:3
        # Written by Paddock. Changes are overwritten when Paddock creates a sandbox.
        schemaVersion: "3"
        kind: mixin
        version: "\#(KitFile.version)"
        displayName: Voice (Paddock)
        description: "Read this when the operator talks to you by voice or you want to tell or ask them something out loud: paddock-voice speaks, asks, and takes the names you work with for their dictation."
        provides: [paddock-voice]

        capabilities:
          - type: com.docker.sandbox/lifecycle@1
            config:
              install:
                - command: |
                    set -eu
                    printf '%s' '\#(tool)' | base64 -d > /usr/local/bin/\#(command)
                    printf '%s' '\#(watch)' | base64 -d > /usr/local/bin/\#(watchCommand)
                    chmod 755 /usr/local/bin/\#(command) /usr/local/bin/\#(watchCommand)
                  user: "0"
                  description: Install paddock-voice and its watcher
                - command: |
                    set -eu
                    printf '%s' '\#(merge)' | base64 -d > /tmp/paddock-voice-merge.js
                    HOME=/home/agent sh /tmp/paddock-voice-merge.js '\#(hooks)' || echo "Paddock: Claude Code voice hook not installed" >&2
                    rm -f /tmp/paddock-voice-merge.js
                  user: "1000"
                  env: [PATH]
                  description: Add the voice prompt hook to Claude Code
          - type: com.docker.sandbox/agent-context@1
            config:
              content: |
                  ## Voice (Paddock)

                  The operator may dictate prompts and talk with you in Paddock's voice popup. What you
                  `say` or `ask` shows there, and is read aloud while they have voice reply on (Paddock
                  tells you with each prompt).

                  - `paddock-voice say "The tests pass; the fix is in the terminal."`: one or two plain
                    sentences, no code, paths, lists, or secrets. While voice reply is on, end with one.
                  - `paddock-voice ask "Deploy to staging now?" --choice yes --choice no`: for a decision.
                    It waits and prints `choice: X`, `answer: TEXT`, `dismissed`, or `timeout`.
                  - `paddock-voice words add NAME...`: names you work with (functions, files, tools), so
                    dictation spells them right.

        """#
    }

    /// Writes the kit if it is missing or differs. Returns the kit directory.
    @discardableResult
    public static func install(in paths: PaddockPaths) throws -> String {
        try KitFile.write(spec, to: directory(in: paths))
    }
}

/// What Paddock tells a tab's agent through `paddock-voice --set-status`.
public struct VoiceSettings: Sendable, Equatable, Codable {
    /// Not muted.
    public var voice: Bool
    /// The agent ends with a spoken summary or question; off, it replies in the terminal as usual.
    public var voiceReply: Bool

    public init(voice: Bool, voiceReply: Bool) {
        self.voice = voice
        self.voiceReply = voiceReply
    }

    public var json: Data {
        (try? JSONEncoder().encode(self)) ?? Data(#"{"voice":false,"voiceReply":false}"#.utf8)
    }
}
