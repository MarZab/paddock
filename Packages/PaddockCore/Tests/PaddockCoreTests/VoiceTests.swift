import Foundation
import Testing
@testable import PaddockCore

struct VoiceTests {
    // MARK: VoiceMessage

    private let tab = "6D3F2C1E-1B2A-4C5D-8E9F-0A1B2C3D4E5F"

    @Test func parsesTheKitsMessages() throws {
        let lines = String(decoding: try Fixture.data("voice", "watch.jsonl"), as: UTF8.self).split(separator: "\n").map(String.init)
        let messages = lines.compactMap(VoiceMessage.init(line:))
        #expect(messages.count == lines.count)
        #expect(messages[0].kind == .words(["PolicyPlanner", "sbx", "llmman"]))
        #expect(messages[1] == VoiceMessage(id: "v-1a2b3c4d", kind: .say(text: "The tests pass; the fix is in the terminal."),
                                            tab: UUID(uuidString: tab), time: Date(timeIntervalSince1970: 1_761_700_000)))
        #expect(messages[2].kind == .ask(question: "Deploy to staging now?", choices: ["yes", "no"],
                                         deadline: Date(timeIntervalSince1970: 1_761_700_300)))
        #expect(messages[3].kind == .cancel && messages[3].id == "v-5e6f7a8b")
    }

    @Test func dropsAnythingThatIsNotExactlyAMessage() {
        func line(_ fields: String) -> String { #"{"id":"v-1a2b3c4d",\#(fields),"tab":"","time":1}"# }
        #expect(VoiceMessage(line: line(#""kind":"say","text":"hi""#)) != nil)
        // unknown kinds, bad ids, empty or long text, control characters
        #expect(VoiceMessage(line: line(#""kind":"run","text":"hi""#)) == nil)
        #expect(VoiceMessage(line: #"{"id":"v-1A2B3C4D","kind":"say","text":"hi","tab":"","time":1}"#) == nil)
        #expect(VoiceMessage(line: #"{"id":"../x","kind":"say","text":"hi","tab":"","time":1}"#) == nil)
        #expect(VoiceMessage(line: line(#""kind":"say","text":"""#)) == nil)
        #expect(VoiceMessage(line: line(#""kind":"say","text":"\#(String(repeating: "a", count: 601))""#)) == nil)
        #expect(VoiceMessage(line: line(#""kind":"say","text":"a\u001b[31mb""#)) == nil)
        // questions: too many choices, a repeated choice, a deadline before the message
        let nine = (1...9).map { "\"c\($0)\"" }.joined(separator: ",")
        #expect(VoiceMessage(line: line(#""kind":"ask","text":"q","choices":[\#(nine)],"deadline":5"#)) == nil)
        #expect(VoiceMessage(line: line(#""kind":"ask","text":"q","choices":["Yes","yes"],"deadline":5"#)) == nil)
        #expect(VoiceMessage(line: #"{"id":"v-1a2b3c4d","kind":"ask","text":"q","deadline":5,"tab":"","time":9}"#) == nil)
        #expect(VoiceMessage(line: line(#""kind":"ask","text":"q""#)) == nil)
        // words: a bad word or too many
        #expect(VoiceMessage(line: line(#""kind":"words","words":["$(rm)"]"#)) == nil)
        let many = (1...201).map { "\"w\($0)\"" }.joined(separator: ",")
        #expect(VoiceMessage(line: line(#""kind":"words","words":[\#(many)]"#)) == nil)
        #expect(VoiceMessage(line: "not json") == nil)
        #expect(VoiceMessage(line: String(repeating: " ", count: 40_000)) == nil)
    }

    @Test func aLateSayIsNotSpokenAndAQuestionLastsUntilItsDeadline() {
        let start = Date(timeIntervalSince1970: 1000)
        let say = VoiceMessage(id: "v-00000001", kind: .say(text: "hi"), tab: nil, time: start)
        #expect(!say.isStale(now: start.addingTimeInterval(30)))
        #expect(say.isStale(now: start.addingTimeInterval(61)))
        let ask = VoiceMessage(id: "v-00000002", kind: .ask(question: "q", choices: [], deadline: start.addingTimeInterval(300)),
                               tab: nil, time: start)
        #expect(!ask.isStale(now: start.addingTimeInterval(299)))
        #expect(ask.isStale(now: start.addingTimeInterval(301)))
    }

    // MARK: Answers and choices

    @Test func answersAreOneLineForTheKit() {
        #expect(VoiceAnswer.dismissed.line == "dismissed")
        #expect(VoiceAnswer.choice("staging").line == "choice: staging")
        #expect(VoiceAnswer.text("go\nahead\u{1B}[2J now").line == "answer: go ahead [2J now")
        #expect(VoiceAnswer.to(choices: ["staging", "production"], answer: "the second one") == .choice("production"))
        #expect(VoiceAnswer.to(choices: ["staging", "production"], answer: "wait until tomorrow") == .text("wait until tomorrow"))
        #expect(VoiceAnswer.to(choices: [], answer: "  ") == nil)
    }

    @Test func choicesMatchByNameOrPlace() {
        let deploy = ["staging", "production", "neither"]
        #expect(VoiceChoice.match("Staging.", choices: deploy) == 0)
        #expect(VoiceChoice.match("let's go with production please", choices: deploy) == 1)
        #expect(VoiceChoice.match("the second one", choices: deploy) == 1)
        #expect(VoiceChoice.match("option 3", choices: deploy) == 2)
        #expect(VoiceChoice.match("the last one", choices: deploy) == 2)
        #expect(VoiceChoice.match("the first", choices: deploy) == 0)
        // more than one named, a place that does not exist, nothing like a choice
        #expect(VoiceChoice.match("staging or production", choices: deploy) == nil)
        #expect(VoiceChoice.match("the fifth", choices: deploy) == nil)
        #expect(VoiceChoice.match("I am not sure", choices: deploy) == nil)
        // a choice that is a number word is taken by name, not by place
        #expect(VoiceChoice.match("two", choices: ["one", "two"]) == 1)
        #expect(VoiceChoice.match("yes", choices: ["yes", "no"]) == 0)
        #expect(VoiceChoice.match("no", choices: ["yes", "no"]) == 1)
        #expect(VoiceChoice.match("Run the tests", choices: ["Run the tests", "Skip"]) == 0)
    }

    // MARK: Spoken text

    @Test func spokenTextDropsMarkdownCodeAndPaths() {
        let text = """
        ## Done
        - Fixed **the parser** in `Sources/PaddockCore/Projects/Ports.swift`.
        ```swift
        let secret = 1
        ```
        See [the docs](https://example.com/x) or https://example.com/y.
        """
        #expect(SpokenText.clean(text) == "Done Fixed the parser in Ports.swift. See the docs or a link")
    }

    @Test func spokenTextDropsInvisibleCharactersAndIsCut() {
        #expect(SpokenText.clean("a\u{202E}b\u{200B}c\u{0007}d") == "abc d")
        let long = Array(repeating: "word", count: 200).joined(separator: " ")
        let cut = SpokenText.clean(long)
        #expect(cut.count <= SpokenText.maxLength && cut.hasSuffix("word"))
    }

    @Test func anUtteranceIsTheCleanedTextAlone() {
        #expect(SpeechQueue.Utterance(project: "claude-plane", text: "Tests **pass**.").spoken == "Tests pass.")
    }

    // MARK: Keywords

    @Test func keywordsAreCheckedAndCombined() {
        #expect(VoiceKeywords.isWord("PolicyPlanner") && VoiceKeywords.isWord("C#") && VoiceKeywords.isWord("swift-nio"))
        #expect(!VoiceKeywords.isWord("") && !VoiceKeywords.isWord("-flag") && !VoiceKeywords.isWord("$(id)"))
        #expect(!VoiceKeywords.isWord(String(repeating: "a", count: 49)))
        #expect(VoiceKeywords.combined(agent: ["sbx", "Ports", "bad;word"], project: ["ports", "Gateway"]) == ["sbx", "Ports", "Gateway"])
        let many = (1...400).map { "w\($0)" }
        #expect(VoiceKeywords.combined(agent: many, project: []).count == VoiceKeywords.maxTotal)
    }

    @Test func projectNamesSkipHiddenAndBuildFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("paddock-voice-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ["Sources/PolicyPlanner.swift", "Sources/Deep/Inner/TooDeep.swift", "node_modules/left/pad.js", ".git/HEAD",
                     "README.md", "a.c"]
        for file in files {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        #expect(VoiceKeywords.projectNames(in: root) == ["Deep", "PolicyPlanner", "README", "Sources"])
    }

    // MARK: Paste

    @Test func dictationIsABracketedPasteWithoutControlCharacters() {
        let data = BracketedPaste.encode("run the tests\u{1B}[201~\u{1B}]0;x\u{07} then\r\nstop ", submit: false)
        #expect(String(decoding: data, as: UTF8.self) == "\u{1B}[200~run the tests[201~]0;x then\n\nstop\u{1B}[201~")
        #expect(String(decoding: BracketedPaste.encode("go", submit: true), as: UTF8.self) == "\u{1B}[200~go\u{1B}[201~\r")
    }

    // MARK: Speech queue

    @Test func theQueueSpeaksOneAtATimeAndSaysWho() async {
        let synth = FakeSynthesizer()
        let queue = SpeechQueue(synthesizer: synth)
        async let first = queue.speak(.init(project: "a", text: "one"))
        async let second = queue.speak(.init(project: "b", text: "two"))
        let outcomes = await [first, second]
        #expect(outcomes == [.done, .done])
        #expect(Set(await synth.spoken) == ["one", "two"])
        #expect(await synth.maxConcurrent == 1)
    }

    @Test func interruptingATabStopsItsSpeechAndKeepsTheOthers() async throws {
        let synth = FakeSynthesizer(duration: .milliseconds(300))
        let queue = SpeechQueue(synthesizer: synth)
        let mine = UUID()
        let speaking = Task { await queue.speak(.init(project: "a", tab: mine, text: "long")) }
        try await Task.sleep(for: .milliseconds(50))
        let waiting = Task { await queue.speak(.init(project: "a", tab: mine, text: "next")) }
        let other = Task { await queue.speak(.init(project: "b", text: "other")) }
        try await Task.sleep(for: .milliseconds(50))
        await queue.interrupt(tab: mine)
        #expect(await speaking.value == .interrupted)
        #expect(await waiting.value == .interrupted)
        #expect(await other.value == .done)
        #expect(await synth.spoken == ["long", "other"])
    }

    @Test func aChattyProjectIsNotQueuedFurther() async throws {
        let synth = FakeSynthesizer(duration: .milliseconds(200))
        let queue = SpeechQueue(synthesizer: synth)
        var tasks: [Task<SpeechQueue.Outcome, Never>] = []
        for index in 0..<5 {
            tasks.append(Task { await queue.speak(.init(project: "a", text: "\(index)")) })
            try await Task.sleep(for: .milliseconds(20))
        }
        var outcomes: [SpeechQueue.Outcome] = []
        for task in tasks { outcomes.append(await task.value) }
        // one speaking, three waiting, the fifth dropped
        #expect(outcomes.filter { $0 == .dropped }.count == 1)
        #expect(outcomes.filter { $0 == .done }.count == 4)
    }

    // MARK: Announcements

    @Test func announcementsSayWhatNeedsTheOperator() {
        func say(_ previous: AgentState.Kind?, _ current: AgentState.Kind, _ setting: VoiceAnnouncements.Setting,
                 looking: Bool = false, session: String? = nil) -> String? {
            VoiceAnnouncements.announcement(project: "claude-plane", session: session, previous: previous, current: current,
                                            setting: setting, looking: looking)
        }
        #expect(say(.working, .waiting, .needsYou) == "claude-plane is waiting for you")
        #expect(say(.working, .idle, .needsYou) == nil)
        #expect(say(.working, .idle, .everyChange) == "claude-plane finished")
        #expect(say(.idle, .idle, .everyChange) == nil)
        #expect(say(.waiting, .idle, .everyChange) == nil)
        #expect(say(.working, .waiting, .off) == nil)
        #expect(say(.working, .waiting, .needsYou, looking: true) == nil)
        #expect(say(.working, .waiting, .needsYou, session: "agent 2") == "claude-plane, agent 2, is waiting for you")
    }
}

/// Records what it was asked to say; `stop()` ends the current one early.
actor FakeSynthesizer: SpeechSynthesizing {
    private(set) var spoken: [String] = []
    private(set) var maxConcurrent = 0
    private var active = 0
    private var stopped = false
    private let duration: Duration

    init(duration: Duration = .milliseconds(20)) {
        self.duration = duration
    }

    func speak(_ text: String) async -> Bool {
        spoken.append(text)
        active += 1
        maxConcurrent = max(maxConcurrent, active)
        stopped = false
        let end = ContinuousClock.now + duration
        while ContinuousClock.now < end, !stopped {
            try? await Task.sleep(for: .milliseconds(10))
        }
        active -= 1
        return !stopped
    }

    func stop() async {
        stopped = true
    }
}

struct DictationCommandTests {
    @Test func onlyAWordOnItsOwnIsACommand() {
        #expect(DictationCommand.strip("Stop.") == ("", [.stop]))
        #expect(DictationCommand.strip("send") == ("", [.send]))
        #expect(DictationCommand.strip(" Deploy to staging. Send.") == (" Deploy to staging.", [.send]))
        #expect(DictationCommand.strip("Fix it. STOP! Then test.") == ("Fix it. Then test.", [.stop]))
        #expect(DictationCommand.strip(" Stop, ") == ("", [.stop]))
        #expect(DictationCommand.strip("Stop. Send.") == ("", [.stop, .send]))
        #expect(DictationCommand.strip("Use main. Cancel.") == ("Use main.", [.stop]))
    }

    @Test func whileAnAgentSpeaksStopCountsAnywhereButInItsOwnWords() {
        let spoken = "The tests pass; the fix is in the terminal."
        #expect(DictationCommand.stopsSpeech(heard: "the tests pass the fix stop", spoken: spoken))
        #expect(DictationCommand.stopsSpeech(heard: "Cancel", spoken: spoken))
        #expect(!DictationCommand.stopsSpeech(heard: "the tests pass the fix is in", spoken: spoken))
        // the speaker saying it is not the operator
        #expect(!DictationCommand.stopsSpeech(heard: "please stop the server", spoken: "Should I stop the server?"))
        #expect(!DictationCommand.stopsSpeech(heard: "nonstop", spoken: spoken))
    }

    @Test func aWordInASentenceIsText() {
        for text in ["Stop the server.", "Don't stop.", "send it to staging", "stop stop", "Send 2.", "cancel the job", "Bus stop?", ""] {
            #expect(DictationCommand.strip(text) == (text, []))
        }
    }
}

struct VoiceConversationTests {
    @Test func eachPopupShowsItsTabAndTheLeftOneTheUntabbed() {
        let mine = UUID(), other = UUID()
        var talk = VoiceConversation()
        talk.append(.init(speaker: .agent, text: "Tests pass.", tab: mine))
        talk.append(.init(speaker: .agent, text: "Deploy?", isQuestion: true, tab: nil))
        talk.append(.init(speaker: .operator, text: "yes", tab: other))
        talk.append(.init(speaker: .operator, text: "  ", tab: mine))
        #expect(talk.entries(for: mine, untabbed: false).map(\.text) == ["Tests pass."])
        #expect(talk.entries(for: mine, untabbed: true).map(\.text) == ["Tests pass.", "Deploy?"])
        #expect(talk.entries(for: nil, untabbed: true).map(\.text) == ["Deploy?"])
    }

    @Test func agentTextLosesInvisibleCharactersAndTheOldestGo() {
        var talk = VoiceConversation()
        talk.append(.init(speaker: .agent, text: "ok\u{202E}gnol", tab: nil))
        #expect(talk.entries.first?.text == "okgnol")
        for index in 0..<VoiceConversation.limit { talk.append(.init(speaker: .operator, text: "\(index)", tab: nil)) }
        #expect(talk.entries.count == VoiceConversation.limit && talk.entries.first?.text == "0")
        #expect(VoiceConversation.text(of: .choice("staging")) == "staging" && VoiceConversation.text(of: .dismissed) == "Dismissed")
    }
}

struct SpeechVoicesTests {
    private let voices = [
        SpeechVoice(id: "samantha", name: "Samantha", language: "en-US", quality: .basic),
        SpeechVoice(id: "zoe", name: "Zoe", language: "en-US", quality: .premium),
        SpeechVoice(id: "daniel", name: "Daniel", language: "en-GB", quality: .premium),
        SpeechVoice(id: "ava", name: "Ava", language: "en-US", quality: .enhanced),
        SpeechVoice(id: "bells", name: "Bells", language: "en-US", quality: .basic, isNovelty: true),
        SpeechVoice(id: "anna", name: "Anna", language: "de-DE", quality: .premium),
    ]

    @Test func theBestVoiceForTheLanguageComesFirst() {
        #expect(SpeechVoices.offered(voices, language: "en_US").map(\.id) == ["zoe", "daniel", "ava", "samantha"])
        #expect(SpeechVoices.pick(voices, language: "en-US", chosen: nil)?.id == "zoe")
        #expect(SpeechVoices.pick(voices, language: "fr-FR", chosen: nil) == nil)
    }

    @Test func theOperatorsChoiceWinsWhileItIsInstalled() {
        #expect(SpeechVoices.pick(voices, language: "en-US", chosen: "daniel")?.id == "daniel")
        #expect(SpeechVoices.pick(voices, language: "en-US", chosen: "gone")?.id == "zoe")
    }

    @Test func onlyBasicVoicesSuggestABetterOne() {
        #expect(!SpeechVoices.suggestsBetter(voices, language: "en-US"))
        #expect(SpeechVoices.suggestsBetter(voices.filter { $0.quality == .basic }, language: "en-US"))
        #expect(SpeechVoices.suggestsBetter(voices, language: "sl-SI"))
    }
}

struct VoiceActivityTests {
    @Test func speechStandsOutFromTheRoom() {
        var activity = VoiceActivity()
        let room = (0..<50).map { _ in activity.isSpeech(level: -58) }
        #expect(!room.contains(true))
        // a long sentence does not become the background
        let sentence = (0..<150).map { _ in activity.isSpeech(level: -30) }  // about 12 s
        #expect(!sentence.contains(false))
        let after = activity.isSpeech(level: -57)
        #expect(!after)
    }

    @Test func aNoisyRoomRaisesTheBar() {
        var activity = VoiceActivity()
        for _ in 0..<600 { _ = activity.isSpeech(level: -35) }
        let same = activity.isSpeech(level: -33)
        let louder = activity.isSpeech(level: -15)
        #expect(!same && louder)
    }

    @Test func levelsAreRMSInDecibels() {
        let silence = [Float](repeating: 0, count: 64)
        let full = [Float](repeating: 1, count: 64)
        let tenth = [Float](repeating: 0.1, count: 64)
        silence.withUnsafeBufferPointer { #expect(VoiceActivity.level(of: $0) == -100) }
        full.withUnsafeBufferPointer { #expect(abs(VoiceActivity.level(of: $0)) < 0.01) }
        tenth.withUnsafeBufferPointer { #expect(abs(VoiceActivity.level(of: $0) + 20) < 0.01) }
    }
}

struct WakeWordTests {
    private let paddock = WakeWord("Paddock")

    @Test func whatFollowsTheWordIsTheDictation() {
        #expect(paddock?.after("Paddock, run the tests.") == "run the tests.")
        #expect(paddock?.after("so I said to him paddock. Open the browser") == "Open the browser")
        #expect(paddock?.after("PADDOCK") == "")
    }

    @Test func nothingCountsUntilItIsSaid() {
        #expect(paddock?.after("run the tests") == nil)
        #expect(paddock?.after("") == nil)
        // a whole word, not part of one
        #expect(paddock?.after("paddocks are fenced") == nil)
    }

    @Test func aPhraseMatchesWordByWord() {
        let hey = WakeWord("Hey Paddock")
        #expect(hey?.phrase == "Hey Paddock")
        #expect(hey?.after("hey, paddock: what failed?") == "what failed?")
        #expect(hey?.after("paddock what failed") == nil)
    }

    @Test func emptyOrLongPhrasesTurnItOff() {
        #expect(WakeWord("") == nil)
        #expect(WakeWord(" ,. ") == nil)
        #expect(WakeWord("one two three four five") == nil)
    }

    @Test func eitherDefaultWordStarts() throws {
        let words = try #require(WakeWords(setting: WakeWords.defaultSetting))
        #expect(words.phrases == ["Paddock", "computer"])
        #expect(words.after("Computer, open the report") == "open the report")
        #expect(words.after("paddock run the tests") == "run the tests")
        // the first said starts it, even when the other comes later in the dictation
        #expect(words.after("computer, rename it paddock tools") == "rename it paddock tools")
        #expect(words.after("what a nice day") == nil)
        #expect(words.hint == "\"Paddock\" or \"computer\"")
    }

    @Test func anEmptySettingTurnsTheStartWordOff() {
        #expect(WakeWords(setting: "") == nil)
        #expect(WakeWords(setting: " , ") == nil)
        #expect(WakeWords(setting: "Jarvis")?.hint == "\"Jarvis\"")
    }
}

struct WaitingMusicTests {
    private func rms(_ from: Double, _ to: Double) -> Double {
        let times = stride(from: from, to: to, by: 1.0 / 8000)
        let sum = times.reduce(0.0) { $0 + Double(WaitingMusic.sample(at: $1) * WaitingMusic.sample(at: $1)) }
        return (sum / Double(times.underestimatedCount)).squareRoot()
    }

    @Test func itStaysQuiet() {
        for step in 0..<200_000 {
            let sample = WaitingMusic.sample(at: Double(step) / 997)
            #expect(abs(sample) <= WaitingMusic.ceiling)
        }
        #expect(WaitingMusic.sample(at: 0) == 0)
    }

    @Test func itFadesIn() {
        #expect(rms(0, 0.5) < rms(5, 5.5) / 3)
        #expect(rms(5, 5.5) > 0.02)
    }

    @Test func afterAMinuteOnlyASoftNoteNowAndThen() {
        // the chords are gone, and a note from 76 s has died away
        #expect(rms(82.5, 83.5) < 0.001)
        // the next note rings
        #expect(rms(84, 84.5) > 0.01)
        #expect(rms(84, 84.5) < rms(30, 30.5))
    }

    @Test func theRendererFadesOutAndSaysWhenItIsSilent() {
        let renderer = WaitingMusicRenderer(sampleRate: 8000)
        var buffer = [Float](repeating: 0, count: 8000 * 5)
        #expect(buffer.withUnsafeMutableBufferPointer { renderer.render(into: $0) })
        #expect(buffer.contains { $0 != 0 })
        renderer.stop()
        var tail = [Float](repeating: 1, count: 8000 * 2)
        let playing = tail.withUnsafeMutableBufferPointer { renderer.render(into: $0) }
        #expect(!playing)
        #expect(tail[8000...].allSatisfy { $0 == 0 })
        #expect(abs(tail[0]) > 0 || abs(tail[1]) > 0)
    }
}

struct DictationTextTests {
    @Test(arguments: [".", "", "  ", ", .", "...", "?!", "Hmm.", "uh, um", "Mm-hmm."])
    func garbageIsNotSent(text: String) {
        #expect(DictationText.prompt(text) == nil)
    }

    @Test func wordsAreSentWithoutLeadingPunctuation() {
        #expect(DictationText.prompt(", run the tests.") == "run the tests.")
        #expect(DictationText.prompt("  Fix it ") == "Fix it")
        #expect(DictationText.prompt("42") == "42")
        #expect(DictationText.prompt("um, fix the build") == "um, fix the build")
        #expect(DictationText.prompt("Oh no.") == "Oh no.")
    }
}
